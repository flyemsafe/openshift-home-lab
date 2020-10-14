#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline

## Required Vars
PROJECT_NAME="qubinode-installer"
PROJECT_DIR="$HOME/${PROJECT_NAME}"
QUBINODE_URL="https://github.com/flyemsafe"
QUBINODE_ZIP_URL="${QUBINODE_URL}/${PROJECT_NAME}/archive"
QUBINODE_TAR_URL="${QUBINODE_URL}/${PROJECT_NAME}/tarball"
QUBINODE_BRANCH="newinstaller"
QUBINODE_REMOTE_ZIP_FILE="${QUBINODE_ZIP_URL}/${QUBINODE_BRANCH}.zip"
QUBINODE_REMOTE_TAR_FILE="${QUBINODE_TAR_URL}/${QUBINODE_BRANCH}"

# downloads the qubinode code using curl 
function curl_download()
{
    cd "${HOME}"
    curl -LJ -o "${PROJECT_NAME}.tar.gz" "${QUBINODE_REMOTE_TAR_FILE}"
    mkdir "${PROJECT_NAME}"
    tar -xzf "${PROJECT_NAME}.tar.gz" -C "${PROJECT_NAME}" --strip-components=1
    if [ -d "${PROJECT_DIR}" ]
    then
        rm -f "${PROJECT_NAME}.tar.gz"
    fi
}

# Download the project using git
function git_clone_code(){
  git clone "${QUBINODE_URL}/${PROJECT_NAME}.git"
  cd "${PROJECT_NAME}"
  git checkout "${QUBINODE_BRANCH}"
}

# calling a wget to download  qubinode node code
function wget_download(){
    cd $HOME
    wget ${QUBINODE_ZIP_URL}/${QUBINODE_REMOTE_ZIP_FILE}
    extract_quibnode_installer ${QUBINODE_REMOTE_ZIP_FILE}
}

# extracts the qubinode installer into the home directory
function extract_quibnode_installer(){
    echo "${1}"
    unzip "$HOME/${1}"
    rm "$HOME/${1}"
    NAMED_RELEASE=$(echo "${1}" | sed -e 's/.zip//')
    mv "${PROJECT_NAME}-${NAMED_RELEASE}" "${PROJECT_NAME}"
}

# starting the qubinode installer 
function start_qubinode_install(){
    start_qubinode_download
    cd "${PROJECT_DIR}/"
    ./"${PROJECT_NAME}" -m setup
}

# Start qubinode deployment with config
function start_qubinode_install_with_config () 
{
    local config_file
    config_file="$1"
    
    #if [ -f $config_file ] && [ ! -f "${PROJECT_DIR}/qubinode_vars.txt" ]
    if [ ! -f $config_file ]
    then
        printf '%s\n' "$config_file does not exist"
        exit 1
    else
        start_qubinode_download
        test -d "${PROJECT_DIR}" && cp $config_file "${PROJECT_DIR}/qubinode_vars.txt"
    fi

    if [ ! -f "${PROJECT_DIR}/qubinode_vars.txt" ]
    then
        cd "${PROJECT_DIR}/"
        ./"${PROJECT_NAME}" -m setup
    else
        printf '%s\n' "$PROJECT_DIR does not exist"
        exit 1
    fi
}

# start the qubinode installer check and download if does not exist
function start_qubinode_download()
{
    local unzip_found=no
    local git_found=no
    local wget_found=no
    local curl_found=no
    local download_method=""

    if [ ! -d "${PROJECT_DIR}" ]
    then 
        ## chek for curl
        if which curl> /dev/null 2>&1
        then
            curl_download
        fi
      
        ## check for the presence of unzip
        if which unzip> /dev/null 2>&1
        then
            unzip_found=yes
        fi
      
        ## chek for git
        if which git> /dev/null 2>&1
        then
            git_clone_code
        fi
      
        ## chek for wget
        if which wget> /dev/null 2>&1
        then
            wget_download
        fi
    else
        printf '%s\n' "The Qubinode project directory ${PROJECT_DIR} already exists."
        printf '%s\n' "Run ${PROJECT_DIR}/qubinode-installer -h to see additional options"
        exit 1
    fi
}

# Remove qubinode installer and conpoments
function remove_qubinode_folder(){
    if [ -d  "${PROJECT_DIR}" ];
    then 
        sudo rm -rf "${PROJECT_DIR}" 
    fi 

    if [ -d /usr/share/ansible-runner-service ] && [ ! -f /etc/systemd/system/ansible-runner-service.service ];
    then 
      sudo rm -rf /usr/share/ansible-runner-service
      sudo rm -rf /usr/local/bin/ansible_runner_service
      sudo rm -rf /tmp/ansible-runner-service/
    fi 

    #if [ -f /home/"${USER}"/.ssh/id_rsa ];
    #then
    #  sudo rm -rf /home/"${USER}"/.ssh/id_rsa 
    #  sudo rm -rf /home/"${USER}"/.ssh/id_rsa.pub
    #fi  

}


# displays usage
function script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -v|--verbose               Displays verbose output
     -c|--config                Install Qubinode installer using config file
     -d|--delete                Remove Qubinode installer 
EOF
}

## returns zero/true if root user
function is_root () {
    return $(id -u)
}

function arg_error ()
{
    printf '%s\n' "$1" >&2
    exit 1
}

function main ()
{
    local config_file
    local user_input
    local args
    args=${1-default}
    
    # Exit if this is executed as the root user
    if is_root 
    then
        echo "Error: qubi-installer should be run as a normal user, not as root!"
        exit 1
    fi

    while :; do
        case "$args" in
            -h|-\?|--help)
                script_usage
                exit
                ;;
            -c|--config)
                user_input=${2-default}
                if [ "$user_input" ]
                then
                    config_file="$user_input"
                    shift
                else 
                    arg_error 'ERROR: "--config" requires a configuration file.'
                fi
                start_qubinode_install_with_config "$config_file"
                ;;
            -d|--delete)
                remove_qubinode_folder
                ;;
            --)
                shift
                break
                ;;
            -?*)
                printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
                ;;
            *)
                start_qubinode_download
        esac
        shift
    done
}


main "$@"



