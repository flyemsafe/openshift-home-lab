#!/bin/bash

function config_err_msg () {
    cat << EOH >&2
  There was an error finding the full path to the qubinode-installer project directory.
EOH
}

# this function just make sure the script
# knows the full path to the project directory
# and runs the config_err_msg if it can't determine
# that start_deployment.conf can find the project directory
function setup_required_paths () {
    project_dir="`dirname \"$0\"`"
    project_dir="`( cd \"$project_dir\" && pwd )`"
    if [ -z "$project_dir" ] ; then
        config_err_msg; exit 1
    fi

    if [ ! -d "${project_dir}/playbooks/vars" ] ; then
        config_err_msg; exit 1
    fi
}


##---------------------------------------------------------------------
## Functions for setting up sudoers
##---------------------------------------------------------------------
function has_sudo() {
    sudo -k
    local prompt

    prompt=$(sudo -n ls 2>&1)
    #prompt=$(sudo -nv 2>&1)
    if [ $? -eq 0 ]
    then
        echo "has_sudo__pass_set"
    elif echo $prompt | grep -q '^sudo:'
    then
        echo "has_sudo__needs_pass"
    else
        echo "no_sudo"
    fi
}

function elevate_cmd () {
    local cmd=$@

    HAS_SUDO=$(has_sudo)

    case "$HAS_SUDO" in
    has_sudo__pass_set)
        sudo $cmd
        ;;
    has_sudo__needs_pass)
        printf "%s\n" " Please supply sudo password for the following command: ${cyn}sudo $cmd${end}"
        sudo $cmd
        ;;
    *)
        printf "%s\n" " Please supply root password for the following command: ${cyn}su -c \"$cmd\"${end}"
        su -c "$cmd"
        ;;
    esac
}

function setup_sudoers () {
   printf "%s\n" ""
   printf "%s\n" "     ${txu}${txb}Setup Sudoers${txend}${txuend}"
   printf "%s\n" " The qubinode-installer runs as a normal user. It sets up"
   printf "%s\n" " your current user account for passwordless sudo."
   printf "%s\n" ""
   SUDOERS_TMP=$(mktemp)
   echo "${CURRENT_USER} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_TMP}"
   elevate_cmd test -f "/etc/sudoers.d/${CURRENT_USER}"
   sudo cp "${SUDOERS_TMP}" "/etc/sudoers.d/${CURRENT_USER}"
   sudo chmod 0440 "/etc/sudoers.d/${CURRENT_USER}"
}

##---------------------------------------------------------------------
## Get Storage Information
##---------------------------------------------------------------------
function getPrimaryDisk () {
    if which lsblk >/dev/null 2>&1
    then
        declare -a DISKS=()
        dev=$(eval $(lsblk -oMOUNTPOINT,PKNAME -P| \
		grep 'MOUNTPOINT="/"'); echo $PKNAME | sed 's/[0-9]*$//')
        PRIMARY_DISK_FOUND=no
        ALL_DISK=""
        if [ "A${dev}" != "A" ];
        then
           PRIMARY_DISK_FOUND=yes
           if [[ "A${PRIMARY_DISK}" == "A" ]] || [[ "A${PRIMARY_DISK}" == 'A""' ]]
           then
               primary_disk="$dev"
           else
               primary_disk="${PRIMARY_DISK}"
           fi
           mapfile -t DISKS < <(lsblk -dp | \
               grep -o '^/dev[^ ]*'|awk -F'/' '{print $3}' | \
               grep -v ${primary_disk})
           ALL_DISK="${DISKS[@]}"
        fi
    fi
}

