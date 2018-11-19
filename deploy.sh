#!/bin/bash -l

# This script assumes that the following variables are set in the environment:
#
# DEPLOYMENT_ROOT: path to deploy to

set -o nounset

DEFAULT_DEPLOYMENT_DIR="/gpfs/bbp.cscs.ch/ssd/tmp_compile/deploy_test"
DEFAULT_DEPLOYMENT_DATEDATE="$(date +%Y-%m-%d)"

DEPLOYMENT_ROOT=${DEPLOYMENT_ROOT:-${DEFAULT_DEPLOYMENT_DIR}}
export DEPLOYMENT_ROOT

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
    echo "${DEPLOYMENT_ROOT}/install/${what}/${DEPLOYMENT_DATE}"
}

last_install_dir() {
    what=$1
    find "${DEPLOYMENT_ROOT}/install/${what}" -mindepth 1 -maxdepth 1 -type d|sort|tail -n1
}

configure_compilers() {
    GCC_DIR=`spack location --install-dir gcc@6.4.0`

    while read -r line; do
        set +o nounset
        spack load ${line}
        set -o nounset
        if [[ ${line} != *"intel-parallel-studio"* ]]; then
            spack compiler find --scope=user
        fi

        if [[ ${line} = *"intel"* ]]; then
            # update intel modules to use gcc@6.4.0 in .cfg files
            install_dir=$(spack location --install-dir ${line})
            for f in $(find ${install_dir} -name "icc.cfg" -o -name "icpc.cfg" -o -name "ifort.cfg"); do
                if ! grep -q "${GCC_DIR}" $f; then
                    echo "-gcc-name=${GCC_DIR}/bin/gcc" >> ${f}
                    echo "-Xlinker -rpath=${GCC_DIR}/lib" >> ${f}
                    echo "-Xlinker -rpath=${GCC_DIR}/lib64" >> ${f}
                    log "[CFG] Updated ${f} with newer GCC"
                fi
            done
        elif [[ ${line} = *"pgi"* ]]; then
            #update pgi modules for network installation
            PGI_DIR=$(dirname $(which makelocalrc))
            makelocalrc ${PGI_DIR} -gcc ${GCC_DIR}/bin/gcc -gpp ${GCC_DIR}/bin/g++ -g77 ${GCC_DIR}/bin/gfortran -x -net
        fi
        spack unload ${line}
    done

    sed  -i 's#.*f\(77\|c\): null#      f\1: /usr/bin/gfortran#' ${HOME}/.spack/compilers.yaml
}

filter_specs() {
    package_list=$1
    spack filter --not-installed $(<${package_list})
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
        git --rev-parse HEAD &> "${datadir}/spack_deploy.version"

        rm -f "${datadir}/specs.txt"
        for stub in ${spec_definitions[$stage]}; do
            log "...using ${stub}.yaml"
            spackd --input packages/${stub}.yaml packages x86_64 > "${datadir}/specs.txt"
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

    log "gathering specs"
    spec_list="$(filter_specs ${HOME}/specs.txt)"
    if [[ -z "${spec_list}" ]]; then
        log "...found no new packages"
        return 1
    else
        log "found the following specs"
        echo "${spec_list}"
        log "...checking specs"
        check_specs "${spec_list}"
        log "...installing specs"
        spack install -y --log-format=junit --log-file="${HOME}/stack.xml" "${spec_list}"
    fi

    spack module tcl refresh --delete-tree -y
    spack export --module tcl > "${HOME}/packages.yaml"

    if [[ "${what}" == "compilers" && -n "${spec_list}" ]]; then
        log "adding compilers"
        configure_compilers <<< "${spec_list}"
    fi

    cp "${HOME}/.spack/compilers.yaml" "${HOME}"
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
    set -- "${stages}"
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

[[ ${do_generate} != "no" ]] && generate_specs "$@"
for what in ${stages}; do
    if [[ ${desired[${what}]+_} && ${do_install} != "no" ]]; then
        install_specs ${what}
    fi
done
