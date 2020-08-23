#!/bin/bash
#############################################################
## Name          : nextcloud-backup.sh
## Version       : 1.1
## Date          : 2018-03-06
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04 - 20.04 LTS, NextCloud 12.0.4
## Purpose       : Backup web server while online.
## Run Frequency : One or multiple times per day.
## Exit Codes    : (if multiple errors, value is the addition of codes)
##   0 = Success
##   1 = rsync failure
##   2 = Archive creation failure
##   4 = Remote copy failure
##   8 = Cannot connect to MySQL NFS mount
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2012-05-14 1.0 LTH Created script.
## 2017-08-31 1.1 LTH Updated variable names to current standard.
## 2018-03-06 1.2 LTH Adapted from ownCloud to NextCloud.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/${Company}-nextcloud-backup.log"
TargetDir="${BackupDir}/nextcloud"
LockFile="${TempDir}/nextcloud-backup.lock"
ArchiveFile="`date +%Y-%m-%d-%H-%M`_nextcloud-backup.${ArchiveMethod}"
Sources="/var/www/nextcloud/ /var/log/apache2/ /etc/apache2/ /etc/php/7.0/ /etc/network/interfaces /etc/hosts"
ErrorFlag=0
ReturnValue=0

#######################################
##            FUNCTIONS              ##
#######################################
function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other backup jobs can run.
    rm "${LockFile}" 1>/dev/null 2>&1
  fi
  echo "`date +%Y-%m-%d_%H:%M:%S` - NextCloud backup exit code: ${ErrorFlag}" >> ${LogFile}
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Binaries ##
Tar="$(which tar)"
My7zip="$(which 7za)"
Rsync="$(which rsync)"
if [ -f ${LockFile} ]; then
  ## Script lock file detected.  Abort script.
  f_sendmail "NextCloud Backup Aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when backup is not actually running."
  exit 1
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi
StartTime="$(date +%s)"
echo "`date +%Y-%m-%d_%H:%M:%S` - Backup started." >> ${LogFile}

## Connect to the MySQL server to kick-off a remote database backup.
#mount tema1-mysql:/srv/samba/share /mnt/tema1-mysql

## Output the version information to a text file which will be included in the backup.
if [ -f "${AppDir}/version-info.txt" ]; then
  rm "${AppDir}/version-info.txt"
fi
lsb_release -cd >> ${AppDir}/version-info.txt
apache2 -v >> ${AppDir}/version-info.txt
php -i >> ${AppDir}/version-info.txt

## Check destination folder.  Create folder structure if not present.
if [ ! -d "${TargetDir}" ]; then
  mkdir -p ${TargetDir}
fi
## Synchronize files to backup folder.
## Synchronize files to backup folder.
${Rsync} -apogHK --delete --exclude=*.pid ${AppDir} ${TargetDir} 1>/dev/null 2>&1
ReturnValue=$?
if [ ${ReturnValue} -ne 0 ]; then
  ## ERROR: Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Backup failed. ${AppDir} -> ${TargetDir}" >> ${LogFile}
  f_sendmail "Backup Failure - rsync" "ERROR: Backup failed. ${AppDir} -> ${TargetDir}, RETURN VALUE = ${ReturnValue}"
  ErrorFlag=${ErrorFlag} + 1
fi
## Compress the backup into a single file based on archive method specified.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TempDir}/${ArchiveFile}" >> ${LogFile}
case "${ArchiveMethod}" in
tar.7z)
  ## NOTE: Compression changed from 9(ultra) to 7 since it was blowing out on 512 MB RAM
  ${Tar} -cpf - ${Sources} | ${My7zip} a -si -mx=7 -w${TempDir} ${TempDir}/${ArchiveFile} 1>/dev/null 2>&1
  ReturnValue=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C / -xf -
  ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C ${TempDir}/restore --strip-components=1 -xf -
  ;;
tgz)
  ${Tar} -cpzf ${TempDir}/${ArchiveFile} ${Sources} 1>/dev/null 2>&1
  ReturnValue=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## tar -C / -xzf ${TempDir}/${ArchiveFile}
  ## tar -C ${TempDir}/restore --strip-components=1 -xzf ${TempDir}/${ArchiveFile}
  ;;
*)
  ${Tar} -cpzf ${TempDir}/${ArchiveFile} ${Sources} 1>/dev/null 2>&1
  ReturnValue=$?
  ;;
esac

if [ ${ReturnValue} -ne 0 ]; then
  ## tar command failed.  Send warning email.
  f_sendmail "NextCloud Backup Failure - tar" "tar failed with return value of ${ReturnValue}"
  ErrorFlag=$((${ErrorFlag} + 2))
fi
mv ${TempDir}/${ArchiveFile} ${TargetDir}/.

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

echo "`date +%Y-%m-%d_%H:%M:%S` --- Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" >> ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - NextCloud backup completed." >> ${LogFile}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ErrorFlag}
