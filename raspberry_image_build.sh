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
EXTRA_PACKAGES="openssh-server,vim,avahi-daemon,bridge-utils,curl,gcc,make,software-properties-common,ubuntu-keyring"
INITIAL_SIZE_GB="2"
ARCH="armhf"
TARGET_DISK="/dev/mmcblk0"
NIC_LIST=(eth0)
IMAGE_DEVICE="/dev/loop0"
DEBOOTSTRAP="qemu-debootstrap --arch $ARCH"
DEFAULT_USER="ubuntu"
DEFAULT_USER_SSHKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCe5Y4UD861L62QApdGrRbhVExS1V3RgGlnRXPYTEIraoQPzBdbhn3OU9q3FRRvIdYgM2LFaYe8ClTqENM0BUHq8DeEm9wiQVu0+TWz8KIGoDJEjUpaFsKrIrtC3uP7lqyJYzzUR0nyJxL00Uf1otXTcJ+9d4RIbNtu370ooLoQZN6LaYN/54NKqiRJ0DXtzY+2iTc2U/ptgfN1YQMizpjjwz2k57JX7UlxnLT3jVFOBF6wu9jT+HEaCDbFbOSDYiziqEz52qvhBRhqrr87nrzSkilv+JHigLMgLmrBuWavCXqdzl7PmNKqfWkj1lI5KlxcA+UHZDJtpIBrblHa91p5 davide@murray.local"
# -------------------

