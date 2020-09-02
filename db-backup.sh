#!/bin/bash
#############################################################
## Name          : db-backup.sh
## Version       : 1.6
## Date          : 2020-06-25
## Author        : LHammonds
## Purpose       : Complete encrypted backup of MariaDB/MySQL databases.
## Compatibility : Verified on to work on:
##                  - Ubuntu Server 20.04 LTS
##                  - MariaDB 10.4.13
## Requirements  : p7zip-full (if ArchiveMethod=tar.7z), sendemail
## Run Frequency : Once per day after hours or as needed
##                 (will not shutdown service)
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = lock file detected
##    2 = root access
##    4 = 7zip not installed
##    8 = sql export failure
##   16 = archive failure
##   32 = archive purge failure
##   64 = configuration error
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2011-12-19 1.0 LTH Created script.
## 2012-01-09 1.1 LTH Bugfix - f_PurgeOldestArchive
## 2017-04-13 1.2 LTH Corrected variable casing.
## 2017-04-24 1.3 LTH All databases minus an exception list.
## 2017-09-01 1.4 LTH Handle folder creation upon 1st time run.
## 2017-12-27 1.5 LTH Added directory/file permission setting.
## 2020-06-25 1.6 LTH Added encryption, removed remote push.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

## Change the password in this file to anything other than the default! ##
source /etc/passenc

Title="${Company}-db-backup"
DBDir="/opt/mariadb"
TargetDir="${BackupDir}/db"
OffsiteBackDir="${BackupDir}/remote"
CryptPassFile="${TempDir}/${Title}.gpg"
Timestamp="`date +%Y-%m-%d_%H%M`"
LogFile="${LogDir}/${Company}-db-backup.log"
LockFile="${TempDir}/${Company}-db-backup.lock"
DatabasesToExclude="'information_schema','mysql','performance_schema','JunkUserDB1','JunkUserDB2'"
ErrorFlag=0

## Binaries, you can let the script find them or you can set the full path manually here. ##
TAR="$(which tar)"
MY7ZIP="$(which 7za)"
MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"
SORT="$(which sort)"
SED="$(which sed)"
AWK="$(which awk)"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  echo "`date +%Y-%m-%d_%H:%M:%S` - DB backup exit code: ${ErrorFlag}" >> ${LogFile}

  if [ -f ${LockFile} ];then
    ## Remove lock file so other backup jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  ## Email the result to the administrator.
  if [ ${ErrorFlag} -eq 0 ]; then
    f_sendmail "[Success] DB Backup" "DB backup completed with no errors."
  else
    f_sendmail "[Failure] DB Backup" "DB backup failed.  ErrorFlag = ${ErrorFlag}"
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
} ## f_cleanup()

function f_emergencyexit()
{
  ## Purpose: Exit script as cleanly as possible.
  f_cleanup
  exit ${ErrorFlag}
} ## f_emergencyexit()

function f_encrypt()
{
  ArcFile=$1
  EncFile=$2
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  echo ${CryptPass} > ${CryptPassFile}
#  echo "`date +%Y-%m-%d_%H:%M:%S` --- Encrypting archive: ${TempDir}/${EncFile}" >> ${LogFile}
  if ! gpg --cipher-algo aes256 --output ${TempDir}/${EncFile} --passphrase-file ${CryptPassFile} --batch --yes --no-tty --symmetric ${TempDir}/${ArcFile}; then
    ## Encryption failed, log results, send email, terminate program.
    rm ${CryptPassFile}
    echo "ERROR: Encryption failed. ${ArcFile}" | tee -a ${LogFile}
    ErrorFlag=16
    f_cleanup
  else
    ## Encryption succeeded, create checksum files and delete archive.
    sha512sum ${TempDir}/${EncFile} > ${TempDir}/${EncFile}.sha512
    ## Delete archive file and its checksum.
    rm ${TempDir}/${ArcFile}
    rm ${CryptPassFile}
  fi
  ## Set expected permissions and move to destination.
  chmod 0600 ${TempDir}/${EncFile}.sha512
  chmod 0600 ${TempDir}/${EncFile}
  chown root:root ${TempDir}/${EncFile}.sha512
  chown root:root ${TempDir}/${EncFile}*
  echo "`date +%Y-%m-%d_%H:%M:%S` --- Created: ${TargetDir}/${EncFile}" >> ${LogFile}
  mv ${TempDir}/${EncFile}.sha512 ${TargetDir}/.
  mv ${TempDir}/${EncFile} ${TargetDir}/.
} ## f_encrypt

