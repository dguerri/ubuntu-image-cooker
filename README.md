Cloud Images
============

`cloud_image_build.sh`

Build minimal Ubuntu images for Cloud VMs and Baremetal from scratch.

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

Build minimal Ubuntu images for Cloud VMs and Baremetal from scratch.


Example usage
-------------

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