function usage() {
    echo -e "
$SCRIPT_NAME - Davide Guerri <davide.guerri@gmail.com>

Build ${RED}Raspberry${NC} ${BLU}P${YLW}i${NC} Ubuntu images

Usage:

    $SCRIPT_NAME <build|cleanup|chroot|flash> [<options>]

Commands:

    build       Build a new raw image

        $SCRIPT_NAME build [-v <version>] [-p <path>] [-s <bash_script>]

        Options:
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

        Options:
            -p <path>       Directory to use as a working directory.
                            (Default <script directory>/rpii)
        Examples:
            $SCRIPT_NAME cleanup
            $SCRIPT_NAME cleanup -p /tmp/myimage


    chroot      Chroot into the image. The image must have been already built.

        $SCRIPT_NAME chroot [-p <path>]

        Options:
            -p <path>       Directory to use as a working directory.
                            (Default <script directory>/rpii)
        Examples:
            $SCRIPT_NAME chroot
            $SCRIPT_NAME chroot -p /tmp/myimage


    flash       Flash the image to a block device setting the given hostname

        $SCRIPT_NAME chroot -d <device> -[-h <hostname>] [-p <path>]

        Options:
            -d <device>     Device to write the image to.
            -h <hostname>   Hostname to use in the flashed image.
            -p <path>       Directory to use as a working directory.
                            (Default <script directory>/rpii)

        Examples:
            $SCRIPT_NAME flash -d /dev/sdb
            $SCRIPT_NAME flash -d /dev/sdb -h rpi001
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

    log "Creating a ${YLW}$INITIAL_SIZE_GB${NC}GB raw image"
    rm -f "$image_path"
    fallocate -l "${INITIAL_SIZE_GB}G" "$image_path"

    log "Initializing loop device $IMAGE_DEVICE"
    losetup "$IMAGE_DEVICE" "$image_path"

    log "Partitioning $IMAGE_DEVICE"
    sfdisk "$IMAGE_DEVICE" -D -uM <<EOF
,64,c,*
,,83
;
EOF
    partprobe "$IMAGE_DEVICE"

    log "Creating filesystems"
    mkfs.vfat "${IMAGE_DEVICE}p1"
    mkfs.ext4 "${IMAGE_DEVICE}p2"

    log "Mounting filesystems"
    mkdir -p "$chroot_dir"
    mount "${IMAGE_DEVICE}p2" "$chroot_dir"

    log "Executing debootstrap (this will take a while)"
    $DEBOOTSTRAP --verbose --arch "$ARCH" --components="$COMPONENTS" \
        --include="$EXTRA_PACKAGES" "$version" "$chroot_dir" \
        http://ports.ubuntu.com/

    log "Preparing the chroot environment"
    mkdir -p "$chroot_dir/boot/firmware"
    mount "${IMAGE_DEVICE}p1" "$chroot_dir/boot/firmware"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"

    log "Creating /etc/fstab"
    cat <<EOF > $chroot_dir/etc/fstab
proc                /proc           proc    defaults          0       0
${TARGET_DISK}p1    /boot/firmware  vfat    defaults          0       2
${TARGET_DISK}p2    /               ext4    defaults,noatime  0       1
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

    log "Installing Raspberry Pi PPA"
    # Install the RPi PPA
    cat <<EOF >"$chroot_dir/etc/apt/preferences.d/rpi2-ppa"
    Package: *
    Pin: release o=LP-PPA-fo0bar-rpi2
    Pin-Priority: 990

    Package: *
    Pin: release o=LP-PPA-fo0bar-rpi2-staging
    Pin-Priority: 990
EOF

    cat <<EOF >"$chroot_dir/etc/apt/sources.list"
deb http://ports.ubuntu.com/ ${version} main restricted universe multiverse
deb http://ports.ubuntu.com/ ${version}-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ ${version}-security main restricted universe multiverse
deb http://ports.ubuntu.com/ ${version}-backports main restricted universe multiverse
EOF

    chroot "$chroot_dir" apt-add-repository -y ppa:fo0bar/rpi2
    chroot "$chroot_dir" apt-get update

    log "Installing Linux kernel"
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" apt-get -y \
        --no-install-recommends install linux-image-rpi2
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" apt-get -y \
        install ubuntu-standard raspberrypi-bootloader-nokernel \
        rpi2-ubuntu-errata language-pack-en
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" apt-get -y \
        install initramfs-tools
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" apt-get -y \
        install flash-kernel

    log "Coping Linux kernel to /boot/firmware/kernel7.img"
    VMLINUZ=$(find "$chroot_dir/boot/" -name "vmlinuz-*" | sort | tail -n 1)
    [ -z "$VMLINUZ" ] && exit 1
    cp "$VMLINUZ" "$chroot_dir/boot/firmware/kernel7.img"

    log "Coping initrd to /boot/firmware/initrd7.img"
    INITRD=$(find "$chroot_dir/boot/" -name "initrd.img-*" | sort | tail -n 1)
    [ -z "$INITRD" ] && exit 1
    cp "$INITRD" "$chroot_dir/boot/firmware/initrd7.img"

    log "Setting up firmware config"
    cat <<EOF >$chroot_dir/boot/firmware/config.txt
# For more options and information see
# http://www.raspberrypi.org/documentation/configuration/config-txt.md
EOF
    ln -sf firmware/config.txt "$chroot_dir/boot/config.txt"
    echo "dwc_otg.lpm_enable=0 console=tty1 root=${TARGET_DISK}p2 rootwait" \
        > "$chroot_dir/boot/firmware/cmdline.txt"
    ln -sf firmware/cmdline.txt "$chroot_dir/boot/cmdline.txt"

    log "Enabling modules to load at boot"
    # Load sound module on boot
    cat <<EOF >"$chroot_dir/lib/modules-load.d/rpi2.conf"
snd_bcm2835
bcm2708_rng
EOF

    log "Blacklisting platform modules not applicable to the RPi2"
    cat <<EOF >$chroot_dir/etc/modprobe.d/rpi2.conf
blacklist snd_soc_pcm512x_i2c
blacklist snd_soc_pcm512x
blacklist snd_soc_tas5713
blacklist snd_soc_wm8804
EOF

    log "Setting up user '$DEFAULT_USER'"
    chroot "$chroot_dir" <<EOF
adduser --gecos "Default user" --add_extra_groups \
    --disabled-password "$DEFAULT_USER"
mkdir "/home/${DEFAULT_USER}/.ssh"
chmod 700 "/home/${DEFAULT_USER}/.ssh"
echo $DEFAULT_USER_SSHKEY > "/home/${DEFAULT_USER}/.ssh/authorized_keys"
chown -R ${DEFAULT_USER}:${DEFAULT_USER} "/home/${DEFAULT_USER}/.ssh"
echo "${DEFAULT_USER} ALL=(ALL) NOPASSWD: ALL" > \
    "/etc/sudoers.d/${DEFAULT_USER}-no-pw"
EOF

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
    local chroot_dir
    chroot_dir="$1"

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - mount_stuff"

    mount "${IMAGE_DEVICE}p2" "$chroot_dir"
    mount "${IMAGE_DEVICE}p1" "$chroot_dir/boot/firmware"
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
        "$chroot_dir/boot/firmware" "$chroot_dir"
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

    losetup "$IMAGE_DEVICE" "$image_path"
    mount_stuff "$chroot_dir"
    log "Chrooting in a bash shell, <ctrl+d> to exit"
    reset_redirections
    LANG=C chroot "$chroot_dir"
    redirect_to_log "$SCRIPT_DIR/build.log"
    umount_stuff "$chroot_dir"
    losetup -d "${IMAGE_DEVICE}"

    trap - SIGKILL SIGINT SIGTERM EXIT
}

