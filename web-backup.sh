#!/bin/bash
#############################################################
## Name          : web-backup.sh
## Version       : 1.0
## Date          : 2020-10-08
## Author        : LHammonds
## Purpose       : Complete encrypted backup of web site.
## Compatibility : Verified on to work on:
##                  - Ubuntu Server 20.04 LTS
##                  - Apache 2.4.41
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
## 2020-10-08 1.0 LTH Created script. (fork from db-backup 1.7)
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

## Change the password in this file to anything other than the default! ##
source /etc/passenc

Title="web-backup"
TargetDir="${BackupDir}/web"
RemoteDir="${BackupDir}/remote"
WorkingDir="${TempDir}/web"
CryptPassFile="${TempDir}/${Title}.gpg"
Timestamp="`date +%Y-%m-%d_%H%M`"
LogFile="${LogDir}/${Company}-${Title}.log"
LockFile="${TempDir}/${Company}-${Title}.lock"
ErrorFlag=0

## Binaries, you can let the script find them or you can set the full path manually here. ##
TarCmd="$(which tar)"
ZipCmd="$(which 7za)"
AwkCmd="$(which awk)"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  ## Purpose: Perform cleanup tasks which is last step of the script.
  echo "`date +%Y-%m-%d_%H:%M:%S` - ${Title} exit code: ${ErrorFlag}" >> ${LogFile}

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
}  ## f_cleanup() ##

function f_emergencyexit()
{
  ## Purpose: Exit script as cleanly as possible.
  f_cleanup
  exit ${ErrorFlag}
}  ## f_emergencyexit() ##

function f_encrypt()
{
  ArcFile=$1
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  echo ${CryptPass} > ${CryptPassFile}
#  echo "`date +%Y-%m-%d_%H:%M:%S` -- Encrypting archive: ${ArcFile}.enc" >> ${LogFile}
  if ! gpg --cipher-algo aes256 --output /${ArcFile}.enc --passphrase-file ${CryptPassFile} --batch --yes --no-tty --symmetric ${ArcFile}; then
    ## Encryption failed, log results, send email, terminate program.
    rm ${CryptPassFile}
    echo "ERROR: Encryption failed. ${ArcFile}" | tee -a ${LogFile}
    ErrorFlag=16
    f_cleanup
  else
    ## Encryption succeeded, create checksum files and delete archive.
    sha512sum ${ArcFile}.enc > ${ArcFile}.sha512
    ## Delete archive file and its checksum.
    rm ${ArcFile}
    rm ${CryptPassFile}
  fi
  ## Set expected permissions and move to destination.
  chmod 0600 ${ArcFile}.enc
  chmod 0600 ${ArcFile}.sha512
  chown root:root ${ArcFile}.enc
  chown root:root ${ArcFile}.sha512
  echo "`date +%Y-%m-%d_%H:%M:%S` -- Created ${ArcFile}.enc" >> ${LogFile}
  ## Copy to local storage ##
#  cp ${ArcFile}.enc ${TargetDir}/.
#  cp ${ArcFile}.sha512 ${TargetDir}/.
  ## Move to remote storage pickup location ##
#  mv ${ArcFile}.enc ${RemoteDir}/.
#  mv ${ArcFile}.sha512 ${RemoteDir}/.
} ## f_encrypt()

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
      echo "Missing expected file: ${OrgFile}" | tee -a ${LogFile}
    fi
    ## Set expected permissions.
    chmod 0600 ${ArcFile}
    chown root:root ${ArcFile}
  fi
}  ## f_archive_file() ##

function f_archive_webserver()
{
  ArchiveFile=$1
  Sources="/var/log/apache2/ /etc/apache2/ /etc/php/ /etc/netplan/ /etc/hosts /etc/letsencrypt/"
  ## Output the version information to a text file which will be included in the backup.
  case "${ArchiveMethod}" in
  tar.7z)
    ## NOTE: Compression changed from 9(ultra) to 7 since it was blowing out on 512 MB RAM
    echo "${TarCmd} cpf - ${Sources} | ${ZipCmd} a -si -mx=7 -w${TempDir} ${ArchiveFile}"
    ${TarCmd} cpf - ${Sources} | ${ZipCmd} a -si -mx=7 -w${TempDir} ${ArchiveFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C / -xf -
    ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C ${TempDir}/restore --strip-components=1 -xf -
    ;;
  tgz)
    ${TarCmd} -cpzf ${ArchiveFile} ${Sources} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## tar -C / -xzf ${TempDir}/${ArchiveFile}
    ## tar -C ${TempDir}/restore --strip-components=1 -xzf ${TempDir}/${ArchiveFile}
    ;;
  *)
    ${TarCmd} -cpzf ${ArchiveFile} ${Sources} 1>/dev/null 2>&1
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## tar command failed.  Send warning email.
    f_sendmail "${Title} Backup Failure - Archive" "Archive failed with return value of ${ReturnValue}"
    ErrorFlag=$((${ErrorFlag} + 2))
  fi
}  ## f_archive_webserver() ##

