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

RED='\033[0;31m'
GRN='\033[0;32m'
# shellcheck disable=SC2034
YLW='\033[0;33m'
BLU='\033[0;34m'
NC='\033[0m'

function log() {
    local message="${1:-}"

    echo -en "${GRN}[${BLU}$(date +'%d-%m-%Y')${NC} " >&29
    echo -en "${BLU}$(date +'%H:%M:%S')${GRN}]${NC} " >&29
    echo -e "${NC}$message" >&29
}

function error() {
    local message="${1:-}"

    echo -en "${GRN}[${BLU}$(date +'%d-%m-%Y')${NC} " >&29
    echo -en "${BLU}$(date +'%H:%M:%S')${GRN}]${NC} " >&29
    echo -e "${RED}$message${NC}" >&29
}

function redirect_to_log() {
    local logfile="$1"
    
    # Redirection magic
    exec 29>&1
    exec >>"$logfile"
    exec 2>&1
}

function reset_redirections() {
    exec 1>&29
    exec 2>&1
    exec 29>&-
}
