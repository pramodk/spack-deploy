#!/bin/bash
set -e
source "setup_env.sh"

timestamp=`date +"%a-%d-%m-%Y-%H-%M"`

configure_compilers() {
    GCC_DIR=`spack location --install-dir gcc@6.4.0`

    if [ ! -d $GCC_DIR ]; then
        echo "Error : gcc@6.4.0 not installed ?"
        exit 1
    fi

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
                    echo "[CFG] Updated ${f} with newer GCC"
                fi
            done
        elif [[ ${line} = *"pgi"* ]]; then
            #update pgi modules for network installation (on uc2 nodes)
            PGI_DIR=$(dirname $(which makelocalrc))
            makelocalrc ${PGI_DIR} -gcc ${GCC_DIR}/bin/gcc -gpp ${GCC_DIR}/bin/g++ -g77 ${GCC_DIR}/bin/gfortran -x -net

            #configure pgi network license
            template=`find $PGI_DIR -name localrc* | tail -n 1`
            for node in bbpv1 bbpv2 r2i3n0 r2i3n1 r2i3n2 r2i3n3 r2i3n4 r2i3n5 r2i3n6
            do
                cp $template $PGI_DIR/localrc.$node || echo "Same file"
            done
        fi
        spack unload ${line}
    done

    sed  -i 's#.*f\(77\|c\): null#      f\1: /usr/bin/gfortran#' ${HOME}/.spack/compilers.yaml
}



install_specs() {
    package_list=$1
    category=$2
    to_be_installed=$(spack filter --not-installed $(cat $package_list))

    if [[ -z "${to_be_installed}" ]]
    then
        echo "All specs already installed"
    else
        echo "Installing packages "
        spack spec -Il ${to_be_installed}
        spack install --log-format=junit --log-file=${category}.${timestamp}.xml ${to_be_installed}
        #spack filter --not-installed $(cat $package_list) > todo.txt
        #while read -r package
        #do
        #    spack spec -Il ${package}
        #    spack install --log-format=junit --log-file=${category}.xml ${package}
        #done < todo.txt

        if [[ $category = *"compilers"* ]]; then
            echo "Configuring compilers "
            configure_compilers <<< "${to_be_installed}"
        fi
    fi
}

# unset mpi variables
unset `env | awk -F= '/^\w/ {print $1}' | egrep '(PMI|SLURM_)' | xargs`

cd $WORKSPACE/HOME_DIR/spack-deploy
for category in "${package_categories[@]}"
do
    package_list=`basename $category .yaml`.txt
    echo "Installing packages in category $category"
    install_specs $package_list $category
done

echo -e "All specs installed"