function cleanup() {
    local chroot_dir
    chroot_dir="$1"

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - cleanup"

    log "Unmounting filesystems"
    umount_stuff "$chroot_dir"

    log "Detaching $IMAGE_DEVICE"
    losetup -d "$IMAGE_DEVICE"
}

function flash() {
    local device image_path hostname
    device="$1"
    image_path="$2"
    hostname="${3:-}"

    echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - flash"

    trap '{ error "Something went wrong!"; exit 2; }' \
        EXIT
    trap '{ trap - EXIT; error "Interrupted"; exit 3; }' SIGKILL SIGINT SIGTERM

    local image_name choice tmp_dir
    tmp_dir="$(mktemp -d)"
    image_name="$(basename "$image_path")"

    log "Flashing image $image_path to ${RED}$device${NC}"
    log "Press ${RED}y${NC}, ${GRN}n${NC} to abort"
    read -s -n1 choice
    case "$choice" in
        y|Y)
            true
            ;;
        *)
            return
            ;;
    esac

    log "Copying $image_path to $tmp_dir/$image_name"
    cp "$image_path" "$tmp_dir/$image_name"

    if [ -n "$hostname" ]; then
        log "Setting image hostname to $hostname"
        mkdir "$tmp_dir/mnt"
        losetup "$IMAGE_DEVICE" "$tmp_dir/$image_name"
        partprobe "$IMAGE_DEVICE"
        mount -t ext4 "$IMAGE_DEVICE"p2 "$tmp_dir/mnt"
        echo "$hostname" > "$tmp_dir/mnt/etc/hostname"
        echo -e "127.0.0.1\t$hostname" >> "$tmp_dir/mnt/etc/hosts"
        umount "$tmp_dir/mnt"
        losetup -d "$IMAGE_DEVICE"
    fi

    log "Writing $tmp_dir/$image_name to $device (this will take a while)"
    dd if="$tmp_dir/$image_name" of="$device" bs=32M
    rm -rf "$tmp_dir"

    log "${YLW}D${BLU}o${RED}n${GRN}e${NC}!"

    trap - SIGKILL SIGINT SIGTERM EXIT
}

# --- Main

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

DEFAULT_VERSION="trusty"
DEFAULT_BUILD_DIR="$SCRIPT_DIR/rpii"

. "$SCRIPT_DIR/_utils.sh"

redirect_to_log "$SCRIPT_DIR/build.log"
log "Verbose log redirected to ${BLU}$SCRIPT_DIR/build.log${NC}"
echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started"

# Install cleanup using signal handlers

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

        chroot_stuff "$_chroot_dir" "$_build_dir/image.raw"
        ;;

    flash)
        _build_dir="$DEFAULT_BUILD_DIR"

        while getopts ":d:h:p:" option; do
            case "$option" in
                d)
                    _device="$OPTARG"
                    ;;
                h)
                    _hostname="$OPTARG"
                    ;;
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

        if [ -z "${_device:-}" ]; then
            log "Missing device (-d)"
            usage
            exit 2
        fi

        flash "$_device" "$_build_dir/image.raw" "${_hostname:-}"
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
