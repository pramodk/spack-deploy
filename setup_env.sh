#!/bin/bash

############################## SPACK REPOSITORY #############################
export WORKSPACE=`pwd`

echo "
=====================================================================
Preparing environment...
====================================================================="

export PATH=`pwd`:$PATH
export WORKSPACE=`pwd`/workspace
export SOFTS_DIR_PATH=$WORKSPACE/deployment
mkdir -p $WORKSPACE/HOME_DIR $SOFTS_DIR_PATH $SPACK_MIRROR_DIR

# TODO : Change this
#export SPACK_MIRROR_DIR=$WORKSPACE/mirror
export SPACK_MIRROR_DIR=/gpfs/bbp.cscs.ch/apps/hpc/test/central-mirror

# new $HOME to avoid conflict with ~/.spack
export HOME=$WORKSPACE/HOME_DIR
#rm -rf $HOME/.spack
cd $HOME

# clone both spack related repos
if [ ! -d spack ]; then
    git clone https://github.com/BlueBrain/spack.git -b fix/python-packages
    git clone https://github.com/pramodk/spack-deploy.git -b base-packages
    git clone ssh://bbpcode.epfl.ch/user/kumbhar/spack-licenses spack/etc/spack/licenses
fi

export SPACK_ROOT=`pwd`/spack
export PATH=$SPACK_ROOT/bin:$PATH

# copy config files
mkdir -p $SPACK_ROOT/etc/spack/defaults/linux
cp $WORKSPACE/HOME_DIR/spack-deploy/configs/packages.yaml $SPACK_ROOT/etc/spack/defaults/linux/
cp $WORKSPACE/HOME_DIR/spack-deploy/configs/config.yaml $SPACK_ROOT/etc/spack/defaults/linux/

source $SPACK_ROOT/share/spack/setup-env.sh

# create virtualenv
SPACKD_VIRTUALENV_PATH=`pwd`/venv
if [ ! -d $SPACKD_VIRTUALENV_PATH ]; then
    virtualenv -p $(which python) ${SPACKD_VIRTUALENV_PATH} --clear
    . ${SPACKD_VIRTUALENV_PATH}/bin/activate
    curl https://bootstrap.pypa.io/get-pip.py | python
fi

. ${SPACKD_VIRTUALENV_PATH}/bin/activate
pip install -U spack-deploy/

# create list of all packages
declare -a package_categories=(compilers.yaml system-tools.yaml serial-libraries.yaml python-packages.yaml parallel-libraries.yaml bbp-packages.yaml)

cd $WORKSPACE/HOME_DIR/spack-deploy
for config in "${package_categories[@]}"
do
    package_list=`basename $config .yaml`.txt
    spackd --input packages/$config packages x86_64 --output $package_list
done

deactivate

# use mirror with spack
spack mirror add --scope=site central_mirror ${SPACK_MIRROR_DIR} || echo "Mirror in scope already added!"
