#!/bin/bash

### OLD VARS
DEPLOY_IDM_VM_PLAYBOOK="${QUBINODE_PROJECT_DIR}/playbooks/idm_vm_deployment.yml"
product_in_use=idm
DNS_SERVER_NAME=$(awk -F'-' '/idm_hostname:/ {print $2; exit}' "${idm_vars_file}" | tr -d '"')
prefix=$(awk '/instance_prefix:/ {print $2;exit}' "${vars_file}")
idm_server_name=$(awk '/idm_server_name:/ {print $2;exit}' "${vars_file}")
suffix=$(awk '/idm_server_name:/ {print $2;exit}' "${idm_vars_file}" |tr -d '"')
idm_srv_hostname="$prefix-$suffix"
idm_srv_fqdn="$prefix-$suffix.$domain"
    deploy_idm_server=$(awk '/deploy_idm_server:/ {print $2; exit}' "${idm_vars_file}"| tr -d '"')
    ask_use_existing_idm=$(awk '/ask_use_existing_idm:/ {print $2; exit}' "${idm_vars_file}"| tr -d '"')


### NEW VARS
idm_dns_forwarder="${IDM_DNS_FORWARDER:?}"
idm_server_ptr="${IDM_SERVER_PTR:?}"

function display_idmsrv_unavailable () {
    printf "%s\n" "${yel}Either the IdM server variable idm_public_ip is not set.${end}"
    printf "%s\n" "${yel}Or the IdM server is not reachable.${end}"
    printf "%s\n" "${yel}Ensure the IdM server is running, update the variable and try again.${end}"
    exit 1
}



function isIdMrunning () {
     # Test idm server 
    prefix=$(awk '/instance_prefix:/ {print $2;exit}' "${vars_file}")
    suffix=$(awk '/idm_server_name:/ {print $2;exit}' "${idm_vars_file}" |tr -d '"')
    idm_srv_fqdn="$prefix-$suffix.$domain"


    if ! curl -k -s "https://${idm_srv_fqdn}/ipa/config/ca.crt" >/dev/null 2>&1
    then
        idm_running=false
    elif curl -k -s "https://${idm_srv_fqdn}/ipa/config/ca.crt" >/dev/null 2>&1
    then
        idm_running=true
    else
        idm_running=false
    fi
}

function qubinode_teardown_idm () {
     
     libvirt_dir=$(awk '/^kvm_host_libvirt_dir/ {print $2}' "${kvm_host_vars_file}")
     local vmdisk="${libvirt_dir}/${idm_srv_hostname}_vda.qcow2"
     if sudo virsh list --all |grep -q "${idm_srv_hostname}"
     then
         echo "Remove IdM VM"
         ansible-playbook "${DEPLOY_IDM_VM_PLAYBOOK}" --extra-vars "vm_teardown=true" || exit $?
     fi
     echo "Ensure IdM server deployment is cleaned up"
     ansible-playbook "${IDM_SERVER_CLEANUP_PLAYBOOK}" || exit $?
     sudo test -f "${vmdisk}" && sudo rm -f "${vmdisk}"

     printf "\n\n*************************\n"
     printf "* IdM server VM deleted *\n"
     printf "*************************\n\n"
}

function qubinode_deploy_idm_vm () {
    if grep deploy_idm_server "${idm_vars_file}" | grep -q yes
    then
        isIdMrunning
        if [ "A${idm_running}" == "Afalse" ]
        then
            qubinode_setup
            ask_user_for_custom_idm_server
            
        fi

        IDM_SERVER_CLEANUP_PLAYBOOK="${project_dir}/playbooks/idm_server_cleanup.yml"
        SET_IDM_STATIC_IP=$(awk '/idm_check_static_ip/ {print $2; exit}' "${idm_vars_file}"| tr -d '"')

        if [ "A${idm_running}" == "Afalse" ]
        then
            echo "running playbook ${DEPLOY_IDM_VM_PLAYBOOK}"
            if [ "A${SET_IDM_STATIC_IP}" == "Ayes" ]
            then
                echo "Deploy with custom IP"
                idm_server_ip=$(awk '/idm_server_ip:/ {print $2}' "${idm_vars_file}")
                if [ "A${idm_server_ip}" == 'A""' ];
                then
                  printf "%s\n" ""
                  printf "%s\n" "  The IdM server does not have a static ip defined"
                  printf "%s\n\n" "  Please enter desiered static ip."
                  set_idm_static_ip
                fi
                idm_server_ip=$(awk '/idm_server_ip:/ {print $2}' "${idm_vars_file}")
                #ansible-playbook "${DEPLOY_IDM_VM_PLAYBOOK}" --extra-vars "vm_ipaddress=${idm_server_ip}"|| exit $?
             else
                 echo "Deploy without custom IP"
                 #ansible-playbook "${DEPLOY_IDM_VM_PLAYBOOK}" || exit $?
             fi
         fi
     fi
}

function qubinode_idm_status () {
    isIdMrunning
    if [ "A${idm_running}" == "Atrue" ]
    then
        printf "\n"
        printf "     ${blu}IdM server is installed${end}\n"
        printf "   ${yel}****************************************************${end}\n"
        printf "    Webconsole: ${cyn}https://${idm_srv_fqdn}/ipa/ui/${end} \n"
        printf "    IP Address: ${cyn}${idm_server_ip}${end} \n"
        printf "    Username: ${cyn}${idm_admin_user}${end}\n"
        printf "    Password: Run the below command to view the vault variable ${cyn}admin_user_password${end} \n\n"
        printf "    ${blu}Run:${end} ${grn}ansible-vault view $HOME/qubinode-installer/playbooks/vars/vault.yml ${vaultfile}${end} \n\n"
     else
        printf "%s\n" " ${red}IDM Server was not properly deployed please verify deployment.${end}"
        exit 1
     fi
}

function qubinode_install_idm () {
    isIdMrunning
    if [ "A${idm_running}" != "Atrue" ]
    then
        ask_user_input
        DEPLOY_IDM_SERVER_PLAYBOOK="${project_dir}/playbooks/idm_server.yml"

        echo "Install and configure the IdM server"
        idm_server_ip=$(awk '/idm_server_ip:/ {print $2}' "${idm_vars_file}")
        echo "Current IP of IDM Server ${idm_server_ip}" || exit $?
        ansible-playbook "${DEPLOY_IDM_SERVER_PLAYBOOK}" --extra-vars "vm_ipaddress=${idm_server_ip}" || exit $?
	qubinode_idm_status
     else
	qubinode_idm_status
     fi
}

function qubinode_deploy_idm () {
    check_additional_storage

    # Ensure host system is setup as a KVM host
    kvm_host_health_check
    if [[ "A${KVM_IN_GOOD_HEALTH}" != "Aready"  ]]; then
      qubinode_setup_kvm_host
    fi
    ask_user_for_custom_idm_server

    qubinode_deploy_idm_vm
    qubinode_install_idm
}

function qubinode_idm_maintenance () {
    case ${product_maintenance} in
       stop)
            name=$idm_srv_hostname
	    qubinode_rhel_maintenance
            ;;
       start)
            name=$idm_srv_hostname
	    qubinode_rhel_maintenance
            ;;
       status)
            qubinode_idm_status
            ;;
       *)
           echo "No arguement was passed"
           ;;
    esac
}