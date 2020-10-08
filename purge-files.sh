#!/bin/bash
#############################################################
## Name          : purge-files.sh
## Version       : 1.0
## Date          : 2020-10-08
## Author        : LHammonds
## Purpose       : Purge files older than x days
## Compatibility : Verified on to work on Ubuntu Server 20.04 LTS
## Requirements  : None
## Run Frequency : As needed (such as daily)
## Exit Codes    : None
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2020-10-08 1.0 LTH Created script.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

Title="${Company}-purge-files"
LogFile="${LogDir}/${Title}.log"
Default=30

#######################################
##            FUNCTIONS              ##
#######################################

function f_purge()
{
  Folder=$1
  FilePattern=$2
  Days=$3
  ## Document files to be deleted in the log.
  echo " - [INFO] ${Folder}/${FilePattern} +${Days}" >> ${LogFile}
  /usr/bin/find ${Folder} -maxdepth 1 -name "${FilePattern}" -mtime +${Days} -type f -exec /usr/bin/ls -l {} \; >> ${LogFile}
  /usr/bin/find ${Folder} -maxdepth 1 -name "${FilePattern}" -mtime +${Days} -type f -delete 1>/dev/null 2>&1

}  ## f_purge() ##

#######################################
##           MAIN PROGRAM            ##
#######################################
echo "`date +%Y-%m-%d_%H:%M:%S` - Purge started." >> ${LogFile}
f_purge /bak/srv-database/remote *.enc ${Default}
f_purge /bak/srv-database/remote *.sha512 ${Default}
f_purge /bak/srv-web/remote *.gz 14
echo "`date +%Y-%m-%d_%H:%M:%S` - Purge completed." >> ${LogFile}
