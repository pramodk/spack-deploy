#!/bin/bash -l

# This script assumes that the following variables are set in the environment:
#
# DEPLOYMENT_ROOT: path to deploy to

set -o errexit
set -o nounset

DEFAULT_DEPLOYMENT_ROOT="/gpfs/bbp.cscs.ch/apps/hpc/test/$(whoami)/deployment"
DEFAULT_DEPLOYMENT_DATA="/gpfs/bbp.cscs.ch/data/project/proj20/pramod_scratch/SPACK_DEPLOYMENT/download"
DEFAULT_DEPLOYMENT_DATE="$(date +%Y-%m-%d)"


DEPLOYMENT_DATA=${DEPLOYMENT_DATA:-${DEFAULT_DEPLOYMENT_DATA}}
DEPLOYMENT_ROOT=${DEPLOYMENT_ROOT:-${DEFAULT_DEPLOYMENT_ROOT}}
SPACK_MIRROR_DIR="${DEPLOYMENT_ROOT}/mirror"
export DEPLOYMENT_ROOT SPACK_MIRROR_DIR

declare -A spec_definitions=([compilers]=compilers
                             [tools]=system-tools
                             [libraries]="parallel-libraries serial-libraries python-packages"
                             [applications]=bbp-packages)
declare -A spec_parentage=([tools]=compilers
                           [libraries]=tools
                           [applications]=libraries)
stages="compilers tools libraries applications"

log() {
    echo "$(tput bold)### $@$(tput sgr0)" >&2
}

install_dir() {
    what=$1
    date="${DEPLOYMENT_DATE:-${DEFAULT_DEPLOYMENT_DATE}}"
    echo "${DEPLOYMENT_ROOT}/install/${what}/${date}"
}

last_install_dir() {
    what=$1
    find "${DEPLOYMENT_ROOT}/install/${what}" -mindepth 1 -maxdepth 1 -type d|sort|tail -n1
}

configure_compilers() {
    while read -r line; do
        set +o nounset
        spack load ${line}
        set -o nounset
        if [[ ${line} != *"intel-parallel-studio"* ]]; then
            spack compiler find --scope=user
        fi

        if [[ ${line} = *"intel"* ]]; then
            GCC_DIR=$(spack location --install-dir gcc@6.4.0)

            # update intel modules to use gcc@6.4.0 in .cfg files
            install_dir=$(spack location --install-dir ${line})
            for f in $(find ${install_dir} -name "icc.cfg" -o -name "icpc.cfg" -o -name "ifort.cfg"); do
                if ! grep -q "${GCC_DIR}" $f; then
                    echo "-gcc-name=${GCC_DIR}/bin/gcc" >> ${f}
                    echo "-Xlinker -rpath=${GCC_DIR}/lib" >> ${f}
                    echo "-Xlinker -rpath=${GCC_DIR}/lib64" >> ${f}
                    log "updated ${f} with newer GCC"
                fi
            done
        elif [[ ${line} = *"pgi"* ]]; then
            #update pgi modules for network installation
            PGI_DIR=$(dirname $(which makelocalrc))
            makelocalrc ${PGI_DIR} -gcc ${GCC_DIR}/bin/gcc -gpp ${GCC_DIR}/bin/g++ -g77 ${GCC_DIR}/bin/gfortran -x -net

            #configure pgi network license
            template=$(find $PGI_DIR -name localrc* | tail -n 1)
            for node in bbpv1 bbpv2 r2i3n0 r2i3n1 r2i3n2 r2i3n3 r2i3n4 r2i3n5 r2i3n6; do
                cp $template $PGI_DIR/localrc.$node || true
            done
        fi
        spack unload ${line}
    done

    sed  -i 's#.*f\(77\|c\): null#      f\1: /usr/bin/gfortran#' ${HOME}/.spack/compilers.yaml
}

