#!/bin/bash
#############################################################
## Name          : apt-upgrade.sh
## Version       : 1.3
## Date          : 2017-03-16
## Author        : LHammonds
## Purpose       : Keep system updated (rather than use unattended-upgrades)
## Compatibility : Verified on Ubuntu Server 16.04 LTS
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
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- -----------------------
## 2012-06-01 1.0 LTH Created script.
## 2013-01-08 1.1 LTH Allow visible status output if run manually.
## 2013-03-11 1.2 LTH Added company prefix to log files.
## 2017-03-16 1.3 LTH Made compatible with 16.04 LTS
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
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: ${ErrorMsg}" | tee -a ${LogFile}
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
  echo "** Script aborted **"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when check space is not actually running."
  ErrorMsg="This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when check space is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=1
  f_cleanup
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi
## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "ERROR: Root user required to run this script.\n"
  ErrorMsg="Root user required to run this script."
  ErrorFlag=2
  f_cleanup
fi

## Make sure the cleanup function is called from this point forward.
trap f_cleanup EXIT

echo "`date +%Y-%m-%d_%H:%M:%S` - Begin script." | tee -a ${LogFile}
echo "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Update" | tee -a ${LogFile}
${AptGetCmd} update > /dev/null 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Update return code of ${ReturnCode}"
  ErrorFlag=4
  f_cleanup
fi
echo "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Upgrade" | tee -a ${LogFile}
echo "--------------------------------------------------" >> ${LogFile}
${AptGetCmd} --assume-yes upgrade >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Upgrade return code of ${ReturnCode}"
  ErrorFlag=8
  f_cleanup
fi
echo "--------------------------------------------------" >> ${LogFile}
echo "`date +%Y-%m-%d_%H:%M:%S` --- Apt-Get Autoremove" | tee -a ${LogFile}
echo "--------------------------------------------------" >> ${LogFile}
${AptGetCmd} --assume-yes autoremove >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Autoremove return code of ${ReturnCode}"
  ErrorFlag=16
  f_cleanup
fi
echo "--------------------------------------------------" >> ${LogFile}
echo "`date +%Y-%m-%d_%H:%M:%S` --- Apt-get Autoclean" | tee -a ${LogFile}
echo "--------------------------------------------------" >> ${LogFile}
${AptGetCmd} autoclean >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Autoclean return code of ${ReturnCode}"
  ErrorFlag=32
  f_cleanup
fi
echo "--------------------------------------------------" >> ${LogFile}
echo "`date +%Y-%m-%d_%H:%M:%S` --- Apt-get Clean" | tee -a ${LogFile}
echo "--------------------------------------------------" >> ${LogFile}
${AptGetCmd} clean >> ${LogFile} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorMsg="Apt-Get Clean return code of ${ReturnCode}"
  ErrorFlag=64
  f_cleanup
fi
echo "--------------------------------------------------" >> ${LogFile}
echo "`date +%Y-%m-%d_%H:%M:%S` - End script." | tee -a ${LogFile}

## Perform cleanup routine.
f_cleanup
