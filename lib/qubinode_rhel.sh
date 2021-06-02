#!/bin/bash

# @file lib/qubinode_rhel.sh
# @brief A library of bash functions for deploying a rhel vm.
# @description
#  These functions generates the vars for required by the ansible
#  role deploy-kvm-vm for deploying RHEL VMs.

# @description
# Builds the required vm attributes based on -a arguments passed.
function qubinode_rhel_vm_attributes () {
    local rhel_options="${product_options[*]:-none}"
    local name_prefix="${NAME_PREFIX:-qbn}"
    local suffix="rhel"
    local instance_id=$((1 + RANDOM % 4096))
    local rhel_major="${RHEL_MAJOR:-8}"
    local qcow_rhel7_name="${QCOW_RHEL7_NAME:?}"
    local qcow_rhel8_name="${QCOW_RHEL8_NAME:?}"
    local kvm_host_gateway="${KVM_HOST_GW:?}"
    local rhel_vm_default_release="${RHEL_VM_DEFAULT_RELEASE:-8}"
    local response
    local qcow_rhel7_checksum="${QCOW_RHEL7_CHECKSUM:?}"
    local qcow_rhel8_checksum="${QCOW_RHEL8_CHECKSUM:?}"

    if [ "A${rhel_options}" != "Anone" ]
    then
        # Get RHEL release provided
        if [ "${release:-A}" != "A" ]
        then
            export rhel_vm_major_release="$release"
        else
            export rhel_vm_major_release=${rhel_major}
        fi

        # Get the pet name for the RHEL VM
        if [ "${name:-A}" != "A" ]
        then
            if [ -f "${project_dir:?}/.rhel/${name}.yml" ]
            then
                rhel_vm_hostname="${name}"
            elif sudo virsh list --all | grep -qo "${name}"
            then
                rhel_vm_hostname="${name}"
            elif echo "${name}" | grep -q "${name_prefix}"
            then
                rhel_vm_hostname="${name}"
            else
                rhel_vm_hostname="${name_prefix}-${name}"
            fi
        else
            rhel_vm_hostname="${name_prefix}-${suffix}${rhel_vm_major_release}-${instance_id}"
        fi

        ## Exit if trying to create a vm with a name that already exist
        if [ "A${teardown:-no}" != "Ayes" ]
        then
            if sudo virsh list --all | grep "${rhel_vm_hostname}" > /dev/null 2>&1
            then
                echo "The name ${rhel_vm_hostname} is already in use. Please try again with a different name."
                exit 0
            fi
        fi

        ## Get User Requested Instance size
        local rhel_vm_size="${size:-small}"
        case "${rhel_vm_size}" in
            small)
                vcpu=1
                memory=800
                disk=10G
                expand_os_disk=no
                ;;
            medium)
                vcpu=2
                memory=2048
                disk=60G
                expand_os_disk=yes
                ;;
            large)
                vcpu=4
                memory=8192
                disk=60G
                expand_os_disk=yes
                ;;
            xlarge)
                vcpu=4
                memory=16384
                disk=60G
                expand_os_disk=yes
                enabled_nested=yes
                extra_disk=yes
                ;;
            *)
                printf "%s\n" "The VM size ${rhel_vm_size} is not valid"
                printf "%s\n" "Choose ${cyn:?}yes${end:?} to deploy a small VM or ${cyn:?}no${end:?}"
                printf "%s\n" "to abort and try again."
                confirm "  Do you want to deploy a small instead? ${cyn:?}yes/no${end:?}"
                printf "%s\n" ""
                if [ "A${response}" == "Ayes" ]
                then
                    vcpu=1
                    memory=800
                    disk=10G
                    expand_os_disk=no
	            else
                     exit 1
                fi
                ;;
        esac                         
        export "rhel_vm_memory=$memory"
        export "rhel_vm_disk=$disk"
        export "rhel_vm_expandisk=$expand_os_disk"
        export "rhel_vm_vcpu=$vcpu"
        export "enabled_nested=${enabled_nested:-no}"
        export "extra_disk=${extra_disk:-no}"

        ## Which RHEL release to deploy
        case "${rhel_vm_release:-8}" in
            7)
                export rhel_vm_qcow_image="${qcow_rhel7_name}"
                export rhel_qcow_image_checksum="${qcow_rhel7_checksum}"
                export rhel_vm_os_version="{rhel7_vm_version}"
                ;;
            8)
                export rhel_vm_qcow_image="${qcow_rhel8_name}"
                export rhel_qcow_image_checksum="${qcow_rhel8_checksum}"
                export rhel_vm_os_version="{rhel7_vm_version}"
                ;;
            *)
                printf "%s\n" "The RHEL release ${rhel_vm_default_release} is not valid"
                printf "%s\n" "Choose ${cyn:?}yes${end:?} to deploy the defaul RHEL release or ${cyn:?}no${end:?}"
                printf "%s\n" "to abort and try again."
                confirm "  Do you want to deploy the RHEL release ${rhel_vm_default_release} instead? ${cyn:?}yes/no${end:?}"
                printf "%s\n" ""
                if [ "A${response}" == "Ayes" ]
                then
                     export rhel_vm_qcow_image="${RHEL_VM_DEFAULT_QCOW_IMG:?}"
                     export rhel_qcow_image_checksum="${RHEL_VM_DEFAULT_QCOW_IMG_CHECKSUM:?}"
                     export rhel_vm_os_version="${RHEL_VM_OS_VERSION:?}"
                     rhel_vm_major_release="${rhel_vm_default_release}"
	            else
                     exit 1
                fi
        esac
            
        ## Use static ip address if provided
        if [ "${ip:-A}" != "A" ]
        then
            export vm_ipaddress="${ip}"
            export vm_mask_prefix="${KVM_HOST_MASK_PREFIX}"
            export vm_gateway="${kvm_host_gateway}"
        else
            export vm_mask_prefix=""
            export vm_gateway=""
            export vm_ipaddress=""
        fi

        ## Use netmask prefix if provided
        if [ "${cidr:-A}" != "A" ]
        then
            export vm_mask_prefix="${cidr}"
        else
            export vm_mask_prefix="${KVM_HOST_MASK_PREFIX}"
        fi
 
        ## Use gateway if provided if provided
        if [ "${gw:-A}" != "A" ]
        then
            export vm_gateway="${gw}"
        fi

        ## Use mac address if provided
        if [ "${mac:-A}" != "A" ]
        then
            export vm_mac="${mac}"
            sed -i "s/vm_mac:.*/vm_mac: "$mac"/g" "${rhel_vars_file}"
        fi
    fi
}

