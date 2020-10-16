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

# starting the qubinode installer 
function setup_qubinode(){
    download_qubinode_project
    cd "${PROJECT_DIR}/"
    ./"${PROJECT_NAME}" -m setup
}

# Start qubinode deployment with config
function setup_qubinode_with_config () 
{
    local config_file
    config_file="$1"
    
    #if [ -f $config_file ] && [ ! -f "${PROJECT_DIR}/qubinode_vars.txt" ]
    if [ ! -f $config_file ]
    then
        printf '%s\n' "$config_file does not exist"
        exit 1
    else
        download_qubinode_project
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
function download_qubinode_project()
{
    local util_cmds="wget curl unzip tar"

    if [ ! -d "${PROJECT_DIR}" ]
    then
        if which curl> /dev/null 2>&1 && which tar> /dev/null 2>&1
        then
            cd "${HOME}"
            curl -LJ -o "${PROJECT_NAME}.tar.gz" "${QUBINODE_REMOTE_TAR_FILE}"
            mkdir "${PROJECT_NAME}"
            tar -xzf "${PROJECT_NAME}.tar.gz" -C "${PROJECT_NAME}" --strip-components=1
	    rm -f "${PROJECT_NAME}.tar.gz" 
        elif which curl> /dev/null 2>&1 && which unzip> /dev/null 2>&1
        then
            cd "${HOME}"
            curl -LJ -o "${QUBINODE_BRANCH}.zip" "${QUBINODE_REMOTE_ZIP_FILE}"
            unzip "${QUBINODE_BRANCH}.zip"
            rm "${QUBINODE_BRANCH}.zip"
            mv "${PROJECT_NAME}-${QUBINODE_BRANCH}" "${PROJECT_NAME}"
        elif which wget> /dev/null 2>&1 && which tar> /dev/null 2>&1
        then
            cd "${HOME}"
            wget "${QUBINODE_REMOTE_TAR_FILE}" -O "${PROJECT_NAME}.tar.gz"
            mkdir "${PROJECT_NAME}"
            tar -xzf "${PROJECT_NAME}.tar.gz" -C "${PROJECT_NAME}" --strip-components=1
	    rm -f "${PROJECT_NAME}.tar.gz"
        elif which wget> /dev/null 2>&1 && which unzip> /dev/null 2>&1
        then
            cd "${HOME}"
            wget "${QUBINODE_REMOTE_ZIP_FILE}"
            unzip "${QUBINODE_BRANCH}.zip"
            rm "${QUBINODE_BRANCH}.zip"
            mv "${PROJECT_NAME}-${QUBINODE_BRANCH}" "${PROJECT_NAME}"
        else
            local count=0
            for util in $util_cmds
            do
                if ! which $util> /dev/null 2>&1
                then
                    missing_cmd[count]="$util"
                    count=$((count+1))
                fi
            done
            printf '%s\n' "Error: could not find the following ${#missing_cmd[@]} utilies: ${missing_cmd[*]}"
            exit 1
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
    
    while true
    do
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
                setup_qubinode_with_config "$config_file"
		break
                ;;
            -d|--download)
		download_qubinode_project
		break
                ;;
            -r|--remove)
                remove_qubinode_folder
		break
                ;;
            --)
                shift
                break
                ;;
            -?*)
                printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
                ;;
            *)
               setup_qubinode
	       break
        esac
        shift
    done
}


main "$@"



