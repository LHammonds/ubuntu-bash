#!/bin/bash
#############################################################
## Name          : db-ondemand-backup.sh
## Version       : 1.2
## Date          : 2017-09-01
## Author        : LHammonds
## Purpose       : Backup of a single database
## Compatibility : Verified on Ubuntu Server 10.04 - 20.04 LTS, MySQL 5.1.62 - 5.5.22, MariaDB 10.3.8 - 10.4.8
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
## 2017-04-13 1.1 LTH Corrected variable casing.
## 2017-09-01 1.2 LTH Handle folder creation upon 1st time run.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/db-ondemand-backup.log"
LockFile="${TempDir}/db-ondemand-backup.lock"
TargetDir="${BackupDir}/mysql-db"
OffsiteBackDir="${OffsiteDir}/${Hostname}/mysql-db"
ErrorFlag=0

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
  OldestFile=`ls -1t ${OffsiteBackDir} | tail -1`
  if [ "${OldestFile}" = "" ]; then
    ## Error. Filename variable empty.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purge error: OldestFile variable is empty." >> ${LogFile}
    return 9
  else   
    FileSize=`ls -lak "${OffsiteBackDir}/${OldestFile}" | awk '{ print $5 }' | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`
    echo "`date +%Y-%m-%d_%H:%M:%S` --- Purging old file: ${OffsiteBackDir}/${OldestFile}, Size = ${FileSize} kb" >> ${LogFile}
    rm "${OffsiteBackDir}/${OldestFile}"
    if [ -f "${OffsiteBackDir}/${OldestFile}" ]; then
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
    ## Remove lock file so other rsync jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  if [[ "${TargetDir}" != "" && "{TargetDir}" != "/" ]]; then
    ## Remove local backup files.
    rm -rf ${TargetDir}/*
  fi
}

function f_emergencyexit()
{
  ## Purpose: Exit script as cleanly as possible.
  ## Parameter #1 = Error Code
  f_cleanup
  echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL backup exit code: ${ErrorFlag}" >> ${LogFile}
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

if [ -f ${LockFile} ]; then
  ## Program lock file detected.  Abort script.
  echo "Lock file detected, aborting script."
  f_sendmail "[Failure] MySQL DB Backup Aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when this script is not actually running."
  exit 1
else
  ## Create the lock file to ensure only one script is running at a time.
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

## Figure out which database will be backed up. Only one per run.
if [ -f "${ShareDir}/mediawiki" ]; then
  DatabaseName="mediawiki"
  rm "${ShareDir}/mediawiki"
elif [ -f "${ShareDir}/intranetwp" ]; then
  DatabaseName="intranetwp"
  rm "${ShareDir}/intranetwp"
elif [ -f "${ShareDir}/intranetwpdev" ]; then
  DatabaseName="intranetwpdev"
  rm "${ShareDir}/intranetwpdev"
elif [ -f "${ShareDir}/owncloud" ]; then
  DatabaseName="owncloud"
  rm "${ShareDir}/owncloud"
elif [ -f "${ShareDir}/phpbb" ]; then
  DatabaseName="phpbb"
  rm "${ShareDir}/phpbb"
elif [ -f "${ShareDir}/wordpress" ]; then
  DatabaseName="wordpress"
  rm "${ShareDir}/wordpress"
fi
if [[ "${DatabaseName}" = "" ]]; then
  echo "No database selected. Exiting script."
  f_cleanup 0
  exit 0
fi

ArchiveFile="`date +%Y-%m-%d-%H-%M`_mysql-db-${DatabaseName}.${ArchiveMethod}"

echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL ${DatabaseName} backup started." >> ${LogFile}

## If the 7-Zip archive method is specified, make sure the package is installed.
if [ "${ArchiveMethod}" = "tar.7z" ]; then
  if [ ! -f "/usr/bin/7za" ]; then
    ## Required package (7-Zip) not installed.
    echo "`date +%Y-%m-%d_%H:%M:%S` - CRITICAL ERROR: 7-Zip package not installed.  Please install by typing 'aptitude -y install p7zip-full'" >> ${LogFile}
    ErrorFlag=1
    f_emergencyexit ${ErrorFlag}
  fi
fi

StartTime="$(date +%s)"

## Backup individual database.
${MYSQLDUMP} ${DatabaseName} > ${TargetDir}/${DatabaseName}.sql
## Create database sub-folder.
mkdir -p ${TargetDir}/${DatabaseName}
## Export each table in the database individually.
for SingleTable in `echo "show tables" | $MYSQL ${DatabaseName}|grep -v Tables_in_`;
do
  FileName=${TargetDir}/${DatabaseName}/${SingleTable}.sql
  case "${SingleTable}" in
    general_log)
      ${MYSQLDUMP} ${DatabaseName} ${SingleTable} --skip-lock-tables > ${FileName}
      ;;
    slow_log)
      ${MYSQLDUMP} ${DatabaseName} ${SingleTable} --skip-lock-tables > ${FileName}
      ;;
    *)
      ${MYSQLDUMP} ${DatabaseName} ${SingleTable} > ${FileName}
      ;;
  esac
done

## Compress the backup into a single file based on archive method specified.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TempDir}/${ArchiveFile}" >> ${LogFile}
case "${ArchiveMethod}" in
tar.7z)
  ${TAR} -cpf - ${TargetDir} | ${MY7ZIP} a -si -mx=7 -w${TempDir} ${TempDir}/${ArchiveFile} 1>/dev/null 2>&1
  ReturnValue=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C / -xf -
  ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C ${TempDir}/restore --strip-components=1 -xf -
  ;;
tgz)
  ${TAR} -cpzf ${TempDir}/${ArchiveFile} ${TargetDir} 1>/dev/null 2>&1
  ReturnValue=$?
  ## Restore using one of the following commands (do not uncomment, only for notation):
  ## tar -C / -xzf ${TempDir}/${ArchiveFile}
  ## tar -C ${TempDir}/restore --strip-components=1 -xzf ${TempDir}/${ArchiveFile}
  ;;
*)
  ${TAR} -cpzf ${TempDir}/${ArchiveFile} ${TargetDir} 1>/dev/null 2>&1
  ReturnValue=$?
  ;;
esac

if [ ${ReturnValue} -ne 0 ]; then
  ## tar command failed.  Send warning email.
  f_sendmail "[Failure] MySQL Backup Failure - tar" "tar failed with return value of ${ReturnValue}"
  ErrorFlag=$((${ErrorFlag} + 2))
fi

## Mount the remote folder. ##
f_mount

if [ -f ${OffsiteTestFile} ]; then
  ## Offline file found. Assuming failed mount.
  ErrorFlag=$((${ErrorFlag} + 16))
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: Offline file detected: ${OffsiteTestFile}" >> ${LogFile}
  f_emergencyexit ${ErrorFlag}
fi

## If destination folder does not exist, create it. Mainly for 1st time use.
if [ ! -d ${OffsiteBackDir} ]; then
  mkdir -p ${OffsiteBackDir}
fi

FreeSpace=`df -k ${OffsiteDir} | grep ${OffsiteDir} | awk '{ print $3 }'`
BackupSize=`ls -lak "${TempDir}/${ArchiveFile}" | awk '{ print $5 }'`

## Make sure space is available on the remote server to copy the file.
if [ ${FreeSpace} -lt ${BackupSize} ]; then
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
cp ${TempDir}/${ArchiveFile} ${OffsiteBackDir}/${ArchiveFile} 1>/dev/null 2>&1
if [ ! -f ${OffsiteBackDir}/${ArchiveFile} ]; then
  ## NON-FATAL ERROR: Copy command did not work.  Send email notification.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- WARNING: Remote copy failed. ${OffsiteBackDir}/${ArchiveFile} does not exist!" >> ${LogFile}
  f_sendmail "[Failure] MySQL Backup Failure - Remote Copy" "Remote copy failed. ${OffsiteBackDir}/${ArchiveFile} does not exist\n\nBackup file still remains in this location: ${Hostname}:${TempDir}/${ArchiveFile}"
else
  ## Remove local copy of the compressed backup file
  rm ${TempDir}/${ArchiveFile}
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

echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL ${DatabaseName} backup completed." >> ${LogFile}

## Perform cleanup routine.
f_cleanup

## Email the result to the administrator.
if [ ${ErrorFlag} -eq 0 ]; then
  f_sendmail "[Success] MySQL DB Backup Success" "MySQL backup completed with no errors."
else
  f_sendmail "[Failure] MySQL DB Backup ERROR" "MySQL backup failed.  ErrorFlag = ${ErrorFlag}"
fi

## Exit with the combined return code value.
exit ${ErrorFlag}
