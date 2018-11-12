#!/bin/bash -l

# This script assumes that the following variables are set in the environment:
#
# DEPLOYMENT_ROOT: path to deploy to

DEFAULT_DEPLOMENT_DIR=/gpfs/bbp.cscs.ch/ssd/tmp_compile/deploy_test
DEPLOYMENT_ROOT=${DEPLOYMENT_ROOT:-${DEFAULT_DEPLOMENT_DIR}}

export DEPLOYMENT_ROOT

DEPLOY=${DEPLOY:-applications}
declare -A PARENTS=([tools]=compilers [libraries]=tools [applications]=libraries)

case "${DEPLOY}" in
    compilers)
        ;;
    tools)
        ;;
    libraries)
        ;;
    applications)
        ;;
    *)
        echo "\$DEPLOY needs to be set to one of: compilers, tools, libraries, applications!"
        exit 1
esac

HOME="${DEPLOYMENT_ROOT}/${DEPLOY}/data"
STACK="${DEPLOYMENT_ROOT}/${DEPLOY}/data/stack.xml"
PACKAGES="${DEPLOYMENT_ROOT}/${DEPLOY}/packages.yaml"

export HOME

mkdir -p "${HOME}/.spack/linux" $(dirname "${STACK}") $(dirname "${PACKAGES}")

cp -r configs/*.yaml "${HOME}/.spack/linux"

if [[ -n "${PARENTS[$DEPLOY]}" ]]; then
    cp "${DEPLOYMENT_ROOT}/${PARENTS[$DEPLOY]}/data/packages.yaml" "${HOME}/.spack/linux"
    cp "${DEPLOYMENT_ROOT}/${PARENTS[$DEPLOY]}/data/compilers.yaml" "${HOME}/.spack/linux"
fi

. ${DEPLOYMENT_ROOT}/spack/share/spack/setup-env.sh

export SOFTS_DIR_PATH="${DEPLOYMENT_ROOT}/${DEPLOY}"
export HOME=/tmp/

TO_BE_INSTALLED=$(spack filter --not-installed $(<"${HOME}/specs.txt"))

if [[ -n "$TO_BE_INSTALLED" ]]; then
    spack -C "${SCOPE}" spec -Il ${TO_BE_INSTALLED}
    spack -C "${SCOPE}" install --log-format=junit --log-file=${STACK} ${TO_BE_INSTALLED}
else
    echo "[packages for ${DEPLOY} already installed]"
    cp resources/success.xml "${STACK}"
fi

spack export > "${PACKAGES}"

if [[ "${DEPLOY}" == "compilers" ]]; then
fi
