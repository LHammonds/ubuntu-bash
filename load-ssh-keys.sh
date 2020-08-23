#!/bin/bash
#############################################################
## Name          : load-ssh-keys.sh
## Version       : 1.0
## Date          : 2017-02-16
## Author        : LHammonds
## Compatibility : Ubuntu Server 16.04 LTS
## Requirements  : Run as root
## Purpose       : Load SSH keys into memory which will allow FTP login
##                 without prompts. Useful for automated FTP scripts.
## Run Frequency : As needed
## Exit Codes    : None
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- -----------------------
## 2017-02-16 1.0 LTH Created script.
#############################################################

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "\nERROR: Root user required to run this script.\n"
  echo -e "Type 'sudo su' to temporarily become root user.\n"
  exit
fi
clear
ssh-add -l >/dev/null
if [ "$?" == 2 ]; then
  ## Agent not loaded, load it up.
  eval `ssh-agent -s`
fi
echo "Purging any existing keys from memory..."
ssh-add -D
echo "Enter the Company #1 SSH passphrase..."
ssh-add /root/.ssh/ssh2rsa-company1-private.rsa
echo "Enter the Company #2 SSH passphrase..."
ssh-add /root/.ssh/ssh2rsa-company1-private.rsa
echo "Listing all keys in memory..."
ssh-add -l
echo "Complete. Keys will remain in memory until the next reboot."
echo ""
read -p "Press [Enter] key to continue..."