function f_decrypt()
{
  EncryptedFile=$1
  DecryptedFile=$2
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  echo ${CryptPass} > ${CryptPassFile}
  if ! gpg --cipher-algo aes256 --output ${DecryptedFile} --passphrase-file ${CryptPassFile} --quiet --batch --yes --no-tty --decrypt ${EncryptedFile}; then
    ## Decryption failed, log results, send email, terminate program.
    echo "ERROR: Decryption failed: ${EncryptedFile}" | tee -a ${LogFile}
    ErrorFlag=32
    f_cleanup
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
} ## f_decrypt

function f_archive_file()
{
  OrgFile=$1
  ArcFile=$2
  ## Set expected permissions.
  chmod 0600 ${TempDir}/${OrgFile}
  chown root:root ${TempDir}/${OrgFile}
  ## Create archive
#  echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TempDir}/${ArcFile}" >> ${LogFile}
  case "${ArchiveMethod}" in
  tar.7z)
    ${TAR} -cpf - ${TempDir}/${OrgFile} | ${MY7ZIP} a -si -mx=9 -w${TempDir} ${TempDir}/${ArcFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C / -xf -
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C /tmp/restore --strip-components=1 -xf -
    ;;
  tgz)
    ${TAR} -cpzf ${TempDir}/${ArcFile} ${TempDir}/${OrgFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## tar -C / -xzf /tmp/archive.tar.gz
    ## tar -C /tmp/restore --strip-components=1 -xzf /tmp/archive.tar.gz
    ;;
  *)
    ${TAR} -cpzf ${TempDir}/${ArcFile} ${TempDir}/${OrgFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## tar command failed.  Send warning email.
    f_sendmail "DB Backup Archive Creation Failure" "tar failed with return value of ${ReturnValue}"
    ErrorFlag=8
  else
    ## tar succeeded.  Remove original file.
    if [ -f ${TempDir}/${OrgFile} ]; then
      rm ${TempDir}/${OrgFile}
    else
      echo "Missing expected file: ${TempDir}/${OrgFile}" | tee -a ${LogFile}
    fi
    ## Set expected permissions.
    chmod 0600 ${TempDir}/${ArcFile}
    chown root:root ${TempDir}/${ArcFile}
  fi
} ## f_archive_file()