##---------------------------------------------------------------------
## Get network information
##---------------------------------------------------------------------
get_primary_interface () {
    ## Get all interfaces except wireless and bridge
    declare -a INTERFACES=()
    mapfile -t INTERFACES < <(ip link | \
	    awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'|\
	    sed -e 's/^[[:space:]]*//')
    ALL_INTERFACES="${INTERFACES[@]}"
    
    if [[ "A${NETWORK_DEVICE}" == "A" ]] || [[ "A${NETWORK_DEVICE}" == 'A""' ]]
    then
        netdevice=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
    else
        netdevice="${NETWORK_DEVICE}"
    fi

    if [[ "A${IPADDRESS}" == "A" ]] || [[ "A${IPADDRESS}" == 'A""' ]]
    then
        ipaddress=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
    else
        ipaddress="${IPADDRESS}"
    fi

    if [[ "A${GATEWAY}" == "A" ]] || [[ "A${GATEWAY}" == 'A""' ]]
    then
        gateway=$(ip route get 8.8.8.8 | awk -F"via " 'NR==1{split($2,a," ");print a[1]}')
    else
        gateway="${GATEWAY}"
    fi

    if [[ "A${NETWORK}" == "A" ]] || [[ "A${NETWORK}" == 'A""' ]]
    then
        network=$(ip route | awk -F'/' "/$ipaddress/ {print \$1}")
    else
        network="${NETWORK}"
    fi

    if [[ "A${REVERSE_ZONE}" == "A" ]] || [[ "A${REVERSE_ZONE}" == 'A""' ]]
    then
        reverse_zone=$(echo "$network" | awk -F . '{print $4"."$3"."$2"."$1".in-addr.arpa"}'| sed 's/^[^.]*.//g')
    else
        reverse_zone="${REVERSE_ZONE}"
    fi

    if [[ "A${NETWORK_DEVICE}" == "A" ]] || [[ "A${NETWORK_DEVICE}" == 'A""' ]]
    then
        macaddr=$(ip addr show $netdevice | grep link | awk '{print $2}' | head -1)
    else
        macaddr="${MACADDR}"
    fi

    ## Verify networking
    if [ "A${VERIFIED_NETWORKING}" != "Ayes" ]
    then
        verify_networking
    fi
}

function verify_networking () {
    printf "%s\n" "  ${blu}Networking Details${end}"
    printf "%s\n" "  ${blu}***********************************************************${end}"
    printf "%s\n\n" "  The below networking information was discovered and will be used for setting a bridge network."
    
    printf "%s\n" "  ${blu}NETWORK_DEVICE${end}=${cyn}${netdevice:?}${end}"
    printf "%s\n" "  ${blu}IPADDRESS${end}=${cyn}${ipaddress:?}${end}"
    printf "%s\n" "  ${blu}GATEWAY${end}=${cyn}${gateway:?}${end}"
    printf "%s\n" "  ${blu}NETWORK${end}=${cyn}${network:?}${end}"
    printf "%s\n\n" "  ${blu}MACADDR${end}=${cyn}${macaddr:?}${end}"
    confirm "  Would you like to change these details? ${cyn}yes/no${end}"
    if [ "A${response}" == "Ayes" ]
    then
        printf "%s\n\n" "  ${blu}Choose a attribute to change: ${end}"
        tmp_file=$(mktemp)
        while true
        do
            networking_opts=("netdevice - ${cyn}${netdevice:?}${end}" \
                             "ipaddress - ${cyn}${ipaddress:?}${end}" \
                             "gateway   - ${cyn}${gateway:?}${end}" \
                             "network   - ${cyn}${network:?}${end}" \
                             "macaddr   - ${cyn}${macaddr:?}${end}" \
                             "Reset     - Revert changes" \
                             "Save      - Save changes")
            createmenu "${networking_opts[@]}"
            result=$(echo "${selected_option}"| awk '{print $1}')
            case $result in
                netdevice)
            	echo "netdevice=$netdevice" >> $tmp_file
                    echo -n "  Enter the network interface:  "
                    read user_input
                    confirm "  You entered ${cyn}$user_input${end}, is this correct? ${cyn}yes/no${end}"
                    if [ "A${response}" == "Ayes" ]
                    then
                        netdevice="$user_input"
                    fi
                    ;;
                ipaddress)
            	echo "ipaddress=$ipaddress" >> $tmp_file
                    echo -n "  Enter ip address to assign to ${netdevice}:  "
                    read user_input
                    confirm "  You entered ${cyn}$user_input${end}, is this correct? ${cyn}yes/no${end}"
                    if [ "A${response}" == "Ayes" ]
                    then
                        ipaddress="$user_input"
                    fi
                    ;;
                gateway)
            	echo "gateway=$gateway" >> $tmp_file
                    echo -n "  Enter gateway address to assign to ${netdevice}:  "
                    read user_input
                    confirm "  You entered ${cyn}$user_input${end}, is this correct? ${cyn}yes/no${end}"
                    if [ "A${response}" == "Ayes" ]
                    then
                        gateway="$user_input"
                    fi
                    ;;
                network)
            	echo "network=$network" >> $tmp_file
                    echo -n "  Enter the netmask cidr for ip ${ipaddress}:  "
                    read user_input
                    confirm "  You entered ${cyn}$user_input${end}, is this correct? ${cyn}yes/no${end}"
                    if [ "A${response}" == "Ayes" ]
                    then
                        network="$user_input"
                    fi
                    ;;
                macaddr)
            	echo "macaddr=$macaddr" >> $tmp_file
                    echo -n "  Enter the mac address assocaited with ${netdevice}:  "
                    read user_input
                    confirm "  You entered ${cyn}$user_input${end}, is this correct? ${cyn}yes/no${end}"
                    if [ "A${response}" == "Ayes" ]
                    then
                        macaddr="$user_input"
                    fi
                    ;;
                Reset)
            	source $tmp_file
            	echo > $tmp_file
                    ;;
                Save) 
                    break
            	;;
                * ) 
                    echo "Please answer a valid choice"
            	;;
            esac
        
        done
    fi

    ## Mark network verification as done
    VERIFIED_NETWORKING=yes
}

