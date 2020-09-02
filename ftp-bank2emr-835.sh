#!/bin/bash
#############################################################
## Name          : ftp-bank2emr-835.sh
## Version       : 1.3
## Date          : 2017-03-06
## Author        : LHammonds
## Bank Contacts : Redacted
## Purpose       : Copy transaction files to bank.
## Compatibility : Verified on Ubuntu Server 12.04 LTS
## Requirements  : sendemail
## Run Frequency : Every few minutes (or as often as desired)
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = FTP failure
##    2 = failure to mount remote folder
##    3 = failure to copy
##    4 = failure to archive
##    5 = failure to unmount remote folder
##   10 = Lock file detected
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2016-06-23 1.0 LTH Created script.
## 2016-12-01 1.1 LTH Bugfixes and code improvements
## 2016-12-06 1.2 LTH Fixed "if no files exist"
## 2017-03-06 1.3 LTH Updated to point to new location/folder
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

export SSHPASS='EnterSuperSecretCodeHere'
FTPID=${BANKID}
FTPIP=${BANKIP}
LogFile="${LogDir}/bank2emr-835.log"
FTPCmd="${TempDir}/bank2emr-835.ftp"
LockFile="${TempDir}/bank2emr-835.lock"
OffsiteDir="/mnt/remote"
OffsiteTestFile="${OffsiteDir}/offline.txt"
OffsiteShare="//srv-winserver/share"
FTPDir="/home/user/835fromBank/emr/835"
SourceDir="/bak/bank/inbound/new/emr/835"
ArchiveDir="/bak/bank/inbound/archive/emr/835"
TargetDir="${OffsiteDir}/bank/inbound/835"
AppTitle="bank2emr-835"

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

echo "lcd ${SourceDir}" > ${FTPCmd}
echo "cd ${FTPDir}" >> ${FTPCmd}
echo "ls -l" >> ${FTPCmd}
echo "mget *" >> ${FTPCmd}
echo "rm *" >> ${FTPCmd}

echo "`date +%Y-%m-%d_%H:%M:%S` Script started." >> ${LogFile}
## Download the files.
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP started." >> ${LogFile}
sshpass -e sftp -oBatchMode=no -b ${FTPCmd} ${FTPID}@${FTPIP} 1>> ${LogFile} 2>&1
ReturnCode=$?
case "${ReturnCode}" in
"0")
  ## Have seen this ReturnCode when no files exist to FTP
  echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP complete. FTP ReturnCode: ${ReturnCode}" >> ${LogFile}
  ;;
"1")
  ## Have seen this ReturnCode when no files exist to FTP
  echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP complete. FTP ReturnCode: ${ReturnCode}" >> ${LogFile}
  ;;
"2")
  ## Have seen this ReturnCode when no files exist to FTP
  echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP complete. FTP ReturnCode: ${ReturnCode}" >> ${LogFile}
  ;;
*)
  echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: FTP failed! FTP ReturnCode: ${ReturnCode}" >> ${LogFile}
  f_sendmail "[Failed] ${AppTitle}" "Exit code 1, FTP ReturnCode: ${ReturnCode}"
  f_cleanup
  exit 1
  ;;
esac

## If no files exist, there is nothing to do.
files=$(ls -A ${SourceDir} 2> /dev/null | wc -l)
if [ "${files}"  = "0" ]; then
  echo "`date +%Y-%m-%d_%H:%M:%S` -- No files to process." >> ${LogFile}
  echo "`date +%Y-%m-%d_%H:%M:%S` Script finished." >> ${LogFile}
  f_cleanup
  exit 0
fi

## Mount the remote share.
if [ -f ${OffsiteTestFile} ]; then
  ## Not currently mounted.  Mount the share folder.
  mount -t cifs "${OffsiteShare}" "${OffsiteDir}" --options nouser,rw,nofail,noexec,credentials=/etc/cifscgc2
  ## Give the system time to mount the folder.
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    ## Mount failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: Cannot mount remote share folder." >> ${LogFile}
    f_sendmail "[Failed] ${AppTitle}" "Script exit code 2, failure to mount offsite folder."
    f_cleanup
    exit 2
  fi
fi

## Transfer files to destination
echo "`date +%Y-%m-%d_%H:%M:%S` -- Copying files to ${TargetDir}" >> ${LogFile}
for f in ${SourceDir}/*; do
  cp "$f" ${TargetDir}/.
  if [[ $? != 0 ]]; then
    echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: Copy failed! Code: $?" >> ${LogFile}
    f_sendmail "[Failed] ${AppTitle}" "Script exit code 3, failure to copy files."
    f_cleanup
    exit 3
  fi
done

## Archive files
echo "`date +%Y-%m-%d_%H:%M:%S` -- Archiving files to ${ArchiveDir}" >> ${LogFile}
for f in ${SourceDir}/*; do
  mv "$f" ${ArchiveDir}/.
  if [[ $? != 0 ]]; then
    echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: Archive failed! Code: $?" >> ${LogFile}
    f_sendmail "[Failed] ${AppTitle}" "Script exit code 4, failure to move files."
    f_cleanup
    exit 4
  fi
done

## Unmount the remote share.
if [ ! -f ${OffsiteTestFile} ]; then
  ## Currently mounted.  Dismount the share folder.
  umount ${OffsiteDir}
  sleep 2
  if [ ! -f ${OffsiteTestFile} ]; then
    ## Unmount failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` -- WARNING: Cannot unmount remote share folder. (Exit Code 1)" >> ${LogFile}
    f_sendmail "[Warning] ${AppTitle}" "Script exit code 5, failure to unmount remote share."
    f_cleanup
    exit 5
  fi
fi

if [ -f ${FTPCmd} ]; then
  rm ${FTPCmd}
fi
echo "`date +%Y-%m-%d_%H:%M:%S` Script finished." >> ${LogFile}
f_cleanup
exit 0
