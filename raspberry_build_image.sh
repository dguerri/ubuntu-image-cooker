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
components="main,restricted,universe,multiverse"
extra_packages="openssh-server,vim,avahi-daemon,bridge-utils,curl,gcc,make,software-properties-common,ubuntu-keyring"
initial_size_gb="2"
arch="armhf"
target_disk="/dev/mmcblk0"
nic_list=(eth0)
image_device="/dev/loop0"
debootstrap="qemu-debootstrap --arch $arch"
default_user="ubuntu"
default_user_sshkey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCe5Y4UD861L62QApdGrRbhVExS1V3RgGlnRXPYTEIraoQPzBdbhn3OU9q3FRRvIdYgM2LFaYe8ClTqENM0BUHq8DeEm9wiQVu0+TWz8KIGoDJEjUpaFsKrIrtC3uP7lqyJYzzUR0nyJxL00Uf1otXTcJ+9d4RIbNtu370ooLoQZN6LaYN/54NKqiRJ0DXtzY+2iTc2U/ptgfN1YQMizpjjwz2k57JX7UlxnLT3jVFOBF6wu9jT+HEaCDbFbOSDYiziqEz52qvhBRhqrr87nrzSkilv+JHigLMgLmrBuWavCXqdzl7PmNKqfWkj1lI5KlxcA+UHZDJtpIBrblHa91p5 davide@murray.local"
# -------------------

