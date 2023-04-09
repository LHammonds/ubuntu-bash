#!/bin/bash
#############################################################
## Name          : apt-upgrade.sh
## Version       : 1.5
## Date          : 2022-05-31
## Author        : LHammonds
## Purpose       : Keep system updated (rather than use unattended-upgrades)
## Compatibility : Verified on Ubuntu Server 18.04 thru 22.04 LTS
## Requirements  : Sendemail, run as root
## Run Frequency : Recommend once per day.
## Parameters    : None
## Exit Codes    :
##    0 = Success
##    1 = ERROR: Lock file detected.
##    2 = ERROR: Not run as root user.
##    4 = ERROR: APT update Error.
##    8 = ERROR: APT upgrade Error.
##   16 = ERROR: APT autoremove Error.
##   32 = ERROR: APT autoclean Error.
##   64 = ERROR: APT clean Error.
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2012-06-01 1.0 LTH Created script.
## 2013-01-08 1.1 LTH Allow visible status output if run manually.
## 2013-03-11 1.2 LTH Added company prefix to log files.
## 2017-03-16 1.3 LTH Made compatible with 16.04 LTS.
## 2019-09-23 1.4 LTH Set to not overwrite existing config file.
## 2022-05-31 1.5 LTH Changed echo statements to printf.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-apt-upgrade.log"
LockFile="${TempDir}/${Company}-apt-upgrade.lock"
ErrorFlag=0
ErrorMsg=""
ReturnCode=0
AptCmd="$(which apt)"
AptGetCmd="$(which apt-get)"

#######################################
##            FUNCTIONS              ##
#######################################
function f_cleanup()
{
  if [ -f ${LockFile} ]; then
    ## Remove lock file so subsequent jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  ## Temporarily pause script in case user is watching output.
  sleep 2
  if [ ${ErrorFlag} -gt 0 ]; then
    ## Display error message to user in case being run manually.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: ${ErrorMsg}\n" | tee -a ${LogFile}
    ## Email error notice.
    f_sendmail "ERROR ${ErrorFlag}: Script aborted" "${ErrorMsg}"
  fi
  exit ${ErrorFlag}
}

#######################################
##           MAIN PROGRAM            ##
#######################################
clear
if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  printf "** Script aborted **\n"
  printf "This script tried to run but detected the lock file: ${LockFile}\n"
  printf "Please check to make sure the file does not remain when check space is not actually running.\n"
  ErrorMsg="This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when check space is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=1
  f_cleanup
else
  printf "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}\n" > ${LockFile}
fi
## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "ERROR: Root user required to run this script.\n"
  ErrorMsg="Root user required to run this script."
  ErrorFlag=2
  f_cleanup
fi

## Make sure the cleanup function is called from this point forward.
trap f_cleanup EXIT

printf "`date +%Y-%m-%d_%H:%M:%S` - Begin script.\n" | tee -a ${LogFile}
printf "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Update\n" | tee -a ${LogFile}
${AptGetCmd} update > /dev/null 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Update return code of ${ReturnCode}"
  ErrorFlag=4
  f_cleanup
fi
printf "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Upgrade\n" | tee -a ${LogFile}
printf "==================================================\n" >> ${LogFile}
${AptGetCmd} --assume-yes --option Dpkg::Options::="--force-confdef" --option Dpkg::Options::="--force-confold" upgrade >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Upgrade return code of ${ReturnCode}"
  ErrorFlag=8
  f_cleanup
fi
printf "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Dist-Upgrade\n" | tee -a ${LogFile}
printf "==================================================\n" >> ${LogFile}
${AptGetCmd} --assume-yes --option Dpkg::Options::="--force-confdef" --option Dpkg::Options::="--force-confold" dist-upgrade >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Dist-Upgrade return code of ${ReturnCode}"
  ErrorFlag=8
  f_cleanup
fi
printf "==================================================\n" >> ${LogFile}
printf "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Autoremove\n" | tee -a ${LogFile}
printf "==================================================\n" >> ${LogFile}
${AptGetCmd} --assume-yes autoremove >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Autoremove return code of ${ReturnCode}"
  ErrorFlag=16
  f_cleanup
fi
printf "==================================================\n" >> ${LogFile}
printf "`date +%Y-%m-%d_%H:%M:%S` --- Apt-get Autoclean\n" | tee -a ${LogFile}
printf "==================================================\n" >> ${LogFile}
${AptGetCmd} autoclean >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Autoclean return code of ${ReturnCode}"
  ErrorFlag=32
  f_cleanup
fi
printf "==================================================\n" >> ${LogFile}
printf "`date +%Y-%m-%d_%H:%M:%S` --- Apt-get Clean\n" | tee -a ${LogFile}
printf "==================================================\n" >> ${LogFile}
${AptGetCmd} clean >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Clean return code of ${ReturnCode}"
  ErrorFlag=64
  f_cleanup
fi
printf "==================================================\n" >> ${LogFile}
printf "`date +%Y-%m-%d_%H:%M:%S` - End script.\n" | tee -a ${LogFile}

## Perform cleanup routine.
f_cleanup
