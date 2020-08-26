#!/bin/bash
#############################################################
## Name          : ftp-bank2pharma-835.sh
## Version       : 1.0
## Date          : 2017-03-17
## Author        : LHammonds
## Bank Contacts : Redacted
## Purpose       : Copy transaction files from bank to pharmacy
## Compatibility : Verified on Ubuntu Server 12.04 LTS
## Requirements  : sendemail
## Run Frequency : Every few minutes (or as often as desired)
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = lock file detected from another running script.
##    2 = ssh-agent keys not loaded.
##    4 = Source FTP problem (bank).
##    8 = Target FTP problem (pharma).
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2017-03-17 1.0 LTH Created script.
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
SourceIP=${BANKIP}
SourceID=${BANKID}
SourceFTP="/home/user/835fromBank/pharma/835"

TargetIP=sftp.pharma.net
TargetID=pharmasftp
TargetFTP="/prod/to_pharma/remits/835"

LogFile="${LogDir}/bank2pharma-835.log"
FTPCmd="${TempDir}/bank2pharma-835.ftp"
LockFile="${TempDir}/bank2pharma-835.lock"
NewDir="/bak/bank/inbound/new/pharma/835"
ArchiveDir="/bak/bank/inbound/archive/pharma/835"
ErrorFlag=0
ErrorMsg=""
AppTitle="bank2pharma-835"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LockFile} ]; then
    ## Remove lock file so other check space jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  if [ -f ${FTPCmd} ]; then
    ## Remove temp file.
    rm ${FTPCmd} 1>/dev/null 2>&1
  fi
  if [ ${ErrorFlag} -gt 0 ]; then
    ## Display error message to user in case being run manually.
    echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: ${ErrorMsg}" | tee -a ${LogFile}
    ## Email error notice.
    f_sendmail "ERROR ${ErrorFlag}: Script aborted" "${ErrorMsg}"
  fi
  exit ${ErrorFlag}
}

#######################################
##              MAIN                 ##
#######################################

if [ -f ${LockFile} ]; then
  # Lock file detected.  Abort script.
  echo "${AppTitle} script aborted"
  echo "This script tried to run but detected the lock file: ${LockFile}"
  echo "Please check to make sure the file does not remain when not actually running."
  ErrorMsg="This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when not actually running.\n\nIf you find that the script is not running/hung, you can remove it by typing 'rm ${LockFile}'"
  ErrorFlag=1
  echo "`date +%Y-%m-%d_%H:%M:%S` --- ERROR: ${ErrorMsg}" | tee -a ${LogFile}
  f_sendmail "ERROR ${ErrorFlag}: Script aborted" "${ErrorMsg}"
  exit ${ErrorFlag}
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
  echo "ERROR - ssh-agent not pre-loaded with authentication key."
  echo "ERROR - ssh-agent not pre-loaded with authentication key." >> ${LogFile}
  echo "You must load the SSH keys before running this script."
  ErrorFlag=2
  ErrorMsg="ssh-agent not pre-loaded with authentication key."
  f_cleanup
fi

## Download files from the source FTP site.

echo "lcd ${NewDir}" > ${FTPCmd}
echo "cd ${SourceFTP}" >> ${FTPCmd}
echo "ls -l" >> ${FTPCmd}
echo "mget *" >> ${FTPCmd}
echo "rm *" >> ${FTPCmd}
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP download started." >> ${LogFile}
sshpass -e sftp -oBatchMode=no -b ${FTPCmd} ${SourceID}@${SourceIP} 1>> ${LogFile} 2>&1

## NOTE: If there are no files to get, FTP always exits immediately with
##       an error code of 2 and fails to issue any commands after mget.
##       Therefore my only option is to remove the error check which will
##       not notify us if the FTP server is actually inaccessible.

#if [[ $? != 0 ]]; then
#  echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: FTP failed! (Exit Code 2)" >> ${LogFile}
#  ErrorFlag=4
#  ErrorMsg="Source FTP failed."
#  f_cleanup
#fi
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP download complete." >> ${LogFile}

for f in ${NewDir}/*; do
  ## Check and see if there are any files in the folder.
  if [ ! -e "$f" ]; then
    ## There are no files...nothing to do...exit.
    echo "`date +%Y-%m-%d_%H:%M:%S` -- No files to process." >> ${LogFile}
    echo "`date +%Y-%m-%d_%H:%M:%S` Script completed." >> ${LogFile}
    f_cleanup
  fi
  break
done

## Upload the files to the target FTP site.
echo "lcd ${NewDir}" > ${FTPCmd}
echo "cd ${TargetFTP}" >> ${FTPCmd}
echo "mput *" >> ${FTPCmd}
echo "`date +%Y-%m-%d_%H:%M:%S` -- FTP upload started." >> ${LogFile}
sftp -b ${FTPCmd} ${TargetID}@${TargetIP} 1>> ${LogFile} 2>&1
if [[ $? != 0 ]]; then
  echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: FTP failed! (Exit Code 2)" >> ${LogFile}
  ErrorFlag=8
  ErrorMsg="Target FTP upload failed."
  f_cleanup
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