##---------------------------------------------------------------------
## Check for RHSM registration
##---------------------------------------------------------------------
function pre_os_check () {
    RHSM_SYSTEM=no
    rhel_release=$(cat /etc/redhat-release | grep -o [7-8].[0-9])
    rhel_major=$(sed -rn 's/.*([0-9])\.[0-9].*/\1/p' /etc/redhat-release)
    os_name=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
    if [ "A${os_name}" == 'A"Red Hat Enterprise Linux"' ]
    then
	RHSM_SYSTEM=yes
        if ! which subscription-manager > /dev/null 2>&1
        then
            printf "%s\n" ""
            printf "%s\n" " ${red}Error: subcription-manager command not found.${end}"
            printf "%s\n" " ${red}The subscription-manager command is required.${end}"
	    exit 1
	fi
    fi
}

	    
function check_rhsm_status () {
    SYSTEM_REGISTERED=no
    if [ "A${RHSM_SYSTEM}" == 'Ayes' ]
    then
	if sudo subscription-manager status | grep -q 'Overall Status: Current'
        then
	    SYSTEM_REGISTERED=yes
	else
	    SYSTEM_REGISTERED=no
        fi
    fi
}

function verify_rhsm_status () {
   sudo subscription-manager identity > /dev/null 2>&1
   RESULT="$?"
   if [ "A${RESULT}" == "A1" ]
   then
       printf "%s\n" " ${red}This system is not yet registered to Red Hat.${end}"
       printf "%s\n\n" " Please run: ${grn}qubinode-installer -m rhsm${end}"
       exit 1
   fi

   status_result=$(mktemp)
   sudo subscription-manager status > "${status_result}" 2>&1
   status=$(awk -F: '/Overall Status:/ {print $2}' "${status_result}"|sed 's/^ *//g')
   if [ "A${status}" != "ACurrent" ]
   then
       sudo subscription-manager refresh > /dev/null 2>&1
       sudo subscription-manager attach --auto > /dev/null 2>&1
   fi

   #check again
   sudo subscription-manager status > "${status_result}" 2>&1
   status=$(awk -F: '/Overall Status:/ {print $2}' "${status_result}"|sed 's/^ *//g')
   if [ "A${status}" != "ACurrent" ]
   then
       printf "%s\n" " Cannot determine the subscription status of ${yel}$(hostname)${end}"
       printf "%s\n" " Error details are: "
       cat "${status_result}"
       printf "%s\n\n" " Please resolved and try again"
       exit 1
   else
       printf "%s\n\n" "  ${yel}Successfully registered $(hostname) to RHSM${end}"
   fi
}

