#!/bin/bash
#############################################################
## Name          : reboot-check.sh
## Version       : 1.3
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : Run as root
## Purpose       : Stop services and reboot server but only if necessary.
## Run Frequency : Daily after update.
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2017-12-13 1.0 LTH Created script.
## 2019-09-24 1.1 LTH Added email notification.
## 2019-10-01 1.2 LTH Added better event logging.
## 2022-05-31 1.3 LTH Replaced echo statements with printf.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-reboot-check.log"

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "\nERROR: Root user required to run this script.\n"
  printf "Type 'sudo su' to temporarily become root user.\n"
  exit 1
fi

printf "`date +%Y-%m-%d_%H:%M:%S` Current Kernel: `/bin/uname -nr`\n" | tee -a ${LogFile}
if [ -f /var/run/reboot-required ]; then
  printf "`date +%Y-%m-%d_%H:%M:%S` - Reboot required.\n" | tee -a ${LogFile}
  cat /var/run/reboot-required.pkgs >> ${LogFile}
  f_sendmail "[INFO] ${Hostname} Reboot Notice" "${Hostname} rebooted at `date +%Y-%m-%d_%H:%M:%S`"
  ${ScriptDir}/prod/reboot.sh
else
  printf "`date +%Y-%m-%d_%H:%M:%S` - No reboot required.\n" | tee -a ${LogFile}
fi
