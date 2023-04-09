#!/bin/bash
#############################################
## Name          : sql-subnet-mod.sh
## Version       : 1.1
## Date          : 2017-04-13
## Author        : LHammonds
## Purpose       : Update the name field for a range of Class C IPs (e.g. DHCP)
## Compatibility : Verified on Ubuntu Server 14.04-22.04 LTS, MariaDB 10.0.x-10.1.x
## Requirements  : Parameter #1 = Subnet.  Ex: 192.168.0
##               : Parameter #2 = Start IP
##               : Parameter #3 = End IP
##               : Parameter #4 = Name that will replace all names in range.
## Run Frequency : As needed
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = lock file detected
##    2 = not run as root
##    3 = missing parameter
################ CHANGE LOG #################
## DATE       WHO WHAT WAS CHANGED
## ---------- --- ----------------------------
## 2016-03-01 LTH Created script.
## 2017-04-13 LTH Corrected variable casing.
#############################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/${Company}-sql-subnet-mod.log"
LockFile="${TempDir}/${Company}-sql-subnet-mod.lock"
SQLFile="${TempDir}/${Company}-sql-subnet-mod.sql"
SubnetStart=1
SubnetEnd=256
ErrorFlag=0

#######################################
##            FUNCTIONS              ##
#######################################
function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other rsync jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
  exit ${ErrorFlag}
}

function f_showhelp()
{
  echo -e "\nPurpose: Update the name field for a range of Class C IPs."
  echo -e "Usage: ${ScriptName} [${LRED}SubnetPrefix${COLORRESET}] [${LGREEN}StartIP${COLORRESET}] [${LBLUE}EndIP${COLORRESET}] [${LYELLOW}Name${COLORRESET}]"
  echo -e "Example #1: ${ScriptName} ${LRED}198.203.194${COLORRESET} ${LGREEN}100${COLORRESET} ${LBLUE}200${COLORRESET} ${LYELLOW}DHCP${COLORRESET}"
  echo -e "Example #2: ${ScriptName} ${LRED}192.168.107${COLORRESET} ${LGREEN}1${COLORRESET} ${LBLUE}254${COLORRESET} ${LYELLOW}unused${COLORRESET}"
  echo -e "Example #3: ${ScriptName} ${LRED}172.30.20${COLORRESET} ${LGREEN}50${COLORRESET} ${LBLUE}100${COLORRESET} ${LYELLOW}DHCP${COLORRESET}\n"
}

#######################################
##           MAIN PROGRAM            ##
#######################################

## Binaries ##
MYSQL="$(which mysql)"

if [ -f ${LockFile} ]; then
  ## Program lock file detected.  Abort script.
  echo "Lock file detected, aborting script."
  exit 1
else
  ## Create the lock file to ensure only one script is running at a time.
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "ERROR: Root user required to run this script.\n"
  ErrorFlag=2
  f_cleanup
fi

## Check existance of required command-line parameters.
case "$1" in
  "")
    f_showhelp
    ErrorFlag=3
    f_cleanup
    ;;
  --help|-h|-?)
    f_showhelp
    ErrorFlag=3
    f_cleanup
    ;;
  *)
    Subnet=$1
    ;;
esac

case "$2" in
  "")
    f_showhelp
    ErrorFlag=3
    f_cleanup
    ;;
  *)
    IPStart=$2
    ;;
esac

case "$3" in
  "")
    f_showhelp
    ErrorFlag=3
    f_cleanup
    ;;
  *)
    IPEnd=$3
    ;;
esac

case "$4" in
  "")
    f_showhelp
    ErrorFlag=3
    f_cleanup
    ;;
  *)
    IPName=$4
    ;;
esac

echo "`date +%Y-%m-%d_%H:%M:%S` - SQL Subnet modify for ${Subnet}.${IPStart}-${IPEnd} = ${IPName} started." | tee -a ${LogFile}

StartTime="$(date +%s)"

if [ -f "${SQLFile}" ]; then
  ## Delete temp file.
  rm ${SQLFile}
fi

# for loop, 1-255, create data insert statements into SQLFile
Index=${IPStart}
while [ ${Index} -le ${IPEnd} ]; do
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
  echo "UPDATE tbl_ip SET name = '${IPName}' WHERE ip = '${Subnet}.${Buffer}${Index}';" >> ${SQLFile}
  let Index=${Index}+1
done

cat ${SQLFile} | ${MYSQL} inventory;

if [ -f "${SQLFile}" ]; then
  ## Delete temp file.
  rm ${SQLFile}
fi

## Calculate total time for backup.
FinishTime="$(date +%s)"
ElapsedTime="$(expr ${FinishTime} - ${StartTime})"
Hours=$((${ElapsedTime} / 3600))
ElapsedTime=$((${ElapsedTime} - ${Hours} * 3600))
Minutes=$((${ElapsedTime} / 60))
Seconds=$((${ElapsedTime} - ${Minutes} * 60))

echo "`date +%Y-%m-%d_%H:%M:%S` --- Total run time: ${Hours} hour(s) ${Minutes} minute(s) ${Seconds} second(s)" | tee -a ${LogFile}

echo "`date +%Y-%m-%d_%H:%M:%S` - SQL Subnet modify for ${Subnet}.${IPStart}-${IPEnd} = ${IPName} completed." | tee -a ${LogFile}

## Perform cleanup routine.
f_cleanup