function f_archive_web()
{
  WebSite=$1
  ArchiveFile=$2
  Sources="${WebSite}"
  ## Output the version information to a text file which will be included in the backup.
  if [ -f "${WebSite}/version-info.txt" ]; then
    rm "${WebSite}/version-info.txt"
  fi
  lsb_release -cd >> ${WebSite}/version-info.txt
  apache2 -v >> ${WebSite}/version-info.txt
  php -i >> ${WebSite}/version-info.txt
  echo "`date +%Y-%m-%d_%H:%M:%S` -- Space consumed in ${WebSite} = `du -sh ${WebSite} | ${AwkCmd} '{ print $1 }'`" >> ${WebSite}/version-info.txt

  ## Compress the backup into a single file based on archive method specified.
  case "${ArchiveMethod}" in
  tar.7z)
    ## NOTE: Compression changed from 9(ultra) to 7 since it was blowing out on 512 MB RAM
    ${TarCmd} cpf - ${Sources} | ${ZipCmd} a -si -mx=7 -w${TempDir} ${ArchiveFile} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C / -xf -
    ## 7za x -so -w/tmp ${TempDir}/${ArchiveFile} | tar -C ${TempDir}/restore --strip-components=1 -xf -
    ;;
  tgz)
    ${TarCmd} -cpzf ${ArchiveFile} ${Sources} 1>/dev/null 2>&1
    ReturnValue=$?
    ## Restore using one of the following commands (do not uncomment, only for notation):
    ## tar -C / -xzf ${TempDir}/${ArchiveFile}
    ## tar -C ${TempDir}/restore --strip-components=1 -xzf ${TempDir}/${ArchiveFile}
    ;;
  *)
    ${TarCmd} -cpzf ${ArchiveFile} ${Sources} 1>/dev/null 2>&1
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## tar command failed.  Send warning email.
    f_sendmail "${Title} Backup Failure - Archive" "Archive failed with return value of ${ReturnValue}"
    ErrorFlag=$((${ErrorFlag} + 2))
  fi
  rm "${WebSite}/version-info.txt"
}  ## f_archive_web() ##

function f_webserver_backup()
{
  File=$1
  ## f_archive_web Parameters = [archive name]
  f_archive_webserver ${WorkingDir}/${File}
  f_encrypt ${WorkingDir}/${File}
  ## Copy archives to remote folder to be pulled by remote server.
  cp --preserve=all ${WorkingDir}/${File}.* ${RemoteDir}/.
  ## Move archives to local storage.
  mv ${WorkingDir}/${File}.* ${TargetDir}/.
  echo "`date +%Y-%m-%d_%H:%M:%S` -- Created ${TargetDir}/${File}.enc" >> ${LogFile}
}  ## f_webserver_backup() ##

function f_web_backup()
{
  Folder=$1
  File=$2
  ## f_archive_web Parameters = [Website root path] [archive name]
  f_archive_web ${Folder} ${WorkingDir}/${File}
  f_encrypt ${WorkingDir}/${File}
  ## Copy archives to remote folder to be pulled by remote server.
  cp --preserve=all ${WorkingDir}/${File}.* ${RemoteDir}/.
  ## Move archives to local storage.
  mv ${WorkingDir}/${File}.* ${TargetDir}/.
  echo "`date +%Y-%m-%d_%H:%M:%S` -- Created ${TargetDir}/${File}.enc" >> ${LogFile}
}  ## f_web_backup() ##

#######################################
##       PRE-REQUISITE CHECKS        ##
#######################################

if [ -f ${LockFile} ]; then
  ## Program lock file detected.  Abort script.
  f_sendmail "${Title} aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when this script is not actually running."
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
if [ ! -d ${RemoteDir} ]; then
  mkdir -p ${RemoteDir}
  chmod 0700 ${RemoteDir}
fi
if [ ! -d ${TargetDir} ]; then
  mkdir -p ${TargetDir}
  chmod 0700 ${TargetDir}
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

echo "`date +%Y-%m-%d_%H:%M:%S` - ${Title} started." >> ${LogFile}
StartTime="$(date +%s)"

## Backup web server files
f_webserver_backup ${Timestamp}-webserver.${ArchiveMethod}

## Backup individual web sites
f_web_backup /var/www/mediawiki ${Timestamp}-web-mediawiki.${ArchiveMethod}
f_web_backup /var/www/nextcloud ${Timestamp}-web-nextcloud.${ArchiveMethod}
f_web_backup /var/www/phpbb ${Timestamp}-web-phpbb.${ArchiveMethod}
f_web_backup /var/www/cumulusclips ${Timestamp}-web-cumulusclips.${ArchiveMethod}

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

echo "`date +%Y-%m-%d_%H:%M:%S` -- Total backup time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" >> ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - ${Title} completed." >> ${LogFile}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ErrorFlag}