function register_system () {

    if [ "A${RHSM_SYSTEM}" == "Ayes" -a "A${SYSTEM_REGISTERED}" == "Ano" ]
    then
        printf "%s\n" "  ${blu}***********************************************************${end}"
        printf "%s\n" "  ${blu}RHSM Registration${end}"
        rhsm_reg_result=$(mktemp)
        echo sudo subscription-manager register \
    	      "${RHSM_CMD_OPTS}" --force \
    	      --release="'${RHEL_RELEASE}'"|\
    	      sh > "${rhsm_reg_result}" 2>&1
        RESULT="$?"
        if [ ${RESULT} -eq 0 ]
        then
            verify_rhsm_status
	    SYSTEM_REGISTERED="yes"
    	else
    	    printf "%s\n" " ${red}$(hostname) registration to RHSM was unsuccessfull.${end}"
            cat "${rhsm_reg_result}"
	    exit 1
        fi
    fi
}


##---------------------------------------------------------------------
## Get User Input
##---------------------------------------------------------------------

## Confirm user selection
function confirm () {
    continue=""
    while [[ "${continue}" != "yes" ]];
    do
        read -r -p "${1:-Are you sure Yes or no?} " response
        if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            response="yes"
            continue="yes"
        elif [[ $response =~ ^([nN][oO])$ ]]
        then
            #echo "You choose $response"
            response="no"
            continue="yes"
        else
            printf "%s\n" " ${blu}Try again!${end}"
        fi
    done
}

# generic user choice menu
# this should eventually be used anywhere we need
# to provide user with choice
function createmenu () {
    select selected_option; do # in "$@" is the default
        if [ $REPLY -eq $REPLY ]
        #if [ "$REPLY" == "$REPLY" 2>/dev/null ]
        then
            if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#)) ]; then
                break;
            else
                echo "    ${blu}Please make a vaild selection (1-$#).${end}"
            fi
         else
            echo "    ${blu}Please make a vaild selection (1-$#).${end}"
         fi
    done
}

# this configs prints out asterisks when sensitive data
# is being entered
function read_sensitive_data () {
    # based on shorturl.at/BEHY3
    sensitive_data=''
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && { printf '\n'; break; } # ENTER pressed; output \n and break.
      if [[ $char == $'\x7f' ]]; then # backspace was pressed
          # Remove last char from output variable.
          [[ -n $sensitive_data ]] && sensitive_data=${sensitive_data%?}
          # Erase '*' to the left.
          printf '\b \b'
      else
        # Add typed char to output variable.
        sensitive_data+=$char
        # Print '*' in its stead.
        printf '*'
      fi
    done
}

function check_vault_values () {
    ANSIBLE_VAULT_CMD_EXIST=no
    vault_parse_cmd="cat"
    if which ansible-vault >/dev/null 2>&1
    then
        ANSIBLE_VAULT_CMD_EXIST=yes
        if ansible-vault view "${VAULT_FILE}" >/dev/null 2>&1
        then
	    vault_parse_cmd="ansible-vault view"
	fi
    fi

    if [ -f "${VAULT_FILE}" ]
    then
        RHSM_USERNAME=$($vault_parse_cmd "${VAULT_FILE}" | awk '/rhsm_username:/ {print $2}')
        RHSM_PASSWORD=$($vault_parse_cmd "${VAULT_FILE}" | awk '/rhsm_password:/ {print $2}')
        RHSM_ORG=$($vault_parse_cmd "${VAULT_FILE}" | awk '/rhsm_org:/ {print $2}')
        RHSM_ACTKEY=$($vault_parse_cmd "${VAULT_FILE}" | awk '/rhsm_activationkey:/ {print $2}')
        ADMIN_USER_PASS=$($vault_parse_cmd "${VAULT_FILE}" | awk '/admin_user_password:/ {print $2}')
        IDM_SSH_USER=$($vault_parse_cmd "${VAULT_FILE}" | awk '/idm_ssh_user:/ {print $2}')
        IDM_DM_PASS=$($vault_parse_cmd "${VAULT_FILE}" | awk '/idm_dm_pwd:/ {print $2}')
        IDM_ADMIN_PASS=$($vault_parse_cmd "${VAULT_FILE}" | awk '/idm_admin_pwd:/ {print $2}')
        TOWER_PG_PASS=$($vault_parse_cmd "${VAULT_FILE}" | awk '/tower_pg_password:/ {print $2}')
        TOWER_MQ_PASS=$($vault_parse_cmd "${VAULT_FILE}" | awk '/tower_rabbitmq_password:/ {print $2}')
        IDM_USER_PASS=$($vault_parse_cmd "${VAULT_FILE}" | awk '/idm_admin_pwd:/ {print $2}')
    fi
}

