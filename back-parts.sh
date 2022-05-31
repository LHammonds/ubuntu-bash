#!/bin/bash
#############################################################
## Name : back-parts.sh (Backup Partitions)
## Version : 1.6
## Date : 2022-05-31
## Author : LHammonds
## Purpose : Backup partitions
## Compatibility : Verified on Ubuntu Server 22.04 LTS
##                 Verified with fsarchiver 0.8.6)
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
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-09 1.0 LTH Created script.
## 2017-03-16 1.1 LTH Updated variable standards.
## 2017-08-31 1.2 LTH Added create folder if not exist.
## 2017-10-04 1.3 LTH Set file permissions.
## 2020-01-01 1.4 LTH Remove any prior temp snapshots before starting.
## 2020-05-27 1.5 LTH Removed offsite copy section. The offsite
##                    location will pull files for better security.
## 2022-05-31 1.6 LTH Replaced echo statements with printf.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-back-parts.log"
LockFile="${TempDir}/${Company}-back-parts.lock"
TargetDir="${BackupDir}/partitions"
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
    printf "`date +%Y-%m-%d_%H:%M:%S` - Backup aborted.\n" >> ${LogFile}
  fi
  exit ${ErrorFlag}
}

function f_archive_fs()
{
  FSName=$1
  FSPath=$2

  ## Purge old backup files.
  if [ -f ${TargetDir}/${Hostname}-${FSName}.fsa ]; then
    rm ${TargetDir}/${Hostname}-${FSName}.fsa
  fi
  if [ -f ${TargetDir}/${Hostname}-${FSName}.txt ]; then
    rm ${TargetDir}/${Hostname}-${FSName}.txt
  fi
  if [ -f ${TargetDir}/${Hostname}-${FSName}.md5 ]; then
    rm ${TargetDir}/${Hostname}-${FSName}.md5
  fi

  ## Unmount FileSystem.
  umount /${FSName}

  LVLabel="${Hostname}:${FSPath}->/${FSName}"
  ## Create the compressed and encrypted archive of the snapshot.
  fsarchiver savefs --compress=7 --jobs=1 --cryptpass="${CryptPass}" --label="${LVLabel}" ${TargetDir}/${Hostname}-${FSName}.fsa ${FSPath} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of the archive failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of ${TargetDir}/${FSName}.fsa failed, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create an informational text file about the archive.
  fsarchiver archinfo --cryptpass="${CryptPass}" ${TargetDir}/${Hostname}-${FSName}.fsa > ${TargetDir}/${Hostname}-${FSName}.txt 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of info text failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of info file failed for ${TargetDir}/${FSName}.txt, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create a checksum file about the archive.
  md5sum ${TargetDir}/${Hostname}-${FSName}.fsa > ${TargetDir}/${Hostname}-${FSName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of md5 checksum failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of checksum failed for ${TargetDir}/${FSName}.md5, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Verify that the checksum file can validate against the archive.
  md5sum --check --status ${TargetDir}/${Hostname}-${FSName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Verification failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: md5 validation check failed for ${TargetDir}/${FSName}.md5. Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Set file permissions.
  chmod 0600 ${TargetDir}/${Hostname}-${FSName}.*

  BackupSize=`ls -lak --block-size=m "${TargetDir}/${Hostname}-${FSName}.fsa" | awk '{ print $5 }'`

  printf "`date +%Y-%m-%d_%H:%M:%S` --- Created: ${TargetDir}/${Hostname}-${FSName}.fsa, ${BackupSize}\n" >> ${LogFile}

  ## Remount FileSystem.
  mount /${FSName}
}

function f_archive_vol()
{
  LVName=$1
  LVPath=${LVG}/${LVName}

  ## Purge old backup files.
  if [ -f ${TargetDir}/${Hostname}-${LVName}.fsa ]; then
    rm ${TargetDir}/${Hostname}-${LVName}.fsa
  fi
  if [ -f ${TargetDir}/${Hostname}-${LVName}.txt ]; then
    rm ${TargetDir}/${Hostname}-${LVName}.txt
  fi
  if [ -f ${TargetDir}/${Hostname}-${LVName}.md5 ]; then
    rm ${TargetDir}/${Hostname}-${LVName}.md5
  fi

  ## Create the snapshot volume of the partition to be backed up.
  lvcreate --size=${MaxTempVolSize} --snapshot --name="tempsnap" ${LVPath} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of temporary volume failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of temp volume failed for ${LVPath}, size=${MaxTempVolSize}, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=8
    f_cleanup
  fi

  ## Give the OS a moment to let the LV create command do its thing.
  sleep 2

  LVLabel="${Hostname}:${LVPath}"
  ## Create the compressed and encrypted archive of the snapshot.
  fsarchiver savefs --compress=7 --jobs=1 --cryptpass="${CryptPass}" --label="${LVLabel}" ${TargetDir}/${Hostname}-${LVName}.fsa ${TempLV} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of the archive failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of ${TargetDir}/${Hostname}-${LVName}.fsa failed, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create an informational text file about the archive.
  fsarchiver archinfo --cryptpass="${CryptPass}" ${TargetDir}/${Hostname}-${LVName}.fsa > ${TargetDir}/${Hostname}-${LVName}.txt 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of info text failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of info file failed for ${TargetDir}/${Hostname}-${LVName}.txt, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Create a checksum file about the archive.
  md5sum ${TargetDir}/${Hostname}-${LVName}.fsa > ${TargetDir}/${Hostname}-${LVName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Creation of md5 checksum failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Creation of checksum failed for ${TargetDir}/${Hostname}-${LVName}.md5, Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  ## Set file permissions.
  chmod 0600 ${TargetDir}/${Hostname}-${LVName}.*

  ## Remove the snapshot.
  lvremove --force ${TempLV} > /dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Removal of temporary volume failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Removal of temp volume failed. ${TempLV}. Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=8
    f_cleanup
  fi

  ## Give the OS a moment to let the LV remove command do its thing.
  sleep 2

  ## Verify that the checksum file can validate against the archive.
  md5sum --check --status ${TargetDir}/${Hostname}-${LVName}.md5
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    ## Verification failed.
    printf "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: md5 validation check failed for ${TargetDir}/${Hostname}-${LVName}.md5. Return Code = ${ReturnCode}\n" >> ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi

  BackupSize=`ls -lak --block-size=m "${TargetDir}/${Hostname}-${LVName}.fsa" | awk '{ print $5 }'`

  printf "`date +%Y-%m-%d_%H:%M:%S` --- Created: ${TargetDir}/${Hostname}-${LVName}.fsa, ${BackupSize}\n" >> ${LogFile}

}

#######################################
##           MAIN PROGRAM            ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  printf "Backup partitions script aborted\n"
  printf "This script tried to run but detected the lock file: ${LockFile}\n"
  printf "Please check to make sure the file does not remain when backup partitions is not actually running.\n"
  f_sendmail "ERROR: Backup partitions script aborted" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when backup partitions is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=1
  exit ${ErrorFlag}
else
  printf "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}\n" > ${LockFile}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "`date +%Y-%m-%d_%H:%M:%S` ERROR: Root user required to run this script.\n" >> ${LogFile}
  ErrorFlag=2
  f_cleanup
fi

## Requirement Check: Software
command -v fsarchiver > /dev/null 2>&1 && ReturnCode=0 || ReturnCode=1
if [ ${ReturnCode} = 1 ]; then
  ## Required program not installed.
  printf "`date +%Y-%m-%d_%H:%M:%S` ERROR: fsarchiver not installed.\n" >> ${LogFile}
  ErrorFlag=4
  f_cleanup
fi

## Make sure target folder exists.
if [ ! -d ${TargetDir} ]; then
  mkdir -p ${TargetDir}
fi
## Remove old snapshot from a prior run if it exists.
lvremove --force ${TempLV} > /dev/null 2>&1

StartTime="$(date +%s)"
printf "`date +%Y-%m-%d_%H:%M:%S` - Partition backup started.\n" >> ${LogFile}

f_archive_fs boot /dev/sda2
f_archive_vol root
f_archive_vol home
f_archive_vol srv
f_archive_vol usr
f_archive_vol var
f_archive_vol tmp
f_archive_vol opt
#f_archive_vol swap

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

printf "`date +%Y-%m-%d_%H:%M:%S` --- Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)\n" >> ${LogFile}

printf "`date +%Y-%m-%d_%H:%M:%S` - Partition backup finished.\n" >> ${LogFile}
f_cleanup
