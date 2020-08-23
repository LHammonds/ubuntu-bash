#!/bin/bash
#############################################################
## Name          : mediawiki-backup.sh
## Version       : 1.2
## Date          : 2017-08-22
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04-16.04.3 LTS
## Requirements  : Requires sharing SSH IDs on this and remote server.
## Purpose       : Backup web server while online.
## Run Frequency : One or multiple times per day.
## Exit Codes    : (if multiple errors, value is the addition of codes)
##   0 = Success
##   1 = rsync failure
##   2 = Archive creation failure
##   4 = Remote copy failure
##   8 = Cannot connect to MySQL NFS mount
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2012-05-14 1.0 LTH Created script.
## 2015-03-19 1.1 LTH Changed quotes used on Sources variable.
## 2017-08-22 1.2 LTH Replaced NFS mount to remote copy command.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/${Company}-mediawiki-backup.log"
Target="${BackupDir}/mediawiki"
LockFile="${TempDir}/mediawiki-backup.lock"
ArchiveFile="`date +%Y-%m-%d-%H-%M`_mediawiki-backup.${ArchiveMethod}"
Sources="/bak/mediawiki/www/ /var/log/apache2/ /etc/apache2/ /etc/php/ /etc/network/interfaces /etc/hosts"
ErrorFlag=0
ReturnValue=0

