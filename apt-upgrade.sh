#!/bin/bash
#############################################################
## Name          : apt-upgrade.sh
## Version       : 1.0
## Date          : 2012-06-01
## Author        : LHammonds
## Purpose       : Keep system updated (rather than use unattended-upgrades)
## Compatibility : Verified on Ubuntu Server 12.04 LTS
## Requirements  : Sendemail, run as root
## Run Frequency : Recommend once per day.
## Parameters    : None
## Exit Codes    :
##    0 = Success
##    1 = ERROR: Lock file detected.
##    2 = ERROR: Not run as root user.
##    4 = ERROR: Aptitude update Error.
##    8 = ERROR: Aptitude safe-upgrade Error.
##   16 = ERROR: Aptitude autoclean Error.
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- -----------------------
## 2012-06-01 1.0 LTH Created script.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LOGFILE="${LOGDIR}/apt-upgrade.log"
LOCKFILE="${TEMPDIR}/apt-upgrade.lock"
ErrorFlag=0
ReturnCode=0
APTCMD="$(which aptitude)"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LOCKFILE} ];then
    ## Remove lock file so subsequent jobs can run.
    rm ${LOCKFILE} 1>/dev/null 2>&1
  fi
  exit ${ErrorFlag}
}

#######################################
##           MAIN PROGRAM            ##
#######################################

if [ -f ${LOCKFILE} ]; then
  # Lock file detected.  Abort script.
  echo "** Script aborted **"
  echo "This script tried to run but detected the lock file: ${LOCKFILE}"
  echo "Please check to make sure the file does not remain when check space is not actually running."
  f_sendmail "ERROR: Script aborted" "This script tried to run but detected the lock file: ${LOCKFILE}\n\nPlease check to make sure the file does not remain when check space is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LOCKFILE}'"
  ErrorFlag=1
  f_cleanup
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${SCRIPTNAME}" > ${LOCKFILE}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "ERROR: Root user required to run this script.\n"
  ErrorFlag=2
  f_cleanup
fi

echo "`date +%Y-%m-%d_%H:%M:%S` - Begin script." >> ${LOGFILE}
echo "`date +%Y-%m-%d_%H:%M:%S` --- Aptitude Update" >> ${LOGFILE}
${APTCMD} update > /dev/null 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorFlag=4
  f_cleanup
fi
echo "`date +%Y-%m-%d_%H:%M:%S` --- Aptitude Safe-Upgrade" >> ${LOGFILE}
echo "--------------------------------------------------" >> ${LOGFILE}
${APTCMD} safe-upgrade --assume-yes --target-release `lsb_release -cs`-security >> ${LOGFILE} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorFlag=8
  f_cleanup
fi
echo "--------------------------------------------------" >> ${LOGFILE}
echo "`date +%Y-%m-%d_%H:%M:%S` --- Aptitude Autoclean" >> ${LOGFILE}
echo "--------------------------------------------------" >> ${LOGFILE}
${APTCMD} autoclean >> ${LOGFILE} 2>&1
ReturnCode=$?
if [[ "${ReturnCode}" -gt 0 ]]; then
  ErrorFlag=16
  f_cleanup
fi
echo "--------------------------------------------------" >> ${LOGFILE}
echo "`date +%Y-%m-%d_%H:%M:%S` - End script." >> ${LOGFILE}

## Perform cleanup routine.
f_cleanup
