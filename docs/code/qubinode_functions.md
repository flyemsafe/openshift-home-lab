# lib/qubinode_functions.sh

A library of bash functions for getting the kvm host ready for ansible.

## Overview

This contains the majority of the functions required to
get the system to a state where ansible and python is available.

## Index

* [is_root()](#is_root)
* [run_su_cmd()](#run_su_cmd)
* [getPrimaryDisk()](#getprimarydisk)
* [toaddr()](#toaddr)
* [tonum()](#tonum)
* [return_netmask_ipaddr()](#return_netmask_ipaddr)
* [get_primary_interface()](#get_primary_interface)
* [libvirt_network_info()](#libvirt_network_info)
* [verify_networking_info()](#verify_networking_info)

### is_root()

#### Exit codes

* **0**: if root user

### run_su_cmd()

#### Exit codes

* **0**: if successful

### getPrimaryDisk()

Trys to determine which disk device is assosiated with the root mount /.

### toaddr()

Takes the output from the function tonum and converts it to a network address
then setting the result as a varible.

#### Example

```bash
toaddr $NETMASKNUM NETMASK
```

#### Arguments

* **$1** (number): returned by tonum
* **$2** (variable): to set the result to

#### Output on stdout

* Returns a valid network address

### tonum()

Performs bitwise operation on each octet by it's host bit lenght adding each
result for the total. 

#### Example

```bash
tonum $IPADDR IPADDRNUM
tonum $NETMASK NETMASKNUM
```

#### Arguments

* **$1** (the): ip address or netmask
* **$2** (the): variable to store the result it   

#### Output on stdout

* The bitwise number for the specefied network info

### return_netmask_ipaddr()

Returns the broadcast, netmask and network for a given ip address and netmask.

#### Example

```bash
return_netmask_ipaddr 192.168.2.11/24
return_netmask_ipaddr 192.168.2.11 255.255.255.0
```

#### Arguments

* **$1** (ipinfo): Accepts either ip/cidr or ip/mask

### get_primary_interface()

Discover which interface provides internet access and use that as the
default network interface. Determines the follow info about the interface.
* network device name
* ip address
* gateway
* network
* mac address
* pointer record (ptr) notation for the ip address

### libvirt_network_info()

Give user the choice of creating a NAT or Bridge libvirt network or to use
an existing libvirt network.

### verify_networking_info()

Asks user to confirm discovered network information.

#### See also

* [get_primary_interface](#get_primary_interface)