function usage() {
    echo -e "
$script_name - Davide Guerri <davide.guerri@gmail.com>

Build ${RED}Raspberry Pi${NC} ${BLU}2${NC} Ubuntu images

    Usage:
        $script_name <build|cleanup|mount|umount|chroot> [version]
        $script_name flash <version> <block device> [hostname]

Options:

    build       Build a new raw image
                Examples:
                    $script_name build        # Build trusty by default
                    $script_name build vivid

    cleanup     Remove previous build directory (not including the image)
                Examples:
                    $script_name cleanup      # Cleanup trusty by default
                    $script_name cleanup vivid

    mount       Mount the image (assumes nbd device already set up)
                Examples:
                    $script_name mount        # Mount trusty by default
                    $script_name mount vivid

    umount      Umount the image (leave the nbd device untouched)
                Examples:
                    $script_name umount       # Unmount trusty by default
                    $script_name umount vivid

    chroot      Chroot into the image (i.e. set up nbd device, mount image,
                spawn an interactive chroot'ed shell, umount, unset nbd device)
                Examples:
                    $script_name chroot      # Chroot to trusty by default
                    $script_name chroot vivid

    flash       Flash the image to a block device setting the given hostname
                Examples:
                    $script_name flash trusty /dev/sdb rpi001
" >&29
}

function build() {
    log "Strarting build of a ${YLW}$version${NC} box, arch ${YLW}$arch${NC}"
    log "Target disk: ${YLW}$target_disk${NC}"
    log "Network interface(s): ${YLW}${nic_list[*]}${NC}"

    mkdir -p "$build_dir"

    log "Creating a ${YLW}$initial_size_gb${NC}GB raw image"
    rm -f "$image_path"
    fallocate -l "${initial_size_gb}G" "$image_path"

    log "Initializing loop device $image_device"
    losetup "$image_device" "$image_path"

    log "Partitioning $image_device"
    sfdisk "$image_device" -D -uM <<EOF
,64,c,*
,,83
;
EOF
    partprobe "$image_device"

    log "Creating filesystems"
    mkfs.vfat "${image_device}p1"
    mkfs.ext4 "${image_device}p2"

    log "Mounting filesystems"
    mkdir -p "$chroot_dir"
    mount "${image_device}p2" "$chroot_dir"

    log "Executing debootstrap (this will take a while)"
    $debootstrap --verbose --arch "$arch" --components="$components" \
        --include="$extra_packages" "$version" "$chroot_dir" \
        http://ports.ubuntu.com/

    log "Preparing the chroot environment"
    mkdir -p "$chroot_dir/boot/firmware"
    mount "${image_device}p1" "$chroot_dir/boot/firmware"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"

    log "Creating /etc/fstab"
    cat <<EOF > $chroot_dir/etc/fstab
proc                /proc           proc    defaults          0       0
${target_disk}p1    /boot/firmware  vfat    defaults          0       2
${target_disk}p2    /               ext4    defaults,noatime  0       1
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

    log "Creating /etc/network/interfaces with interface(s): '${nic_list[*]}'"
    cat <<EOF > $chroot_dir/etc/network/interfaces
auto lo
iface lo inet loopback
EOF

    for nic in "${nic_list[@]}"; do
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
    echo "dwc_otg.lpm_enable=0 console=tty1 root=${target_disk}p2 rootwait" \
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

    log "Setting up user '$default_user'"
    chroot "$chroot_dir" <<EOF
adduser --gecos "Default user" --add_extra_groups \
    --disabled-password "$default_user"
mkdir "/home/${default_user}/.ssh"
chmod 700 "/home/${default_user}/.ssh"
echo $default_user_sshkey > "/home/${default_user}/.ssh/authorized_keys"
chown -R ${default_user}:${default_user} "/home/${default_user}/.ssh"
echo "${default_user} ALL=(ALL) NOPASSWD: ALL" > \
    "/etc/sudoers.d/${default_user}-no-pw"
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
}

function mount_stuff() {
    mount "${image_device}p2" "$chroot_dir"
    mount "${image_device}p1" "$chroot_dir/boot/firmware"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"
}

function umount_stuff() {
    set +e

    lsof -t "$chroot_dir" | xargs kill >/dev/null 2>&1
    umount "$chroot_dir/dev" "$chroot_dir/proc" "$chroot_dir/sys" \
        "$chroot_dir/boot/firmware" "$chroot_dir"

    set -e
}

function chroot_stuff() {
    losetup "$image_device" "$image_path"
    mount_stuff
    log "Chrooting in a bash shell, <ctrl+d> to exit"
    reset_redirections
    LANG=C chroot "$chroot_dir"
    redirect_to_log "$script_dir/$version-build.log"
    umount_stuff
    losetup -d "${image_device}"
}

function cleanup() {
    log "Unmounting filesystems"
    umount_stuff

    log "Detaching ${image_device}"
    losetup -d "${image_device}"
}

function flash() {
    local device hostname tmp_dir image_name choice
    device="$1"
    hostname=${2:-}
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
        losetup "$image_device" "$tmp_dir/$image_name"
        partprobe "$image_device"
        mount -t ext4 "$image_device"p2 "$tmp_dir/mnt"
        echo "$hostname" > "$tmp_dir/mnt/etc/hostname"
        echo -e "127.0.0.1\t$hostname" >> "$tmp_dir/mnt/etc/hosts"
        umount "$tmp_dir/mnt"
        losetup -d "$image_device"
    fi

    log "Writing $tmp_dir/$image_name to $device (this will take a while)"
    dd if="$tmp_dir/$image_name" of="$device" bs=32M
    rm -rf "$tmp_dir"

    log "${YLW}D${BLU}o${RED}n${GRN}e${NC}!"
}

# --- Main

default_version="trusty"
version="${2:-$default_version}"
build_dir="/tmp/$version-build"
image_path="$build_dir/$version.raw"
chroot_dir="$build_dir/mnt"

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "${BASH_SOURCE[0]}")"

. "$script_dir/_utils.sh"

redirect_to_log "$script_dir/$version-build.log"

# Install cleanup using signal handlers
trap '{ error "Something went wrong!"; cleanup; exit 2; }' EXIT
trap '{ trap - EXIT; error "Interrupted"; cleanup;  exit 3; }' SIGHUP SIGINT \
    SIGTERM

log "Verbose log redirected to ${BLU}$script_dir/$version-build.log${NC}"

command=${1:-usage}
echo "-----[ $(date +'%d-%m-%Y %H:%M:%S') started - $command - $version"

case "${command}" in
    build)
        build
        log "Exiting";
        cleanup;
        ;;
    cleanup)
        cleanup
        log "Removing build dir"
        rm -rf "$chroot_dir"
        ;;
    mount)
        mount_stuff
        ;;
    umount)
        umount_stuff
        ;;
    chroot)
        chroot_stuff
        ;;
    flash)
        if [ $# -lt 3 ]; then
                usage
                trap - EXIT
                exit 1
        fi
        flash "$3" "${4:-}"
        ;;
    *)
        usage
        trap - EXIT
        exit 1
        ;;
esac

trap - EXIT
exit 0
