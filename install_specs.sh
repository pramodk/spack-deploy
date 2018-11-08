#!/bin/bash
set -e
source "setup_env.sh"

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
        spack install --log-format=junit --log-file=${category}.xml ${to_be_installed}
        #spack filter --not-installed $(cat $package_list) > todo.txt
        #while read -r package
        #do
        #    spack spec -Il ${package}
        #    spack install --log-format=junit --log-file=${category}.xml ${package}
        #done < todo.txt
    fi
}

# use mirror with spack
spack mirror add --scope=site central_mirror ${SPACK_MIRROR_DIR} || echo "Scope already added!"

cd $WORKSPACE/HOME_DIR/spack-deploy
for category in "${package_categories[@]}"
do
    # skip compilers for now
    if [[ $category = *"compilers"* ]]; then
        continue
    fi

    package_list=`basename $category .yaml`.txt
    echo "Installing packages in category $category"
    install_specs $package_list $category
done

echo -e "All specs installed"
