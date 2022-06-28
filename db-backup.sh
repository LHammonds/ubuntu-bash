#!/bin/bash
#############################################################
## Name          : db-backup.sh
## Version       : 1.9
## Date          : 2022-06-28
## Author        : LHammonds
## Purpose       : Complete encrypted backup of MariaDB databases.
## Compatibility : Verified on to work on:
##                  - Ubuntu Server 22.04 LTS
##                  - MariaDB 10.6.7
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
## 2020-10-09 1.7 LTH Added support for MariaDB roles.
##                    This scripts is no longer compatible with MySQL.
## 2021-11-10 1.8 LTH Changed backticks to single quotes.
## 2022-06-28 1.9 LTH Replaced echo with print statements.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

## Change the password in this file to anything other than the default! ##
source /etc/passenc

Title="db-backup"
DBDir="/opt/mariadb"
TargetDir="${BackupDir}/db"
RemoteDir="${BackupDir}/remote"
WorkingDir="${TempDir}/db"
CryptPassFile="${TempDir}/${Title}.gpg"
Timestamp="`date +%Y-%m-%d_%H%M`"
LogFile="${LogDir}/${Company}-${Title}.log"
LockFile="${TempDir}/${Company}-${Title}.lock"
DatabasesToExclude="'information_schema','mysql','performance_schema','JunkUserDB1','JunkUserDB2'"
ErrorFlag=0

## Binaries, you can let the script find them or you can set the full path manually here. ##
TarCmd="$(which tar)"
ZipCmd="$(which 7za)"
MysqlCmd="$(which mysql)"
MysqldumpCmd="$(which mysqldump)"
SedCmd="$(which sed)"
AwkCmd="$(which awk)"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  printf "`date +%Y-%m-%d_%H:%M:%S` - ${Title} exit code: ${ErrorFlag}\n" >> ${LogFile}

  if [ -f ${LockFile} ];then
    ## Remove lock file so other backup jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  ## Email the result to the administrator.
  if [ ${ErrorFlag} -eq 0 ]; then
    f_sendmail "[Success] ${Title}" "${Title} completed with no errors."
  else
    f_sendmail "[Failure] ${Title}" "${Title} failed.  ErrorFlag = ${ErrorFlag}"
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
  if [ ! "$(ls -A ${WorkingDir})" ]; then
    rmdir ${WorkingDir}
  fi
} ## f_cleanup() ##

function f_emergencyexit()
{
  ## Purpose: Exit script as cleanly as possible.
  f_cleanup
  exit ${ErrorFlag}
} ## f_emergencyexit() ##

function f_encrypt()
{
  ArcFile=$1
  EncFile=$2
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  printf "${CryptPass}\n" > ${CryptPassFile}
  if ! gpg --cipher-algo aes256 --output /${EncFile} --passphrase-file ${CryptPassFile} --batch --yes --no-tty --symmetric ${ArcFile}; then
    ## Encryption failed, log results, send email, terminate program.
    rm ${CryptPassFile}
    printf "[ERROR] Encryption failed. ${ArcFile}\n" | tee -a ${LogFile}
    ErrorFlag=16
    f_cleanup
  else
    ## Encryption succeeded, create checksum files and delete archive.
    sha512sum ${EncFile} > ${EncFile}.sha512
    ## Delete archive file and its checksum.
    rm ${ArcFile}
    rm ${CryptPassFile}
  fi
  ## Set expected permissions and move to destination.
  chmod 0600 ${EncFile}.sha512
  chmod 0600 ${EncFile}
  chown root:root ${EncFile}.sha512
  chown root:root ${EncFile}*
  printf "`date +%Y-%m-%d_%H:%M:%S` -- Created ${EncFile}\n" >> ${LogFile}
} ## f_encrypt() ##

function f_decrypt()
{
  EncryptedFile=$1
  DecryptedFile=$2
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  printf "${CryptPass}\n" > ${CryptPassFile}
  if ! gpg --cipher-algo aes256 --output ${DecryptedFile} --passphrase-file ${CryptPassFile} --quiet --batch --yes --no-tty --decrypt ${EncryptedFile}; then
    ## Decryption failed, log results, send email, terminate program.
    printf "[ERROR] Decryption failed: ${EncryptedFile}\n" | tee -a ${LogFile}
    ErrorFlag=99
    f_cleanup
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
} ## f_decrypt() ##

