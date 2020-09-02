#!/bin/bash
#############################################################
## Name          : ftp-company2app.sh
## Version       : 1.0
## Date          : 2016-08-24
## Author        : LHammonds
## Contacts      : Redacted
## Purpose       : Move files from external company to App
## Compatibility : Verified on Ubuntu Server 12.04 LTS
## Requirements  : sendemail
## Run Frequency : Early morning 5am to 8am
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = failure to mount remote folder
##    2 = failure to FTP files
## Background Information:
## -----------------------
## EmployeeName will selectively export certain files from App and will
## export the files at night. The files will be picked up by these
## scripts on the FTP server. External company will then pick up the files
## and process them.  Once finished, they will place on the FTP server.
## These scripts will then push those files back to the App server.
##
## Client Connection Settings:
## ---------------------------
## WinSCP 5.9.2
##  * File Protocol: FTP
##  * Encryption: TLS/SSL Explicit encryption
##  * Host name: 123.456.789.012 (IP Redacted)
##  * Port: 990
##
## FileZilla 3.22.1
##  * Host: 123.456.789.012 (IP Redacted)
##  * Port: 990
##  * Protocol: FTP - File Transfer Protocol
##  * Encryption: Require explicit FTP over TLS
##  * Login Type: Normal
##
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2016-08-24 1.0 LTH Created script.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/company2app.log"
OffsiteDir="/mnt/srv-app/"
OffsiteShare="//srv-app/linux"
OffsiteTestFile="${OffsiteDir}/offline.txt"
SourceDir="/srv/sftp/company/public/outbound"
TargetDir="${OffsiteDir}/company/inbound"
Title="company2app"

echo "`date +%Y-%m-%d_%H:%M:%S` Script started." >> ${LogFile}

## Mount the remote share.
if [ -f ${OffsiteTestFile} ]; then
  ## Not currently mounted.  Mount the share folder.
  mount -t cifs "${OffsiteShare}" "${OffsiteDir}" --options nouser,rw,nofail,noexec,credentials=/etc/cifspw
  ## Give the system time to mount the folder.
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    ## Mount failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: Cannot mount remote share folder." >> ${LogFile}
    f_sendmail "[Failed] ${Title}" "Script exit code 2, failure to mount offsite folder."
    exit 2
  fi
fi

for f in ${SourceDir}/*; do
  ## Check and see if there are any files in the folder.
  if [ ! -e "$f" ]; then
    ## There are no files...nothing to do...exit.
    echo "`date +%Y-%m-%d_%H:%M:%S` Script aborted, no files to move." >> ${LogFile}
    echo "Unmounting remote file share..."
    umount ${OffsiteDir}
    exit 0
  fi
  break
done

## Transfer files to destination
echo "`date +%Y-%m-%d_%H:%M:%S` -- Moving files to ${TargetDir}" >> ${LogFile}
for f in ${SourceDir}/*; do
  mv --verbose "$f" ${TargetDir}/. >> ${LogFile}
  if [[ $? != 0 ]]; then
    echo "`date +%Y-%m-%d_%H:%M:%S` ** ERROR: Move failed! Code: $?" >> ${LogFile}
    f_sendmail "[Failed] ${Title}" "Script exit code 3, failure to move files."
    exit 3
  fi
done

## Unmount the remote share.
if [ ! -f ${OffsiteTestFile} ]; then
  ## Currently mounted.  Dismount the share folder.
  umount ${OffsiteDir}
  sleep 2
  if [ ! -f ${OffsiteTestFile} ]; then
    ## Unmount failed.
    echo "`date +%Y-%m-%d_%H:%M:%S` -- WARNING: Cannot unmount remote share folder. (Exit Code 1)" >> ${LogFile}
    f_sendmail "[Warning] ${Title}" "Script exit code 5, failure to unmount remote share."
    exit 5
  fi
fi

echo "`date +%Y-%m-%d_%H:%M:%S` Script finished." >> ${LogFile}