function rhsm_get_reg_method () {
    printf "%s\n" "  ${blu}***********************************************************${end}"
    printf "%s\n\n" "  ${blu}Red Hat Subscription Registration${end}"

    printf "%s\n" "  Your credentials for access.redhat.com is needed."
    printf "%s\n" "  RHSM registration has two methods:"
    printf "%s\n" "     option 1: ${cyn}activation key${end}"
    printf "%s\n\n" "     option 2: ${cyn}username/password${end}"
    printf "%s\n\n" "  Option 2 is the most commonly used"
    printf "%s\n" "  ${blu}Choose a registration method${end}"
    rhsm_msg=("Activation Key" "Username and Password")
    createmenu "${rhsm_msg[@]}"
    rhsm_reg_method="${selected_option}"
    RHSM_REG_METHOD=$(echo "${rhsm_reg_method}"|awk '{print $1}')
}

function accept_sensitive_input () {
    while true
    do
        printf "%s" "  $MSG_ONE"
        read_sensitive_data
        USER_INPUT1="${sensitive_data}"
        printf "%s" "  $MSG_TWO"
        read_sensitive_data
        USER_INPUT2="${sensitive_data}"
        [ "$USER_INPUT1" == "$USER_INPUT2" ] && break
        printf "%s\n"  "  ${cyn}Please try again${end}: "
        printf "%s\n"
    done
}

        
function rhsm_credentials_prompt () {
    if [ "A${RHSM_REG_METHOD}" == "AUsername" ]
    then
        if [[ "A${RHSM_USERNAME}" == 'A""' ]] || [[ "A${RHSM_USERNAME}" == 'A' ]]
        then
            printf "%s\n" ""
            echo -n "  Enter your RHSM username and press ${cyn}[ENTER]${end}: "
            read rhsm_username
            confirm "  You entered ${cyn}$rhsm_username${end}, is this correct? ${cyn}yes/no${end}"
            if [ "A${response}" == "Ayes" ]
            then
                RHSM_USERNAME="$rhsm_username"
            fi
	    
        fi

        if [[ "A${RHSM_PASSWORD}" == 'A""' ]] || [[ "A${RHSM_PASSWORD}" == 'A' ]]
        then
	    MSG_ONE="Enter your RHSM password and press ${cyn}[ENTER]${end}:"
            MSG_TWO="Enter your RHSM password password again ${cyn}[ENTER]${end}:"
	    accept_sensitive_input
            RHSM_PASSWORD="${USER_INPUT2}"
        fi

	## set registration argument
	RHSM_CMD_OPTS="--username=${RHSM_USERNAME} --password=${RHSM_PASSWORD}"
    fi

    if [ "A${RHSM_REG_METHOD}" == "AActivation" ]
    then
        if [[ "A${RHSM_ORG}" == 'A""' ]] || [[ "A${RHSM_ORG}" == 'A' ]]
        then
            printf "%s\n\n" ""
	    MSG_ONE="Enter your RHSM org id and press ${cyn}[ENTER]${end}:"
            MSG_TWO="Enter your RHSM org id again ${cyn}[ENTER]${end}:"
	    accept_sensitive_input
            RHSM_ORG="${USER_INPUT2}"
        fi

        if [[ "A${RHSM_ACTKEY}" == 'A""' ]] || [[ "A${RHSM_ACTKEY}" == 'A' ]]
        then
            echo -n "  ${blu}Enter your RHSM activation key and press${end} ${cyn}[ENTER]${end}: "
            read rhsm_actkey
            confirm "  You entered ${cyn}$rhsm_actkey${end}, is this correct? ${cyn}yes/no${end}"
            if [ "A${response}" == "Ayes" ]
            then
                RHSM_ACTKEY="$rhsm_actkey"
            fi
        fi

	## Set registration argument
	RHSM_CMD_OPTS="--org=${RHSM_ORG} --activationkey=${RHSM_ACTKEY}"
    fi
}

function ask_user_for_rhsm_credentials () {
    if [[ "A${RHSM_REG_METHOD}" == "A" ]] || [[ "A${RHSM_REG_METHOD}" == 'A""' ]]
    then
	rhsm_get_reg_method
        rhsm_credentials_prompt
    else
        rhsm_credentials_prompt
    fi
}

