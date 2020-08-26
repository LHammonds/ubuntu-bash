#!/bin/bash
#############################################################
## Name          : ftp-pharma2bank-835.sh
## Version       : 1.0
## Date          : 2017-01-10
## Author        : LHammonds
## Bank Contacts : Redacted
## Purpose       : Copy transaction files to bank.
## Compatibility : Verified on Ubuntu Server 12.04 LTS
## Requirements  : sendemail
## Run Frequency : Every few minutes (or as often as desired)
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = failure to mount remote folder
##    2 = failure to FTP files
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2016-12-09 1.0 LTH Created script.
#############################################################

## NOTE: Since this ssh key requires a passphrase, we use
##       ssh-agent to hold the value of the pasphrase while
##       the server has not rebooted. The passphrase will need
##       to be loaded each time the server is rebooted. The
##       PID and lock file variables also have to be set and we
##       use /root/.bashrc to point the variables to each session
##       that logs in after it using this code:
## _SSH_AGENT_SOCKET=`find /tmp/ -type s -name agent.\* 2> /dev/null | grep '/tmp/ssh-.*/agent.*'`
## _SSH_AGENT_PID=`ps aux | grep ssh-agent | grep -v "grep" | awk '{print $2}'`
## export SSH_AUTH_SOCK=${_SSH_AGENT_SOCKET}
## export SSH_AGENT_PID=${_SSH_AGENT_PID}

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

export SSHPASS='EnterSuperSecretCodeHere'
SourceIP=sftp.pharma.net
SourceID=phramasftp
SourceFTP="/prod/from_pharma/remit"
TargetIP=${BANKIP}
TargetID=${BANKID}
TargetFTP="/home/user/835toBank/State"
LogFile="${LogDir}/pharma2bank-835.log"
FTPCmd="${TempDir}/pharma2bank-835.ftp"
LockFile="${TempDir}/pharma2bank-835.lock"
NewDir="/bak/bank/outbound/new/pharma/835"
ArchiveDir="/bak/bank/outbound/archive/pharma/835"
AppTitle="pharma2bank-835"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other check space jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  if [ -f ${FTPCmd} ];then
    ## Remove temp file.
    rm ${FTPCmd} 1>/dev/null 2>&1
  fi
}

#######################################
##              MAIN                 ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "${AppTitle} script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when not actually running."
  f_sendmail "ERROR: ${AppTitle} script aborted" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  exit 10
else
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

echo "`date +%Y-%m-%d_%H:%M:%S` Script started." >> ${LogFile}

#if [ ${#SSH_AUTH_SOCK} -lt 1 ]; then
  ## Variable is empty, try to find running ssh-agent and use it.
#  _SSH_AGENT_SOCKET=`find /tmp/ -type s -name agent.\* 2> /dev/null | grep '/tmp/ssh-.*/agent.*'`
#  _SSH_AGENT_PID=`ps aux | grep ssh-agent | grep -v "grep" | awk '{print $2}'`
#  export SSH_AUTH_SOCK=${_SSH_AGENT_SOCKET}
#  export SSH_AGENT_PID=${_SSH_AGENT_PID}
#fi

## Point the required variables to the loaded ssh-agent
export SSH_AUTH_SOCK=`find /tmp/ -type s -name agent.\* 2> /dev/null | grep '/tmp/ssh-.*/agent.*'`
export SSH_AGENT_PID=`ps aux | grep ssh-agent | grep -v "grep" | awk '{print $2}'`

if [ ${#SSH_AUTH_SOCK} -lt 1 ]; then
  ## Variable still empty.  Houston, we have a problem.
  echo "ERROR - ssh-agent not pre-loaded with authentication key." | tee -a ${LogFile}
  echo "You must load the SSH keys before running this script."
  f_cleanup
  exit 0
fi

## Get files from Pharmacy
## Download the files.

echo "lcd ${NewDir}" > ${FTPCmd}
echo "cd ${SourceFTP}" >> ${FTPCmd}
echo "ls -l" >> ${FTPCmd}
echo "mget *" >> ${FTPCmd}
echo "rm *" >> ${FTPCmd}
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP download started." >> ${LogFile}
sftp -b ${FTPCmd} ${SourceID}@${SourceIP} 1>> ${LogFile} 2>&1
if [[ $? != 0 ]]; then
  echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: FTP failed! (Exit Code 2)" >> ${LogFile}
  f_cleanup
  exit 2
fi
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP download complete." >> ${LogFile}


for f in ${NewDir}/*; do
  ## Check and see if there are any files in the folder.
  if [ ! -e "$f" ]; then
    ## There are no files...nothing to do...exit.
    echo "`date +%Y-%m-%d_%H:%M:%S` -- No files to process." >> ${LogFile}
    echo "`date +%Y-%m-%d_%H:%M:%S` Script completed." >> ${LogFile}
    f_cleanup
    exit 0
  fi
  break
done

## Upload the files to the bank.
echo "lcd ${NewDir}" > ${FTPCmd}
echo "cd ${TargetFTP}" >> ${FTPCmd}
echo "mput *" >> ${FTPCmd}
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP upload started." >> ${LogFile}
sshpass -e sftp -oBatchMode=no -b ${FTPCmd} ${TargetID}@${TargetIP} 1>> ${LogFile} 2>&1
if [[ $? != 0 ]]; then
  echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: FTP failed! (Exit Code 2)" >> ${LogFile}
  f_cleanup
  exit 2
else
  ## Need to move all files to a completed folder at this point. ##
  echo "`date +%Y-%m-%d_%H:%M:%S` -- Moving files to ${ArchiveDir}" >> ${LogFile}
  for f in ${NewDir}/*; do
    mv "$f" ${ArchiveDir}/.
  done
fi
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP upload complete." >> ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` Script finished." >> ${LogFile}
f_cleanup
exit 0
