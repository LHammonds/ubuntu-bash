#!/bin/bash
#############################################################
## Name          : check_uptime.sh (Nagios)
## Version       : 1.1
## Date          : 2019-11-13
## Author        : LHammonds
## Compatibility : Ubuntu Server 18.04 - 20.04 LTS
## Requirements  : None
## Optional      : Parameter #1 = Warning threshold in days.
##                 Parameter #2 = Critical threshold in days.
## Purpose       : Check system uptime.
## Run Frequency : As needed
## Exit Codes    :
##   0 = OK
##   1 = Warning
##   2 = Critical
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2019-11-11 1.0 LTH Created script.
## 2019-11-13 1.0 LTH Reading uptime value direct from source file.
#############################################################
ParmWarnDay=$1
ParmCritDay=$2
DefaultWarn=30
DefaultCrit=40
if [ "${ParmWarnDay}" == "" ] || [ "${ParmCritDay}" == "" ]; then
  ## Use default values.
  ParmWarnDay=${DefaultWarn}
  ParmCritDay=${DefaultCrit}
fi
RawSeconds=`cat /proc/uptime | cut -d" " -f1`
TotalSeconds=`bc<<<"scale=0; ${RawSeconds} / 1"`
TotalMinutes=`bc<<<"scale=0; ${TotalSeconds} / 60"`
Hours=`bc<<<"scale=0; ${TotalMinutes} / 60"`
HourMinutes=`bc<<<"scale=0; ${Hours} * 60"`
Minutes=`bc<<<"scale=0; ${TotalMinutes} - (${HourMinutes})"`
Days=`bc<<<"scale=0; ${Hours} / 24"`
if [[ "${Days}" -lt "${ParmWarnDay}" ]]; then
  echo "Uptime OK: ${Days} day(s) ${Hours} hour(s) ${Minutes} minute(s) | uptime=${TotalMinutes}.000000;;;"
  exit 0
fi
if [ "${Days}" -ge "${ParmWarnDay}" ] && [ "${Days}" -le "${ParmCritDay}" ]; then
  echo "Uptime WARNING: ${Days} day(s) ${Hours} hour(s) ${Minutes} minute(s) | uptime=${TotalMinutes}.000000;;;"
  exit 1
fi
if [[ "${Days}" -gt "${ParmCritDay}" ]]; then
  echo "Uptime CRITICAL: ${Days} day(s) ${Hours} hour(s) ${Minutes} minute(s) | uptime=${TotalMinutes}.000000;;;"
  exit 2
fi
