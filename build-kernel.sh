
#! /bin/bash
# shellcheck disable=SC2154
# shellcheck disable=SC2199
# shellcheck disable=SC2086
# shellcheck source=/dev/null
#
# Copyright (C) 2020-22 UtsavBalar1231 <utsavbalar1231@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

cd /drone/src/ || exit

HOME="/drone/src"

if [[ "$@" =~ "gcc"* ]]; then
    KBUILD_COMPILER_STRING=$(${HOME}/gcc64/bin/aarch64-elf-gcc --version | head -n1 | sed -e 's/aarch64-elf-gcc\ //' | perl -pe 's/\(//gs' | perl -pe 's/\)//gs')
    KBUILD_LINKER_STRING=$(${HOME}/gcc64/bin/aarch64-elf-ld --version | head -n1 | perl -pe 's/\(//gs' | perl -pe 's/\)//gs')
else
    KBUILD_COMPILER_STRING=$(${HOME}/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
    KBUILD_LINKER_STRING=$(${HOME}/clang/bin/ld.lld --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' | sed 's/(compatible with [^)]*)//')
fi

export KBUILD_COMPILER_STRING
export KBUILD_LINKER_STRING

#
# Enviromental Variables
#

# Set the last commit author
AUTHOR=$(git log -n 1 --pretty=format:'%an')

# Set the current branch name
BRANCH=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)

# Set the last commit sha
COMMIT=$(git rev-parse --short HEAD)

# Set current date
DATE=$(date +"%d.%m.%y")

# Set Kernel link
KERNEL_LINK=https://github.com/KazuDante89/android_kernel_lisa

# Set Kernel Version
KERNELVER=$(make kernelversion)

# Set Post Message
MESSAGE="$AUTHOR: $REF$KERNEL_LINK/commit/$COMMIT"

# Set our directory
OUT_DIR=out/

if [[ "$@" =~ "gcc"* ]]; then
    VERSION=$(echo "${KBUILD_COMPILER_STRING}" | awk '{print $1,$2,$3}')
elif [[ "$@" =~ "aosp-clang"* ]]; then
    if [[ -f ${HOME}/clang/AndroidVersion.txt ]]; then
        VERSION=$(cat ${HOME}/clang/AndroidVersion.txt | head -1)
    fi
else
    VERSION=""
fi
export VERSION

# Set Compiler
if [[ "$@" =~ "gcc"* ]]; then
    COMPILER=${VERSION}
elif [[ "$@" =~ "aosp-clang"* ]]; then
    COMPILER="AOSP Clang ${VERSION}"
else
    COMPILER="Proton Clang ${VERSION}"
fi
export COMPILER

# Get reference string
REF=$(echo "${BRANCH}" | grep -Eo "[^ /]+\$")

CSUM=$(cksum <<<${COMMIT} | cut -f 1 -d ' ')

# Select LTO or non LTO builds
if [[ "$@" =~ "lto"* ]]; then
    VERSION="Phantom-X-${DEVICE^^}-${TYPE}-LTO-${DATE}"
else
    VERSION="Phantom-X-${DEVICE^^}-${TYPE}-${DATE}"
fi

# Export Zip name
export ZIPNAME="${VERSION}.zip"

# How much kebabs we need? Kanged from @raphielscape :)
if [[ -z "${KEBABS}" ]]; then
    COUNT="$(grep -c '^processor' /proc/cpuinfo)"
    export KEBABS="$((COUNT * 2))"
fi

if [[ "$@" =~ "gcc"* ]]; then
    ARGS="ARCH=arm64 \
    O=${OUT_DIR} \
    CROSS_COMPILE=aarch64-elf- \
    CROSS_COMPILE_COMPAT=arm-eabi- \
    -j${KEBABS}
    "
else
    ARGS="ARCH=arm64 \
    O=${OUT_DIR} \
    LLVM=1 \
    LLVM_IAS=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    -j${KEBABS}
"
fi

dts_source=arch/arm64/boot/dts/vendor/qcom

# Post to CI channel
function tg_post_msg() {
    # curl -s -X POST https://api.telegram.org/bot"${BOT_API_KEY}"/sendAnimation -d animation="https://media.giphy.com/media/PPgZCwZPKrLcw75EG1/giphy.gif" -d chat_id="${CHAT_ID}"
    curl -s -X POST https://api.telegram.org/bot"${BOT_API_KEY}"/sendMessage -d text="<code>IMMENSITY Automated build</code>
<b>BUILD TYPE</b> : <code>${TYPE}</code>
<b>DEVICE</b> : <code>${DEVICE}</code>
<b>COMPILER</b> : <code>${COMPILER}</code>
<b>KERNEL VERSION</b> : <code>${KERNELVER}</code>
<i>Build started on Drone Cloud!</i>
<a href='https://cloud.drone.io/UtsavBalar1231/kernel_xiaomi_sm8250/${DRONE_BUILD_NUMBER}'>Check the build status here</a>" -d chat_id="${CHAT_ID}" -d parse_mode=HTML
}

