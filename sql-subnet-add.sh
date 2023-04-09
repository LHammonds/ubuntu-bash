#!/bin/bash
#############################################
## Name          : sql-subnet-add.sh
## Version       : 1.1
## Date          : 2017-04-13
## Author        : LHammonds
## Purpose       : Insert entire class C subnet range into a database.
##               : Default value is "unused" unless it responds to a ping.
## Compatibility : Verified on Ubuntu Server 14.04-22.04 LTS, MariaDB 10.0.x-10.1.x
## Requirements  : Parameter #1 = Subnet.  Ex: 192.168.0
## Run Frequency : As needed
## Exit Codes    : (if multiple errors, value is the addition of codes)
##    0 = success
##    1 = lock file detected
##    2 = not run as root
##    3 = missing parameter
################ CHANGE LOG #################
## DATE       WHO WHAT WAS CHANGED
## ---------- --- ----------------------------
## 2016-02-04 LTH Created script.
## 2017-04-13 LTH Corrected variable casing.
#############################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

LogFile="${LogDir}/${Company}-sql-subnet-add.log"
LockFile="${TempDir}/${Company}-sql-subnet-add.lock"
SQLFile="${TempDir}/${Company}-sql-subnet-add.sql"
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
  echo -e "\nPurpose: Insert a new Class C subnet into the inventory"
  echo -e "         database and check what is active or not."
  echo -e "Usage: ${ScriptName} [${LRED}SubnetPrefix${COLORRESET}]"
  echo -e "Example #1: ${ScriptName} ${LRED}198.203.194${COLORRESET}"
  echo -e "Example #2: ${ScriptName} ${LRED}192.168.107${COLORRESET}"
  echo -e "Example #3: ${ScriptName} ${LRED}172.30.20${COLORRESET}\n"
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

echo "`date +%Y-%m-%d_%H:%M:%S` - SQL Subnet insert for ${Subnet}.0 started." | tee -a ${LogFile}

StartTime="$(date +%s)"

if [ -f "${SQLFile}" ]; then
  ## Delete temp file.
  rm ${SQLFile}
fi

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
    echo -e "${Subnet}.${Index} is ${LRED}inactive${COLORRESET}."
    echo "INSERT INTO tbl_ip (ip,name,mac,type_id,DateModified) VALUES ('${Subnet}.${Buffer}${Index}','unused','unknown',NULL,NOW());" >> ${SQLFile}
  else
    echo -e "${Subnet}.${Index} is ${LGREEN}active${COLORRESET}."
    echo "INSERT INTO tbl_ip (ip,name,mac,type_id,DateModified) VALUES ('${Subnet}.${Buffer}${Index}','unknown but active','unknown',NULL,NOW());" >> ${SQLFile}
  fi
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

echo "`date +%Y-%m-%d_%H:%M:%S` - SQL Subnet insert for ${Subnet}.0 completed." | tee -a ${LogFile}

## Perform cleanup routine.
f_cleanup

