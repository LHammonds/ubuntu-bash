#!/bin/bash
#############################################################
## Name          : mariadb-user-encrypt.sh
## Version       : 1.0
## Date          : 2018-04-16
## Author        : LHammonds
## Purpose       : Export REVOKE,DROP,GRANT statements for all users.
##               : Encrypt the files for storage
## How to Decrypt:
##   gpg --cipher-algo aes256 --output decrypted-target.txt /
##       --passphrase-file /etc/gpg.conf --batch --yes /
##       --no-tty --decrypt encrypted-file.enc
## Compatibility : Verified on Ubuntu Server 16.04 - 20.04 LTS
##               : Verified on MariaDB 10.1.32 thru 10.4.8
## Requirements  : percona-toolkit (tested using version 3.0.6)
##               : gpgv (tested using version 2.2.4)
## Run Frequency : Often as desired.
## NOTE          : Grant files contain the grant commands only. Revoke files
##                 contain the revoke, drop and grant commands together.
## Parameters    : None
## Exit Codes    :
## 0  = Success
## 1  = ERROR: Lock file detected
## 2  = ERROR: Must be root user
## 4  = ERROR: percona-toolkit not installed
## 8  = ERROR: gpgv not installed
## 16 = ERROR: encryption failure
## 32 = ERROR: checksum mismatch
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2018-04-16 1.0 LTH Created script.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
BackupDir=${BackupDir}/mysql
Title="${Company}-mariadb-user-encrypt"
LogFile="${LogDir}/${Title}.log"
LockFile="${TempDir}/${Title}.lock"
GrantFile="${Company}-user-grant.sql"
RevokeFile="${Company}-user-revoke.sql"
## Change this password to anything other than the default! ##
CryptPass="abc123"
CryptPassFile="${TempDir}/${Title}.gpg"
ErrorFlag=0
ReturnCode=0

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
    echo "`date +%Y-%m-%d_%H:%M:%S` - Encrypt aborted." >> ${LogFile}
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
  exit ${ErrorFlag}
} ## f_cleanup

function f_encrypt()
{
  filename=$1
  encrypted=$2
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  echo ${CryptPass} > ${CryptPassFile}
  if ! gpg --cipher-algo aes256 --output ${encrypted} --passphrase-file ${CryptPassFile} --batch --yes --no-tty --symmetric ${filename}; then
    ## Encryption failed, log results, send email, terminate program.
    echo "ERROR: Encryption failed. ${filename}" | tee -a ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
} ## f_encrypt

function f_compare()
{
  filename=$1
  if ! sha512sum --status --check ${filename}; then
    ## Comparison failed, log results, send email, terminate program.
    echo "ERROR: Checksum mismatch: ${filename}" | tee -a ${LogFile}
    ErrorFlag=32
    f_cleanup
  fi
} ## f_compare

#######################################
##       PREREQUISITE CHECKS         ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "Backup partitions script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when backup partitions is not actually running."
  f_sendmail "ERROR: Encrypt script aborted" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when script is not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=1
  exit ${ErrorFlag}
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo "ERROR: Root user required to run this script." | tee -a ${LogFile}
  ErrorFlag=2
  f_cleanup
fi

## Requirement Check: Software
command -v pt-show-grants > /dev/null 2>&1 && ReturnCode=0 || ReturnCode=1
if [ ${ReturnCode} = 1 ]; then
  ## Required program not installed.
  echo "ERROR: percona-toolkit not installed." | tee -a ${LogFile}
  ErrorFlag=4
  f_cleanup
fi
command -v gpg > /dev/null 2>&1 && ReturnCode=0 || ReturnCode=1
if [ ${ReturnCode} = 1 ]; then
  ## Required program not installed.
  ## NOTE: gpgv comes standard with Ubuntu Server 16.04 LTS
  echo "ERROR: gpgv not installed." | tee -a ${LogFile}
  ErrorFlag=8
  f_cleanup
fi

#######################################
##           MAIN PROGRAM            ##
#######################################

echo "`date +%Y-%m-%d_%H:%M:%S` - Export/Encrypt started." | tee -a ${LogFile}

## Export grant commands only
pt-show-grants --user root --separate --flush > ${BackupDir}/${GrantFile}
## Export revoke, drop and grant commands
pt-show-grants --user root --separate --flush --revoke --drop > ${BackupDir}/${RevokeFile}

## Encrypt files for transfer and storage
f_encrypt ${BackupDir}/${GrantFile} ${BackupDir}/${GrantFile}.enc
f_encrypt ${BackupDir}/${RevokeFile} ${BackupDir}/${RevokeFile}.enc

## Create checksum files
sha512sum ${BackupDir}/${GrantFile} > ${BackupDir}/${GrantFile}.sha512
sha512sum ${BackupDir}/${RevokeFile} > ${BackupDir}/${RevokeFile}.sha512
sha512sum ${BackupDir}/${GrantFile}.enc > ${BackupDir}/${GrantFile}.enc.sha512
sha512sum ${BackupDir}/${RevokeFile}.enc > ${BackupDir}/${RevokeFile}.enc.sha512

## Verify checksum results
f_compare ${BackupDir}/${GrantFile}.sha512
f_compare ${BackupDir}/${RevokeFile}.sha512
f_compare ${BackupDir}/${GrantFile}.enc.sha512
f_compare ${BackupDir}/${RevokeFile}.enc.sha512

## Remove unencrypted files
rm ${BackupDir}/${GrantFile}
rm ${BackupDir}/${RevokeFile}

## Set file permissions.
chmod 0600 ${BackupDir}/${GrantFile}*
chmod 0600 ${BackupDir}/${RevokeFile}*

/bin/ls -l ${BackupDir}/${GrantFile}.enc | tee -a ${LogFile}
/bin/ls -l ${BackupDir}/${RevokeFile}.enc | tee -a ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - Export/Encrypt finished." | tee -a ${LogFile}
f_cleanup
