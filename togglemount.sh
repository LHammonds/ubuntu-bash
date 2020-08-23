#!/bin/bash
#############################################################
## Name          : togglemount.sh
## Version       : 1.1
## Date          : 2017-03-17
## Author        : LHammonds
## Compatibility : Ubuntu Server 10.04 - 16.04 LTS
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
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf
ErrorFlag=0
if [ -f ${OffsiteDir}/offline.txt ]; then
  echo "Windows share is not mounted.  Mounting share now..."
  f_mount
  sleep 2
  if [ -f ${OffsiteDir}/online.txt ]; then
    echo "Mount successful.  Listing contents:"
  else
    echo "Mount failed.  Listing contents:"
    ErrorFlag=1
  fi
else
  echo "Windows share is mounted.  Dismounting share now..."
  f_umount
  sleep 2
  if [ -f ${OffsiteDir}/offline.txt ]; then
    echo "Dismount successful.  Listing contents:"
  else
    echo "Dismount failed.  Listing contents:"
    ErrorFlag=1
  fi
fi
ls -l ${OffsiteDir}
exit ${ErrorFlag}
