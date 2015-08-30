#!/usr/bin/env bash

set -eux

DOCKER_PACKAGE="docker.io_1.6.2%7Edfsg1-1ubuntu3%7E14.04.1_armhf.deb"
DOCKER_DEB_URL="http://launchpadlibrarian.net/211914968/$DOCKER_PACKAGE"

curl -L $DOCKER_DEB_URL -o /root/$DOCKER_PACKAGE
dpkg -i /root/$DOCKER_PACKAGE