# @description
# Function to download the rhel qcow image from RHSM using the user offline token.
function rhsm_cli_download_rhel_qcow () {
    local rhsm_cli_cmd="${project_dir:?}/.python/rhsm_cli/bin/rhsm-cli"
    local rhsm_cli_config="/home/${ADMIN_USER:?}/.config/rhsm-cli.conf"
    local rhsm_offline_token
    local rhsm_token_file="${RHSM_TOKEN:-none}"

    # save token to config file
    if [ ! -f "${rhsm_cli_config}" ]
    then
        rhsm_offline_token=$(cat "$rhsm_token_file")
        if "$rhsm_cli_cmd" -t "$rhsm_offline_token" savetoken 2>/dev/null
        then
            printf "%s\n" "    Failure validating token provided by $RHSM_TOKEN"
            printf "%s\n" "    Please verify your token is correct or generate a new one and try again."
            exit 1
        fi
    fi

    # Download from rhel qcow image from Red Hat
    if [ -f "$rhsm_cli_config" ]
    then
        $rhsm_cli_cmd images --checksum "$rhel_qcow_image_checksum" 2>/dev/null
        if [ -f "${project_dir}/${rhel_vm_qcow_image}" ]
        then
            downloaded_qcow_checksum=$(sha256sum "${project_dir}/${rhel_vm_qcow_image}"|awk '{print $1}')
            if [ "$downloaded_qcow_checksum" != "$rhel_qcow_image_checksum" ]
            then
                echo "The downloaded $rhel_vm_qcow_image validation fail"
                printf "%s\n" "    The downloaded $rhel_vm_qcow_image validation failed"
                printf "%s\n" "    Try refreshing updating the var rhel_qcow_image_checksum with a new checksum/"
                exit 1
            else
                if sudo test ! -f "${libvirt_dir}/${rhel_vm_qcow_image}"
                then
                    sudo cp "${project_dir}/${rhel_vm_qcow_image}"  "${libvirt_dir}/${rhel_vm_qcow_image}"
                fi
            fi
        fi
    fi

}