#######################################
##            FUNCTIONS              ##
#######################################
function f_PurgeOldestArchive()
{
  ## Purpose: Delete the oldest archive on the remote site.
  ## Return values:
  ##    0 = Success
  ##    1 = Cannot delete file
  ##    9 = Configuration error, path empty

  ## Variable Error Check. *
  if [ ${OffsiteBackDir} = "" ]; then
    ## Make darn sure the path is not empty since we do NOT
    ## want to start purging files from a random location.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purge error: OffsiteBackDir site variable is empty!" >> ${LogFile}
    return 9
  fi
  ## Get the name of the oldest file.
  OldestFile=`ls -1t ${OffsiteBackDir}/${Hostname} | tail -1`
  if [ "${OldestFile}" = "" ]; then
    ## Error. Filename variable empty.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purge error: OldestFile variable is empty." >> ${LogFile}
    return 9
  else   
    FileSize=`ls -lak "${OffsiteBackDir}/${Hostname}/${OldestFile}" | awk '{ print $5 }' | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purging old file: ${OffsiteBackDir}/${Hostname}/${OldestFile}, Size = ${FileSize} kb" >> ${LogFile}
    rm "${OffsiteBackDir}/${Hostname}/${OldestFile}"
    if [ -f "${OffsiteBackDir}/${Hostname}/${OldestFile}" ]; then
      ## File still exists.  Return error.
      return 1
    else
      return 0
    fi
  fi
}

function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other backup jobs can run.
    rm "${LockFile}" 1>/dev/null 2>&1
  fi
  echo "`date +%Y-%m-%d_%H:%M:%S` - MediaWiki backup exit code: ${ErrorFlag}" >> ${LogFile}
}

function f_emergencyexit()
{
  ## Purpose: Exit script as cleanly as possible.
  ## Parameter #1 = Error Code
  f_cleanup
  echo "`date +%Y-%m-%d_%H:%M:%S` - Backup exit code: ${ErrorFlag}" >> ${LogFile}
  exit $1
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Binaries ##
TarCmd=$(which tar)
ZipCmd=$(which 7za)
RsyncCmd=$(which rsync)

if [ -f ${LockFile} ]; then
  ## Script lock file detected.  Abort script.
  f_sendmail "MediaWiki Backup Aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when backup is not actually running."
  exit 1
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

StartTime="$(date +%s)"
echo "`date +%Y-%m-%d_%H:%M:%S` - Backup started." >> ${LogFile}

## Copy file to the MySQL server which will kick-off a remote database backup.
echo "Time to backup MediaWiki!" > /tmp/mediawiki
scp /tmp/mediawiki root@tema1-mysql:/srv/samba/share/.
rm /tmp/mediawiki

## Output the version information to a text file which will be included in the backup.
if [ -f "${AppDir}/version-info.txt" ]; then
  rm "${AppDir}/version-info.txt"
fi
lsb_release -cd >> ${AppDir}/version-info.txt
apache2 -v >> ${AppDir}/version-info.txt
php -i >> ${AppDir}/version-info.txt

## Check destination folder.  Create folder structure if not present.
if [ ! -d "${Target}" ]; then
  mkdir -p ${Target}
fi

## Synchronize files to backup folder.
${RsyncCmd} -apogHK --delete --exclude=*.pid ${AppDir} ${Target} 1>/dev/null 2>&1
ReturnValue=$?
if [ ${ReturnValue} -ne 0 ]; then
  ## ERROR: Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Backup failed. ${AppDir} -> ${Target}" >> ${LogFile}
  f_sendmail "Backup Failure - rsync" "ERROR: Backup failed. ${AppDir} -> ${Target}, RETURN VALUE = ${ReturnValue}"
  ErrorFlag=${ErrorFlag} + 1
fi

## Compress the backup into a single file based on archive method specified.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TempDir}/${ArchiveFile}" >> ${LogFile}
case "${ArchiveMethod}" in
tar.7z)
  ## NOTE: Compression changed from 9(ultra) to 7 since it was blowing out on 512 MB RAM
  echo "${TarCmd} cpf - ${Sources} | ${ZipCmd} a -si -mx=7 -w${TempDir} ${TempDir}/${ArchiveFile}"
  ${TarCmd} cpf - ${Sources} | ${ZipCmd} a -si -mx=7 -w${TempDir} ${TempDir}/${ArchiveFile} 1>/dev/null 2>&1
  ReturnValue=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C / -xf -
  ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C ${TempDir}/restore --strip-components=1 -xf -
  ;;
tgz)
  ${TarCmd} -cpzf ${TempDir}/${ArchiveFile} ${Sources} 1>/dev/null 2>&1
  ReturnValue=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## tar -C / -xzf ${TempDir}/${ArchiveFile}
  ## tar -C ${TempDir}/restore --strip-components=1 -xzf ${TempDir}/${ArchiveFile}
  ;;
*)
  ${TarCmd} -cpzf ${TempDir}/${ArchiveFile} ${Sources} 1>/dev/null 2>&1
  ReturnValue=$?
  ;;
esac

if [ ${ReturnValue} -ne 0 ]; then
  ## tar command failed.  Send warning email.
  f_sendmail "MediaWiki Backup Failure - tar" "tar failed with return value of ${ReturnValue}"
  ErrorFlag=$((${ErrorFlag} + 2))
fi

## Mount the remote folder. ##
f_mount

if [ -f ${OffsiteTestFile} ]; then
  ## Local test file found.  Assuming failed mount.
  ErrorFlag=$((${ErrorFlag} + 16))
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Cannot detect remote location: ${OffsiteTestFile}" >> ${LogFile}
  f_emergencyexit ${ErrorFlag}
fi

FreeSpace=`df -k ${OffsiteDir} | grep ${OffsiteDir} | awk '{ print $4 }'`
BackupSize=`ls -lak "${TempDir}/${ArchiveFile}" | awk '{ print $5 }'`

## Make sure space is available on the remote server to copy the file.
if [[ ${FreeSpace} -lt ${BackupSize} ]]; then
  ## Not enough free space available.  Purge existing backups until there is room.
  EnoughSpace=0
  while [ ${EnoughSpace} -eq 0 ]
  do
    f_PurgeOldestArchive
    ReturnValue=$?
    case ${ReturnValue} in
    1)
      ## Cannot purge archives to free up space.  End program gracefully.
      echo "`date +%Y-%m-%d_%H:%M:%S` - ERROR: Not enough free space on ${OffsiteBackDir} and cannot purge old archives.  Script aborted." >> ${LogFile}
      ## Stop and exit the script with an error code.
      ErrorFlag=$((${ErrorFlag} + 4))
      f_emergencyexit ${ErrorFlag}
      ;;
    9)
      ## Configuration error, end program gracefully.
      echo "`date +%Y-%m-%d_%H:%M:%S` - ERROR: Configuration problem. Script aborted." >> ${LogFile}
      ## Stop and exit the script with an error code.
      ErrorFlag=$((${ErrorFlag} + 8))
      f_emergencyexit ${ErrorFlag}
      ;;
    esac
    FreeSpace=`df -k ${OffsiteDir} | grep ${OffsiteDir} | awk '{ print $3 }'`
    if [ ${FreeSpace} -gt ${BackupSize} ]; then
      ## Enough space is now available.
      EnoughSpace=1
    else
      ## Not enough space is available yet.
      EnoughSpace=0
    fi
  done
fi

## Copy the backup to an offsite storage location.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Copying archive file to offsite location." >> ${LogFile}
cp ${TempDir}/${ArchiveFile} ${OffsiteDir}/${Hostname}/${ArchiveFile} 1>/dev/null 2>&1
if [ ! -f ${OffsiteDir}/${Hostname}/${ArchiveFile} ]; then
  ## NON-FATAL ERROR: Copy command did not work.  Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- WARNING: Remote copy failed. ${OffsiteDir}/${Hostname}/${ArchiveFile} does not exist!" >> ${LogFile}
  f_sendmail "MediaWiki Backup Failure - Remote Copy" "Remote copy failed. ${OffsiteDir}/${Hostname}/${ArchiveFile} does not exist\n\nBackup file still remains in this location: ${Hostname}:${TempDir}/${ArchiveFile}"
else
  ## Remove local copy of the compressed backup file
  rm "${TempDir}/${ArchiveFile}"
fi

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

echo "`date +%Y-%m-%d_%H:%M:%S` - MediaWiki backup completed." >> ${LogFile}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ErrorFlag}
