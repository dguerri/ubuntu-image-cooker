Cloud Images
============

`cloud_image_build.sh`

Build minimal Ubuntu images for Cloud VMs and Baremetal, from scratch.

Example usage
-------------

    TBW

Available commands
------------------

    cloud_image_build.sh - Davide Guerri <davide.guerri@gmail.com>

    Build Cloud Ubuntu images (VM and BM)

    Usage:

        cloud_image_build.sh <build|cleanup|chroot> [<options>]

    Commands:

        build       Build a new qcow2 image

            cloud_image_build.sh build [-v <version>] [-p <path>] [-s <bash_script>]

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
                cloud_image_build.sh build
                cloud_image_build.sh build -v vivid -p /tmp/myimage


        cleanup     Remove previous build directory (not including the image)

            cloud_image_build.sh cleanup [-p <path>]

            Opions:
                -p <path>       Directory to use as a working directory.
                                (Default <script directory>/image-build)
            Examples:
                cloud_image_build.sh cleanup
                cloud_image_build.sh cleanup -p /tmp/myimage


        chroot      Chroot into the image. The image must have been already built.

            cloud_image_build.sh chroot [-p <path>]

            Opions:
                -p <path>       Directory to use as a working directory.
                                (Default <script directory>/image-build)
            Examples:
                cloud_image_build.sh chroot
                cloud_image_build.sh chroot -p /tmp/myimage


Raspberry Pi
============

`raspberry_image_build.sh`

Build minimal Ubuntu images for Raspberry Pi 2 from scratch.


Example usage
-------------

    root@rpi-oven:~/scripts# ./build_image.sh build
    [04-08-2015 23:24:18] Verbose log redirected to /root/scripts/build.log
    [04-08-2015 23:24:18] Starting build of a trusty box, arch armhf
    [04-08-2015 23:24:18] Target disk: /dev/mmcblk0
    [04-08-2015 23:24:18] Network interface(s): eth0
    [04-08-2015 23:24:18] Creating a 2GB raw image
    [04-08-2015 23:24:18] Initializing loop device /dev/loop0
    [04-08-2015 23:24:18] Partitioning /dev/loop0
    [04-08-2015 23:24:18] Creating filesystems
    [04-08-2015 23:24:18] Mounting filesystems
    [04-08-2015 23:24:18] Executing debootstrap (this will take a while)
    [04-08-2015 23:33:28] Preparing the chroot environment
    [04-08-2015 23:33:28] Creating /etc/fstab
    [04-08-2015 23:33:28] Creating /etc/hostname
    [04-08-2015 23:33:28] Creating /etc/hosts
    [04-08-2015 23:33:28] Creating /etc/network/interfaces with interface(s): 'eth0'
    [04-08-2015 23:33:28] Installing Raspberry Pi PPA
    [04-08-2015 23:34:20] Installing Linux kernel and initramfs-tools
    [04-08-2015 23:42:48] Coping Linux kernel to /boot/firmware/kernel7.img
    [04-08-2015 23:42:48] Coping initrd to /boot/firmware/initrd7.img
    [04-08-2015 23:42:48] Setting up firmware config
    [04-08-2015 23:42:48] Enabling modules to load at boot
    [04-08-2015 23:42:48] Blacklisting platform modules not applicable to the RPi2
    [04-08-2015 23:42:48] Setting up user 'ubuntu'
    [04-08-2015 23:42:49] Add ssh key for 'ubuntu'
    [04-08-2015 23:42:49] Cleaning up the image
    [04-08-2015 23:42:49] ******* your image is ready: '/root/scripts/rpii/image.raw' *******
    [04-08-2015 23:42:49] Exiting
    [04-08-2015 23:42:49] Unmounting filesystems
    [04-08-2015 23:42:50] Detaching /dev/loop0
    root@rpi-oven:~/scripts#
    root@rpi-oven:~/scripts# ./raspberry_image_build.sh flash -d /dev/sdb -h rpi-1
    [04-08-2015 08:58:43] Verbose log redirected to /root/scripts/build.log
    [04-08-2015 08:58:43] Flashing image /root/scripts/rpii/image.raw to /dev/sdb
    [04-08-2015 08:58:43] Press y, n to abort
    [04-08-2015 08:58:47] Copying /root/scripts/rpii/image.raw to /tmp/tmp.2IzJDikDfc/image.raw
    [04-08-2015 08:58:49] Setting image hostname to rpi-1
    [04-08-2015 08:58:51] Writing /tmp/tmp.2IzJDikDfc/image.raw to /dev/sdb (this will take a while)
    [04-08-2015 09:02:59] Done!


Available commands
------------------

    raspberry_image_build.sh - Davide Guerri <davide.guerri@gmail.com>

    Build Raspberry Pi Ubuntu images

    Usage:

        raspberry_image_build.sh <build|cleanup|chroot|flash> [<options>]

    Commands:

        build       Build a new raw image

            raspberry_image_build.sh build [-v <version>] [-p <path>] [-s <bash_script>]

            Options:
                -v <version>    Version to build, e.g.: vivid, trusty, precise,
                                utopic, ... (Default: trusty)
                -p <path>       Directory to use as a working directory.
                                If it doesn't exist, a new directory will be
                                created. (Default <script directory>/rpii)
                -s <script>     Bash script to run right before umounting the
                                image. The script will be run in a chrooted
                                environment.
            Examples:
                raspberry_image_build.sh build
                raspberry_image_build.sh build -v vivid -p /tmp/myimage

        cleanup     Remove previous build directory (not including the image)

            raspberry_image_build.sh cleanup [-p <path>]

            Options:
                -p <path>       Directory to use as a working directory.
                                (Default <script directory>/rpii)
            Examples:
                raspberry_image_build.sh cleanup
                raspberry_image_build.sh cleanup -p /tmp/myimage

        chroot      Chroot into the image (i.e. set up loop device, mount image,
                    spawn an interactive chroot'ed shell, umount, unset loop
                    device). The image must have been already built.

            raspberry_image_build.sh chroot [-p <path>]

            Options:
                -p <path>       Directory to use as a working directory.
                                (Default <script directory>/rpii)
            Examples:
                raspberry_image_build.sh chroot
                raspberry_image_build.sh chroot -p /tmp/myimage

        flash       Flash the image to a block device setting the given hostname

            raspberry_image_build.sh chroot -d <device> -[-h <hostname>] [-p <path>]

            Options:
                -d <device>     Device to write the image to.
                -h <hostname>   Hostname to use in the flashed image.
                -p <path>       Directory to use as a working directory.
                                (Default <script directory>/rpii)

            Examples:
                raspberry_image_build.sh flash -d /dev/sdb
                raspberry_image_build.sh flash -d /dev/sdb -h rpi001
