#!/bin/bash
#
# Copyright 2020, Data61/CSIRO
#
# SPDX-License-Identifier: BSD-2-Clause
#

set -exuo pipefail

# Source common functions
DIR="${BASH_SOURCE%/*}"
test -d "$DIR" || DIR=$PWD
# shellcheck source=utils/common.sh
. "$DIR/utils/common.sh"

# Don't make caches by default. Docker will set this to be 'yes'
: "${MAKE_CACHES:=no}"

# By default, assume we are on a desktop (usually less destructive)
: "${DESKTOP_MACHINE:=yes}"

# Docker may set this variable - fill if not set
: "${SCM:=https://github.com}"

# tmp space for building
: "${TEMP_DIR:=/tmp}"

# Default locale/language config if not set elsewhere
: "${DEFAULT_LOCALE:='en_US.UTF-8 UTF-8'}"
: "${DEFAULT_LANG:='en_US.UTF-8'}"
: "${DEFAULT_LANGUAGE:='en_US:en:C'}"
: "${DEFAULT_KBLAYOUT:='fi'}"

# Add additional architectures for cross-compiled libraries.
# Install the tools required to compile seL4.
as_root apt-get update -q
as_root dpkg --add-architecture armhf
as_root dpkg --add-architecture armel
as_root apt-get install -y --no-install-recommends \
    astyle=3.1-2+b1 \
    build-essential \
    ccache \
    cmake \
    cmake-curses-gui \
    coreutils \
    cpio \
    curl \
    device-tree-compiler \
    doxygen \
    libarchive-dev \
    libcc1-0 \
    libncurses-dev \
    libuv1 \
    libxml2-utils \
    locales \
    ninja-build \
    protobuf-compiler \
    python3-protobuf \
    qemu-system-x86 \
    sloccount \
    u-boot-tools \
    clang-11 \
    g++-10 \
    g++-10-aarch64-linux-gnu \
    g++-10-arm-linux-gnueabi \
    g++-10-arm-linux-gnueabihf \
    gcc-10 \
    gcc-10-aarch64-linux-gnu \
    gcc-10-arm-linux-gnueabi \
    gcc-10-arm-linux-gnueabihf \
    gcc-10-base \
    gcc-10-multilib \
    gcc-riscv64-unknown-elf \
    libclang-11-dev \
    qemu-system-arm \
    qemu-system-misc
    # end of list

if [ "$DESKTOP_MACHINE" = "no" ] ; then
    compiler_version=10

    # Set default compiler to be gcc-$compiler_version using update-alternatives
    # This is necessary particularly for the cross-compilers, which don't put
    # a genericly named version of themselves in the PATH.
    for compiler in gcc \
                    g++ \
                    # end of list
        do
        for file in $(dpkg-query -L ${compiler} | grep /usr/bin/); do
            name=$(basename "$file")
            echo "$name - $file"
            as_root update-alternatives --install "$file" "$name" "$file-$compiler_version" 50 || :  # don't stress if it doesn't work
            as_root update-alternatives --auto "$name" || :
        done
    done

    for compiler in gcc-${compiler_version}-arm-linux-gnueabi \
                    cpp-${compiler_version}-arm-linux-gnueabi \
                    g++-${compiler_version}-arm-linux-gnueabi \
                    gcc-${compiler_version}-aarch64-linux-gnu \
                    cpp-${compiler_version}-aarch64-linux-gnu \
                    g++-${compiler_version}-aarch64-linux-gnu \
                    gcc-${compiler_version}-arm-linux-gnueabihf \
                    cpp-${compiler_version}-arm-linux-gnueabihf \
                    g++-${compiler_version}-arm-linux-gnueabihf \
                    # end of list
    do
        echo ${compiler}
        for file in $(dpkg-query -L ${compiler} | grep /usr/bin/); do
            name=$(basename "$file" | sed "s/-${compiler_version}\$//g")
            # shellcheck disable=SC2001
            link=$(echo "$file" | sed "s/-${compiler_version}\$//g")
            echo "$name - $file"
            (
                as_root update-alternatives --install "${link}" "${name}" "${file}" 60 && \
                as_root update-alternatives --auto "${name}"
            ) || : # Don't worry if this fails
        done
    done

    # Ensure that clang-11 shows up as clang
    for compiler in clang \
                    clang++ \
                    # end of list
        do
            as_root update-alternatives --install /usr/bin/"$compiler" "$compiler" "$(which "$compiler"-11)" 60 && \
            as_root update-alternatives --auto "$compiler"
    done
    # Do a quick check to make sure it works:
    clang --version
fi

# Get seL4 python3 deps
# Pylint is for checking included python scripts
# Setuptools sometimes is a bit flaky, so double checking it is installed here
as_root pip3 install --no-cache-dir \
    setuptools
as_root pip3 install --no-cache-dir \
    pylint \
    sel4-deps
    # end of list


if [ "$MAKE_CACHES" = "yes" ] ; then
    # Build seL4test for a few platforms to populate binary artifact caches.
    # This should improve build times by caching libraries that rarely change.
    mkdir -p ~/.sel4_cache
    try_nonroot_first mkdir -p "$TEMP_DIR/sel4test" || chown_dir_to_user "$TEMP_DIR/sel4test"
    pushd "$TEMP_DIR/sel4test"
        repo init -u "${SCM}/seL4/sel4test-manifest.git" --depth=1
        repo sync -j 4
        mkdir build
        pushd build
            for plat in "sabre" "ia32" "x86_64" "tx1" "tk1 -DARM_HYP=ON"; do
                # shellcheck disable=SC2086  # no "" around plat, so HYP still works
                ../init-build.sh -DPLATFORM=$plat
                ninja
                rm -rf ./*
            done
        popd
    popd
    rm -rf sel4test
fi

if [ "$DESKTOP_MACHINE" = "no" ] ; then

    # Set up locale/language config
    printf '%s' "$DEFAULT_LOCALE" | as_root tee /etc/locale.gen > /dev/null
    printf 'LANG=%s' "$DEFAULT_LANG" | as_root tee /etc/default/locale > /dev/null
    printf 'LANGUAGE=%s' "$DEFAULT_LANGUAGE" | as_root tee -a /etc/default/locale > /dev/null
    as_root dpkg-reconfigure --frontend=noninteractive locales
    as_root locale-gen
    as_root update-locale LANG="$DEFAULT_LANG"
    printf 'export LANG=%s' "$DEFAULT_LANG" >> "$HOME/.bashrc"
    printf 'export LANGUAGE=%s' "$DEFAULT_LANGUAGE" >> "$HOME/.bashrc"

    # Setup default keyboard layout just in case.
    as_root apt-get install -y --no-install-recommends keyboard-configuration
    printf '%s\n' \
        "# KEYBOARD CONFIGURATION FILE" \
        "# Consult the keyboard(5) manual page." \
        "" \
        "XKBMODEL=\"pc105\"" \
        "XKBLAYOUT=\"$DEFAULT_KBLAYOUT\"" \
        "XKBVARIANT=\"\"" \
        "XKBOPTIONS=\"\"" \
        "" \
        "BACKSPACE=\"guess\"" | as_root tee /etc/default/keyboard > /dev/null
    as_root dpkg-reconfigure --frontend=noninteractive keyboard-configuration

fi

# If we have been using Debian Snapshot, then we need to switch
# back to using the normal apt repos, for anyone using the image after this point.
possibly_toggle_apt_snapshot
