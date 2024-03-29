#!/bin/bash
#############################################################
## Name          : db-decrypt.sh
## Version       : 1.3
## Date          : 2022-06-29
## Author        : LHammonds
## Purpose       : Decrypt and extract database archives.
## Compatibility : Verified on to work on:
##                  - Ubuntu Server 22.04 LTS
##                  - MariaDB 10.6.7
## Requirements  : p7zip-full (if ArchiveMethod=tar.7z), sendemail
## Run Frequency : As needed
## Input         : (Optional) filename prefix to reduce list of options.
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = lock file detected
##    2 = root access
##    4 = 7zip not installed
##    8 = decrypt failure
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- -----------------------
## 2020-06-25 1.0 LTH Created script.
## 2020-10-09 1.1 LTH Added command-line option for filename prefix.
## 2020-10-12 1.2 LTH Code cleanup.
## 2022-06-29 1.3 LTH Replaced echo with printf statements.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

## Change the password in this file to anything other than the default! ##
source /etc/passenc

Title="db-decrypt"
SourceDir="${BackupDir}/db"
CryptPassFile="${TempDir}/${Title}.gpg"
Timestamp="`date +%Y-%m-%d_%H%M`"
LogFile="${LogDir}/${Company}-${Title}.log"
LockFile="${TempDir}/${Company}-${Title}.lock"
ErrorFlag=0

## Binaries, you can let the script find them or you can set the full path manually here. ##
TarCmd="$(which tar)"
ZipCmd="$(which 7za)"
TeeCmd="$(which tee)"
GpgCmd="$(which gpg)"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  printf "`date +%Y-%m-%d_%H:%M:%S` - ${Title} exit code: ${ErrorFlag}\n" >> ${LogFile}

  if [ -f ${LockFile} ]; then
    ## Remove lock file so other backup jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
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

function f_decrypt()
{
  EncryptedFile=$1
  DecryptedFile=$2
  ## Create temporary password file
  touch ${CryptPassFile}
  chmod 0600 ${CryptPassFile}
  printf "${CryptPass}\n" > ${CryptPassFile}
  if ! ${GpgCmd} --cipher-algo aes256 --output ${DecryptedFile} --passphrase-file ${CryptPassFile} --quiet --batch --yes --no-tty --decrypt ${EncryptedFile}; then
    ## Decryption failed, log results, send email, terminate program.
    printf "[ERROR] Decryption failed: ${EncryptedFile}\n" | ${TeeCmd} -a ${LogFile}
    ErrorFlag=8
    f_cleanup
  fi
  if [ -f ${CryptPassFile} ]; then
    ## Remove temporary file
    rm ${CryptPassFile}
  fi
} ## f_decrypt

function f_extract()
{
  if [ ! -d ${TempDir}/decrypt ]; then
    mkdir ${TempDir}/decrypt
  fi
  ArcFile=$1
  case "${ArchiveMethod}" in
  tar.7z)
    ${ZipCmd} x -so -w${TempDir} ${ArcFile} | ${TarCmd} -C ${TempDir}/decrypt --strip-components=2 -xf -
    ReturnValue=$?
    ;;
  tgz)
    ${TarCmd} -C ${TempDir}/decrypt --strip-components=2 -xzf ${ArcFile}
    ;;
  *)
    ${TarCmd} -C ${TempDir}/decrypt --strip-components=2 -xzf ${ArcFile}
    ReturnValue=$?
    ;;
  esac
  if [ ${ReturnValue} -ne 0 ]; then
    ## Extract command failed. Display warning.
    printf "${Title} - Archive extract failure. Return value of ${ReturnValue}\n"
  else
    ## Remove decrypted archive file and list extracted file(s).
    rm ${ArcFile}
    find ${TempDir}/decrypt -name "*.sql"
  fi
} ## f_extract()


#######################################
##       PREREQUISITE CHECKS         ##
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
  printf "[ERROR] Root user required to run this script.\n" | ${TeeCmd} -a ${LogFile}
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
## If a parameter was passed, set it as the filename prefix.
if [ -z "${1}" ]; then
  Prefix=""
else
  Prefix=${1}
fi

#######################################
##           MAIN PROGRAM            ##
#######################################

printf "`date +%Y-%m-%d_%H:%M:%S` - ${Title} started.\n" >> ${LogFile}

printf "The following `*.enc` archives were found; select one:\n"
# set the prompt used by select, replacing "#?"
PS3="Use number to select a file or 'stop' to cancel: "
# allow the user to choose a file
cd ${SourceDir}
select EncFile in ${Prefix}*.enc
do
  if [[ "${REPLY}" == "stop" ]]; then
    ## User requested to terminate script.
    break;
  fi
  if [[ "${EncFile}" == "" ]]; then
    ## User made invalid selection.
    printf "'${REPLY}' is not a valid number\n"
    continue
  fi
  ## User selected a file.
  printf "${EncFile} selected\n" | ${TeeCmd} -a ${LogFile}
  # ArcFile= EncFile without .enc extension.
  ArcFile=$(printf "${EncFile%.*}\n")
  f_decrypt ${EncFile} ${ArcFile}
  f_extract ${ArcFile}
  ## Email the result to the administrator.
  if [ ${ErrorFlag} -eq 0 ]; then
    f_sendmail "[Success] ${Title}" "${Title} completed with no errors.\n\n${EncFile}"
  else
    f_sendmail "[Failure] ${Title}" "${Title} failed.  ErrorFlag = ${ErrorFlag}\n\nAttempted to decrypt ${EncFile}"
  fi
  break
done

printf "`date +%Y-%m-%d_%H:%M:%S` - ${Title} completed.\n" >> ${LogFile}

## Perform cleanup routine.
f_cleanup
## Exit with the combined return code value.
exit ${ErrorFlag}