populate_mirror() {
    what=$1
    log "populating mirror for ${what}"

    specfile="$(install_dir ${what})/data/specs.txt"
    spec_list=$(spack filter --not-installed $(cat ${specfile}))

    if [[ -z "${spec_list}" ]]; then
        log "...found no new packages"
        return 0
    fi

    if [[ "${what}" = "compilers" ]]; then
        for compiler in intel intel-parallel-studio pgi; do
            mkdir -p ${SPACK_MIRROR_DIR}/${compiler}
            cp ${DEPLOYMENT_DATA}/${compiler}/* ${SPACK_MIRROR_DIR}/${compiler}/
        done
    fi

    log "found the following specs"
    echo "${spec_list}"
    spack mirror create -D -d ${SPACK_MIRROR_DIR} ${spec_list}
    spack mirror add --scope=user my_mirror ${SPACK_MIRROR_DIR} || log "mirror already added!"
}

filter_specs() {
    package_list=$1
    cat ${package_list}
    # spack filter --not-installed $(<${package_list})
}

check_specs() {
    spack spec -Il "$@"
}

generate_specs() {
    what="$@"

    if [[ -z "${what}" ]]; then
        log "asked to generate no specs!"
        return 1
    fi

    venv="${DEPLOYMENT_ROOT}/deploy/venv"

    log "updating the deployment virtualenv"
    # Recreate the virtualenv and update the command line
    mkdir -p ${venv}
    virtualenv -q -p $(which python) ${venv} --clear
    set +o nounset
    . ${venv}/bin/activate
    set -o nounset
    pip install -q --force-reinstall -U .

    for stage in ${what}; do
        log "generating specs for ${stage}"
        datadir="$(install_dir ${stage})/data"

        mkdir -p "${datadir}"
        env &> "${datadir}/spack_deploy.env"
        git rev-parse HEAD &> "${datadir}/spack_deploy.version"

        rm -f "${datadir}/specs.txt"
        for stub in ${spec_definitions[$stage]}; do
            log "...using ${stub}.yaml"
            spackd --input packages/${stub}.yaml packages x86_64 >> "${datadir}/specs.txt"
        done
    done
}

copy_configuration() {
    what="$1"

    log "copying configuration"
    log "...into ${HOME}"
    rm -rf "${HOME}/.spack"
    mkdir -p "${HOME}/.spack"
    cp configs/*.yaml "${HOME}/.spack"

    if [[ ${spec_parentage[${what}]+_} ]]; then
        parent="${spec_parentage[$what]}"
        pdir="$(last_install_dir ${parent})"
        log "...using configuration output of ${parent}"
        cp "${pdir}/data/packages.yaml" "${HOME}/.spack"
        cp "${pdir}/data/compilers.yaml" "${HOME}/.spack"
    fi

    if [[ -d "configs/${what}" ]]; then
        log "...using specialized configuration files: $(ls configs/${what})"
        cp configs/${what}/*.yaml "${HOME}/.spack"
    fi
}

install_specs() {
    what="$1"

    location="$(install_dir ${what})"
    HOME="${location}/data"
    SOFTS_DIR_PATH="${location}"
    export HOME SOFTS_DIR_PATH

    copy_configuration "${what}"

    log "sourcing spack environment"
    . ${DEPLOYMENT_ROOT}/deploy/spack/share/spack/setup-env.sh
    env &> "${HOME}/spack.env"
    (cd "${DEPLOYMENT_ROOT}/deploy/spack" && git rev-parse HEAD) &> "${HOME}/spack.version"

    populate_mirror "${what}"

    log "gathering specs"
    spec_list=$(spack filter --not-installed $(< ${HOME}/specs.txt))

    if [[ -z "${spec_list}" ]]; then
        log "...found no new packages"
    else
        log "found the following specs"
        echo "${spec_list}"
        log "...checking specs"
        spack spec -Il ${spec_list}
        log "...installing specs"
        spack install -y --log-format=junit --log-file="${HOME}/stack.xml" ${spec_list}
        cp "${HOME}/stack.xml" "${what}.xml"
    fi

    spack module tcl refresh --delete-tree -y
    . ${DEPLOYMENT_ROOT}/deploy/spack/share/spack/setup-env.sh
    spack export --scope=user --explicit > "${HOME}/packages.yaml"

    if [[ "${what}" = "compilers" ]]; then
        cp configs/packages.yaml ${HOME}/packages.yaml
        if [[ -n "${spec_list}" ]]; then
            log "adding compilers"
            configure_compilers <<< "${spec_list}"
        fi
    fi

    cp "${HOME}/.spack/compilers.yaml" "${HOME}" || true
}

usage() {
    echo "usage: $0 [-gi] stage...1>&2"
    exit 1
}

do_generate=default
do_install=default
while getopts "gi" arg; do
    case "${arg}" in
        g)
            do_generate=yes
            [[ ${do_install} = "default" ]] && do_install=no
            ;;
        i)
            do_install=yes
            [[ ${do_generate} = "default" ]] && do_generate=no
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ "$@" = "all" ]]; then
    set -- ${stages}
else
    unknown=
    for what in "$@"; do
        if [[ ! ${spec_definitions[${what}]+_} ]]; then
            unknown="${unknown} ${what}"
        fi
    done
    if [[ -n "${unknown}" ]]; then
        echo "unknown stage(s):${unknown}"
        echo "allowed:          ${stages}"
        exit 1
    fi
fi

declare -A desired
for what in "$@"; do
    desired[${what}]=Yes
done

unset $(set +x; env | awk -F= '/^(PMI|SLURM)_/ {print $1}' | xargs)

[[ ${do_generate} != "no" ]] && generate_specs "$@"
for what in ${stages}; do
    if [[ ${desired[${what}]+_} && ${do_install} != "no" ]]; then
        install_specs ${what}
    fi
done
