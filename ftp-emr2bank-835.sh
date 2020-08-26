#!/bin/bash
#############################################################
## Name          : ftp-emr2bank-835.sh
## Version       : 1.2
## Date          : 2017-03-06
## Author        : LHammonds
## BBVA Contacts : Redacted
## Purpose       : Copy transaction files to bank.
## Compatibility : Verified on Ubuntu Server 12.04 LTS
## Requirements  : sendemail
## Run Frequency : Every few minutes (or as often as desired)
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = failure to mount remote folder
##    2 = failure to FTP files
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2016-06-26 1.0 LTH Created script.
## 2016-12-01 1.1 LTH Bugfixes and code improvements
## 2017-03-06 1.2 LTH Updated to point to new location/folder
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

export SSHPASS='EnterSuperSecretCodeHere'
FTPID=${BANKID}
FTPIP=${BANKIP}
LogFile="${LogDir}/emr2bank-835.log"
FTPCmd="${TempDir}/emr2bank-835.ftp"
LockFile="${TempDir}/emr2bank-835.lock"
OffsiteDir="/mnt/remote"
OffsiteTestFile="${OffsiteDir}/offline.txt"
OffsiteShare="//srv-winserver/share"
SourceDir="${OffsiteDir}/bank/outbound/835"
TargetDir="/bak/bank/outbound/archive/emr/835"
TargetFTP="/home/user/835toBank/emr"
AppTitle="emr2bank-835"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other check space jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  if [ -f ${FTPCmd} ];then
    ## Remove temp file.
    rm ${FTPCmd} 1>/dev/null 2>&1
  fi
}

#######################################
##              MAIN                 ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "${AppTitle} script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when not actually running."
  f_sendmail "ERROR: ${AppTitle} script aborted" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  exit 10
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

echo "`date +%Y-%m-%d_%H:%M:%S` Script started." >> ${LogFile}

## Mount the remote share.
if [ -f ${OffsiteTestFile} ]; then
  ## Not currently mounted.  Mount the share folder.
  mount -t cifs "${OffsiteShare}" "${OffsiteDir}" --options nouser,rw,nofail,noexec,credentials=/etc/cifspw
  ## Give the system time to mount the folder.
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    ## Mount failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` ERROR: Cannot mount remote share folder. (Exit Code 1)" >> ${LogFile}
    f_sendmail "[Failed] ${AppTitle}" "Exit code 1 - Cannot mount"
    f_cleanup
    exit 1
  fi
fi

for f in ${SourceDir}/*; do
  ## Check and see if there are any files in the folder.
  if [ ! -e "$f" ]; then
    ## There are no files...nothing to do...exit.
    umount ${OffsiteDir}
    echo "`date +%Y-%m-%d_%H:%M:%S` -- No files to process." >> ${LogFile}
    echo "`date +%Y-%m-%d_%H:%M:%S` Script completed." >> ${LogFile}
    f_cleanup
    exit 0
  fi
  break
done

echo "lcd ${SourceDir}" > ${FTPCmd}
echo "cd ${TargetFTP}" >> ${FTPCmd}
echo "mput *" >> ${FTPCmd}

## Upload the files.
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP started." >> ${LogFile}
sshpass -e sftp -oBatchMode=no -b ${FTPCmd} ${FTPID}@${FTPIP} 1>> ${LogFile} 2>&1
if [[ $? != 0 ]]; then
  echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: FTP failed! (Exit Code 2)" >> ${LogFile}
  f_sendmail "[Failed] ${AppTitle}" "Exit code 2 - FTP failure"
  f_cleanup
  exit 2
else
  ## Need to move all files to a completed folder at this point. ##
  echo "`date +%Y-%m-%d_%H:%M:%S` -- Moving files to ${TargetDir}" >> ${LogFile}
  for f in ${SourceDir}/*; do
    mv "$f" ${TargetDir}/.
  done
  echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP complete." >> ${LogFile}
fi

## Unmount the remote share.
if [ ! -f ${OffsiteTestFile} ]; then
  ## Currently mounted.  Dismount the share folder.
  umount ${OffsiteDir}
  sleep 2
  if [ ! -f ${OffsiteTestFile} ]; then
    ## Unmount failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` ** WARNING: Cannot unmount remote share folder. (Exit Code 3)" >> ${LogFile}
    f_sendmail "[Warning] ${AppTitle}" "Exit code 3 - Cannot unmount"
    f_cleanup
    exit 3
  fi
fi

if [ -f ${FTPCmd} ]; then
  rm ${FTPCmd}
fi
echo "`date +%Y-%m-%d_%H:%M:%S` Script completed." >> ${LogFile}
f_cleanup
exit 0
