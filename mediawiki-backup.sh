#!/bin/bash
#############################################################
## Name          : mediawiki-backup.sh
## Version       : 1.1
## Date          : 2015-03-19
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04 LTS
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
## 2015-03-19 1.1 LTH Changed quotes used on SOURCES variable.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LOGFILE="${LOGDIR}/${COMPANY}-mediawiki-backup.log"
TARGET="${BACKUPDIR}/mediawiki"
LOCKFILE="${TEMPDIR}/mediawiki-backup.lock"
ARCHIVEFILE="`date +%Y-%m-%d-%H-%M`_mediawiki-backup.${ARCHIVEMETHOD}"
SOURCES="/bak/mediawiki/www/ /var/log/apache2/ /etc/apache2/ /etc/php5/ /etc/network/interfaces /etc/hosts"
ERRORFLAG=0
RETURNVALUE=0

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
  if [ ${OFFSITEBACKDIR} = "" ]; then
    ## Make darn sure the path is not empty since we do NOT
    ## want to start purging files from a random location.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purge error: OFFSITEBACKDIR site variable is empty!" >> ${LOGFILE}
    return 9
  fi
  ## Get the name of the oldest file.
  OLDESTFILE=`ls -1t ${OFFSITEBACKDIR}/${HOSTNAME} | tail -1`
  if [ "${OLDESTFILE}" = "" ]; then
    ## Error. Filename variable empty.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purge error: OLDESTFILE variable is empty." >> ${LOGFILE}
    return 9
  else   
    FILESIZE=`ls -lak "${OFFSITEBACKDIR}/${HOSTNAME}/${OLDESTFILE}" | awk '{ print $5 }' | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purging old file: ${OFFSITEBACKDIR}/${HOSTNAME}/${OLDESTFILE}, Size = ${FILESIZE} kb" >> ${LOGFILE}
    rm "${OFFSITEBACKDIR}/${HOSTNAME}/${OLDESTFILE}"
    if [ -f "${OFFSITEBACKDIR}/${HOSTNAME}/${OLDESTFILE}" ]; then
      ## File still exists.  Return error.
      return 1
    else
      return 0
    fi
  fi
}

function f_cleanup()
{
  if [ -f ${LOCKFILE} ];then
    ## Remove lock file so other backup jobs can run.
    rm "${LOCKFILE}" 1>/dev/null 2>&1
  fi
  echo "`date +%Y-%m-%d_%H:%M:%S` - MediaWiki backup exit code: ${ERRORFLAG}" >> ${LOGFILE}
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Binaries ##
TAR="$(which tar)"
MY7ZIP="$(which 7za)"
RSYNC="$(which rsync)"

if [ -f ${LOCKFILE} ]; then
  ## Script lock file detected.  Abort script.
  f_sendmail "MediaWiki Backup Aborted - Lock File" "This script tried to run but detected the lock file: ${LOCKFILE}\n\nPlease check to make sure the file does not remain when backup is not actually running."
  exit 1
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${SCRIPTNAME}" > ${LOCKFILE}
fi

StartTime="$(date +%s)"
echo "`date +%Y-%m-%d_%H:%M:%S` - Backup started." >> ${LOGFILE}

## Connect to the MySQL server to kick-off a remote database backup.
mount srv-mysql:/srv/samba/share /mnt/srv-mysql
if [ -f /mnt/srv-mysql/offline.txt ];then
  ## The mount command did not work.
  ERRORFLAG=${ERRORFLAG} + 8
else
  ## Create the key file to trigger a backup of the database.
  echo "Time to backup MediaWiki!" > /mnt/srv-mysql/mediawiki
  umount /mnt/srv-mysql
fi

## Output the version information to a text file which will be included in the backup.
if [ -f "${APPDIR}/version-info.txt" ]; then
  rm "${APPDIR}/version-info.txt"
fi
lsb_release -cd >> ${APPDIR}/version-info.txt
apache2 -v >> ${APPDIR}/version-info.txt
php -i >> ${APPDIR}/version-info.txt

## Check destination folder.  Create folder structure if not present.
if [ ! -d "${TARGET}" ]; then
  mkdir -p ${TARGET}
fi

## Synchronize files to backup folder.
${RSYNC} -apogHK --delete --exclude=*.pid ${APPDIR} ${TARGET} 1>/dev/null 2>&1
RETURNVALUE=$?
if [ ${RETURNVALUE} -ne 0 ]; then
  ## ERROR: Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Backup failed. ${APPDIR} -> ${TARGET}" >> ${LOGFILE}
  f_sendmail "Backup Failure - rsync" "ERROR: Backup failed. ${APPDIR} -> ${TARGET}, RETURN VALUE = ${RETURNVALUE}"
  ERRORFLAG=${ERRORFLAG} + 1
fi

## Compress the backup into a single file based on archive method specified.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TEMPDIR}/${ARCHIVEFILE}" >> ${LOGFILE}
case "${ARCHIVEMETHOD}" in
tar.7z)
  ## NOTE: Compression changed from 9(ultra) to 7 since it was blowing out on 512 MB RAM
  ${TAR} -cpf - ${SOURCES} | ${MY7ZIP} a -si -mx=7 -w${TEMPDIR} ${TEMPDIR}/${ARCHIVEFILE} 1>/dev/null 2>&1
  RETURNVALUE=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## 7za x -so -w/tmp ${TEMPDIR}/${ARCHIVEFILE} | tar -C / -xf -
  ## 7za x -so -w/tmp ${TEMPDIR}/${ARCHIVEFILE} | tar -C ${TEMPDIR}/restore --strip-components=1 -xf -
  ;;
tgz)
  ${TAR} -cpzf ${TEMPDIR}/${ARCHIVEFILE} ${SOURCES} 1>/dev/null 2>&1
  RETURNVALUE=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## tar -C / -xzf ${TEMPDIR}/${ARCHIVEFILE}
  ## tar -C ${TEMPDIR}/restore --strip-components=1 -xzf ${TEMPDIR}/${ARCHIVEFILE}
  ;;
*)
  ${TAR} -cpzf ${TEMPDIR}/${ARCHIVEFILE} ${SOURCES} 1>/dev/null 2>&1
  RETURNVALUE=$?
  ;;
esac

if [ ${RETURNVALUE} -ne 0 ]; then
  ## tar command failed.  Send warning email.
  f_sendmail "MediaWiki Backup Failure - tar" "tar failed with return value of ${RETURNVALUE}"
  ERRORFLAG=$((${ERRORFLAG} + 2))
fi

## Mount the remote folder. ##
f_mount

if [ ! -f ${OFFSITETESTFILE} ]; then
  ## Could not find expected file on remote site.  Assuming failed mount.
  ERRORFLAG=$((${ERRORFLAG} + 16))
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Cannot detect remote location: ${OFFSITETESTFILE}" >> ${LOGFILE}
  f_emergencyexit ${ERRORFLAG}
fi

FREESPACE=`df -k ${OFFSITEDIR} | grep ${OFFSITEDIR} | awk '{ print $4 }'`
BACKUPSIZE=`ls -lak "${TEMPDIR}/${ARCHIVEFILE}" | awk '{ print $5 }'`

## Make sure space is available on the remote server to copy the file.
if [[ ${FREESPACE} -lt ${BACKUPSIZE} ]]; then
  ## Not enough free space available.  Purge existing backups until there is room.
  ENOUGHSPACE=0
  while [ ${ENOUGHSPACE} -eq 0 ]
  do
    f_PurgeOldestArchive
    RETURNVALUE=$?
    case ${RETURNVALUE} in
    1)
      ## Cannot purge archives to free up space.  End program gracefully.
      echo "`date +%Y-%m-%d_%H:%M:%S` - ERROR: Not enough free space on ${OFFSITEBACKDIR} and cannot purge old archives.  Script aborted." >> ${LOGFILE}
      ## Stop and exit the script with an error code.
      ERRORFLAG=$((${ERRORFLAG} + 4))
      f_emergencyexit ${ERRORFLAG}
      ;;
    9)
      ## Configuration error, end program gracefully.
      echo "`date +%Y-%m-%d_%H:%M:%S` - ERROR: Configuration problem. Script aborted." >> ${LOGFILE}
      ## Stop and exit the script with an error code.
      ERRORFLAG=$((${ERRORFLAG} + 8))
      f_emergencyexit ${ERRORFLAG}
      ;;
    esac
    FREESPACE=`df -k ${OFFSITEDIR} | grep ${OFFSITEDIR} | awk '{ print $3 }'`
    if [ ${FREESPACE} -gt ${BACKUPSIZE} ]; then
      ## Enough space is now available.
      ENOUGHSPACE=1
    else
      ## Not enough space is available yet.
      ENOUGHSPACE=0
    fi
  done
fi

## Copy the backup to an offsite storage location.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Copying archive file to offsite location." >> ${LOGFILE}
cp ${TEMPDIR}/${ARCHIVEFILE} ${OFFSITEDIR}/${HOSTNAME}/${ARCHIVEFILE} 1>/dev/null 2>&1
if [ ! -f ${OFFSITEDIR}/${HOSTNAME}/${ARCHIVEFILE} ]; then
  ## NON-FATAL ERROR: Copy command did not work.  Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- WARNING: Remote copy failed. ${OFFSITEDIR}/${HOSTNAME}/${ARCHIVEFILE} does not exist!" >> ${LOGFILE}
  f_sendmail "MediaWiki Backup Failure - Remote Copy" "Remote copy failed. ${OFFSITEDIR}/${HOSTNAME}/${ARCHIVEFILE} does not exist\n\nBackup file still remains in this location: ${HOSTNAME}:${TEMPDIR}/${ARCHIVEFILE}"
else
  ## Remove local copy of the compressed backup file
  rm "${TEMPDIR}/${ARCHIVEFILE}"
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

echo "`date +%Y-%m-%d_%H:%M:%S` --- Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" >> ${LOGFILE}

echo "`date +%Y-%m-%d_%H:%M:%S` - MediaWiki backup completed." >> ${LOGFILE}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ERRORFLAG}