function ask_for_admin_user_pass () {
    # root user password to be set for virtual instances created
    if [[ "A${ADMIN_USER_PASS}" == 'A""' ]] || [[ "A${ADMIN_USER_PASS}" == 'A' ]]
    then
        printf "%s\n\n" ""
        printf "%s\n" "  When entering passwords, do not ${cyn}Backspace${end}."
        printf "%s\n" "  Use ${cyn}Ctrl-c${end} to cancel then run the installer again."
	printf "%s\n" "  ${blu}***********************************************************${end}"
        printf "%s\n" "  Your username ${cyn}${CURRENT_USER}${end} will be used to ssh into all the VMs created."

        MSG_ONE="Enter a password for ${cyn}${CURRENT_USER}${end} ${blu}[ENTER]${end}:"
        MSG_TWO="Enter a password again for ${cyn}${CURRENT_USER}${end} ${blu}[ENTER]${end}:"
        accept_sensitive_input
        ADMIN_USER_PASS="$USER_INPUT2"
    fi
}

function check_additional_storage () {
    getPrimaryDisk
    if [[ "A${CREATE_LIBVIRT_LVM}" != "Ano" ]]
    then
        if [[ "A${LIBVIRT_POOL_DISK}" == "A" ]] || [[ "A${LIBVIRT_POOL_DISK}" == 'A""' ]]
        then
            CHECK_STORAGE=yes
            CREATE_LIBVIRT_LVM=yes
        else
            LIBVIRT_POOL_DISK="$LIBVIRT_POOL_DISK"
            CHECK_STORAGE=no
        fi
    else
        ## default behaviour is to dedicate a disk to libvirt directory pool
        CREATE_LIBVIRT_LVM="$CREATE_LIBVIRT_LVM"
    fi

    if [ "A${CHECK_STORAGE}" == "Ayes" ]
    then
        printf "%s\n" "  ${blu}***********************************************************${end}"
        printf "%s\n\n" "    ${cyn}Storage Setup${end}"
        printf "%s\n" "   It is recommended to dedicate a disk to $LIBVIRT_DIR."
        printf "%s\n" "   Qubinode uses libvirt directory pool for VM disk storage"
        printf "%s\n" ""

        declare -a AVAILABLE_DISKS=($ALL_DISK)
        if [ ${#AVAILABLE_DISKS[@]} -gt 1 ]
        then
            printf "%s\n" "   Your primary storage device appears to be ${blu}${PRIMARY_DISK}${end}."
            printf "%s\n\n" "   The following additional storage devices where found:"

            for disk in $(echo ${AVAILABLE_DISKS[@]})
            do
                printf "%s\n" "     ${blu} * ${end}${blu}$disk${end}"
            done
        fi


        confirm "   Do you want to dedicate a storage device: ${blu}yes/no${end}"
        printf "%s\n" " "
        if [ "A${response}" == "Ayes" ]
        then
            printf "%s\n" "   Please select secondary disk to be used."
            createmenu "${AVAILABLE_DISKS[@]}"
            libvirt_pool_disk=$(echo "${selected_option}"|awk '{print $1}')
            LIBVIRT_POOL_DISK="$libvirt_pool_disk"
            CREATE_LIBVIRT_LVM=yes
	else
            LIBVIRT_POOL_DISK=""
            CREATE_LIBVIRT_LVM=no
        fi
    fi
}

function ask_idm_password () {
    # root user password to be set for virtual instances created
    if [[ "A${IDM_USER_PASS}" == 'A""' ]] || [[ "A${IDM_USER_PASS}" == 'A' ]]
    then
        printf "%s\n\n" ""
        printf "%s\n" "  When entering passwords, do not ${blu}Backspace${end}."
        printf "%s\n" "  Use ${blu}Ctrl-c${end} to cancel then run the installer again."
        unset IDM_USER_PASS
        printf "%s\n" "  ${blu}**************************************************${end}"
        MSG_ONE="Enter a password for the IdM server ${blu}${IDM_SERVER_HOSTNAME}.${DOMAIN}${end} ${cyn}[ENTER]${end}:"
        MSG_TWO="Enter a password again for the IdM server ${blu}${IDM_SERVER_HOSTNAME}.${DOMAIN}${end} ${cyn}[ENTER]${end}:"
        accept_sensitive_input
        IDM_USER_PASS="${USER_INPUT2}"
    fi
}

function set_idm_static_ip () {
    printf "%s\n" ""
    read -p " $static_ip_msg: " USER_IDM_SERVER_IP
    idm_server_ip="${USER_IDM_SERVER_IP}"
    confirm "  You entered ${cyn}$idm_server_ip${end}, is this correct? ${cyn}yes/no${end}"
    if [ "A${response}" == "Ayes" ]
    then
        IDM_SERVER_IP="${idm_server_ip}"
	USE_IDM_STATIC_IP=yes
        printf "%s\n\n" " $static_ip_result_msg ${cyn}$idm_server_ip${end}"
    fi
}

function ask_about_domain() {
    if [[ "A${DOMAIN}" == "A" ]] || [[ "A${DOMAIN}" == 'A""' ]]
    then
        printf "%s\n" "   The domain ${blu}${GENERATED_DOMAIN}${end} was generated for you."
        confirm "   Do you want to change it? ${blu}yes/no${end}"
        if [ "A${response}" == "Ayes" ]
        then
            echo -n "   Enter your domain name: "
            read USER_DOMAIN
            DOMAIN="$USER_DOMAIN"
        else
            DOMAIN="${GENERATED_DOMAIN}"
        fi
    fi
}


function ask_about_idm() {
    ## Should IdM be deployed
    if [[ "A${DEPLOY_IDM}" == "Ayes" ]] || [[ "A${DEPLOY_IDM}" != 'Ano' ]]
    then
	case "${IDM_DEPLOY_METHOD}" in new|existing|no)
            DEPLOY_IDM="no"
	    ;;
	*)
            printf "%s\n" "  ${blu}***********************************************************${end}"
            printf "%s\n\n" "  ${blu}Red Hat Identity Manager (IdM)${end}"
            printf "%s\n" "  An IdM server can be deployed if LDAP is needed."
            printf "%s\n" "  The installer can deploy or connect to an existing IdM server."
            printf "%s\n" "  What would you like to do?"
            idm_choices=('new' 'existing' 'no deployment')
            createmenu "${idm_choices[@]}"
            idm_choice=$(echo "${selected_option}"|awk '{print $1}')
            confirm "  Continue with ${blu}$idm_choice${end} deployment of IdM server? ${blu}yes/no${end}"
            if [ "A${response}" == "Ayes" ]
            then
                DEPLOY_IDM="yes"
                IDM_DEPLOY_METHOD="${idm_choice}"
		if [ "A${IDM_DEPLOY_METHOD}" == "Aexisting" ]
		then
		    USE_EXISTING_IDM=yes
		else
		    USE_EXISTING_IDM=no
		fi
            else
                printf "%s\n" "  You can change configuration options $QUBINODE_VARS"
                printf "%s\n" "  and run the installer again."
            fi
	    ;;
	esac
    fi

    ## Verify domain with user
    ask_about_domain

    ## Options for IDM server deployment
    if [[ "A${USE_EXISTING_IDM}" == "Ayes" ]]
    then
	if [ "A${IDM_EXISTING_HOSTNAME}" == "A" -a "A${IDM_EXISTING_HOSTNAME}" == 'A""' ]
	then
            printf "%s\n" "  Please provide the hostname of the existing IdM server."
            printf "%s\n\n" "  For example if you IdM server is ${blu}dns01.lab.com${end}, you should enter ${blu}dns01${end}."
            read -p "  ${blu}Enter the existing DNS server hostname?${end} " IDM_NAME
            idm_hostname="${IDM_NAME}"
            confirm "  You entered ${cyn}$idm_hostname${end}, is this correct? ${cyn}yes/no${end}"
            if [ "A${response}" == "Ayes" ]
            then
                IDM_EXISTING_HOSTNAME="$idm_hostname"
            fi
	fi

	if [ "A${IDM_SERVER_IP}" == "A" -a "A${IDM_SERVER_IP}" == 'A""' ]
	then
    	    ## Get the Idm server ip
	    static_ip_msg=" Enter the ip address for the existing IdM server"
            static_ip_result_msg=" The qubinode-installer will connect to the IdM server on"
    	    set_idm_static_ip
	fi

	if [ "A${IDM_EXISTING_ADMIN_USER}" == "A" -a "A${IDM_EXISTING_ADMIN_USER}" == 'A""' ]
	then
            read -p "  What is the your existing IdM server admin username? " IDM_USER
            idm_admin_user=$IDM_USER
            confirm "  You entered $idm_admin_user, is this correct? ${blu}yes/no${end}"
            if [ "A${response}" == "Ayes" ]
            then
    	    IDM_EXISTING_ADMIN_USER="$idm_admin_user"
            fi
	fi

	##get user password
	ask_idm_password
    fi

    ### Deploy new IdM server
    if [[ "A${IDM_DEPLOY_METHOD}" == "Anew" ]]
    then
	USE_EXISTING_IDM=no
	if [ "A${IDM_SERVER_IP}" == "A" -a "A${IDM_SERVER_IP}" == 'A""' ]
	then
            printf "%s\n" ""
            printf "%s\n" "  The IdM server will be assigned a dynamic ip address from"
            printf "%s\n\n" "  your network. You can assign a static ip address instead."
            confirm "  Would you like to assign a static ip address to the IdM server? ${cyn}yes/no${end}"
            if [ "A${response}" == "Ayes" ]
            then
                static_ip_msg=" Enter the ip address you would like to assign to the IdM server"
                static_ip_result_msg=" The qubinode-installer will connect to the IdM server on"
                set_idm_static_ip
            fi
	fi
    fi

    ## allow-zone-overlap
    if [ "A${ALLOW_ZONE_OVERLAP}" == "A" -a "A${ALLOW_ZONE_OVERLAP}" == 'A""' ]
    then
        printf "%s\n" "  You can safely choose no for this next question."
        printf "%s\n" "  Choose yes if you using an existing domain name."
        confirm "  Would you like to enable allow-zone-overlap? ${cyn}yes/no${end}"
        if [ "A${response}" == "Ayes" ]
        then
             ALLOW_ZONE_OVERLAP=yes
        else
             ALLOW_ZONE_OVERLAP=no
        fi
    fi
}

