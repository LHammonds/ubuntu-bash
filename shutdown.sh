#!/bin/bash
#############################################################
## Name          : shutdown.sh
## Version       : 1.1
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : Run as root
## Purpose       : Stop services and power off server.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2018-04-19 1.0 LTH Created script.
## 2022-05-31 1.1 LTH Replaced echo statements with printf.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-shutdown.log"

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "\nERROR: Root user required to run this script.\n"
  printf "Type 'sudo su' to temporarily become root user.\n"
  exit 1
fi

clear
printf "`date +%Y-%m-%d_%H:%M:%S` - Shutdown initiated.\n" | tee -a ${LogFile}
${ScriptDir}/prod/servicestop.sh
printf "Shutting down...\n"
printf "3\n"
sleep 1
printf "2\n"
sleep 1
printf "1\n"
sleep 1
shutdown -P now
