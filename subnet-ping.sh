#!/bin/bash
#############################################
## Name          : subnet-ping.sh
## Version       : 1.0
## Date          : 2017-07-11
## Author        : LHammonds
## Purpose       : Ping and log for active IPs for a specified class C subnet.
## Compatibility : Verified on Ubuntu Server 16.04-22.04 LTS
## Requirements  : Parameter #1 = Subnet.  Ex: 192.168.0
## Run Frequency : As needed
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = missing parameter
################ CHANGE LOG #################
## DATE       WHO WHAT WAS CHANGED
## ---------- --- ----------------------------
## 2017-07-11 LTH Created script.
#############################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/${Company}-subnet-ping.log"
SubnetStart=1
SubnetEnd=256
ErrorFlag=0

#######################################
##            FUNCTIONS              ##
#######################################
function f_cleanup()
{
  exit ${ErrorFlag}
}

function f_showhelp()
{
  echo -e "\nPurpose: Ping class C subnet for active responses."
  echo -e "Usage: ${ScriptName} [${LRED}SubnetPrefix${COLORRESET}]"
  echo -e "Example #1: ${ScriptName} ${LRED}198.203.194${COLORRESET}"
  echo -e "Example #2: ${ScriptName} ${LRED}192.168.107${COLORRESET}"
  echo -e "Example #3: ${ScriptName} ${LRED}172.30.20${COLORRESET}\n"
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Check existance of required command-line parameters.
case "$1" in
  "")
    f_showhelp
    ErrorFlag=2
    f_cleanup
    ;;
  --help|-h|-?)
    f_showhelp
    ErrorFlag=2
    f_cleanup
    ;;
  *)
    Subnet=$1
    ;;
esac

echo "`date +%Y-%m-%d_%H:%M:%S` - MySQL Subnet ping for ${Subnet}.0 started." | tee -a ${LogFile}

StartTime="$(date +%s)"

# for loop, 1-255, create data insert statements into SQLFile
Index=${SubnetStart}
while [ ${Index} -lt ${SubnetEnd} ]; do
  ## Add a buffer to the last octet to make it sort nicely.
  case ${#Index} in
    [1])
    Buffer="00"
    ;;
    [2])
    Buffer="0"
    ;;
    *)
    Buffer=""
    ;;
  esac

  ## See if IP addresses are active or inactive.
  ping -c 1 -W 1 ${Subnet}.${Index} 1>/dev/null 2>&1
  ReturnCode=$?
  if [ ${ReturnCode} != 0 ]; then
    echo -e "${Subnet}.${Index} is inactive." | tee -a ${LogFile}
  else
    echo -e "${Subnet}.${Index} is active." | tee -a ${LogFile}
  fi
  let Index=${Index}+1
done

## Calculate total time for job.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

echo "`date +%Y-%m-%d_%H:%M:%S` --- Total run time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" | tee -a ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - Subnet ping for ${Subnet}.0/24 completed." | tee -a ${LogFile}
echo "Log file = ${LogFile}"

## Perform cleanup routine.
f_cleanup
