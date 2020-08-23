#!/bin/bash
#############################################################
## Name          : reboot-check.sh
## Version       : 1.2
## Date          : 2019-10-01
## Author        : LHammonds
## Compatibility : Ubuntu Server 16.04.3 - 18.04.3 LTS
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
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-reboot-check.log"

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "\nERROR: Root user required to run this script.\n"
  echo -e "Type 'sudo su' to temporarily become root user.\n"
  exit
fi

echo "`date +%Y-%m-%d_%H:%M:%S` Current Kernel: `/bin/uname -nr`" | tee -a ${LogFile}
if [ -f /var/run/reboot-required ]; then
  echo "`date +%Y-%m-%d_%H:%M:%S` - Reboot required." | tee -a ${LogFile}
  cat /var/run/reboot-required.pkgs >> ${LogFile}
  f_sendmail "[INFO] ${Hostname} Reboot Notice" "${Hostname} rebooted at `date +%Y-%m-%d_%H:%M:%S`"
  ${ScriptDir}/prod/reboot.sh
else
  echo "`date +%Y-%m-%d_%H:%M:%S` - No reboot required." | tee -a ${LogFile}
fi
