#!/bin/bash
#
# Copyright (c) 2015 Davide Guerri <davide.guerri@gmail.com>
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

set -e
set -u

# -------------------
COMPONENTS="main,restricted,universe,multiverse"
EXTRA_PACKAGES="openssh-server,acpid,sudo,cloud-init,cloud-initramfs-growroot"
INITIAL_SIZE_GB="8"
ARCH="amd64"
TARGET_DISK="/dev/sda"
NIC_LIST=(eth0)
IMAGE_DEVICE="/dev/nbd0"
DEBOOTSTRAP="debootstrap"
# -------------------

function usage() {
    echo -e "
$SCRIPT_NAME - Davide Guerri <davide.guerri@gmail.com>

Build ${BLU}Cloud${NC} Ubuntu images (${BLU}BM${NC} ${RED}and ${BLU}BM${NC})

Usage:

    $SCRIPT_NAME <build|cleanup|chroot> [<options>]

Commands:

    build       Build a new qcow2 image

        $SCRIPT_NAME build [-v <version>] [-p <path>] [-s <bash_script>]

        Opions:
            -v <version>    Version to build, e.g.: vivid, trusty, precise,
                            utopic, ... (Default: trusty)
            -p <path>       Directory to use asa working directory.
                            If it doesn't exist, a new directory will be
                            created. (Default <script directory>/rpii)
            -s <script>     Bash script to run right before umounting the
                            image. The script will be run in a chrooted
                            environment.
        Examples:
            $SCRIPT_NAME build
            $SCRIPT_NAME build -v vivid -p /tmp/myimage


    cleanup     Remove previous build directory (not including the image)

        $SCRIPT_NAME cleanup [-p <path>]

        Opions:
            -p <path>       Directory to use as a working directory.
                            (Default <script directory>/rpii)
        Examples:
            $SCRIPT_NAME cleanup
            $SCRIPT_NAME cleanup -p /tmp/myimage


    chroot      Chroot into the image. The image must have been already built.

        $SCRIPT_NAME chroot [-p <path>]

        Opions:
            -p <path>       Directory to use as a working directory.
                            (Default <script directory>/rpii)
        Examples:
            $SCRIPT_NAME chroot
            $SCRIPT_NAME chroot -p /tmp/myimage


" >&29
}

function build() {
    local build_dir image_path chroot_dir version script
    build_dir="$1"
    image_path="$2"
    chroot_dir="$3"
    version="$4"
    # shellcheck disable=SC2034
    script="${5:-}"

    if [ -n "$script" ]; then
        log "*** Sorry 'script' feature has not yet been implemented!"
    fi

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - build"

    trap '{ error "Something went wrong!"; cleanup "$chroot_dir"; exit 2; }' \
        EXIT
    trap '{ trap - EXIT; error "Interrupted"; cleanup "$chroot_dir";
            exit 3; }' SIGKILL SIGINT SIGTERM

    log "Strarting build of a ${YLW}$version${NC} box, arch ${YLW}$ARCH${NC}"
    log "Target disk: ${YLW}$TARGET_DISK${NC}"
    log "Network interface(s): ${YLW}${NIC_LIST[*]}${NC}"

    mkdir -p "$build_dir"

    log "Creating a ${YLW}${INITIAL_SIZE_GB}G${NC} qcow2 image"
    rm -f "$image_path"
    qemu-img create -f qcow2 "$image_path" "${INITIAL_SIZE_GB}G"

    log "Initializing nbd device $IMAGE_DEVICE"
    qemu-nbd -c "$IMAGE_DEVICE" "$image_path"

    log "Partitioning $IMAGE_DEVICE"
    sfdisk "$IMAGE_DEVICE" -D -uM <<EOF
