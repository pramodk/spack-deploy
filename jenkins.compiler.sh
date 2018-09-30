#!/bin/bash
set -e

error() {
    set +x
    echo -e "[FATAL] Command returned $1."
    exit 1
}

trap 'error ${?}' ERR


############################## CREATE VIRTUAL ENV #############################
SPACK_DEPLOY_DIR=`pwd`
SPACKD_VIRTUALENV_PATH=$SPACK_DEPLOY_DIR/spackd-env
rm -rf $SPACK_DEPLOY_DIR/spackd-env
virtualenv -p $(which python) ${SPACKD_VIRTUALENV_PATH} --clear
. ${SPACKD_VIRTUALENV_PATH}/bin/activate
pip install --force-reinstall -U .

group="packages/compiler-packages.yaml"
targets="$(spackd --input ${group} targets)"
for target in ${targets}
do
    echo "[${target}] Checking list of packages to be tested"
    spackd --input ${group} packages ${target} --output="all.compilers.${target}.txt"
done

deactivate


############################### SETUP BUILD ENVIRONMENT ###############################
export WORKSPACE=/gpfs/bbp.cscs.ch/ssd/tmp_compile/$USER/deployment/compilers
export DOWNLOAD=/gpfs/bbp.cscs.ch/data/project/proj20/pramod_scratch/SPACK_DEPLOYMENT/download
export SOFTS_DIR_PATH=$WORKSPACE
export SPACK_MIRROR_DIR=$SOFTS_DIR_PATH/mirror
mkdir -p $WORKSPACE/HOME_DIR


################################ CLEANUP SPACK CONFIGS ################################
export HOME=$SOFTS_DIR_PATH/HOME_DIR
cd $HOME
rm -rf $HOME/.spack


################################# CLONE SPACK REPOSITORY ##############################
if [ ! -d spack ]; then
    SPACK_REPO=https://github.com/BlueBrain/spack.git
    SPACK_BRANCH="rebase/092018"
    git clone $SPACK_REPO --single-branch -b $SPACK_BRANCH
    git clone ssh://bbpcode.epfl.ch/user/kumbhar/spack-licenses spack/etc/spack/licenses
fi
export SPACK_ROOT=`pwd`/spack
export PATH=$SPACK_ROOT/bin:$PATH


################################### SETUP PACKAGE CONFIGS ##############################
cd $SPACK_DEPLOY_DIR
mkdir -p $SPACK_ROOT/etc/spack/defaults/linux
cp configs/compilers/* $SPACK_ROOT/etc/spack/defaults/linux/
source $SPACK_ROOT/share/spack/setup-env.sh

echo "Processing package group from $group"


################################## BUILD MIRROR FOR PACKAGES #############################
# copy commercial compiler tarball
for compiler in intel intel-parallel-studio pgi
do
    mkdir -p ${SPACK_MIRROR_DIR}/${compiler}
    cp ${DOWNLOAD}/${compiler}/* ${SPACK_MIRROR_DIR}/${compiler}/
done

for target in ${targets}
do
    echo "[${target}] Populating central mirror"
    while read -r package
    do
        echo "spack mirror create -D -d ${SPACK_MIRROR_DIR} ${package}"
        spack mirror create -D -d ${SPACK_MIRROR_DIR} ${package}
    done < all.compilers.${target}.txt

done

# register mirror with spack
spack mirror add --scope=site compiler_mirror ${SPACK_MIRROR_DIR} || echo "Scope already added!"


################################## BUILD COMPILERS #############################
spack reindex
for target in ${targets}
do
    to_be_installed=$(spack filter --not-installed $(cat all.compilers.${target}.txt))

    if [[ -z "${to_be_installed}" ]]
    then
        echo "[${target}] All compilers already installed"
        cp resources/success.xml compilers.${target}.xml
    else
        spack spec -Il $(cat compilers.${target}.txt)
        spack install --log-format=junit --log-file=compilers.${target}.xml ${to_be_installed}
    fi
done


################################## PREPARE compilers.yaml #############################
while read -r line
do
    if [[ $line = *"intel-parallel-studio"* ]]; then
        continue
    fi
    spack load $line
    spack compiler find --scope=site
    module purge
done < all.compilers.${target}.txt


############################### USE GCC@6.4.0 AS DEFAULT #############################
GCC_DIR=`spack location --install-dir gcc@6.4.0`
while read -r line
do
    spack load $line

    # update intel modules to use gcc@6.4.0 in .cfg files
    if [[ $line = *"intel"* ]]; then
        install_dir=`spack location --install-dir $line`
        for f in $(find $install_dir -name "icc.cfg" -o -name "icpc.cfg" -o -name "ifort.cfg"); do
            if ! grep -q "$GCC_DIR" $f; then
                echo "-gcc-name=$GCC_DIR/bin/gcc" >> $f
                echo "-Xlinker -rpath=$GCC_DIR/lib" >> $f
                echo "-Xlinker -rpath=$GCC_DIR/lib64" >> $f
                echo "[CFG] Updated $f with newer GCC"
            fi
        done
    fi

    #update pgi modules for network installation
    if [[ $line = *"pgi"* ]]; then
        PGI_DIR=$(dirname $(which makelocalrc))
        makelocalrc $PGI_DIR -gcc $GCC_DIR/bin/gcc -gpp $GCC_DIR/bin/g++ -g77 $GCC_DIR/bin/gfortran -x -net
    fi
    spack unload $line
done < all.compilers.${target}.txt


################################## COPY compilers.yaml #############################
cp $SPACK_ROOT/etc/spack/compilers.yaml .
sed  -i 's#.*f77: null#      f77: /usr/bin/gfortran#' compilers.yaml
sed  -i 's#.*fc: null#      fc: /usr/bin/gfortran#' compilers.yaml
echo -e "COMPILERS CONFIG READY : `pwd`/compilers.yaml "


echo -e "ALL COMPILERS INSTALLED"
