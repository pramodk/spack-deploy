#!/bin/bash
set +e
source "setup_env.sh"


create_mirror() {
    package_list=$1
    to_be_installed=$(spack filter --not-installed $(cat $package_list))

    if [[ -z "${to_be_installed}" ]]
    then
        echo "All specs already installed"
    else
        echo "Populating mirror"
        spack mirror create -D -d ${SPACK_MIRROR_DIR} $to_be_installed
    fi
}


cd $WORKSPACE/HOME_DIR/spack-deploy
for category in "${package_categories[@]}"
do
    # skip compilers for now
    if [[ $category = *"compilers"* ]]; then
        continue
    fi

    package_list=`basename $category .yaml`.txt
    echo "Creating mirror for packages in category $category"
    create_mirror $package_list
done

# register mirror with spack
spack mirror add --scope=site central_mirror ${SPACK_MIRROR_DIR} || echo "Scope already added!"

echo -e "Mirror creation finished"
