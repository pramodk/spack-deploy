#!/bin/bash -l

# This script assumes that the following variables are set in the environment:
#
# SPACKD_VIRTUALENV_PATH: path where to setup the virtualenv for "spackd"
# SPACK_CHECKOUT_DIR: path where Spack was cloned
#

# Recreate the virtualenv and update the command line
mkdir -p ${SPACKD_VIRTUALENV_PATH}
virtualenv --version
virtualenv -p $(which python) ${SPACKD_VIRTUALENV_PATH} --clear
. ${SPACKD_VIRTUALENV_PATH}/bin/activate
pip install --force-reinstall -U .
spackd --help

# Copy configuration files into the correct place
cp -v configuration/* ${SPACK_CHECKOUT_DIR}/etc/spack/
cp -v -r external/* /ssoft/spack/external/