function f_archive_file()
{
  OrgFile=$1
  ArcFile=$2
  ## Set expected permissions.
  chmod 0600 ${OrgFile}
  chown root:root ${OrgFile}
  ## Create archive
  case "${ArchiveMethod}" in
  tar.7z)
    ${TarCmd} -cpf - ${OrgFile} | ${ZipCmd} a -si -mx=9 -w${TempDir} ${ArcFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C / -xf -
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C /tmp/restore --strip-components=1 -xf -
    ;;
  tgz)
    ${TarCmd} -cpzf ${ArcFile} ${OrgFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## tar -C / -xzf /tmp/archive.tar.gz
    ## tar -C /tmp/restore --strip-components=1 -xzf /tmp/archive.tar.gz
    ;;
  *)
    ${TarCmd} -cpzf ${ArcFile} ${OrgFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## tar command failed.  Send warning email.
    f_sendmail "${Title} Archive Creation Failure" "Archive failed with return value of ${ReturnValue}"
    ErrorFlag=8
  else
    ## tar succeeded.  Remove original file.
    if [ -f ${OrgFile} ]; then
      rm ${OrgFile}
    else
      printf "Missing expected file: ${OrgFile}\n" | tee -a ${LogFile}
    fi
    ## Set expected permissions.
    chmod 0600 ${ArcFile}
    chown root:root ${ArcFile}
  fi
} ## f_archive_file() ##