,512,83,*
,,83
;
EOF
    partprobe "$IMAGE_DEVICE"

    log "Creating filesystems"
    mkfs.ext2 "${IMAGE_DEVICE}p1"
    mkfs.ext4 "${IMAGE_DEVICE}p2"

    log "Mounting filesystems"
    mkdir -p "$chroot_dir"
    mount "${IMAGE_DEVICE}p2" "$chroot_dir"

    log "Executing debootstrap (this will take a while)"
    $DEBOOTSTRAP --verbose --arch "$ARCH" --components="$COMPONENTS" \
        --include="$EXTRA_PACKAGES" "$version" "$chroot_dir" \
        http://archive.ubuntu.com/ubuntu/

    log "Preparing the chroot environment"
    mount "${IMAGE_DEVICE}p1" "$chroot_dir/boot"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"

    log "Creating /etc/fstab"
    cat <<EOF > $chroot_dir/etc/fstab
${TARGET_DISK}1   /boot   ext2    sync                0   2
${TARGET_DISK}2   /       ext4    errors=remount-ro   0   1
EOF

    log "Creating /etc/hostname"
    echo "ubuntu-$version" > "$chroot_dir/etc/hostname"

    log "Creating /etc/hosts"
    cat <<EOF > $chroot_dir/etc/hosts
127.0.0.1   localhost

# The following lines are desirable for IPv6 capable hosts
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

    log "Creating /etc/network/interfaces with interface(s): '${NIC_LIST[*]}'"
    cat <<EOF > $chroot_dir/etc/network/interfaces
auto lo
iface lo inet loopback
EOF

    for nic in "${NIC_LIST[@]}"; do
        cat <<EOF >> $chroot_dir/etc/network/interfaces

auto $nic
iface $nic inet dhcp
EOF
    done

    log "Giving a personal touch to the login screen (tty)"
    cp "$SCRIPT_DIR/extras/show-ip-address" \
        "$chroot_dir/etc/network/if-up.d/"
    chmod +x "$chroot_dir/etc/network/if-up.d/show-ip-address"

    log "Installing additional packages: grub and Linux kernel"
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" \
        apt-get install -y -q grub-pc linux-image-generic linux-firmware
    echo "GRUB_TERMINAL=console" >> "$chroot_dir/etc/default/grub"

    log "Installing grub (${IMAGE_DEVICE})"
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" \
        grub-install ${IMAGE_DEVICE}
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" update-grub

    log "Fixing grub configuration (using ${TARGET_DISK})"
    sed -i "s|${IMAGE_DEVICE}p|${TARGET_DISK}|g" \
        "$chroot_dir/boot/grub/grub.cfg"

    log "Cleaning up the image"
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" apt-get clean
    rm -f "$chroot_dir/etc/apt/sources.list.save" \
        "$chroot_dir/etc/resolvconf/resolv.conf.d/original" \
        "$chroot_dir/root/.bash_history" \
        "$chroot_dir/etc/*-" \
        "$chroot_dir/var/lib/urandom/random-seed" \
        "$chroot_dir/etc/machine-id"
    rm -rf "$chroot_dir/run/{.,}*" "$chroot_dir/tmp/{.,}*"
    [ -L "$chroot_dir/var/lib/dbus/machine-id" ] || \
        rm -f "$chroot_dir/var/lib/dbus/machine-id"

    log "******* your image is ready: '$image_path' *******"

    trap - SIGKILL SIGINT SIGTERM EXIT
}

function mount_stuff() {
    mount "${IMAGE_DEVICE}p2" "$chroot_dir"
    mount "${IMAGE_DEVICE}p1" "$chroot_dir/boot"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"
}

function umount_stuff() {
    local chroot_dir
    chroot_dir="$1"

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - umount_stuff"

    set +e
    lsof -t "$chroot_dir" | xargs kill >/dev/null 2>&1
    umount "$chroot_dir/dev" "$chroot_dir/proc" "$chroot_dir/sys" \
        "$chroot_dir/boot" "$chroot_dir"
    set -e
}