function tg_post_error() {
    curl -s -X POST https://api.telegram.org/bot"${BOT_API_KEY}"/sendMessage -d text="Error in ${DEVICE}: $1 build!!" -d chat_id="${CHAT_ID}"
    curl -F chat_id="${CHAT_ID}" -F document=@"$(pwd)/build.log" https://api.telegram.org/bot"${BOT_API_KEY}"/sendDocument
    exit 1
}

function enable_lto() {
    if [ "$1" == "gcc" ]; then
        scripts/config --file ${OUT_DIR}/.config \
            -e LTO_GCC \
            -e LD_DEAD_CODE_DATA_ELIMINATION \
            -d MODVERSIONS
    else
        scripts/config --file ${OUT_DIR}/.config \
            -e LTO_CLANG
    fi

    # Make olddefconfig
    cd ${OUT_DIR} || exit
    make -j${KEBABS} ${ARGS} olddefconfig
    cd ../ || exit
}

function disable_lto() {
    if [ "$1" == "gcc" ]; then
        scripts/config --file ${OUT_DIR}/.config \
            -d LTO_GCC \
            -d LD_DEAD_CODE_DATA_ELIMINATION \
            -e MODVERSIONS
    else
        scripts/config --file ${OUT_DIR}/.config \
            -d LTO_CLANG
    fi
}

function pack_image_build() {
    mkdir -p anykernel/kernels/$1

    # Check if the kernel is built
    if [[ -f ${OUT_DIR}/System.map ]]; then
        if [[ -f ${OUT_DIR}/arch/arm64/boot/Image.gz ]]; then
            cp ${OUT_DIR}/arch/arm64/boot/Image.gz anykernel/kernels/$1
        elif [[ -f ${OUT_DIR}/arch/arm64/boot/Image ]]; then
            cp ${OUT_DIR}/arch/arm64/boot/Image anykernel/kernels/$1
        else
            tg_post_error $1
        fi
    else
        tg_post_error $1
    fi

    cp ${OUT_DIR}/arch/arm64/boot/Image anykernel/$1
    cp ${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/yupik.dtb anykernel/$1
    cp ${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/lisa-sm7325-overlay.dtbo anykernel/$1
}

START=$(date +"%s")

tg_post_msg

# Set compiler Path
if [[ "$@" =~ "gcc"* ]]; then
    PATH=${HOME}/gcc64/bin:${HOME}/gcc32/bin:${PATH}
elif [[ "$@" =~ "aosp-clang"* ]]; then
    PATH=${HOME}/gas:${HOME}/clang/bin/:$PATH
    export LD_LIBRARY_PATH=${HOME}/clang/lib64:${LD_LIBRARY_PATH}
else
    PATH=${HOME}/clang/bin/:${PATH}
fi

# Make defconfig
make -j${KEBABS} ${ARGS} "${DEVICE}"_defconfig

# AOSP Build
echo "------ Stating AOSP Build ------"
OS=aosp

if [[ "$@" =~ "lto"* ]]; then
    # Enable LTO
    if [[ "$@" =~ "gcc"* ]]; then
        enable_lto gcc
    else
        enable_lto clang
    fi

    # Make olddefconfig
    cd ${OUT_DIR} || exit
    make -j${KEBABS} ${ARGS} olddefconfig
    cd ../ || exit

fi

make -j${KEBABS} ${ARGS} 2>&1 | tee build.log
find ${OUT_DIR}/$dts_source -name '*.dtb' -exec cat {} + >${OUT_DIR}/arch/arm64/boot/dtb

pack_image_build ${OS}
echo "------ Finishing AOSP Build ------"

END=$(date +"%s")
DIFF=$((END - START))

cd anykernel || exit
zip -r9 "${ZIPNAME}" ./* -x .git .gitignore ./*.zip

RESPONSE=$(curl -# -F "name=${ZIPNAME}" -F "file=@${ZIPNAME}" -u :"${PD_API_KEY}" https://pixeldrain.com/api/file)
FILEID=$(echo "${RESPONSE}" | grep -Po '(?<="id":")[^"]*')

CHECKER=$(find ./ -maxdepth 1 -type f -name "${ZIPNAME}" -printf "%s\n")
if (($((CHECKER / 1048576)) > 5)); then
    curl -s -X POST https://api.telegram.org/bot"${BOT_API_KEY}"/sendMessage -d text="✅ Kernel compiled successfully in $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds for ${DEVICE}" -d chat_id="${CHAT_ID}" -d parse_mode=HTML
    curl -s -X POST https://api.telegram.org/bot"${BOT_API_KEY}"/sendMessage -d text="Kernel build link: https://pixeldrain.com/u/$FILEID" -d chat_id="${CHAT_ID}" -d parse_mode=HTML
    #    curl -F chat_id="${CHAT_ID}" -F document=@"$(pwd)/${ZIPNAME}" https://api.telegram.org/bot"${BOT_API_KEY}"/sendDocument
else
    tg_post_error
fi
cd "$(pwd)" || exit

# Cleanup
rm -fr anykernel/
