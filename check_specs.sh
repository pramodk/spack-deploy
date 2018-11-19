#!/bin/bash
set +e
source "setup_env.sh"


check_specs() {
    package_list=$1
    to_be_installed=$(spack filter --not-installed $(cat $package_list))

    if [[ -z "${to_be_installed}" ]]
    then
        echo "All specs already installed"
    else
        echo "spack spec -Il $to_be_installed"
        spack spec -Il $to_be_installed
    fi
}


cd $WORKSPACE/HOME_DIR/spack-deploy
for category in "${package_categories[@]}"
do
    package_list=`basename $category .yaml`.txt
    echo "Checking installed packages in category $category"
    check_specs $package_list
done


echo -e "Spec concretisation check finished"