# @description
# Ensure the RHEL qcow image is present in the libvirt image directory.
# If the qcow image is not present attempt to download if if user offline
# RHSM token is provided.
function qcow_image_exist () {

    local rhsm_token_file="${RHSM_TOKEN:-none}"
    local rhsm_token_status="notexist"
    #local rhel_qcow_status="notexist"
    local download_rhel_qcow=no
    local libvirt_dir="${LIBVIRT_DIR:-/var/lib/libvirt/images}"
    local rhel_vm_qcow_image="${rhel_vm_qcow_image:-$RHEL_VM_DEFAULT_QCOW_IMG}"
    #local rhel_vm_qcow_image_downloaded="no"
    local rhsm_cli_doc_url="${RHSM_CLI_DOC_URL:?}"


    # check if rhel qcow image is downloaded
    if sudo test -f "${project_dir:?}/${rhel_vm_qcow_image}"
    then
        #rhel_vm_qcow_image_downloaded="yes"
        if sudo test ! -f "${libvirt_dir}/${rhel_vm_qcow_image}"
        then
            sudo cp "${project_dir}/${rhel_vm_qcow_image}"  "${libvirt_dir}/${rhel_vm_qcow_image}"
        fi
    fi

    # check for required OS qcow image exist
    if sudo test ! -f "${libvirt_dir}/${rhel_vm_qcow_image}"
    then
        download_rhel_qcow="yes"
    fi

    # check if rhsm token exist
    if sudo test -f "${rhsm_token_file}"
    then
        rhsm_token_status="exist"
    fi

    # Download RHEL qcow image
    if [[ "${download_rhel_qcow:-no}" == "yes" ]] && [[ "${rhsm_token_status:-notexist}" == "exist" ]]
    then
        #"Install install_rhsm_cli"
        install_rhsm_cli

        #echo "run rhsm_cli_download_rhel_qcow"
        rhsm_cli_download_rhel_qcow
    fi

    # Exit and notify user if qcow image does not exist
    if sudo test ! -f "${libvirt_dir}/${rhel_vm_qcow_image}"
    then
        printf "%s\n" ""
        printf "%s\n" "    ${yel:?}The installer requires the RHEL qcow image $rhel_vm_qcow_image. ${end:?}"
        printf "%s\n" "    ${yel:?}The qcow image should in the directory ${project_dir} ${end:?}"
        printf "%s\n" "    ${yel:?}or ${libvirt_dir}.${end:?}"
        printf "%s\n" ""
        printf "%s\n" "    ${yel:?}Refer to the Qubinode project documentation for info about${end:?}"
        printf "%s\n" "    ${yel:?}downloading the RHEL qcow image $rhel_vm_qcow_image.${end:?}"
        printf "%s\n" "    ${yel:?}$rhsm_cli_doc_url${end:?}"
        exit
    fi

}