function f_archive_folder()
{
  FolderName=$1
  ArcFile=$2
  ## Set expected permissions.
  chmod 0600 ${FolderName}/*
  chown root:root ${FolderName}/*
  ## Create archive
  case "${ArchiveMethod}" in
  tar.7z)
    ${TarCmd} -cpf - ${FolderName}/* | ${ZipCmd} a -si -mx=9 -w${TempDir} ${ArcFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C / -xf -
    ## 7za x -so -w/tmp /tmp/archive.tar.7z | tar -C /tmp/restore --strip-components=1 -xf -
    ;;
  tgz)
    ${TarCmd} -cpzf ${ArcFile} ${FolderName}/* 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## tar -C / -xzf /tmp/archive.tar.gz
    ## tar -C /tmp/restore --strip-components=1 -xzf /tmp/archive.tar.gz
    ;;
  *)
    ${TarCmd} -cpzf ${ArcFile} ${FolderName}/* 1>/dev/null 2>&1
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## Archive command failed.  Send warning email.
    f_sendmail "${Title} Archive Creation Failure" "Archive failed with return value of ${ReturnValue}"
    ErrorFlag=16
  else
    ## Archive command succeeded.  Remove original folder.
    if [ -d ${FolderName} ]; then
      rm -rf ${FolderName}
    else
      printf "Missing expected folder: ${FolderName}\n" | tee -a ${LogFile}
    fi
    ## Set expected permissions.
    chmod 0600 ${ArcFile}
    chown root:root ${ArcFile}
  fi
} ## f_archive_folder() ##

function f_export_systemdb()
{
  ## Dump system database to single file, archive it, encrypt it, set permission, delete temp files
  ${MysqldumpCmd} --skip-lock-tables --databases mysql > ${WorkingDir}/db-system.sql
  f_archive_file ${WorkingDir}/db-system.sql ${WorkingDir}/${Timestamp}-db-system.${ArchiveMethod}
  f_encrypt ${WorkingDir}/${Timestamp}-db-system.${ArchiveMethod} ${WorkingDir}/${Timestamp}-db-system.${ArchiveMethod}.enc
} ## f_export_systemdb() ##

function f_export_users()
{
  ## Dump user accounts/grants to single file, archive it, encrypt it, set permission, delete temp files
  ## Create roles ##
  ${MysqlCmd} --skip-column-names --no-auto-rehash --silent --execute="SELECT User FROM mysql.user WHERE is_role = 'Y';" | ${SedCmd} 's/^/CREATE ROLE /;s/$/;/g;1s/^/## Create Roles ##\n/' > ${WorkingDir}/db-grants.sql
  ## Grant roles ##
  ${MysqlCmd} --skip-column-names --no-auto-rehash --silent --execute="SELECT CONCAT('SHOW GRANTS FOR ''',User,''';') FROM mysql.user WHERE is_role = 'Y'" | ${MysqlCmd} --skip-column-names --no-auto-rehash | ${SedCmd} 's/$/;/g;1s/^/## Grants for Roles ##\n/' >> ${WorkingDir}/db-grants.sql
  ## Create user ##
  ${MysqlCmd} --skip-column-names --no-auto-rehash --silent --execute="SELECT User,Host,Password FROM mysql.user WHERE is_role = 'N' AND User NOT IN ('mariadb.sys','root','mysql');" | ${SedCmd} 's/\t/`@`/;s/\t/` IDENTIFIED BY \x27/;s/^/CREATE USER `/;s/$/\x27;/;1s/^/## Create Users ##\n/' >> ${WorkingDir}/db-grants.sql
  ## User grants ##
  ${MysqlCmd} --skip-column-names --no-auto-rehash --silent --execute="SELECT CONCAT('SHOW GRANTS FOR ''',User,'''@''',Host,''';') FROM mysql.user WHERE User <> '' AND is_role = 'N' AND user NOT IN ('mysql','mariadb.sys','root');" | ${MysqlCmd} --skip-column-names --no-auto-rehash | ${SedCmd} 's/$/;/g;1s/^/## Grants for Users ##\n/' >> ${WorkingDir}/db-grants.sql
  ## Default roles ##
  ${MysqlCmd} --skip-column-names --no-auto-rehash --silent --execute="SELECT default_role,User,Host FROM mysql.user WHERE is_role = 'N' AND User NOT IN ('mariadb.sys','root','mysql') AND default_role <> '';" | ${SedCmd} 's/\t/ FOR `/;s/\t/`@`/;s/^/SET DEFAULT ROLE /;1s/^/## Set Default Roles ##\n/;s/$/`;/' >> ${WorkingDir}/db-grants.sql
  f_archive_file ${WorkingDir}/db-grants.sql ${WorkingDir}/${Timestamp}-db-grants.${ArchiveMethod}
  f_encrypt ${WorkingDir}/${Timestamp}-db-grants.${ArchiveMethod} ${WorkingDir}/${Timestamp}-db-grants.${ArchiveMethod}.enc
} ## f_export_users() ##

function f_export_alldb()
{
  ## Get list of all current databases except those in the exclusion list.
  SqlCmd="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${DatabasesToExclude})"
  DBDumpList=""
  for DB in `"${MysqlCmd}" --no-auto-rehash --skip-column-names --execute="${SqlCmd}"`
  do
    DBDumpList="${DBDumpList} ${DB}"
  done
  ## Dump all user databases to single file, archive it, encrypt it, set permission, delete temp files
  ${MysqldumpCmd} --skip-lock-tables --databases ${DBDumpList} > ${WorkingDir}/db-all.sql
  f_archive_file ${WorkingDir}/db-all.sql ${WorkingDir}/${Timestamp}-db-all.${ArchiveMethod}
  f_encrypt ${WorkingDir}/${Timestamp}-db-all.${ArchiveMethod} ${WorkingDir}/${Timestamp}-db-all.${ArchiveMethod}.enc
} ## f_export_alldb() ##

function f_export_userdb()
{
  ## Get list of all current databases except those in the exclusion list.
  SqlCmd="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${DatabasesToExclude})"
  DBDumpList=""
  for DB in `"${MysqlCmd}" --no-auto-rehash --skip-column-names --execute="${SqlCmd}"`
  do
    DBDumpList="${DBDumpList} ${DB}"
  done
  ## Dump user databases into separate files, archive it, encrypt it, set permission, delete temp files
  for SingleDB in ${DBDumpList}
  do
    ## Backup individual database.
    ${MysqldumpCmd} ${SingleDB} > ${WorkingDir}/${SingleDB}.sql
    f_archive_file ${WorkingDir}/${SingleDB}.sql ${WorkingDir}/${Timestamp}-db-${SingleDB}.${ArchiveMethod}
    f_encrypt ${WorkingDir}/${Timestamp}-db-${SingleDB}.${ArchiveMethod} ${WorkingDir}/${Timestamp}-db-${SingleDB}.${ArchiveMethod}.enc
  done
} ## f_export_userdb() ##

function f_export_tables()
{
  ## Get list of all current databases except those in the exclusion list.
  SqlCmd="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${DatabasesToExclude})"
  DBDumpList=""
  for DB in `"${MysqlCmd}" --no-auto-rehash --skip-column-names --execute="${SqlCmd}"`
  do
    DBDumpList="${DBDumpList} ${DB}"
  done
  ## Dump tables into separate database folders, archive it, encrypt it, set permission, delete temp files
  for SingleDB in ${DBDumpList}
  do
    ## Create database sub-folder.
    mkdir -p ${WorkingDir}/${SingleDB}
    ## Export each table in the database individually.
    for SingleTable in `printf "show tables\n" | ${MysqlCmd} ${SingleDB}|grep -v Tables_in_`;
    do
      DataFile=${WorkingDir}/${SingleDB}/${SingleTable}.sql
      case "${SingleTable}" in
        general_log)
          ${MysqldumpCmd} ${SingleDB} ${SingleTable} --skip-lock-tables > ${DataFile}
          ;;
        slow_log)
          ${MysqldumpCmd} ${SingleDB} ${SingleTable} --skip-lock-tables > ${DataFile}
          ;;
        *)
          ${MysqldumpCmd} ${SingleDB} ${SingleTable} > ${DataFile}
          ;;
      esac
    done
    if [ "$(ls -A ${WorkingDir}/${SingleDB})" ]; then
      f_archive_folder ${WorkingDir}/${SingleDB} ${WorkingDir}/${Timestamp}-tbl-${SingleDB}.${ArchiveMethod}
      f_encrypt ${WorkingDir}/${Timestamp}-tbl-${SingleDB}.${ArchiveMethod} ${WorkingDir}/${Timestamp}-tbl-${SingleDB}.${ArchiveMethod}.enc
    else
      printf "[INFO] Database has no tables: ${SingleDB}\n" >> ${LogFile}
      rmdir ${WorkingDir}/${SingleDB}
    fi
  done
} ## f_export_tables() ##

#######################################
##       PRE-REQUISITE CHECKS        ##
#######################################

if [ -f ${LockFile} ]; then
  ## Program lock file detected.  Abort script.
  f_sendmail "${Title} aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when this script is not actually running."
  exit 1
else
  ## Create the lock file to ensure only one script is running at a time.
  printf "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}\n" > ${LockFile}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "[ERROR] Root user required to run this script.\n" | tee -a ${LogFile}
  ErrorFlag=2
  f_emergencyexit
fi

## If the 7-Zip archive method is specified, make sure the package is installed.
if [ "${ArchiveMethod}" = "tar.7z" ]; then
  if [ ! -f "/usr/bin/7za" ]; then
    ## Required package (7-Zip) not installed.
    printf "`date +%Y-%m-%d_%H:%M:%S` - CRITICAL ERROR: 7-Zip package not installed.  Please install by typing 'sudo apt install p7zip-full'\n" >> ${LogFile}
    ErrorFlag=4
    f_emergencyexit
  fi
fi

## If destination folder does not exist, create it. Mainly for 1st time use.
if [ ! -d ${TargetDir} ]; then
  mkdir -p ${TargetDir}
  chmod 0700 ${TargetDir}
fi

## If destination folder does not exist, create it. Mainly for 1st time use.
if [ ! -d ${RemoteDir} ]; then
  mkdir -p ${RemoteDir}
  chmod 0700 ${RemoteDir}
fi

## Ensure working directory does not contain old data.
if [ -d ${WorkingDir} ]; then
  rm -rf ${WorkingDir}
fi
mkdir -p ${WorkingDir}
chmod 0700 ${WorkingDir}

#######################################
##           MAIN PROGRAM            ##
#######################################

printf "`date +%Y-%m-%d_%H:%M:%S` - ${Title} started.\n" >> ${LogFile}
StartTime="$(date +%s)"

## Document the current partition status:
printf "## Partition status:\n" >> ${LogFile}
df -h >> ${LogFile}

## Document the database version:
printf "## Database version:\n" >> ${LogFile}
${MysqlCmd} --version >> ${LogFile}

## Document the current uptime.
${MysqlCmd} -e status | grep -i uptime >> ${LogFile}

## Document the current size of the database folder.
printf "## Space consumed in ${DBDir} = `du -sh ${DBDir} | ${AwkCmd} '{ print $1 }'`\n" >> ${LogFile}

## Export users, roles and grants.
## NOTE: Useful for local restore, migration or disaster recovery.
f_export_users
## Export the system database.
## NOTE: Useful for local restore or disaster recovery.
f_export_systemdb
## Export all user databases into a single file.
## NOTE: Useful for local restore, migration or disaster recovery.
f_export_alldb
## Export all user databases into individual files.
## NOTE: Useful for local restore, migration or disaster recovery.
f_export_userdb
## Export each table into individual files.
## NOTE: Useful for local restore.
f_export_tables

FreeSpace=`df --block-size=1k ${BackupDir} | grep ${BackupDir} | ${AwkCmd} '{ print $4 }'`
BackupSize=`du --summarize --block-size=1k ${WorkingDir} | ${AwkCmd} '{ print $1 }'`

printf "## FreeSpace=${FreeSpace}k BackupSize=${BackupSize}k\n" >> ${LogFile}

## Make sure space is available in the remote folder to copy the file.
if [ "${FreeSpace}" -lt "${BackupSize}" ]; then
  ## Not enough free space available.  Send email and exit.
    printf "[ERROR] Freespace: Not enough space (${BackupSize}k) in ${BackupDir}\n" | tee -a ${LogFile}
    ErrorFlag=32
else
  ## Copy archives to remote folder to be pulled by remote server.
  printf "## Duplicating archives to ${RemoteDir}\n" >> ${LogFile}
  cp --preserve=all ${WorkingDir}/*.enc ${RemoteDir}/.
  cp --preserve=all ${WorkingDir}/*.sha512 ${RemoteDir}/.
  ## Move archives to local storage.
  printf "## Moving archives to ${TargetDir}\n" >> ${LogFile}
  mv ${WorkingDir}/*.enc ${TargetDir}/.
  mv ${WorkingDir}/*.sha512 ${TargetDir}/.
fi

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

printf "## Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)\n" >> ${LogFile}

printf "`date +%Y-%m-%d_%H:%M:%S` - ${Title} completed.\n" >> ${LogFile}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ErrorFlag}
