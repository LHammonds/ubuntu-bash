#!/bin/bash
#############################################################
## Name : back-parts.sh (Backup Partitions)
## Version : 1.3
## Date : 2017-10-04
## Author : LHammonds
## Purpose : Backup partitions
## Compatibility : Verified on Ubuntu Server 12.04 thru 16.04 LTS (fsarchiver 0.6.12)
## Requirements : Fsarchiver, Sendemail, run as root
## Run Frequency : Once per day or as often as desired.
## Parameters : None
## Exit Codes :
## 0  = Success
## 1  = ERROR: Lock file detected
## 2  = ERROR: Must be root user
## 4  = ERROR: Missing software
## 8  = ERROR: LVM problems
## 16 = ERROR: File creation problems
## 32 = ERROR: Mount/Unmount problems
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-09 1.0 LTH Created script.
## 2017-03-16 1.1 LTH Changed variables to CamelCase.
## 2017-08-31 1.2 LTH Added create folder if not exist.
## 2017-10-04 1.3 LTH Set file permissions.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-back-parts.log"
LockFile="${TempDir}/${Company}-back-parts.lock"
LVG="/dev/LVG"
TempLV="${LVG}/tempsnap"
MaxTempVolSize=1G
ErrorFlag=0
ReturnCode=0
CryptPass="abc123"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other check space jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  if [ ${ErrorFlag} != 0 ]; then
    f_sendmail "ERROR: Script Failure" "Please review the log file on ${Hostname}${LogFile}"
    echo "`date +%Y-%m-%d_%H:%M:%S` - Backup aborted." >> ${LogFile}
  fi
  exit ${ErrorFlag}
}