function run_rhel_deployment () {
    local rhel_vm_name="${1:?}"

    ## define the qcow disk image to use for the libvirt VM
    export rhel_vm_qcow_image_file="/var/lib/libvirt/images/${rhel_vm_name}_vda.qcow2"

    if ! sudo virsh dominfo "${rhel_vm_name}" >/dev/null 2>&1
    then

        sudo test -f "${rhel_vm_qcow_image_file}" && sudo rm -f "${rhel_vm_qcow_image_file}" 
        test -d "${project_dir:?}/.rhel" || mkdir "${project_dir}/.rhel"

        local rhel_vm_ansible_vars_file="${project_dir:?}/.rhel/${rhel_vm_name}.yml"
        local rhel_vm_bash_vars_file="${project_dir:?}/.rhel/${rhel_vm_name}.txt"
        local rhel_vm_vars_template="${QUBINODE_RHEL_VM_VARS_TEMPLATE:?}"
 
        ## Generate bash and ansible vars
        export SOURCE_VARS=no
        generate_qubinode_vars "${rhel_vm_vars_template}" "${rhel_vm_bash_vars_file}" "${QUBINODE_ANSIBLE_VARS_TEMPLATE}" "${rhel_vm_ansible_vars_file}"

        ansible-playbook "${RHEL_PLAYBOOK}" --extra-vars "@${rhel_vm_ansible_vars_file}"
        PLAYBOOK_STATUS=$?
        echo "PLAYBOOK_STATUS=$PLAYBOOK_STATUS"
    fi

    # Run function to remove vm vars file
    #delete_vm_vars_file
}



function delete_vm_vars_file () {
    # check if VM was deployed, if not delete the qcow image created for the vm
    VM_DELETED=no
    if ! sudo virsh list --all |grep -q "${rhel_vm_hostname}"
    then
        sudo test -f $qcow_image_file && sudo rm -f $qcow_image_file
        rm -f "${project_dir}/.rhel/${rhel_vm_hostname}-vars.yml"
	VM_DELETED=yes
    fi
}

function qubinode_deploy_rhel () {
    ## Check if user requested more than one VMs and deploy the requested count
    if [ "${qty:-A}" != "A" ]
    then
        re='^[0-9]+$'
        if ! [[ $qty =~ $re ]]
        then
           echo "error: The value for qty is not a integer." >&2; exit 1
        else
            for num in $(seq 1 "$qty")
            do
                while true
                do
                    instance_id=$((1 + RANDOM % 4096))
                    if ! sudo virsh list --all | grep $instance_id
                    then
                        break
                    fi
                done

                if [ "${VM_MAC:-none}" == 'none' ]
                then
                    export VM_MAC="52:54:$(dd if=/dev/urandom count=1 2>/dev/null | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4/')"
                fi
                if [ "${vm_ipaddress:-none}" != 'none' ]
                then
                    export vm_ipaddress="${vm_ipaddress}"
                fi
                if [ "${name:-A}" != "A" ]
                then
                    if [ -f "${project_dir:?}/.rhel/${name}.yml" ]
                    then
                        rhel_vm_hostname="${name}"
                    elif sudo virsh list --all | grep -qo "${name}"
                    then
                        rhel_vm_hostname="${name}"
                    elif echo "${name}" | grep -q "${name_prefix}"
                    then
                        rhel_vm_hostname="${name}"
                    else
                        rhel_vm_hostname="${name_prefix}-${name}${num}"
                    fi
                else
                    rhel_vm_hostname="${name_prefix}-${suffix}${rhel_vm_major_release}-${instance_id}${num}"
                fi

                run_rhel_deployment "${rhel_vm_hostname}"
            done
        fi 
    else
        if [ "${VM_MAC:-none}" == 'none' ]
        then
            export VM_MAC="52:54:$(dd if=/dev/urandom count=1 2>/dev/null | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4/')"
        fi
        if [ "${vm_ipaddress:-none}" != 'none' ]
        then
            export vm_ipaddress="${vm_ipaddress}"
        fi
        run_rhel_deployment "${rhel_vm_hostname}"
    fi
}

