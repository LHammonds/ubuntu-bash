#!/bin/bash
#############################################################
## Name : mariadb-user-decrypt.sh
## Version : 1.0
## Date : 2018-04-16
## Author : LHammonds
## Purpose : Decrypt the SQL files that were encrypted during backup.
## Compatibility : Verified on Ubuntu Server 16.04 thru 18.04 LTS
##               : Verified on MariaDB 10.1.32 thru 10.4.8
## Requirements : percona-toolkit (tested using version 3.0.6)
##              : gpgv (tested using version 2.2.4)
## Run Frequency : Manually.  When backups need to be decrypted.
## NOTE: Grant files contain the grant commands only.
##       Revoke files contain the revoke, drop and grant commands together.
## Parameters : None
## Exit Codes :
## 0  = Success
## 1  = ERROR: Lock file detected
## 2  = ERROR: Must be root user
## 4  = ERROR: percona-toolkit not installed
## 8  = ERROR: gpgv not installed
## 16 = ERROR: checksum mismatch
## 32 = ERROR: decryption failure
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2018-04-16 1.0 LTH Created script.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
Title="${Company}-mariadb-user-decrypt"
BackupDir=${BackupDir}/mysql
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
    echo "`date +%Y-%m-%d_%H:%M:%S` - Decrypt aborted." | tee -a ${LogFile}
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
  exit ${ErrorFlag}
} ## f_cleanup

function f_compare()
{
  filename=$1
  if ! sha512sum --status --check ${filename}; then
    ## Comparison failed, log results, terminate program.
    echo "ERROR: Checksum mismatch: ${filename}" | tee -a ${LogFile}
    ErrorFlag=16
    f_cleanup
  fi
} ## f_compare

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

#######################################
##       PREREQUISITE CHECKS         ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "Script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when not actually running."
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

echo "`date +%Y-%m-%d_%H:%M:%S` - Decrypt started." | tee -a ${LogFile}

## Verify checksum results on encrypted files
echo "Verifying checksums on encrypted files..."
f_compare ${BackupDir}/${GrantFile}.enc.sha512
f_compare ${BackupDir}/${RevokeFile}.enc.sha512
echo "Encrypted checksums: OK."

## Decrypt files
echo "Decrypting files..."
f_decrypt ${BackupDir}/${GrantFile}.enc ${BackupDir}/${GrantFile}
f_decrypt ${BackupDir}/${RevokeFile}.enc ${BackupDir}/${RevokeFile}

## Verify checksum results on decrypted files
echo "Verifying checksums on decrypted files..."
f_compare ${BackupDir}/${GrantFile}.sha512
f_compare ${BackupDir}/${RevokeFile}.sha512
echo "Decrypted checksums: OK."

## Set file permissions.
chmod 0600 ${BackupDir}/${GrantFile}
chmod 0600 ${BackupDir}/${RevokeFile}

/bin/ls -l ${BackupDir}/${GrantFile} | tee -a ${LogFile}
/bin/ls -l ${BackupDir}/${RevokeFile} | tee -a ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - Decrypt finished." | tee -a ${LogFile}
f_cleanup
