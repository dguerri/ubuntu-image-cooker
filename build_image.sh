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
extra_packages="openssh-server,acpid,sudo,cloud-init,cloud-initramfs-growroot"
initial_size_gb="8"
arch="amd64"
target_disk="/dev/sda"
nic_list=(eth0)
image_device="/dev/nbd0"
debootstrap="debootstrap"
# -------------------

function usage() {
    echo -e "
$script_name - Davide Guerri <davide.guerri@gmail.com>

${BLU}Build Cloud ready Ubuntu images (for VM ${RED}and${BLU} BM)${NC}

    Usage: $script_name <build|cleanup|mount|umount|chroot> [version]

Options:

    build       Build a new qcow2 image
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

" >&29
}

function build() {
    log "Strarting build of a ${YLW}$version${NC} box, arch ${YLW}$arch${NC}"
    log "Target disk: ${YLW}$target_disk${NC}"
    log "Network interface(s): ${YLW}${nic_list[*]}${NC}"

    mkdir -p "$build_dir"

    log "Creating a ${YLW}${initial_size_gb}G${NC} qcow2 image"
    rm -f "$image_path"
    qemu-img create -f qcow2 "$image_path" "${initial_size_gb}G"

    log "Initializing nbd device $image_device"
    qemu-nbd -c "$image_device" "$image_path"

    log "Partitioning $image_device"
    sfdisk "$image_device" -D -uM <<EOF
,512,83,*
,,83
;
EOF
    partprobe "$image_device"

    log "Creating filesystems"
    mkfs.ext2 "${image_device}p1"
    mkfs.ext4 "${image_device}p2"

    log "Mounting filesystems"
    mkdir -p "$chroot_dir"
    mount "${image_device}p2" "$chroot_dir"

    log "Executing debootstrap (this will take a while)"
    $debootstrap --verbose --arch "$arch" --components="$components" \
        --include="$extra_packages" "$version" "$chroot_dir" \
        http://archive.ubuntu.com/ubuntu/

    log "Preparing the chroot environment"
    mount "${image_device}p1" "$chroot_dir/boot"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"

    log "Creating /etc/fstab"
    cat <<EOF > $chroot_dir/etc/fstab
${target_disk}1   /boot   ext2    sync                0   2
${target_disk}2   /       ext4    errors=remount-ro   0   1
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

    log "Giving a personal touch to the login screen (tty)"
    cp "$script_dir/extras/show-ip-address" \
        "$chroot_dir/etc/network/if-up.d/"
    chmod +x "$chroot_dir/etc/network/if-up.d/show-ip-address"

    log "Installing additional packages: grub and Linux kernel"
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" \
        apt-get install -y -q grub-pc linux-image-generic linux-firmware
    echo "GRUB_TERMINAL=console" >> "$chroot_dir/etc/default/grub"

    log "Installing grub (${image_device})"
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" \
        grub-install ${image_device}
    LANG=C DEBIAN_FRONTEND=noninteractive chroot "$chroot_dir" update-grub

    log "Fixing grub configuration (using ${target_disk})"
    sed -i "s|${image_device}p|${target_disk}|g" \
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
}

function mount_stuff() {
    mount "${image_device}p2" "$chroot_dir"
    mount "${image_device}p1" "$chroot_dir/boot"
    mount --bind /dev/ "$chroot_dir/dev"
    mount -t proc none "$chroot_dir/proc"
    mount -t sysfs none "$chroot_dir/sys"
}

function umount_stuff() {
    set +e

    lsof -t "$chroot_dir" | xargs kill >/dev/null 2>&1
    umount "$chroot_dir/dev" "$chroot_dir/proc" "$chroot_dir/sys" \
        "$chroot_dir/boot" "$chroot_dir"

    set -e
}

function chroot_stuff() {
    qemu-nbd -c "$image_device" "$image_path"
    mount_stuff
    log "Chrooting in a bash shell, <ctrl+d> to exit"
    reset_redirections
    LANG=C chroot "$chroot_dir"
    redirect_to_log "$script_dir/$version-build.log"
    umount_stuff
    qemu-nbd -d "${image_device}"
}

function cleanup() {
    log "Unmounting filesystems"
    umount_stuff

    log "Detaching ${image_device}"
    qemu-nbd -d "${image_device}"
}

# --- Main

modprobe nbd max_part=16

default_version="trusty"
version="${2:-$default_version}"
build_dir="/tmp/$version-build"
image_path="$build_dir/$version.qcow2"
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
    *)
        usage
        trap - EXIT
        exit 1
        ;;
esac

trap - EXIT
exit 0
