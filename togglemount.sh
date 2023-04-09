#!/bin/bash
#############################################################
## Name          : togglemount.sh
## Version       : 1.4
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Purpose       : Toggle the mount status of a pre-configured backup mount.
## Run Frequency : Manual as needed.
## Exit Codes    :
##   0 = success
##   1 = failure
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2011-11-05 1.0 LTH Created script.
## 2017-03-17 1.1 LTH Updated variable standards.
## 2019-07-18 1.2 LTH Updated reference file online.txt to offline.txt
## 2020-05-01 1.3 LTH Test file now uses the common variable name.
## 2022-05-31 1.4 LTH Replaced echo statements with printf.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf
ErrorFlag=0

if [ -f ${OffsiteTestFile} ]; then
  printf "Remote share is not mounted.  Mounting share now...\n"
  f_mount
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    printf "Mount failed.  Listing contents:\n"
    ErrorFlag=1
  else
    printf "Mount successful.  Listing contents:\n"
  fi
else
  printf "Remote share is mounted.  Dismounting share now...\n"
  f_umount
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    printf "Dismount successful.  Listing contents:\n"
  else
    printf "Dismount failed.  Listing contents:\n"
    ErrorFlag=1
  fi
fi
ls -l ${OffsiteDir}
exit ${ErrorFlag}