##---------------------------------------------------------------------
## KVM HOST SETUP
##---------------------------------------------------------------------
function install_packages () {
   # install python
    if [ "A${PYTHON3_INSTALLED}" == "Ano" -o "A${ANSIBLE_INSTALLED}" == "Ano" ]
    then
        printf "%s\n" "  ${blu}***********************************************************${end}"
        printf "%s\n\n" "  ${blu}Install Packages${end}"
        if [[ $RHEL_MAJOR == "8" ]]
        then
	    ENABLED_REPOS=$(mktemp)
	    sudo subscription-manager repos --list-enabled > "${ENABLED_REPOS}"
	    for repo in $(echo rhel-8-for-x86_64-baseos-rpms rhel-8-for-x86_64-appstream-rpms ansible-2-for-rhel-8-x86_64-rpms)
	    do
                if ! grep -q $repo "${ENABLED_REPOS}"
		then
                    sudo subscription-manager repos --enable="${repo}" > /dev/null 2>&1
                fi
            done
	fi

	## RHEL7
        if [[ $RHEL_MAJOR == "7" ]]; then
            if [ ! -f /usr/bin/python ]
            then
                printf "%s\n" "   ${yel}Installing required rpms..${end}"
                sudo yum clean all > /dev/null 2>&1
                sudo yum install -y -q -e 0 python python3-pip python2-pip python-dns ansible git podman python-podman-api toolbox
            fi
	 fi

	 ## Install on RHEL8 and fedora
	 if [[ "A${OS_NAME}" == "AFedora" ]] || [[ "$RHEL_MAJOR" == "8" ]]
         then
             printf "%s\n" "   ${yel}Installing required python rpms..${end}"
             sudo yum clean all > /dev/null 2>&1
             sudo rm -r /var/cache/dnf
             sudo yum install -y -q -e 0 python3 python3-pip python3-dns ansible git podman python-podman-api toolbox> /dev/null 2>&1
	 fi

        ## check if python3 is installed
        if which python3> /dev/null 2>&1
        then
          PYTHON3_INSTALLED=yes
        else
          PYTHON3_INSTALLED=no
        fi
    fi

}
