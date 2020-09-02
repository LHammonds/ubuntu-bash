#!/bin/bash
#############################################################
## Name          : reboot.sh
## Version       : 1.3
## Date          : 2020-09-02
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04 - 20.04 LTS
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
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-reboot.log"

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "\nERROR: Root user required to run this script.\n"
  echo -e "Type 'sudo su' to temporarily become root user.\n"
  exit
fi

clear
echo "`date +%Y-%m-%d_%H:%M:%S` - Reboot initiated." | tee -a ${LogFile}
${ScriptDir}/prod/servicestop.sh
## Broadcasting message to any other users logged in via SSH.
echo "WARNING: Rebooting server. Should be back online in 20 seconds." | wall
echo "Rebooting..."
echo "3"
sleep 1
echo "2"
sleep 1
echo "1"
sleep 1
shutdown -r now