function f_archive_folder()
{
  FolderName=$1
  ArcFile=$2
  ## Set expected permissions.
  chmod 0600 ${TempDir}/${FolderName}/*
  chown root:root ${TempDir}/${FolderName}/*
  ## Create archive
#  echo "`date +%Y-%m-%d_%H:%M:%S` --- Compressing archive: ${TempDir}/${ArcFile}" >> ${LogFile}
  case "${ArchiveMethod}" in
  tar.7z)
    ${TAR} -cpf - ${TempDir}/${FolderName}/* | ${MY7ZIP} a -si -mx=9 -w${TempDir} ${TempDir}/${ArcFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C / -xf -
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C /tmp/restore --strip-components=1 -xf -
    ;;
  tgz)
    ${TAR} -cpzf ${TempDir}/${ArcFile} ${TempDir}/${FolderName}/* 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## tar -C / -xzf /tmp/archive.tar.gz
    ## tar -C /tmp/restore --strip-components=1 -xzf /tmp/archive.tar.gz
    ;;
  *)
    ${TAR} -cpzf ${TempDir}/${ArcFile} ${TempDir}/${FolderName}/* 1>/dev/null 2>&1
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## tar command failed.  Send warning email.
    f_sendmail "DB Backup Archive Creation Failure" "tar failed with return value of ${ReturnValue}"
    ErrorFlag=16
  else
    ## tar succeeded.  Remove original folder.
    if [ -d ${TempDir}/${FolderName} ]; then
      rm -rf ${TempDir}/${FolderName}
    else
      echo "Missing expected folder: ${TempDir}/${FolderName}" | tee -a ${LogFile}
    fi
    ## Set expected permissions.
    chmod 0600 ${TempDir}/${ArcFile}
    chown root:root ${TempDir}/${ArcFile}
  fi
} ## f_archive_folder()

#######################################
##       PREREQUISITE CHECKS         ##
#######################################

if [ -f ${LockFile} ]; then
  ## Program lock file detected.  Abort script.
  f_sendmail "DB Backup aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when this script is not actually running."
  exit 1
else
  ## Create the lock file to ensure only one script is running at a time.
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo "ERROR: Root user required to run this script." | tee -a ${LogFile}
  ErrorFlag=2
  f_emergencyexit
fi

## If the 7-Zip archive method is specified, make sure the package is installed.
if [ "${ArchiveMethod}" = "tar.7z" ]; then
  if [ ! -f "/usr/bin/7za" ]; then
    ## Required package (7-Zip) not installed.
    echo "`date +%Y-%m-%d_%H:%M:%S` - CRITICAL ERROR: 7-Zip package not installed.  Please install by typing 'sudo apt install p7zip-full'" >> ${LogFile}
    ErrorFlag=4
    f_emergencyexit
  fi
fi

## If destination folder does not exist, create it. Mainly for 1st time use.
if [ ! -d ${OffsiteBackDir} ]; then
  mkdir -p ${OffsiteBackDir}
  chmod 0700 ${OffsiteBackDir}
fi

#######################################
##           MAIN PROGRAM            ##
#######################################

echo "`date +%Y-%m-%d_%H:%M:%S` - DB Backup started." >> ${LogFile}

## Document the current partition status:
echo "`date +%Y-%m-%d_%H:%M:%S` --- Partition status:" >> ${LogFile}
df -h >> ${LogFile}

## Document the current uptime.
${MYSQL} -e status | grep -i uptime >> ${LogFile}

## Document the current size of the database folder.
echo "`date +%Y-%m-%d_%H:%M:%S` --- Space consumed in ${DBDir} = `du -sh ${DBDir} | awk '{ print $1 }'`" >> ${LogFile}

StartTime="$(date +%s)"

## Build list of user databases.
SQLSTMT="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${DatabasesToExclude})"
MYSQLDUMP_DATABASES=""
for DB in `"${MYSQL}" --no-auto-rehash --skip-column-names --execute="${SQLSTMT}"`
do
  MYSQLDUMP_DATABASES="${MYSQLDUMP_DATABASES} ${DB}"
done

## Dump system database to single file, archive it, encrypt it, set permission, delete temp files
${MYSQLDUMP} --skip-lock-tables --databases mysql > ${TempDir}/db-system.sql
f_archive_file db-system.sql ${Timestamp}-db-system.${ArchiveMethod}
f_encrypt ${Timestamp}-db-system.${ArchiveMethod} ${Timestamp}-db-system.${ArchiveMethod}.enc

## Dump user accounts/grants to single file, archive it, encrypt it, set permission, delete temp files
${MYSQL} --skip-column-names --no-auto-rehash --silent --execute="SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | ${SORT} | ${MYSQL} --skip-column-names --no-auto-rehash | ${SED} 's/$/;/g' > ${TempDir}/db-grants.sql
f_archive_file db-grants.sql ${Timestamp}-db-grants.${ArchiveMethod}
f_encrypt ${Timestamp}-db-grants.${ArchiveMethod} ${Timestamp}-db-grants.${ArchiveMethod}.enc

## Dump all user databases to single file, archive it, encrypt it, set permission, delete temp files
${MYSQLDUMP} --skip-lock-tables --databases ${MYSQLDUMP_DATABASES} > ${TempDir}/db-all.sql
f_archive_file db-all.sql ${Timestamp}-db-all.${ArchiveMethod}
f_encrypt ${Timestamp}-db-all.${ArchiveMethod} ${Timestamp}-db-all.${ArchiveMethod}.enc

## Dump user databases into separate files, archive it, encrypt it, set permission, delete temp files
for SingleDB in ${MYSQLDUMP_DATABASES}
do
  ## Backup individual database.
  ${MYSQLDUMP} ${SingleDB} > ${TempDir}/${SingleDB}.sql
  f_archive_file ${SingleDB}.sql ${Timestamp}-db-${SingleDB}.${ArchiveMethod}
  f_encrypt ${Timestamp}-db-${SingleDB}.${ArchiveMethod} ${Timestamp}-db-${SingleDB}.${ArchiveMethod}.enc
done

## Dump tables into separate database folders, archive it, encrypt it, set permission, delete temp files
for SingleDB in ${MYSQLDUMP_DATABASES}
do
  ## Create database sub-folder.
  mkdir -p ${TempDir}/${SingleDB}
  ## Export each table in the database individually.
  for SingleTable in `echo "show tables" | $MYSQL ${SingleDB}|grep -v Tables_in_`;
  do
    DataFile=${TempDir}/${SingleDB}/${SingleTable}.sql
    case "${SingleTable}" in
      general_log)
        ${MYSQLDUMP} ${SingleDB} ${SingleTable} --skip-lock-tables > ${DataFile}
        ;;
      slow_log)
        ${MYSQLDUMP} ${SingleDB} ${SingleTable} --skip-lock-tables > ${DataFile}
        ;;
      *)
        ${MYSQLDUMP} ${SingleDB} ${SingleTable} > ${DataFile}
        ;;
    esac
  done
  if [ "$(ls -A ${TempDir}/${SingleDB})" ]; then
    f_archive_folder ${SingleDB} ${Timestamp}-tbl-${SingleDB}.${ArchiveMethod}
    f_encrypt ${Timestamp}-tbl-${SingleDB}.${ArchiveMethod} ${Timestamp}-tbl-${SingleDB}.${ArchiveMethod}.enc
  else
    echo "[INFO] Database has no tables: ${SingleDB}" >> ${LogFile}
    rmdir ${TempDir}/${SingleDB}
  fi
done

FreeSpace=`df --block-size=1k ${BackupDir} | grep ${BackupDir} | awk '{ print $4 }'`
BackupSize=`du --summarize --block-size=1k ${TargetDir} | awk '{ print $1 }'`

echo "`date +%Y-%m-%d_%H:%M:%S` FreeSpace=${FreeSpace}k BackupSize=${BackupSize}k" >> ${LogFile}

## Make sure space is available in the remote folder to copy the file.
if [ "${FreeSpace}" -lt "${BackupSize}" ]; then
  ## Not enough free space available.  Send email and exit.
    echo "[ERROR] Freespace: Not enough space (${BackupSize}k) in ${OffsiteBackDir}" | tee -a ${LogFile}
    ErrorFlag=32
else
  ## Copy archives to remote folder to be pulled by remote server.
  echo "`date +%Y-%m-%d_%H:%M:%S` --- Duplicating archives to ${OffsiteBackDir}" >> ${LogFile}
  cp --preserve=all ${TargetDir}/*.enc ${OffsiteBackDir}/.
  cp --preserve=all ${TargetDir}/*.sha512 ${OffsiteBackDir}/.
fi

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

echo "`date +%Y-%m-%d_%H:%M:%S` --- Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" >> ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - DB backup completed." >> ${LogFile}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ErrorFlag}
