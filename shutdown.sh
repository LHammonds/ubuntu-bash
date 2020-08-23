#!/bin/bash
#############################################################
## Name          : shutdown.sh
## Version       : 1.1
## Date          : 2018-05-08
## Author        : LHammonds
## Compatibility : Ubuntu Server 16.04 thru 18.04 LTS
## Requirements  : Run as root
## Purpose       : Notify logged in users, stop services and power off server.
## Run Frequency : As needed
## Parameters    :
##    1 = (Optional) Expected downtime in minutes.
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2018-04-19 1.0 LTH  Created script.
## 2018-05-08 1.1 LTH  Added broadcast message and loop function.
#############################################################

## Import standard variables and functions. ##
source /var/scripts/common/standard.conf

## Define local variables.
LogFile="${LogDir}/${Company}-shutdown.log"
DefaultDowntime=5

#######################################
##            FUNCTIONS              ##
#######################################

function f_loop()
{
  LoopCount=$1
  for LoopIndex in $(seq ${LoopCount} -1 1)
  do
    echo ${LoopIndex}
    sleep 1
  done
} ## f_loop

function f_showhelp()
{
  echo -e "NOTE: Default expected downtime is ${DefaultDowntime} minutes and is optional.\n"
  echo -e "Usage : ${ScriptName} ExpectedDowntimeInMinutes\n"
  echo -e "Example: ${ScriptName} 5\n"
  exit
} ## f_showhelp

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "\nERROR: Root user required to run this script.\n"
  echo -e "Type 'sudo su' to temporarily become root user.\n"
  exit
fi

#######################################
##           MAIN PROGRAM            ##
#######################################

## Check existance of optional command-line parameter.
case "$1" in
  --help|-h|-?)
    f_showhelp
    ;;
  *[0-9]*)
    ## If parameter is a number, allow override.
    TimeOverride=$1
    ;;
  *)
    ## Invalid input supplied. Discard.
    ;;
esac

#clear
echo ""
if [ -z ${TimeOverride+8} ]; then
  ## No override given.  Display user input prompt.
  echo -e "How many minutes do you expect the server to be offline? (default=${DefaultDowntime})"
  read -t 30 TimeInput
  ReturnCode=$?
  if [[ ${ReturnCode} -gt 128 ]]; then
    ## User input timed out. Use default.
    let OfflineTime=${DefaultDowntime}
  else
    ## Evaluate the user-supplied input.
    case ${TimeInput} in
      *[0-9]*)
        ## User-supplied input is a number.  Use it instead of default.
        let OfflineTime="${TimeInput}" ;;
      *)
        ## User-supplied input is invalid.  Use default.
        let OfflineTime=${DefaultDowntime} ;;
    esac
  fi
else
  ## Use commandline override.
  OfflineTime=${TimeOverride}
fi
## Broadcasting message to any other users logged in via SSH.
clear
echo "WARNING: Shutting down server. Should be back online in ${OfflineTime} minutes" | wall

echo "`date +%Y-%m-%d_%H:%M:%S` - Shutdown initiated." | tee -a ${LogFile}
${ScriptDir}/prod/servicestop.sh
echo "Shutting down..."
f_loop 10
shutdown -P now