function chroot_stuff() {
    local chroot_dir image_path
    chroot_dir="$1"
    image_path="$2"

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - chroot"

    trap '{ error "Something went wrong!"; cleanup "$chroot_dir"; exit 2; }' \
        EXIT
    trap '{ trap - EXIT; error "Interrupted"; cleanup "$chroot_dir";
            exit 3; }' SIGKILL SIGINT SIGTERM

    qemu-nbd -c "$IMAGE_DEVICE" "$image_path"
    mount_stuff
    log "Chrooting in a bash shell, <ctrl+d> to exit"
    reset_redirections
    LANG=C chroot "$chroot_dir"
    redirect_to_log "$SCRIPT_DIR/build.log"
    umount_stuff
    qemu-nbd -d "${IMAGE_DEVICE}"
}

function cleanup() {
    local chroot_dir
    chroot_dir="$1"

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - cleanup"

    log "Unmounting filesystems"
    umount_stuff

    log "Detaching ${IMAGE_DEVICE}"
    qemu-nbd -d "${IMAGE_DEVICE}"
}

# --- Main

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

DEFAULT_VERSION="trusty"
DEFAULT_BUILD_DIR="$SCRIPT_DIR/image-build"

. "$SCRIPT_DIR/_utils.sh"

redirect_to_log "$SCRIPT_DIR/build.log"
log "Verbose log redirected to ${BLU}$SCRIPT_DIR/build.log${NC}"
echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started"

modprobe nbd max_part=16

command=${1:-usage}
if [ $# -ge 1 ]; then
    shift
fi

case "$command" in
    build)
        _build_dir="$DEFAULT_BUILD_DIR"
        _version="$DEFAULT_VERSION"

        while getopts "v:p:s:" option; do
            case "$option" in
                v)
                    _version="$OPTARG"
                    ;;
                p)
                    _build_dir="$OPTARG"
                    ;;
                s)
                    _script="$OPTARG"
                    ;;
                \?)
                    log "Invalid option: -$OPTARG"
                    usage
                    exit 2
                    ;;
                :)
                    log "Option -$OPTARG requires an argument"
                    usage
                    exit 2
                    ;;
            esac
        done

        if [ $# -ne $((OPTIND-1)) ]; then
            log "Unrecognized options"
            usage
            exit 2
        fi

        _image_path="$_build_dir/image.raw"
        _chroot_dir="$_build_dir/mnt"

        build "$_build_dir" "$_image_path" "$_chroot_dir" "$_version" \
            "${_script:-}"

        log "Exiting";
        cleanup "$_chroot_dir";
        ;;

    cleanup)
        _build_dir="$DEFAULT_BUILD_DIR"

        while getopts ":p:" option; do
            case "$option" in
                p)
                    _build_dir="$OPTARG"
                    ;;
                \?)
                    log "Invalid option: -$OPTARG"
                    usage
                    exit 2
                    ;;
                :)
                    log "Option -$OPTARG requires an argument"
                    usage
                    exit 2
                    ;;
            esac
        done

        if [ $# -ne $((OPTIND-1)) ]; then
            log "Unrecognized options"
            usage
            exit 2
        fi

        _chroot_dir="$_build_dir/mnt"

        cleanup "$_chroot_dir"

        log "Removing build dir"
        rm -rf "$_chroot_dir"
        ;;

    chroot)
        _build_dir="$DEFAULT_BUILD_DIR"

        while getopts ":p:" option; do
            case "$option" in
                p)
                    _build_dir="$OPTARG"
                    ;;
                \?)
                    log "Invalid option: -$OPTARG"
                    usage
                    exit 2
                    ;;
                :)
                    log "Option -$OPTARG requires an argument"
                    usage
                    exit 2
                    ;;
            esac
        done

        if [ $# -ne $((OPTIND-1)) ]; then
            log "Unrecognized options"
            usage
            exit 2
        fi

        _chroot_dir="$_build_dir/mnt"

        chroot_stuff "$_chroot_dir" "$_build_dir/image.qcow2"
        ;;

    usage)
        usage
        ;;

    *)
        log "Unrecognized command: '$command'"
        usage
        exit 1
        ;;
esac

exit 0
