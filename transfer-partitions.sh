#!/bin/bash
#############################################
## Name          : transfer-partitions.sh
## Version       : 1.0
## Date          : 2020-06-01
## Author        : LHammonds
## Purpose       : Move backed up files from remote servers.
## Compatibility : Verified on Ubuntu Server 20.04 LTS
## Requirements  : None
## Run Frequency : Run as needed.
## Parameters    :
##    1 = (Required) Server name (needs to be resolvable to IP address)
## Exit Codes    :
##    0 = Success
##    1 = ERROR: Missing / Incorrect server name
##    2 = ERROR: Must run as root
##    4 = ERROR: Cannot resolve IP
##    8 = ERROR: LockFile detected
##   16 = ERROR: Mount failure
##   32 = ERROR: rsync failure
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2020-06-01 1.0 LTH Created script.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/${Company}-transfer-partitions.log"
LockFile="${TempDir}/${Company}-transfer-partitions.lock"
SourceDir="/mnt/${1}"
TargetDir="/bak/${1}"
ErrorFlag=0
ReturnCode=0

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other check space jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  echo "`date +%Y-%m-%d_%H:%M:%S` [INFO] Exit code for ${ServerName}: ${ErrorFlag}" | tee -a ${LogFile}
  exit ${ErrorFlag}
}

function f_showhelp()
{
  echo -e "\n${LGREEN}Usage${COLORRESET}  : ${ScriptName} ${LYELLOW}{ServerName}${COLORRESET}"
  echo -e "${LGREEN}Example${COLORRESET}: ${ScriptName} ${LRED}srv-mariadb${COLORRESET}\n"
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Check existance of required command-line parameter(s).
case "$1" in
  "")
    f_showhelp
    ErrorFlag=2
    f_cleanup
    ;;
  --help|-h|-?)
    f_showhelp
    ErrorFlag=1
    f_cleanup
    ;;
  *)
    ServerName=$1
    ;;
esac

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo "[ERROR] Root user required to run this script."
  echo ""
  ErrorFlag=2
  f_cleanup
fi

## Check validity of server name.
## 0 = No associated IP address
## 1 = Found IP address
ReturnCode=`dig +short ${ServerName} | wc -l`
if [ ${ReturnCode} -eq 0 ]; then
  ## ERROR: ServerName not valid.
  echo "[ERROR] ${ServerName} cannot be resolved to an IP address." | tee -a ${LogFile}
  ErrorFlag=4
  f_cleanup
fi

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "Script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when check space is not actually running."
  f_sendmail "ERROR: Transfer partitions script aborted" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when check space is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=8
  f_cleanup
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

## Check if the mount point exists.
if [ ! -d ${SourceDir} ]; then
  ## Create mount point and offline indicator file.
  ## NOTE: If you can see offline.txt, then its not mounted.
  mkdir -p ${SourceDir}
  echo "Offline test file" > ${SourceDir}/offline.txt
  chown root:root ${SourceDir}/offline.txt
  chmod 444 ${SourceDir}/offline.txt
fi
if [ ! -d ${TargetDir} ]; then
  ## Create the target folder destination.
  mkdir -p ${TargetDir}
  chown root:root ${TargetDir}
  chmod 700 ${TargetDir}
fi
echo "`date +%Y-%m-%d_%H:%M:%S` [INFO] Started - ${ServerName}" | tee -a ${LogFile}
## Connect to the server to pull files from.
mount ${ServerName}:/bak ${SourceDir}
## Make sure mount command was successful.
if [ -f ${SourceDir}/offline.txt ]; then
  ## Could not connect to remote server.
  echo "[ERROR] Not mounted: ${SourceDir}" | tee -a ${LogFile}
  ErrorFlag=16
  f_cleanup
else
  echo "`date +%Y-%m-%d_%H:%M:%S` [INFO] rsync ${SourceDir}/partitions ${TargetDir}" | tee -a ${LogFile}
  rsync -apogHK --out-format="%n" --delete --exclude=*.pid ${SourceDir}/partitions ${TargetDir} >> ${LogFile}
  ReturnCode=$?
  if [ ${ReturnCode} -ne 0 ]; then
    ## Fatal error detected.
    echo "`date +%Y-%m-%d_%H:%M:%S` [SEVERE] rsync failed ${SourceDir}/partitions to ${TargetDir}. Return Code = ${ReturnValue}" | tee -a ${LogFile}
    ErrorFlag=32
    umount ${SourceDir}
    f_cleanup
  fi
fi
echo "`date +%Y-%m-%d_%H:%M:%S` [INFO] Completed - ${ServerName}" | tee -a ${LogFile}
## Disconnect from the server.
umount ${SourceDir}
f_cleanup
