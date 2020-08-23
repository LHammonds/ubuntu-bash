#!/bin/bash
#############################################################
## Name          : togglemount.sh
## Version       : 1.3
## Date          : 2020-05-01
## Author        : LHammonds
## Compatibility : Ubuntu Server 10.04 thru 18.04 LTS
## Purpose       : Toggle the mount status of a pre-configured backup mount.
## Run Frequency : Manual as needed.
## Exit Codes    :
##   0 = success
##   1 = failure
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2011-11-05 1.0 LTH Created script.
## 2017-03-17 1.1 LTH Changed variables to CamelCase.
## 2019-07-18 1.2 LTH Updated reference file online.txt to offline.txt
## 2020-05-01 1.3 LTH Test file now uses the common variable name.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf
ErrorFlag=0

if [ -f ${OffsiteTestFile} ]; then
  echo "Remote share is not mounted.  Mounting share now..."
  f_mount
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    echo "Mount failed.  Listing contents:"
    ErrorFlag=1
  else
    echo "Mount successful.  Listing contents:"
  fi
else
  echo "Remote share is mounted.  Dismounting share now..."
  f_umount
  sleep 2
  if [ -f ${OffsiteTestFile} ]; then
    echo "Dismount successful.  Listing contents:"
  else
    echo "Dismount failed.  Listing contents:"
    ErrorFlag=1
  fi
fi
ls -l ${OffsiteDir}
exit ${ErrorFlag}
