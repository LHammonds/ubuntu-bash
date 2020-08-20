#!/bin/bash
#############################################################
## Name          : db-ondemand-backup.sh
## Version       : 1.0
## Date          : 2012-05-14
## Author        : LHammonds
## Purpose       : Backup of a single database
## Compatibility : Verified on Ubuntu Server 10.04 - 14.04 LTS, MySQL 5.1.62 - 5.5.41, MariaDB 10.0.16
## Requirements  : p7zip-full (if ARCHIVEMETHOD=tar.7z), sendemail
## Run Frequency : As needed
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = 7zip not installed
##    2 = archive failure
##    4 = archive purge failure
##    8 = configuration error
##   16 = mount warning
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2012-05-14 1.0 LTH Created script.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LOGFILE="${LOGDIR}/db-ondemand-backup.log"
LOCKFILE="${TEMPDIR}/db-ondemand-backup.lock"
TARGETDIR="${BACKUPDIR}/mysql-db"
OFFSITEBACKDIR="${OFFSITEDIR}/mysql-db"
ERRORFLAG=0

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
  OLDESTFILE=`ls -1t ${OFFSITEBACKDIR} | tail -1`
  if [ "${OLDESTFILE}" = "" ]; then
    ## Error. Filename variable empty.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purge error: OLDESTFILE variable is empty." >> ${LOGFILE}
    return 9
  else   
    FILESIZE=`ls -lak "${OFFSITEBACKDIR}/${OLDESTFILE}" | awk '{ print $5 }' | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purging old file: ${OFFSITEBACKDIR}/${OLDESTFILE}, Size = ${FILESIZE} kb" >> ${LOGFILE}
    rm "${OFFSITEBACKDIR}/${OLDESTFILE}"
    if [ -f "${OFFSITEBACKDIR}/${OLDESTFILE}" ]; then
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
    ## Remove lock file so other rsync jobs can run.
    rm ${LOCKFILE} 1>/dev/null 2>&1
  fi
  if [[ "${TARGETDIR}" != "" && "{TARGETDIR}" != "/" ]]; then
    ## Remove local backup files.
    rm -rf ${TARGETDIR}/*
  fi
  ## Email the result to the administrator.
  if [ ${ERRORFLAG} -eq 0 ]; then
    f_sendmail "MySQL DB Backup Success" "MySQL backup completed with no errors."
  else
    f_sendmail "MySQL DB Backup ERROR" "MySQL backup failed.  ERRORFLAG = ${ERRORFLAG}"
  fi
}

function f_emergencyexit()
{
  ## Purpose: Exit script as cleanly as possible.
  ## Parameter #1 = Error Code
  f_cleanup
  echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL backup exit code: ${ERRORFLAG}" >> ${LOGFILE}
  exit $1
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Binaries ##
TAR="$(which tar)"
MY7ZIP="$(which 7za)"
MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"

if [ -f ${LOCKFILE} ]; then
  ## Program lock file detected.  Abort script.
  f_sendmail "MySQL DB Backup Aborted - Lock File" "This script tried to run but detected the lock file: ${LOCKFILE}\n\nPlease check to make sure the file does not remain when this script is not actually running."
  exit 1
else
  ## Create the lock file to ensure only one script is running at a time.
  echo "`date +%Y-%m-%d_%H:%M:%S` ${SCRIPTNAME}" > ${LOCKFILE}
fi

## Figure out which database will be backed up. Only one per run.
if [ -f "${SHAREDIR}/mediawiki" ]; then
  DATABASE="mediawiki"
  rm "${SHAREDIR}/mediawiki"
elif [ -f "${SHAREDIR}/phpbb" ]; then
  DATABASE="phpbb"
  rm "${SHAREDIR}/phpbb"
elif [ -f "${SHAREDIR}/wordpress" ]; then
  DATABASE="wordpress"
  rm "${SHAREDIR}/wordpress"
fi
if [[ "${DATABASE}" = "" ]]; then
  f_cleanup 0
  exit 0
fi

ARCHIVEFILE="`date +%Y-%m-%d-%H-%M`_mysql-db-${DATABASE}.${ARCHIVEMETHOD}"

echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL ${DATABASE} backup started." >> ${LOGFILE}

## If the 7-Zip archive method is specified, make sure the package is installed.
if [ "${ARCHIVEMETHOD}" = "tar.7z" ]; then
  if [ ! -f "/usr/bin/7za" ]; then
    ## Required package (7-Zip) not installed.
    echo "`date +%Y-%m-%d_%H:%M:%S` - CRITICAL ERROR: 7-Zip package not installed.  Please install by typing 'aptitude -y install p7zip-full'" >> ${LOGFILE}
    ERRORFLAG=1
    f_emergencyexit ${ERRORFLAG}
  fi
fi

StartTime="$(date +%s)"

## Backup individual database.
${MYSQLDUMP} ${DATABASE} > ${TARGETDIR}/${DATABASE}.sql
## Create database sub-folder.
mkdir -p ${TARGETDIR}/${DATABASE}
## Export each table in the database individually.
for TABLE in `echo "show tables" | $MYSQL ${DATABASE}|grep -v Tables_in_`;
do
  FILE=${TARGETDIR}/${DATABASE}/${TABLE}.sql
  case "${TABLE}" in
    general_log)
      ${MYSQLDUMP} ${DATABASE} ${TABLE} --skip-lock-tables > ${FILE}
      ;;
    slow_log)
      ${MYSQLDUMP} ${DATABASE} ${TABLE} --skip-lock-tables > ${FILE}
      ;;
    *)
      ${MYSQLDUMP} ${DATABASE} ${TABLE} > ${FILE}
      ;;
  esac
done

## Compress the backup into a single file based on archive method specified.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TEMPDIR}/${ARCHIVEFILE}" >> ${LOGFILE}
case "${ARCHIVEMETHOD}" in
tar.7z)
  ${TAR} -cpf - ${TARGETDIR} | ${MY7ZIP} a -si -mx=9 -w${TEMPDIR} ${TEMPDIR}/${ARCHIVEFILE} 1>/dev/null 2>&1
  RETURNVALUE=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## 7za x -so -w/tmp ${TEMPDIR}/${ARCHIVEFILE} | tar -C / -xf -
  ## 7za x -so -w/tmp ${TEMPDIR}/${ARCHIVEFILE} | tar -C ${TEMPDIR}/restore --strip-components=1 -xf -
  ;;
tgz)
  ${TAR} -cpzf ${TEMPDIR}/${ARCHIVEFILE} ${TARGETDIR} 1>/dev/null 2>&1
  RETURNVALUE=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## tar -C / -xzf ${TEMPDIR}/${ARCHIVEFILE}
  ## tar -C ${TEMPDIR}/restore --strip-components=1 -xzf ${TEMPDIR}/${ARCHIVEFILE}
  ;;
*)
  ${TAR} -cpzf ${TEMPDIR}/${ARCHIVEFILE} ${TARGETDIR} 1>/dev/null 2>&1
  RETURNVALUE=$?
  ;;
esac

if [ ${RETURNVALUE} -ne 0 ]; then
  ## tar command failed.  Send warning email.
  f_sendmail "MySQL Backup Failure - tar" "tar failed with return value of ${RETURNVALUE}"
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

FREESPACE=`df -k ${OFFSITEDIR} | grep ${OFFSITEDIR} | awk '{ print $3 }'`
BACKUPSIZE=`ls -lak "${TEMPDIR}/${ARCHIVEFILE}" | awk '{ print $5 }'`

## Make sure space is available on the remote server to copy the file.
if [ ${FREESPACE} -lt ${BACKUPSIZE} ]; then
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
cp ${TEMPDIR}/${ARCHIVEFILE} ${OFFSITEBACKDIR}/${ARCHIVEFILE} 1>/dev/null 2>&1
if [ ! -f ${OFFSITEBACKDIR}/${ARCHIVEFILE} ]; then
  ## NON-FATAL ERROR: Copy command did not work.  Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- WARNING: Remote copy failed. ${OFFSITEBACKDIR}/${ARCHIVEFILE} does not exist!" >> ${LOGFILE}
  f_sendmail "MySQL Backup Failure - Remote Copy" "Remote copy failed. ${OFFSITEBACKDIR}/${ARCHIVEFILE} does not exist\n\nBackup file still remains in this location: ${HOSTNAME}:${TEMPDIR}/${ARCHIVEFILE}"
else
  ## Remove local copy of the compressed backup file
  rm ${TEMPDIR}/${ARCHIVEFILE}
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

echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL ${DATABASE} backup completed." >> ${LOGFILE}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ERRORFLAG}
