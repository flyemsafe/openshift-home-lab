#!/bin/bash

# @file qubinode_kvmhost.sh
# @brief A library for discovering facts about the kvm host.
# @description
#   This library updates the ansible vars playbooks/vars/kvm_host.yml then executes
#   the ansible playbook playbooks/setup_kvmhost.yml.

# @description
# Defines vars that are used across all libraries for the project
function kvm_host_variables () {
    ## Ansible vars files
    kvm_host_vars_file="${project_dir}/playbooks/vars/kvm_host.yml"
    all_vars_file="${project_dir}/playbooks/vars/all.yml"


    ###########################################
    ## check ansible vars for predefined values
    ## or update the ansible vars with discovered values

    ## Define this host as a Qubinode
    QUBINODE_SYSTEM=$(awk '/run_qubinode_setup:/ {print $2; exit}' ${kvm_host_vars_file} | tr -d '"')
    libvirt_pool_name=$(cat "${kvm_host_vars_file}" | grep libvirt_pool_name: | awk '{print $2}')
    kvm_host_interface=$(cat "${kvm_host_vars_file}" | grep kvm_host_interface: | awk '{print $2}')
    vg_name=$(cat "${kvm_host_vars_file}"| grep vg_name: | awk '{print $2}')
    requested_brigde=$(cat "${kvm_host_vars_file}"|grep  vm_libvirt_net: | awk '{print $2}' | sed 's/"//g')
    
    ## This is a global var used by functions like qubinode_setup
    host_completed=$(awk '/qubinode_installer_host_completed:/ {print $2;exit}' ${kvm_host_vars_file})

    ## Check if RHEL_RELEASE is already defined
    if awk '/rhel_release:/ {print $2}' ${kvm_host_vars_file} |grep -q [0-9]
    then
        RHEL_RELEASE=$(awk '/rhel_release:/ {print $2}' ${kvm_host_vars_file} |grep [0-9])
    else
        RHEL_RELEASE=""
    fi

    RHEL_VERSION=$(awk '/rhel_version:/ {print $2}' "${all_vars_file}")
    # Set the RHEL version
    if grep '""' "${kvm_host_vars_file}"|grep -q rhel_release
    then
        rhel_release=$(cat /etc/redhat-release | grep -o [7-8].[0-9])
        sed -i "s#rhel_release: \"\"#rhel_release: "$rhel_release"#g" "${kvm_host_vars_file}"
    fi

    local host_rhel_major=$(sed -rn 's/.*([0-9])\.[0-9].*/\1/p' /etc/redhat-release)
    if [ "A${host_rhel_major}" == "A8" ]
    then
       rhel_release=$(awk '/rhel8_version:/ {print $2}' "${all_vars_file}")
    elif [ "A${host_rhel_major}" == "A7" ]
    then
       rhel_release=$(awk '/rhel7_version:/ {print $2}' "${all_vars_file}")
    else
        rhel_release=$(cat /etc/redhat-release | grep -o [7-8].[0-9])
    fi

    if [[ $RHEL_VERSION == "RHEL8" ]]; then
      sed -i 's#libvirt_pkgs_8:#libvirt_pkgs:#g' "${all_vars_file}"
    elif [[ $RHEL_VERSION == "RHEL7" ]]; then
      sed -i 's#libvirt_pkgs_7:#libvirt_pkgs:#g' "${all_vars_file}"
    fi
}

# @description
# Trys to determine which disk device is assosiated with the root mount /.
function getPrimaryDisk () {
    root_mount_lvm=$(/usr/bin/findmnt -nr -o source /)
    primary_disk=$(sudo lvs -o devices --no-headings $root_mount_lvm 2>/dev/null |grep -oP '\/dev\/.*(a)' | awk -F'/' '{print $3}'|sort -un)
    if [ "A${primary_disk}" == "A" ];
    then
       primary_disk=$(/usr/bin/findmnt -nr -o source / | sed -e "s/\/dev\///g")
       echo "lvs not found setting $primary_disk as primary disk"
    else
        primary_disk=$(sudo lvs -o devices --no-headings $root_mount_lvm 2>/dev/null |grep -oP '\/dev\/.*(a)' | awk -F'/' '{print $3}'|sort -un)
        #echo "lvs was found setting ${primary_disk} as primary disk"
    fi  
}

