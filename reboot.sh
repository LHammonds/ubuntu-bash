#!/bin/bash
#############################################################
## Name          : reboot.sh
## Version       : 1.4
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : Run as root
## Purpose       : Stop services and reboot server.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-07 1.0 LTH Created script.
## 2017-12-18 1.1 LTH Added logging.
## 2018-04-19 1.2 LTH Various minor changes.
## 2020-09-02 1.3 LTH Added broadcast notice to all connected SSH users.
## 2022-05-31 1.4 LTH Replaced echo statements with printf.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-reboot.log"

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "\nERROR: Root user required to run this script.\n"
  printf "Type 'sudo su' to temporarily become root user.\n"
  exit 1
fi

clear
printf "`date +%Y-%m-%d_%H:%M:%S` - Reboot initiated.\n" | tee -a ${LogFile}
${ScriptDir}/prod/servicestop.sh
## Broadcasting message to any other users logged in via SSH.
printf "WARNING: Rebooting server. Should be back online in 20 seconds.\n" | wall
printf "Rebooting...\n"
printf "3\n"
sleep 1
printf "2\n"
sleep 1
printf "1\n"
sleep 1
shutdown -r now