function f_archive_fs()
{
  FSName=$1
  FSPath=$2

  ## Purge old backup files.
  if [ -f ${BackupDir}/${Hostname}-${FSName}.fsa ]; then
    rm ${BackupDir}/${Hostname}-${FSName}.fsa
  fi
  if [ -f ${BackupDir}/${Hostname}-${FSName}.txt ]; then
    rm ${BackupDir}/${Hostname}-${FSName}.txt
  fi
  if [ -f ${BackupDir}/${Hostname}-${FSName}.md5 ]; then
    rm ${BackupDir}/${Hostname}-${FSName}.md5
  fi

  ## Unmount FileSystem.
  umount /${FSName}

  LVLabel="${Hostname}:${FSPath}->/${FSName}"
  ## Create the compressed and encrypted archive of the snapshot.
  fsarchiver savefs --compress=7 --jobs=1 --cryptpass="${CryptPass}" --label="${LVLabel}" ${BackupDir}/${Hostname}-${FSName}.fsa ${FSPath} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of the archive failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of ${BackupDir}/${FSName}.fsa failed, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create an informational text file about the archive.
  fsarchiver archinfo --cryptpass="${CryptPass}" ${BackupDir}/${Hostname}-${FSName}.fsa > ${BackupDir}/${Hostname}-${FSName}.txt 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of info text failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of info file failed for ${BackupDir}/${FSName}.txt, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create a checksum file about the archive.
  md5sum ${BackupDir}/${Hostname}-${FSName}.fsa > ${BackupDir}/${Hostname}-${FSName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of md5 checksum failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of checksum failed for ${BackupDir}/${FSName}.md5, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Verify that the checksum file can validate against the archive.
  md5sum --check --status ${BackupDir}/${Hostname}-${FSName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Verification failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: md5 validation check failed for ${BackupDir}/${FSName}.md5. Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Set file permissions.
  chmod 0600 ${BackupDir}/${Hostname}-${FSName}.*

  BackupSize=`ls -lak --block-size=m "${BackupDir}/${Hostname}-${FSName}.fsa" | awk '{ print $5 }'`

  echo "`date +%Y-%m-%d_%H:%M:%S` --- Created: ${BackupDir}/${Hostname}-${FSName}.fsa, ${BackupSize}" >> ${LogFile}

  ## Make sure target folder exists.
  if [ ! -d ${OffsiteDir}/${Hostname} ]; then
    ## Create folder.  This is typical of 1st time use.
    mkdir -p ${OffsiteDir}/${Hostname}
  fi
  ## Copy the backup to an offsite storage location.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- Copying archive file to offsite location." >> ${LogFile}
  cp ${BackupDir}/${Hostname}-${FSName}.* ${OffsiteDir}/${Hostname}/. 1>/dev/null 2>&1
  if [ ! -f ${OffsiteDir}/${Hostname}/${Hostname}-${FSName}.fsa ]; then
    ## NON-FATAL ERROR: Copy command did not work.  Send email notification.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- WARNING: Remote copy failed. ${OffsiteDir}/${Hostname}/${Hostname}-${FSName}.fsa does not exist!" >> ${LogFile}
    f_sendmail "Backup Failure - Remote Copy" "Remote copy failed. ${OffsiteDir}/${Hostname}/${Hostname}-${FSName}.fsa does not exist\n\nBackup file still remains in this location: ${Hostname}:${BackupDir}/${Hostname}-${FSName}.fsa"
  fi

  ## Remount FileSystem.
  mount /${FSName}
}

function f_archive_vol()
{
  LVName=$1
  LVPath=${LVG}/${LVName}

  ## Purge old backup files.
  if [ -f ${BackupDir}/${Hostname}-${LVName}.fsa ]; then
    rm ${BackupDir}/${Hostname}-${LVName}.fsa
  fi
  if [ -f ${BackupDir}/${Hostname}-${LVName}.txt ]; then
    rm ${BackupDir}/${Hostname}-${LVName}.txt
  fi
  if [ -f ${BackupDir}/${Hostname}-${LVName}.md5 ]; then
    rm ${BackupDir}/${Hostname}-${LVName}.md5
  fi

  ## Create the snapshot volume of the partition to be backed up.
  lvcreate --size=${MaxTempVolSize} --snapshot --name="tempsnap" ${LVPath} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of temporary volume failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of temp volume failed for ${LVPath}, size=${MaxTempVolSize}, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=8
    f_cleanup
  fi

  ## Give the OS a moment to let the LV create command do its thing.
  sleep 2

  LVLabel="${Hostname}:${LVPath}"
  ## Create the compressed and encrypted archive of the snapshot.
  fsarchiver savefs --compress=7 --jobs=1 --cryptpass="${CryptPass}" --label="${LVLabel}" ${BackupDir}/${Hostname}-${LVName}.fsa ${TempLV} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of the archive failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of ${BackupDir}/${Hostname}-${LVName}.fsa failed, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create an informational text file about the archive.
  fsarchiver archinfo --cryptpass="${CryptPass}" ${BackupDir}/${Hostname}-${LVName}.fsa > ${BackupDir}/${Hostname}-${LVName}.txt 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of info text failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of info file failed for ${BackupDir}/${Hostname}-${LVName}.txt, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create a checksum file about the archive.
  md5sum ${BackupDir}/${Hostname}-${LVName}.fsa > ${BackupDir}/${Hostname}-${LVName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of md5 checksum failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of checksum failed for ${BackupDir}/${Hostname}-${LVName}.md5, Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Set file permissions.
  chmod 0600 ${BackupDir}/${Hostname}-${LVName}.*

  ## Remove the snapshot.
  lvremove --force ${TempLV} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Removal of temporary volume failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Removal of temp volume failed. ${TempLV}. Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=8
    f_cleanup
  fi

  ## Give the OS a moment to let the LV remove command do its thing.
  sleep 2

  ## Verify that the checksum file can validate against the archive.
  md5sum --check --status ${BackupDir}/${Hostname}-${LVName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Verification failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: md5 validation check failed for ${BackupDir}/${Hostname}-${LVName}.md5. Return Code = ${ReturnCode}" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  BackupSize=`ls -lak --block-size=m "${BackupDir}/${Hostname}-${LVName}.fsa" | awk '{ print $5 }'`

  echo "`date +%Y-%m-%d_%H:%M:%S` --- Created: ${BackupDir}/${Hostname}-${LVName}.fsa, ${BackupSize}" >> ${LogFile}

  ## Make sure target folder exists.
  if [ ! -d ${OffsiteDir}/${Hostname} ]; then
    ## Create folder.  This is typical of 1st time use.
    mkdir -p ${OffsiteDir}/${Hostname}
  fi
  ## Copy the backup to an offsite storage location.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- Copying archive file to offsite location." >> ${LogFile}
  cp ${BackupDir}/${Hostname}-${LVName}.* ${OffsiteDir}/${Hostname}/. 1>/dev/null 2>&1
  if [ ! -f ${OffsiteDir}/${Hostname}/${Hostname}-${LVName}.fsa ]; then
    ## NON-FATAL ERROR: Copy command did not work.  Send email notification.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- WARNING: Remote copy failed. ${OffsiteDir}/${Hostname}/${Hostname}-${LVName}.fsa does not exist!" >> ${LogFile}
    f_sendmail "Backup Failure - Remote Copy" "Remote copy failed. ${OffsiteDir}/${Hostname}/${Hostname}-${LVName}.fsa does not exist\n\nBackup file still remains in this location: ${Hostname}:${BackupDir}/${Hostname}-${LVName}.fsa"
  fi
}

#######################################
##           MAIN PROGRAM            ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "Backup partitions script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when backup partitions is not actually running."
  f_sendmail "ERROR: Backup partitions script aborted" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when backup partitions is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=1
  exit ${ErrorFlag}
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo "`date +%Y-%m-%d_%H:%M:%S` ERROR: Root user required to run this script." >> ${LogFile}
  ErrorFlag=2
  f_cleanup
fi

## Requirement Check: Software
command -v fsarchiver > /dev/null 2>&1 && ReturnCode=0 || ReturnCode=1
if [ ${ReturnCode} = 1 ]; then
  ## Required program not installed.
  echo "`date +%Y-%m-%d_%H:%M:%S` ERROR: fsarchiver not installed." >> ${LogFile}
  ErrorFlag=4
  f_cleanup
fi

## Mount the remote folder. ##
f_mount

if [ -f ${OffsiteTestFile} ]; then
  ## Found local file.  Assuming failed mount.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Cannot detect remote location: ${OffsiteTestFile}" >> ${LogFile}
  ErrorFlag=32
  f_cleanup
fi

StartTime="$(date +%s)"
echo "`date +%Y-%m-%d_%H:%M:%S` - Backup started." >> ${LogFile}

f_archive_fs boot /dev/sda1
f_archive_vol root
f_archive_vol var
f_archive_vol tmp
f_archive_vol home
f_archive_vol usr
f_archive_vol srv
f_archive_vol opt
#f_archive_vol swap

## Unmount the Windows shared folder.
f_umount

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

echo "`date +%Y-%m-%d_%H:%M:%S` --- Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" >> ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - Backup Finished." >> ${LogFile}
f_cleanup