# @description
# If multiple disk devices are found on the kvm host, ask the user if they
# would like to dedicate a disk device for /var/lib/libivrt/images.
# If the var run_storage_check is set to skip, this function terminates.
function check_additional_storage () {
    ## Load system wide variables
    setup_variables

    ## check 
    CHECK_STORAGE=$(awk '/run_storage_check:/ {print $2;}' "${kvm_host_vars_file}" | tr -d '"')

    ## Skip this block if storage
    if [ "A${CHECK_STORAGE}" != "Askip" ]
    then

        printf "%s\n" "  ${yel}****************************************************************************${end}"
        printf "%s\n\n" "    ${cyn}        Storage Setup${end}"
        getPrimaryDisk
        DISK="${primary_disk}"

        declare -a ALL_DISKS=()
        mapfile -t ALL_DISKS < <(lsblk -dp | grep -o '^/dev[^ ]*'|awk -F'/' '{print $3}')
        if [ ${#ALL_DISKS[@]} -gt 1 ]
        then
            printf "%s\n" "   Multiple storage devices are found, you can dedicate one for use exclusively with"
            printf "%s\n" "   $libvirt_dir. This is where the virtual disk devices for all VM’s"
            printf "%s\n" "   are stored. Please note that this process wipes the storage device"
            printf "%s\n" "   then creates a new volume group and logical volume for use with"
            printf "%s\n" "   $libvirt_dir."
            printf "%s\n" ""
            printf "%s\n" "   Your primary storage device appears to be ${yel}${DISK}${end}."
            printf "%s\n\n" "   The following additional storage devices where found:"

            ## List all additional storage devices found
            for disk in $(echo ${ALL_DISKS[@]})
            do
              if [[ $disk != "$primary_disk" ]]
              then
                 printf "%s\n" "     ${yel} * ${end}${blu}$disk${end}"
              fi
            done

            confirm "   Do you want to dedicate a storage device: ${blu}yes/no${end}"
            printf "%s\n" " "
            if [ "A${response}" == "Ayes" ]
            then
              getPrimaryDisk
              echo "Please Select secondary disk to be used."
              DISK="${primary_disk}"

              declare -a ALL_DISKS=()
              mapfile -t ALL_DISKS < <(lsblk -dp | grep -o '^/dev[^ ]*'|awk -F'/' '{print $3}' | grep -v ${primary_disk})
              createmenu "${ALL_DISKS[@]}"
              disk=($(echo "${selected_option}"))

              printf "%s\n" "   ${yel}The installer will wipe the device${end} ${blu}$disk${end} ${yel}and then create a vg,lv and mount it as /var/lib/libvirt/images.${end}"
              confirm "    Continue with $disk? ${blu}yes/no${end}"
              if [ "A${response}" == "Ayes" ]
              then
                  printf "%s\n\n" ""
                  printf "%s\n\n" " ${mag}Using disk: $disk${end}"
                  DISK="${disk}"
                  sed -i "s/create_lvm:.*/create_lvm: "yes"/g" "${kvm_host_vars_file}"
                  sed -i "s/run_storage_check:.*/run_storage_check: "skip"/g" "${kvm_host_vars_file}"
                  sed -i "s/kvm_host_libvirt_extra_disk:.*/kvm_host_libvirt_extra_disk: $DISK/g" "${kvm_host_vars_file}"
              else
                  printf "%s\n\n" " ${mag}Exiting the install, please examine your disk choices and try again.${end}"
                  exit 0
              fi
            else
                setsingledisk
            fi
        else
            setsingledisk
        fi

        #printf "%s\n" "   You can change the path to where the VM disk devices are stored."
        #printf "%s\n" "   The current path is $libvirt_dir. Choose no below if you are not familiar with this."
        #printf "%s\n" "   "
        #confirm "   Do you want to dedicate a storage device: ${blu}yes/no${end}"
        #printf "%s\n" " "
        #if [ "A${response}" == "Ayes" ]
        #then
        #   echo blah
        #fi

    fi

}

#Configure System to use single disk
function setsingledisk()
{
    getPrimaryDisk
    DISK="${primary_disk}"

    printf "%s\n" "   Looks like no additional disk is available."
    printf "%s\n" "   Continuing with your primary storage device: ${yel}${DISK}${end}."
    printf "%s\n\n" "   No changes will be made to ${yel}${DISK}${end}"
    sed -i "s/kvm_host_libvirt_extra_disk:.*/kvm_host_libvirt_extra_disk: $DISK/g" "${kvm_host_vars_file}"
    sed -i "s/run_storage_check:.*/run_storage_check: "skip"/g" "${kvm_host_vars_file}"
    sed -i "s/create_lvm:.*/create_lvm: "no"/g" "${kvm_host_vars_file}"
    printf "%s\n" "  ${yel}****************************************************************************${end}"
echo "I AM HERE $FUNCNAME"  
}

# Ask if this host should be setup as a qubinode host
function ask_user_if_qubinode_setup () {
    # ensure all required variables are setup
    setup_variables
    QUBINODE_SYSTEM=$(awk '/run_qubinode_setup:/ {print $2; exit}' "${kvm_host_vars_file}" | tr -d '"')
    # Ask user if this system should be a qubinode
    if [ "A${QUBINODE_SYSTEM}" == "A" ]
    then
        printf "%s\n" "     ${yel}******************${end}"
        printf "%s\n" "     ${yel}*${end} ${cyn}Qubinode Setup${end} ${yel}*${end}"
        printf "%s\n" "     ${yel}******************${end}"
        printf "%s\n" "   The qubinode-installer configures your hardware as a KVM host"
        printf "%s\n\n" "   otherwise referred as ${grn}Qubinode${end}."

        printf "%s\n" " You can choose ${yel}no${end} if all the following are true: "
        printf "%s\n" "  ${mag}(*)${end} ${blu}A libvirt bridge network is already setup.${end}"
        printf "%s\n" "  ${mag}(*)${end} ${blu}The system is already setup to function as a KVM host.${end}"
        printf "%s\n\n" "  ${mag}(*)${end} ${blu}The system is already registered to Red Hat.${end}"

        printf "%s\n" " If any of the following are ture, choose ${yel}no${end} : "
        printf "%s\n" "  ${mag}(*)${end} ${blu}Your system only have one storage device.${end}"
        printf "%s\n\n" "  ${mag}(*)${end} ${blu}You don't want to dedicate your extra storage device to Libvirt.${end}"

        confirm "${yel} Do you want to continue as a Qubinode?${end} ${blu}yes/no ${end}"
        if [ "A${response}" == "Ayes" ]
        then
            # Set varaible to configure storage and networking
            sed -i "s/run_qubinode_setup:.*/run_qubinode_setup: "$response"/g" "${kvm_host_vars_file}"
        else
            # Set varaible not to configure storage and networking
            sed -i "s/run_qubinode_setup:.*/run_qubinode_setup: "$response"/g" "${kvm_host_vars_file}"
            printf "%s\n\n" ""
            printf "%s\n" "${cyn} You choose not to setup this system as a Qubinode.${end}"
            printf "%s\n" "${cyn} Please understand that by choosing this route you are${end}"
            printf "%s\n" "${cyn} taking ownership of setting up the system to function as${end}"
            printf "%s\n" "${cyn} kvm/libvirt host. Also, support for this setup is limited.${end}"
            printf "%s\n" "${yel} However, pull request are very welcome.${end}"
            printf "%s\n\n" "${cyn} We will now attempt to verify your libvirt storage and network.${end}"

            # Don't expect a second storage device
            sed -i "s/create_lvm:.*/create_lvm: "no"/g" "${kvm_host_vars_file}"

        fi
    fi
echo "I AM HERE $FUNCNAME"  
}

function check_libvirt_pool () {
    # Verify storage and network when not setting up Qubinode
    QUBINODE_SYSTEM=$(awk '/run_qubinode_setup:/ {print $2; exit}' "${kvm_host_vars_file}" | tr -d '"')
    CHECK_LIBVIRT_POOL=$(awk '/libvirt_pool_name_check:/ {print $2; exit}' "${kvm_host_vars_file}" | tr -d '"')
    if [ "A${CHECK_LIBVIRT_POOL}" == "Ayes" ]
    then
        # Check libvirt storage
        LIBVIRT_POOLS=$(sudo virsh pool-list --autostart | awk '/active/ {print $1}'| grep -v qbn | wc -l)
        LIBVIRT_POOLS="${LIBVIRT_POOLS:-0}"
        if [ $LIBVIRT_POOLS -gt 1 ]
        then
            #printf "%s\n\n" " ${mag}Found multiple libvirt pools${end}"
            printf "%s\n" " ${yel}Found multiple libvirt pools, choose one to continue: ${end}"
            declare -a all_pools=()
            mapfile -t all_pools < <(sudo virsh pool-list --autostart | awk '/active/ {print $1}'| grep -v qbn)
            createmenu "${all_pools[@]}"
            POOL=($(echo "${selected_option}"))

            printf "%s\n" " Setting libvirt_pool_name to $POOL"
            sed -i "s/libvirt_pool_name:.*/libvirt_pool_name: "$POOL"/g" "${kvm_host_vars_file}"
            sed -i "s/libvirt_pool_name_check:.*/libvirt_pool_name_check: no/g" "${kvm_host_vars_file}"
        elif [ $LIBVIRT_POOLS -eq 0 ]
        then
            printf "%s\n\n" " ${red}No libvirt pool found, please resolve this issue and try again.${end}"
            exit 2
        else
            POOL=$(sudo virsh pool-list --autostart | awk '/active/ {print $1}'| grep -v qbn)
            if [ "A${POOL}" != "default" ]
            then
                printf "%s\n" " Setting libvirt_pool_name to $POOL"
                sed -i "s/libvirt_pool_name:.*/libvirt_pool_name: "$POOL"/g" "${kvm_host_vars_file}"
                sed -i "s/libvirt_pool_name_check:.*/libvirt_pool_name_check: no/g" "${kvm_host_vars_file}"
            fi
        fi
        # Check the pool capacity
        POOL_CAPACITY=$(sudo virsh pool-dumpxml "${POOL}"| grep capacity | grep -Eo "[[:digit:]]{1,100}")
    fi
echo "I AM HERE $FUNCNAME"  
}

function check_libvirt_network () {
    CHECK_LIBVIRT_NET=$(awk '/vm_libvirt_net_check:/ {print $2; exit}' "${kvm_host_vars_file}" | tr -d '"')
    if [ "A${CHECK_LIBVIRT_NET}" == "Ayes" ]
    then
        # Check libvirt network
        LIBVIRT_NETS=$(sudo virsh net-list --autostart | awk '/active/ {print $1}'| wc -l)
        LIBVIRT_NETS="${LIBVIRT_NETS:-0}"
        if [ $LIBVIRT_NETS -gt 1 ]
        then
            printf "%s\n" "${yel} Found multiple libvirt networks, choose one to continue: ${end}"
            declare -a all_networks=()
            mapfile -t all_networks < <(sudo virsh net-list --autostart | awk '/active/ {print $1}')
            createmenu "${all_networks[@]}"
            NETWORK=($(echo "${selected_option}"))

            printf "%s\n" " Setting vm_libvirt_net to $NETWORK"
            sed -i "s/vm_libvirt_net:.*/vm_libvirt_net: "$NETWORK"/g" "${kvm_host_vars_file}"
            sed -i "s/vm_libvirt_net_check:.*/vm_libvirt_net_check: no/g" "${kvm_host_vars_file}"
        elif [ $LIBVIRT_NETS -eq 0 ]
        then
            printf "%s\n\n" " ${red}No libvirt network found, please resolve this issue and try again.${end}"
            exit 2
        else
            NETWORK=$(sudo virsh net-list --autostart | awk '/active/ {print $1}')
            if [ "A${NETWORK}" != "qubinet" ]
            then
               printf "%s\n" " Setting vm_libvirt_net to $NETWORK"
               sed -i "s/vm_libvirt_net:.*/vm_libvirt_net: $NETWORK/g" "${kvm_host_vars_file}"
               sed -i "s/vm_libvirt_net_check:.*/vm_libvirt_net_check: no/g" "${kvm_host_vars_file}"
            fi
        fi
    fi
echo "I AM HERE $FUNCNAME"  
}

function qubinode_system_auto_install () {
    if [ "A${openshift_auto_install}" != "Atrue" ]
    then
        QUBINODE_SYSTEM=$(awk '/run_qubinode_setup:/ {print $2; exit}' "${kvm_host_vars_file}" | tr -d '"')
    else
        # Set varaible to configure storage and networking
        response=yes
        sed -i "s/run_qubinode_setup:.*/run_qubinode_setup: "$response"/g" "${kvm_host_vars_file}"
        check_additional_storage
    fi
echo "I AM HERE $FUNCNAME"  
}

# Ensure RHEL is set to the supported release
function set_rhel_release () {
    qubinode_required_prereqs
    RHEL_RELEASE=$(awk '/rhel_release/ {print $2}' "${kvm_host_vars_file}" |grep [0-9])
    RELEASE="Release: ${RHEL_RELEASE}"
    CURRENT_RELEASE=$(sudo subscription-manager release --show)

    if [ "A${QUBINODE_SYSTEM}" == "Ayes" ]
    then
        if [ "A${RELEASE}" != "A${CURRENT_RELEASE}" ]
        then
            printf "\n\nSetting RHEL to the supported release: ${RHEL_RELEASE}"
            sudo subscription-manager release --unset
            sudo subscription-manager release --set="${RHEL_RELEASE}"
        else
            printf "\n\n  RHEL release is set to the supported release: ${CURRENT_RELEASE}"
        fi
    fi
echo "I AM HERE $FUNCNAME"  
}

function qubinode_networking () {
    check_for_dns redhat.com
    KVM_HOST_IPADDR=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
    # HOST Gateway not currently in use
    KVM_HOST_GTWAY=$(ip route get 8.8.8.8 | awk -F"via " 'NR==1{split($2,a," ");print a[1]}')
    NETWORK=$(ip route | awk -F'/' "/$KVM_HOST_IPADDR/ {print \$1}")
    PTR=$(echo "$NETWORK" | awk -F . '{print $4"."$3"."$2"."$1".in-addr.arpa"}'| sed 's/^[^.]*.//g')

    # ask user for their IP network and use the default
    if egrep -R changeme.in-addr.arpa "${project_dir}/playbooks/vars/" >/dev/null 2>&1
    then
        network="${NETWORK}"
        PTR=$(echo "$NETWORK" | awk -F . '{print $4"."$3"."$2"."$1".in-addr.arpa"}'|sed 's/^[^.]*.//g')
        test -f "${kvm_host_vars_file}" && sed -i "s/qubinode_ptr:.*/qubinode_ptr: "$PTR"/g" "${kvm_host_vars_file}"
        test -f "${all_vars_file}" && sed -i "s/qubinode_ptr:.*/qubinode_ptr: "$PTR"/g" "${all_vars_file}"
        #test -f "${idm_vars_file}" && sed -i "s/changeme.in-addr.arpa/"$PTR"/g" "${idm_vars_file}"
    fi

    DEFINED_BRIDGE=""
    DEFINED_BRIDGE_ACTIVE=no
    if [ -f "${kvm_host_vars_file}" ]
    then
        iSkvm_host_interface=$(awk '/^kvm_host_interface:/ { print $2}' "${kvm_host_vars_file}")
        DEFINED_BRIDGE=$(awk '/^qubinode_bridge_name:/ {print $2; }' "${kvm_host_vars_file}")
        if sudo ip addr show "${DEFINED_BRIDGE}" > /dev/null 2>&1
        then
            DEFINED_BRIDGE_ACTIVE=yes
        fi
    fi

    KVM_HOST_PRIMARY_INTERFACE=$(ip route list | awk '/^default/ {print $5}'|sed -e 's/^[ \t]*//')
    if [ "A${DEFINED_BRIDGE_ACTIVE}" == "Ayes" ]
    then
        CURRENT_KVM_HOST_PRIMARY_INTERFACE=$(sudo route | grep '^default' | awk '{print $8}'|grep $DEFINED_BRIDGE)
        KVM_HOST_PRIMARY_INTERFACE=$(ip link show master "${DEFINED_BRIDGE}" |awk -F: '/state UP/ {sub(/^[ \t]+/, "");print $2}'|sed -e 's/^[ \t]*//')
    else
        if echo ${iSkvm_host_interface} | grep -q [0-9]
        then
            CURRENT_KVM_HOST_PRIMARY_INTERFACE="${iSkvm_host_interface}"
        else
            CURRENT_KVM_HOST_PRIMARY_INTERFACE="${KVM_HOST_PRIMARY_INTERFACE}"
        fi
    fi

    if sudo ip addr show "${CURRENT_KVM_HOST_PRIMARY_INTERFACE}" > /dev/null 2>&1
    then
        KVM_HOST_MASK_PREFIX=$(ip -o -f inet addr show $CURRENT_KVM_HOST_PRIMARY_INTERFACE | awk '{print $4}'|cut -d'/' -f2)
        mask=$(ip -o -f inet addr show $CURRENT_KVM_HOST_PRIMARY_INTERFACE|awk '{print $4}')

        if [ "A$mask" != "A" ]
        then
            KVM_HOST_NETMASK=$(ipcalc -m $mask|awk -F= '{print $2}')
        fi

        # Set KVM host ip info
        iSkvm_host_netmask=$(awk '/^kvm_host_netmask:/ { print $2}' "${kvm_host_vars_file}")
        if [[ "A${iSkvm_host_netmask}" == "A" ]] || [[ "A${iSkvm_host_netmask}" == 'A""' ]]
        then
            #printf "\n Updating the kvm_host_netmask to ${yel}$KVM_HOST_NETMASK${end}"
            sed -i "s#kvm_host_netmask:.*#kvm_host_netmask: "$KVM_HOST_NETMASK"#g" "${kvm_host_vars_file}"
        fi

        iSkvm_host_ip=$(awk '/^kvm_host_ip:/ { print $2}' "${kvm_host_vars_file}")
        if [[ "A${iSkvm_host_ip}" == "A" ]] || [[ "A${iSkvm_host_ip}" == 'A""' ]]
        then
            #echo "Updating the kvm_host_ip to $KVM_HOST_IPADDR"
            sed -i "s#kvm_host_ip:.*#kvm_host_ip: "$KVM_HOST_IPADDR"#g" "${kvm_host_vars_file}"
        fi

        iSkvm_host_gw=$(awk '/^kvm_host_gw:/ { print $2}' "${kvm_host_vars_file}")
        if [[ "A${iSkvm_host_gw}" == "A" ]] || [[ "A${iSkvm_host_gw}" == 'A""' ]]
        then
            #echo "Updating the kvm_host_gw to $KVM_HOST_GTWAY"
            sed -i "s#kvm_host_gw:.*#kvm_host_gw: "$KVM_HOST_GTWAY"#g" "${kvm_host_vars_file}"
        fi

        iSkvm_host_mask_prefix=$(awk '/^kvm_host_mask_prefix:/ { print $2}' "${kvm_host_vars_file}")
        if [[ "A${iSkvm_host_mask_prefix}" == "A" ]] || [[ "A${iSkvm_host_mask_prefix}" == 'A""' ]]
        then
            #echo "Updating the kvm_host_mask_prefix to $KVM_HOST_MASK_PREFIX"
            sed -i "s#kvm_host_mask_prefix:.*#kvm_host_mask_prefix: "$KVM_HOST_MASK_PREFIX"#g" "${kvm_host_vars_file}"
        fi

        iSkvm_host_interface=$(awk '/^kvm_host_interface:/ { print $2}' "${kvm_host_vars_file}")
        if [ "A${iSkvm_host_interface}" != "A${KVM_HOST_PRIMARY_INTERFACE}" ]
        then
            echo "    Updating the kvm_host_interface to $KVM_HOST_PRIMARY_INTERFACE"
            sed -i "s#kvm_host_interface:.*#kvm_host_interface: "$KVM_HOST_PRIMARY_INTERFACE"#g" "${kvm_host_vars_file}"
        fi

        iSkvm_host_macaddr=$(awk '/^kvm_host_macaddr:/ { print $2}' "${kvm_host_vars_file}")
        if [[ "A${iSkvm_host_macaddr}" == "A" ]] || [[ "A${iSkvm_host_macaddr}" == 'A""' ]]
        then
            foundmac=$(ip addr show $KVM_HOST_PRIMARY_INTERFACE | grep link | awk '{print $2}' | head -1)
            #echo "Updating the kvm_host_macaddr to ${foundmac}"
            sed -i "s#kvm_host_macaddr:.*#kvm_host_macaddr: '"${foundmac}"'#g" "${kvm_host_vars_file}"
        fi
    else
            printf "%s\n\n\n" " "
            printf "%s\n" "    ${red}Could not properly determine your current active network interface${end}"
            printf "%s\n" "    ${blu}You can set the interface value ${end}${yel}kvm_host_interface${end} ${blu}in ${end}${yel}${kvm_host_vars_file}${end}"
            exit 1
    fi
echo "I AM HERE $FUNCNAME"  
}


#function qubinode_check_for_libvirt_nat() {
#    #TODO: This function is no longer needed and should be removed
#    DEFINED_LIBVIRT_NETWORK=$(awk '/vm_libvirt_net:/ {print $2; exit}' "${kvm_host_vars_file}"| tr -d '"')
#    RESULT=$(sudo virsh net-list --all --name | grep -q "${DEFINED_LIBVIRT_NETWORK}")
#    if [[ "A${RESULT}" == "A" ]];
#    then
#        printf "%s\n" "    skipping ${DEFINED_LIBVIRT_NETWORK} configuration"
#        linenum=$(cat "${kvm_host_vars_file}" | grep -n 'create:' | head -1| awk '{print $1}' | tr -d :)
#        sed -i ''${linenum}'s/create:.*/create: false/' "${kvm_host_vars_file}"
#    else
#        printf "%s\n" " Could not find the defined libvirt network ${DEFINED_LIBVIRT_NETWORK}"
#        printf "%s\n" " Will attempt to find and use the first bridge or nat libvirt network"
#
#        nets=$(sudo virsh net-list --all --name)
#        NAT_ARRAY=()
#        printf "%s\n" "   Found libvirt networks:"
#        for item in $(echo $nets)
#        do
#            mode=$(sudo virsh net-dumpxml $item | awk -F"'" '/forward mode/ {print $2}')
#            if [ "A${mode}" == "Anat" ]
#            then
#                NAT_ARRAY+=(${item})
#            fi
#        done
#
#        for nat in ${NAT_ARRAY[@]}
#        do
#           printf "%s\n" "     ${yel} * ${end}${blu}$nat${end}"
#        done
#
#        printf "%s\n" " "
#        printf "%s\n" "   It is recommended to configure a nat network for OCP4 deployments."
#        printf "%s\n" "   Choose one of the options below and the installer will use the selected nat natwork for deployment"
#
#        confirm "   Do you want to use libvirt net: ${blu}yes/no${end}"
#        printf "%s\n" " "
#        if [ "A${response}" == "Ayes" ]
#        then
#          createmenu "${NAT_ARRAY[@]}"
#          nat_network=($(echo "${selected_option}"))
#          confirm "    Continue with $nat_network? ${blu}yes/no${end}"
#          if [ "A${response}" == "Ayes" ]
#          then
#              printf "%s\n\n" ""
#              printf "%s\n\n" " ${mag}Using  libvirt net: $nat_network${end}"
#              sed -i "s/vm_libvirt_net:.*/vm_libvirt_net: "$nat_network"/g" "${kvm_host_vars_file}"
#              linenum=$(cat "${kvm_host_vars_file}" | grep -n 'create:' | head -1 | awk '{print $1}' | tr -d :)
#              sed -i ''${linenum}'s/create:.*/create: false/' "${kvm_host_vars_file}"
#          else
#              printf "%s\n\n" " ${mag}Setup will configure nat network.${end}"
#              exit 0
#          fi
#      fi
#    fi
#}

kvm_host_health_check () {
    KVM_IN_GOOD_HEALTH=""
    check_image_path=$(cat ${all_vars_file}| grep kvm_host_libvirt_dir: | awk '{print $2}')
    requested_brigde=$(awk '/^vm_libvirt_net:/ {print $2;exit}' "${kvm_host_vars_file}")
    libvirt_dir=$(awk '/^kvm_host_libvirt_dir/ {print $2}' "${kvm_host_vars_file}")
    create_lvm=$(awk '/create_lvm:/ {print $2;exit}' "${kvm_host_vars_file}")
    KVM_STATUS="Unknown"

    if [ -f /usr/bin/virsh ]
    then
        if ! sudo virsh net-list | grep -q "$requested_brigde"
        then
            KVM_STATUS="notready"
            kvm_host_health_check_results=(Could not find the libvirt network $requested_brigde)
        else
            KVM_STATUS="ready"
        fi
    fi

    # If dedicated disk for libvirt images, check for the volume group
    if [ "A${create_lvm}" == "Ayes" ]
    then
        if ! sudo vgdisplay | grep -q $vg_name
        then
            KVM_STATUS="notready"
            kvm_host_health_check_results+=(Could not find volume group $vg_name)
        else
            KVM_STATUS="ready"
        fi
    fi

    if [ ! -d $check_image_path ]
    then
        KVM_STATUS="notready"
        kvm_host_health_check_results+=(Could not find libvirt pool dir $check_image_path)
    else
        KVM_STATUS="ready"
    fi

    if ! [ -x "$(command -v virsh)" ]
    then
        KVM_STATUS="notready"
        kvm_host_health_check_results+=(Could not find the virsh command)
    else
        KVM_STATUS="ready"
    fi

    if ! [ -x "$(command -v firewall-cmd)" ]
    then
        KVM_STATUS="notready"
        kvm_host_health_check_results+=(Could not find the firewall-cmd command)
    else
        KVM_STATUS="ready"
    fi

    ## Declare status of KVM host
    KVM_IN_GOOD_HEALTH=$KVM_STATUS
echo "I AM HERE $FUNCNAME"  
}


function qubinode_setup_kvm_host () {
    # set variable to enable prompting user if they want to
    # setup host as a qubinode
    qubinode_maintenance_opt="host"
    qubinode_networking

    # Ensure the base setup is done
    setup_variables
    if [ "A${base_setup_completed}" == "Ano" ]
    then
        qubinode_base_requirements
    fi

    # Check if we should setup qubinode
    QUBINODE_SYSTEM=$(awk '/run_qubinode_setup:/ {print $2; exit}' "${kvm_host_vars_file}" | tr -d '"')

    if [ "A${OS}" != "AFedora" ]
    then
        set_rhel_release
    fi

    HARDWARE_ROLE=$(sudo dmidecode -t 3 | grep Type | awk '{print $2}')

    if [ "A${HARDWARE_ROLE}" != "ALaptop" ]
    then
       ask_user_if_qubinode_setup

       if [ "A${QUBINODE_SYSTEM}" == "Ayes" ]
       then
           printf "%s\n" " ${blu}Setting up qubinode system${end}"
           ansible-playbook "${project_dir}/playbooks/setup_kvmhost.yml" || exit $?
           #qcow_check
       else
           printf "%s\n" " ${blu}not a qubinode system${end}"
       fi
    else
      ask_user_if_qubinode_setup

      if [ "A${QUBINODE_SYSTEM}" == "Ayes" ]
      then
        printf "%s\n" " ${blu}Setting up qubinode system${end}"
        ansible-playbook "${project_dir}/playbooks/setup_kvmhost.yml" || exit $?
        #qcow_check
      else
          printf "%s\n" " ${blu}not a qubinode system${end}"
          printf "%s\n" "   Installing required packages"
          sudo yum install -y -q -e 0 python3-dns libvirt-python python-lxml libvirt python-dns > /dev/null 2>&1
          #qcow_check
      fi
    fi

   # Validate host is setup correctly
   # TODO: this needs more work - it's not doing a valid check
   kvm_host_health_check
   if [ "A${KVM_IN_GOOD_HEALTH}" == "Aready" ]
   then
       sed -i "s/qubinode_installer_host_completed:.*/qubinode_installer_host_completed: yes/g" "${kvm_host_vars_file}"
       printf "\n\n${yel}    ******************************${end}\n"
       printf "${yel}    * KVM Host Setup Complete   *${end}\n"
       printf "${yel}    *****************************${end}\n\n"
   else
       sed -i "s/qubinode_installer_host_completed:.*/qubinode_installer_host_completed: no/g" "${kvm_host_vars_file}"
       printf "\n\n${yel}    ******************************${end}\n"
       printf "${red}    * KVM Host Setup Fail   *${end}\n"
       printf "${yel}    *****************************${end}\n\n"
       for msg in "${kvm_host_health_check_results[*]}"
       do
           printf "%s\n\n" " ${red} $msg ${end}"
       done
       exit
   fi

    sudo usermod -a -G libvirt $(whoami)
    sudo sed -i '/^#unix_sock_group = "libvirt"/s/^#//' /etc/libvirt/libvirtd.conf
    sudo sed -i '/^#unix_sock_rw_perms = "0770""/s/^#//' /etc/libvirt/libvirtd.conf
    sudo systemctl restart libvirtd.service
echo "I AM HERE $FUNCNAME"  
echo "QUBINODE_SYSTEM=$QUBINODE_SYSTEM"
}