function qubinode_rhel_teardown () {

    local rhel_vm_playbook_vars
    local rhel_vm_bash_vars
    local rhel_vm_playbook="${RHEL_PLAYBOOK:?}"
    local rhel_vm_deleted=no

    if [ "${name:-none}" == "none" ]
    then
        printf "%s\n" ""
        printf "%s\n" "Please specify the name of the instance to delete"
        printf "%s\n" "Example: ${blu:?}./qubinode-install -p rhel -a name=qbn-rhel8-348 -d${end:?}"
        exit
    fi

    rhel_vm_playbook_vars="${project_dir}/.rhel/${name}.yml"
    rhel_vm_bash_vars="${project_dir}/.rhel/${name}.txt"

    if [ -f "${rhel_vm_playbook_vars}" ]
    then
        printf "%s\n" ""
        printf "%s\n" "Running playbook to delete ${blu:?}${name}${end:?}"
        if ansible-playbook "${rhel_vm_playbook}" --extra-vars "@${rhel_vm_playbook_vars}" -e "vm_teardown=yes"
        then
            rhel_vm_deleted=yes
            test -f "${rhel_vm_playbook_vars}" && rm -f "${rhel_vm_playbook_vars}"
            test -f "${rhel_vm_bash_vars}" && rm -f "${rhel_vm_bash_vars}" 
        else
            printf "%s\n" "Playbook run to delete ${blu:?}${name}${end:?} failed"
        fi
    elif sudo virsh list --all | grep -q "${name}"
    then
        printf "%s\n" ""
        if sudo virsh list --state-running | grep -oq "${name}"
        then
            printf "%s\n" "Shutting down VM ${blu:?}${name}${end:?}"
            sudo virsh destroy --domain "${name}"
        fi

        printf "%s\n" "Deleting VM ${blu:?}${name}${end:?}"
        if sudo virsh undefine --remove-all-storage --domain "${name}"
        then
            rhel_vm_deleted=yes
        else
            printf "%s\n" "Unable to delete VM ${blu:?}${name}${end:?}"
        fi
    fi

    if [ "${rhel_vm_deleted}" == "yes" ]
    then
        printf "%s\n" ""
        printf "%s\n" "Sucuessflly deleted VM ${blu:?}${name}${end:?}" 
    fi  

}

function qubinode_rhel_maintenance () {
    ## Run the qubinode_rhel function to gather required variables
    qubinode_rhel_vm_attributes 

    VM_STATE=unknown


    if sudo virsh dominfo --domain $name >/dev/null 2>&1
    then
        VM_STATE=$(sudo virsh dominfo --domain $name | awk '/State:/ {print $2}')
        WAIT_TIME=0

        # start up a vm
        if [[ "A${qubinode_maintenance_opt}" == "Astart" ]] && [[ "A${VM_STATE}" == "Ashutoff" ]]
        then
            sudo virsh start $name >/dev/null 2>&1 && printf "%s\n" "$name started"
        fi

        # shutdown a vm
        if [[ "A${qubinode_maintenance_opt}" == "Astop" ]] && [[ "A${VM_STATE}" == "Arunning" ]]
        then
            ansible $name -m command -a"shutdown +1 'Shutting down the VM'" -b >/dev/null 2>&1
            printf "\n Shutting down $name. \n"
            until [[ $VM_STATE != "running" ]] || [[ $WAIT_TIME -eq 10 ]]
            do
                ansible $name -m command -a"shutdown +1 'Shutting down'" -b >/dev/null 2>&1
                VM_STATE=$(sudo virsh dominfo --domain $name | awk '/State/ {print $2}')
                sleep $(( WAIT_TIME++ ))
            done

            if [ $VM_STATE != "running" ]
            then
                printf "%s\n" "$name stopped"
            fi

            if [ $VM_STATE == "running" ]
            then
                sudo virsh destroy $name >/dev/null 2>&1 && printf "%s\n" "$name stopped"
            fi
        fi

        # vm status
        if [ "A${qubinode_maintenance_opt}" == "Astatus" ]
        then
            printf "%s\n" "VM current state is $VM_STATE"
        fi
    fi

    # show VM status
    if [ "A${qubinode_maintenance_opt}" == "Alist" ]
    then
        printf "%s\n" " Id    Name                           State"
        printf "%s\n" " --    ----                           -----"
        sudo virsh list| awk '/rhel/ {printf "%s\n", $0}'
    else
        printf "%s\n" "unknown ${qubinode_maintenance_opt}"
    fi

    printf "%s\n\n" ""
}
