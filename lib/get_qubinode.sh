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
QUBINODE_ARCHIVE_URL="${QUBINODE_ARCHIVE_URL}/${PROJECT_NAME}/archive"
QUBINODE_ZIP_FILE="newinstaller.zip"
QUBINODE_BRANCH="newinstaller"

# Exports the qubinode installer into the home directory
function extract_quibnode_installer(){
    echo "${1}"
    unzip "$HOME/${1}"
    rm "$HOME/${1}"
    NAMED_RELEASE=$(echo "${1}" | sed -e 's/.zip//')
    mv "${PROJECT_NAME}-${NAMED_RELEASE}" "${PROJECT_NAME}"
}

# downloads the qubinode code using curl 
function curl_download(){
    if [ -x /usr/bin/curl ] ; then
        cd $HOME
        curl -OL  "${QUBINODE_ARCHIVE_URL}/${QUBINODE_ZIP_FILE}"
        extract_quibnode_installer "${QUBINODE_ZIP_FILE}"
    fi 
}

# starting the qubinode installer 
function start_qubinode_install(){
    cd "${PROJECT_DIR}/"
    ./"${PROJECT_NAME}" --setup
}

function git_clone_code(){
  git clone "${QUBINODE_URL}/${PROJECT_NAME}.git"
  cd "${PROJECT_NAME}"
  git checkout "${QUBINODE_BRANCH}"
}

# calling a wget to download  qubinode node code
function wget_download(){
    cd $HOME
    wget ${QUBINODE_ARCHIVE_URL}/${QUBINODE_ZIP_FILE}
    extract_quibnode_installer ${QUBINODE_ZIP_FILE}
}

# start the qubinode installer check and download if does not exist
function start_qubinode_download(){

  local unzip_found=no
  local git_found=no
  local wget_found=no
  local curl_found=no

  ## check for the presence of unzip
  if which unzip> /dev/null 2>&1
  then
      unzip_found=yes
  fi

  ## chek for git
  if which git> /dev/null 2>&1
  then
      git_found=yes
  fi

  ## chek for curl
  if which curl> /dev/null 2>&1
  then
      curl_found=yes
  fi

  ## chek for wget
  if which wget> /dev/null 2>&1
  then
      wget_found=yes
  fi

  ## download with curl and zip
  if [ "A${unzip_found}" == "Ayes" ] && [ "A${curl_found}" == "Ayes" ]
  then
      download_method=use_curl
  fi

  ## download with zip and wget
  if [ "A${unzip_found}" == "Ayes" ] && [ "A${wget_found}" == "Ayes" ]
  then
      download_method=use_wget
  fi

  ## download with git
  if [ "A${git_found}" == "Ayes" ]
  then
      download_method=use_git
  fi

  ## Download Qubinode Project
  if  [ ! -d "${PROJECT_DIR}" ]
  then
      case "$download_method" in
          use_curl)
              curl_download
	      ;;
	  use_wget)
              wget_download
	      ;;
	  use_git)
              git_clone_code
	      ;;
	  *)
              echo "Wasn't able to locate any of the following commands: wget, curl, git, zip"
              echo "Please install either curl or wget and zip or just git to continue with install"
              exit 1
      esac

      ## start install
      start_qubinode_install
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
    -i|--install              Install Qubinode installer 
    -d|--delete                 Remove Qubinode installer 
EOF
}

# Parsing menu items 
function parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h | --help)
                script_usage
                exit 0
                ;;
            -v | --verbose)
                verbose=true
                ;;
            -i | --install)
                start_qubinode_download
                ;;
            -d | --delete)
                remove_qubinode_folder
                ;;
            *)
                echo  "Invalid parameter was provided: $param" 
                script_usage
                exit 1
                ;;
        esac
    done
    shift "$((OPTIND-1))"
}


# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    parse_params "$@"
}

# Start main function 
#if [ -z $@ ];
if (( "$OPTIND" == 1 ))
then 
    start_qubinode_download
elif [ ! -z $@ ]
then
    main "$@"
else
    echo "Please see script usage."
    script_usage
fi 


