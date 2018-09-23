#!/bin/bash -l

# This script assumes that the following variables are set in the environment:
#
# SPACKD_VIRTUALENV_PATH: path where to setup the virtualenv for "spackd"
# SPACK_CHECKOUT_DIR: path where Spack was cloned
#

SPACK_MIRROR_DIR=/ssoft/spack/mirror

# Activate 'spackd' and source Spack setup file
. ${SPACK_CHECKOUT_DIR}/share/spack/setup-env.sh
spack --version

. ${SPACKD_VIRTUALENV_PATH}/bin/activate

# Generate the list of software that need to be installed, then fetch every tarball
for target in $(spackd targets)
do
    echo "[${target}] Computing list of packages"
    spackd packages ${target} --output="all_specs.${target}.txt"

    echo "[${target}] Selecting the ones still to be installed"
    # TODO: if concretization is slow this command could output also the yaml file
    SPACK_TARGET_TYPE="${target}" spack filter --not-installed $(cat all_specs.${target}.txt) > to_be_installed.${target}.txt
    # TODO: stash concretized file to reduce deployment time later
    #echo "[${target}] Writing concretized yaml file"
    #spack spec -y $(cat to_be_installed.${target}.txt) > specs.${target}.yaml
    # TODO: read directly from a yaml file to avoid concretization slowdowns
    echo "[${target}] Populating central mirror"
    while read -r line
    do
        echo "spack mirror create -D -d ${SPACK_MIRROR_DIR} ${line}"
        SPACK_TARGET_TYPE="${target}" spack mirror create -D -d ${SPACK_MIRROR_DIR} ${line}
    done < to_be_installed.${target}.txt
done
