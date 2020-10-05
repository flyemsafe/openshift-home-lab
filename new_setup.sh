#!/bin/bash

# shellcheck disable=SC2034 # Define colours
red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;34m'
mag=$'\e[1;35m'
cyn=$'\e[1;36m'
def=$'\e[1;49m'
end=$'\e[0m'

## check for lib/global_functions.sh and source it
## or exit if it's now found
GLOBAL_FUNCTIONS="lib/global_functions.sh"
if [ -f "$GLOBAL_FUNCTIONS" ]
then
    # shellcheck disable=SC1091
    # shellcheck source=lib/global_functions.sh
    source "$GLOBAL_FUNCTIONS"
    setup_required_paths
else
    echo "Could not find $GLOBAL_FUNCTIONS. Make sure you are in the qubinode-installer directory"
fi

## This file consist of functions that are used throughout th code base

VAULT_FILE="${project_dir:?}/playbooks/vars/vault.yml"
QUBINODE_VARS="${project_dir:?}/playbooks/vars/qubinode_vars.yml"
CURRENT_USER=$(whoami)
RANDOM_GENERATED_PASS=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 8)
NAME_PREFIX="qbn"
GENERATED_DOMAIN="${CURRENT_USER}.lan"
GENERATED_IDM_HOSTNAME="${NAME_PREFIX}-idm01"

if [[ "A${LIBVIRT_DIR}" == "A" ]] || [[ "A${LIBVIRT_DIR}" == 'A""' ]]
then
    LIBVIRT_DIR=/var/lib/libvirt/images
else
    LIBVIRT_DIR="${LIBVIRT_DIR}"
fi


if [[ "A${ADMIN_USER}" == "A" ]] || [[ "A${ADMIN_USER}" == 'A""' ]]
then
    ADMIN_USER="$CURRENT_USER"
else
    ADMIN_USER="${ADMIN_USER}"
fi

## Load existing vars
if [ -f "$QUBINODE_VARS" ]
then
    set -o allexport
    # shellcheck disable=SC1091
    # shellcheck source=playbooks/vars/qubinode_vars.yml
    source "$QUBINODE_VARS"
    set +o allexport
fi

## OS Check
pre_os_check

## Get host primary disk
getPrimaryDisk

## check if ansible is installed
if which ansible > /dev/null 2>&1
then
  ANSIBLE_INSTALLED=yes
else
  ANSIBLE_INSTALLED=no
fi

## check if python3 is installed
if which python3> /dev/null 2>&1
then
  PYTHON3_INSTALLED=yes
else
  PYTHON3_INSTALLED=no
fi

## Get main network interface details
get_primary_interface

## These functions will prompt the user
## check sudoers status
HAS_SUDO=$(has_sudo)
if [ "A${HAS_SUDO}" != "Ahas_sudo__pass_set" ]
then
    SUDOERS_SETUP=no
    printf "%s\n\n\n" ""
    setup_sudoers
fi

check_vault_values
check_rhsm_status
ask_for_admin_user_pass
ask_user_for_rhsm_credentials
check_additional_storage
ask_about_idm
register_system
install_packages

cat > "${QUBINODE_VARS}" <<EOF
## qubinode variables for bash and ansible lookup

## not root user
ADMIN_USER="${CURRENT_USER:?}"

##---------------------------------------------------------------------
## Variables for bridge network interface / set to override installer
##---------------------------------------------------------------------
PRIMARY_DISK="${primary_disk:?}"
NETWORK_DEVICE="${netdevice:?}"
IPADDRESS="${ipaddress:?}"
GATEWAY="${gateway:?}"
NETWORK="${network:?}"
MACADDR="${macaddr:?}"

##---------------------------------------------------------------------
## Varibles for DNS server
##---------------------------------------------------------------------
REVERSE_ZONE="${reverse_zone:?}"
DOMAIN="${DOMAIN}"
DEPLOY_IDM="${DEPLOY_IDM}"
USE_EXISTING_IDM="${USE_EXISTING_IDM}"
IDM_EXISTING_HOSTNAME="${IDM_EXISTING_HOSTNAME}"
IDM_SERVER_HOSTNAME="${IDM_EXISTING_HOSTNAME:-$GENERATED_IDM_HOSTNAME}"
IDM_ADMIN_USER="${IDM_EXISTING_ADMIN_USER:-$ADMIN_USER}"
ALLOW_ZONE_OVERLAP="${ALLOW_ZONE_OVERLAP}"
IDM_SERVER_IP="${IDM_SERVER_IP}"
USE_IDM_STATIC_IP="${USE_IDM_STATIC_IP}"
IDM_DEPLOY_METHOD="${IDM_DEPLOY_METHOD}"
DEPLOY_NEW_IDM="${DEPLOY_NEW_IDM}"

##---------------------------------------------------------------------
## Libvirt variables
##---------------------------------------------------------------------
LIBVIRT_DIR="${LIBVIRT_DIR:?}"
LIBVIRT_POOL_DISK="${LIBVIRT_POOL_DISK}"
CREATE_LIBVIRT_LVM="${CREATE_LIBVIRT_LVM}"

##---------------------------------------------------------------------
## Varibles for RHSM
##---------------------------------------------------------------------
RHSM_SYSTEM="${RHSM_SYSTEM:?}"
RHEL_RELEASE="${rhel_release:?}"
RHEL_MAJOR="${rhel_major:?}"
SYSTEM_REGISTERED="${SYSTEM_REGISTERED:?}"
RHSM_REG_METHOD="${RHSM_REG_METHOD}"

##---------------------------------------------------------------------
## DO NOT CHANGE THESE
##---------------------------------------------------------------------
ANSIBLE_INSTALLED="${ANSIBLE_INSTALLED:?}"
PYTHON3_INSTALLED="${PYTHON3_INSTALLED:?}"
ALL_DISK="${ALL_DISK:?}"
ALL_INTERFACES="${ALL_INTERFACES:?}"
OS_NAME=${os_name:?}
VAULT_FILE="${VAULT_FILE:?}"
VERIFIED_NETWORKING="${VERIFIED_NETWORKING}"
QUBINODE_VARS="${QUBINODE_VARS}"

EOF

cat > "${VAULT_FILE:?}" <<EOF
---
rhsm_username: ${RHSM_USERNAME}
rhsm_password: ${RHSM_PASSWORD}
rhsm_org: ${RHSM_ORG}
rhsm_activationkey: ${RHSM_ACTKEY}
admin_user_password: ${ADMIN_USER_PASS}
idm_ssh_user: root
idm_dm_pwd: ${RANDOM_GENERATED_PASS:?}
idm_admin_pwd: ${IDM_USER_PASS:-$ADMIN_USER_PASS}
tower_pg_password: ${RANDOM_GENERATED_PASS:?}
tower_rabbitmq_password: ${RANDOM_GENERATED_PASS:?}
EOF
