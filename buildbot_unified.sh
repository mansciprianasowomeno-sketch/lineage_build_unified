#!/bin/bash
echo ""
echo "LineageOS 19.x Unified Buildbot (Wiko W-K510 Patch Integrated)"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

if [ $# -lt 2 ]
then
    echo "Not enough arguments - exiting"
    echo ""
    exit 1
fi

MODE=${1}
if [ ${MODE} != "device" ] && [ ${MODE} != "treble" ]
then
    echo "Invalid mode - exiting"
    echo ""
    exit 1
fi

NOSYNC=false
PERSONAL=false
for var in "${@:2}"
do
    if [ ${var} == "nosync" ]
    then
        NOSYNC=true
    fi
    if [ ${var} == "personal" ]
    then
        PERSONAL=true
    fi
done

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
WITHOUT_CHECK_API=true
WITH_SU=true

prep_build() {
    echo "Preparing local manifests"
    mkdir -p .repo/local_manifests
    cp ./lineage_build_unified/local_manifests_${MODE}/*.xml .repo/local_manifests 2>/dev/null || true
    echo ""

    echo "Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
    echo ""

    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    mkdir -p ~/build-output
    echo ""

    repopick -t twelve-monet || true
    repopick -Q "status:open+project:LineageOS/android_packages_apps_AudioFX+branch:lineage-19.0" || true
    repopick -Q "status:open+project:LineageOS/android_packages_apps_Etar+branch:lineage-19.0+NOT+317685" || true
    repopick -Q "status:open+project:LineageOS/android_packages_apps_Trebuchet+branch:lineage-19.0+NOT+317783+NOT+318387" || true
    repopick 318971 || true # Move Seedvault to /system_ext partition
}

apply_patches() {
    echo "Applying patch group ${1}"
    if [ -d "~/treble_experimentations/apply-patches.sh" ]; then
        bash ~/treble_experimentations/apply-patches.sh ./lineage_patches_unified/${1}
    elif [ -f "apply-patches.sh" ]; then
        bash apply-patches.sh ./lineage_patches_unified/${1}
    fi
}

prep_device() {
    :
}

prep_treble() {
    apply_patches patches_treble_prerequisite
    apply_patches patches_treble_phh
}

finalize_device() {
    :
}

finalize_treble() {
    rm -f device/*/sepolicy/common/private/genfs_contexts
    if [ -d "device/phh/treble" ]; then
        cd device/phh/treble
        git clean -fdx
        
        # INIETTA DIRETTAMENTE IL FIX NON-SPARSE PER WIKO Y60 (W-K510)
        echo "TARGET_USERIMAGES_SPARSE_EXT_DISABLED := true" >> board/board.mk
        echo "BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1073741824" >> board/board.mk
        
        bash generate.sh lineage
        cd ../../..
    fi
}

build_device() {
    if [ ${1} == "arm64" ]
    then
        lunch lineage_arm64-userdebug
        make -j$(nproc --all) systemimage
        mv $OUT/system.img ~/build-output/lineage-19.0-$BUILD_DATE-UNOFFICIAL-arm64$(${PERSONAL} && echo "-personal" || echo "").img
    else
        brunch ${1}
        mv $OUT/lineage-*.zip ~/build-output/lineage-19.0-$BUILD_DATE-UNOFFICIAL-${1}$($PERSONAL && echo "-personal" || echo "").zip
    fi
}

build_treble() {
    case "${1}" in
        ("A64B") TARGET=treble_a64_bvS;;
        ("A64BG") TARGET=treble_a64_bgS;;
        ("64B") TARGET=treble_arm64_bvS;;
        ("64BG") TARGET=treble_arm64_bgS;;
        (*) echo "Invalid target - exiting"; exit 1;;
    esac
    lunch lineage_${TARGET}-userdebug
    make installclean
    make -j$(nproc --all) systemimage
    mv $OUT/system.img ~/build-output/lineage-19.0-$BUILD_DATE-UNOFFICIAL-${TARGET}$(${PERSONAL} && echo "-personal" || echo "").img
    make vndk-test-sepolicy || true
}

if ${NOSYNC}
then
    echo "ATTENTION: syncing/patching skipped!"
    echo ""
    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    echo ""
else
    prep_build
    echo "Applying patches"
    prep_${MODE}
    apply_patches patches_platform
    apply_patches patches_${MODE}
    if ${PERSONAL}
    then
        apply_patches patches_platform_personal
        apply_patches patches_${MODE}_personal
    fi
    finalize_${MODE}
    echo ""
fi

for var in "${@:2}"
do
    if [ ${var} == "nosync" ] \vert{}\vert{} [ ${var} == "personal" ]
    then
        continue
    fi
    echo "Starting $(${PERSONAL} && echo "personal " || echo "")build for ${MODE}${var}"
    build_${MODE}${var}
done
ls ~/build-output | grep 'lineage' || true

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and$ELAPSEDS seconds"
echo ""
