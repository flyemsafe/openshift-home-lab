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
@stdout The bitwise number for the specefied network info
```

#### Arguments

* **$1** (the): ip address or netmask
* **$2** (the): variable to store the result it   

### return_netmask_ipaddr()

Calculates network and broadcast based on supplied ip address and netmask

