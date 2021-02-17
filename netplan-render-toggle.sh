#!/bin/bash
#############################################################
## Name          : netplan-render-toggle.sh
## Version       : 1.0
## Date          : 2021-02-17
## Author        : LHammonds
## Purpose       : Toggle netplan render between networkd and NetworkManager
## Compatibility : Verified on Ubuntu Desktop 20.04 LTS
## Requirements  : run as root
## Run Frequency : Manually as needed
## Parameters    : None
## Exit Codes :
## 0  = Success
## 1  = ERROR: Must be root user
## 2  = ERROR: Expected networkd configuration file missing
## 3  = ERROR: Could not create NetworkManager file
## 4  = ERROR: Failed to rename networkd file
## 5  = ERROR: Failed to rename NetworkManager file
## 6  = ERROR: Failed to rename NetworkManager file
## 7  = ERROR: Failed to rename networkd file
## 8  = ERROR: Failed to ping test IP address
###################### CHANGE LOG ###########################
## DATE       VER WHO         WHAT WAS CHANGED
## ---------- --- ----------- ---------------------------------------
## 2021-02-17 1.0 LHammonds   Created script.
#############################################################

## NOTE: This script assumes you have a working networkd configuration file.

## Define variables ##
NetworkManagerFile="/etc/netplan/01-network-manager-all"
NetworkdFile="/etc/netplan/01-netcfg"
TestIP="8.8.8.8"

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  echo "[ERROR:1] Root user required to run this script."
  exit 1
fi

## Make sure our primary assumption of an existing default Networkd file exists ##
if [ ! -f ${NetworkdFile}.yaml ] && [ ! -f ${NetworkdFile}.bak ]; then
  ## Abort script since the required default file does not exist ##
  echo "[ERROR:2] Default networkd file nor the backup was found."
  exit 2
fi

## Check if NetworkManager file exists ##
if [ ! -f ${NetworkManagerFile}.yaml ] && [ ! -f ${NetworkManagerFile}.bak ]; then
  ## Create NetworkManager file ##
  echo "[INFO] NetworkManager file not found.  Creating a new one..."
  touch ${NetworkManagerFile}.bak
  chown root:root ${NetworkManagerFile}.bak
  chmod 0644 ${NetworkManagerFile}.bak
  cat << EOF > ${NetworkManagerFile}.bak
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: NetworkManager
EOF
  if [ ! -f ${NetworkManagerFile}.bak ]; then
    echo "[ERROR:3] Could not create NetworkManager file."
    exit 3
  fi
fi

## Toggle between NetworkManager and Networkd each time this script runs ##
if [ -f ${NetworkdFile}.yaml ]; then
  echo "[INFO] Switching from networkd to NetworkManager"
  mv ${NetworkdFile}.yaml ${NetworkdFile}.bak
  ## Make sure the rename worked ##
  if [ ! -e ${NetworkdFile}.bak ]; then
    echo "[ERROR:4] Could not rename ${NetworkdFile}.yaml"
    exit 4
  fi
  ## Rename NetworkManager file ##
  mv ${NetworkManagerFile}.bak ${NetworkManagerFile}.yaml
  ## Make sure the rename worked ##
  if [ ! -f ${NetworkManagerFile}.yaml ]; then
    echo "[ERROR:5] Could not rename ${NetworkManagerFile}.bak"
    exit 5
  fi
  echo "[INFO] Enabling NetworkManager service..."
  systemctl enable NetworkManager.service > /dev/null 2>&1
  systemctl start NetworkManager.service > /dev/null 2>&1
else
  echo "[INFO] Switching from NetworkManager to networkd"
  mv ${NetworkManagerFile}.yaml ${NetworkManagerFile}.bak
  ## Make sure the rename worked ##
  if [ ! -f ${NetworkManagerFile}.bak ]; then
    echo "[ERROR:6] Could not rename ${NetworkManagerFile}.yaml"
    exit 6
  fi
  ## Rename networkd file ##
  mv ${NetworkdFile}.bak ${NetworkdFile}.yaml
  ## Make sure the rename worked ##
  if [ ! -f ${NetworkdFile}.yaml ]; then
    echo "[ERROR:7] Could not rename ${NetworkdFile}.bak"
    exit 7
  fi
  echo "[INFO] Disabling NetworkManager service..."
  systemctl disable NetworkManager.service > /dev/null 2>&1
  systemctl stop NetworkManager.service > /dev/null 2>&1
fi

echo "[INFO] Applying changes to NetPlan..."
netplan generate
netplan apply

if [ -f ${NetworkManagerFile}.yaml ]; then
  echo "[INFO] Restarting NetworkManager service..."
  systemctl restart NetworkManager.service > /dev/null 2>&1
fi

echo "[INFO] Current network settings..."
ip address | grep inet

echo "[INFO] Current interfaces that are UP..."
ip link | grep -i -w UP

ping -c 1 ${TestIP} > /dev/null
ReturnCode=$?
if [ ${ReturnCode} -eq 0 ]; then
  echo "[INFO] Successful ping test to ${TestIP}"
else
  echo "[ERROR:8] Cannot ping ${TestIP}"
  echo "[INFO] Something is incorrect with the configuration or network"
fi

## Clean exit of script at this point ##
exit 0
