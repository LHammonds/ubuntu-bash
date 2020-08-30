#!/bin/bash
#############################################################
## Name          : image-converter.sh
## Version       : 1.0
## Date          : 2020-08-27
## Author        : LHammonds
## Purpose       : Convert, compress, rename uploaded images & update database.
##                 Used in conjunction with a Xataface web app.
## Compatibility : Verified on Ubuntu Server 20.04 LTS, MariaDB 10.5.5
## Requirements  : imagemagick, MariaDB
## Run Frequency : As needed
## Exit Codes    :
##    0 = success
##    1 = nothing to process
##    2 = root user check failed
##    3 = lock file detected
##    4 = imagemagick or MariaDB not installed
##    5 = missing image
##    6 = unexpected scenario
##    7 = unexpected scenario
##    8 = conversion error
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2020-08-27 1.0 LTH Created script.
#############################################################

## Import common variables and functions. ##
source /var/scripts/common/standard.conf

AppTitle="image-converter"
LogFile="${LogDir}/${Company}-${AppTitle}.log"
LockFile="${TempDir}/${AppTitle}.lock"
ImgDir="/var/www/track.hammondslegacy.com/inv/tables/tbl_image/Filepath"

#######################################
##            FUNCTIONS              ##
#######################################

function f_cleanup()
{
  if [ -f ${LockFile} ];then
    ## Remove lock file so other rsync jobs can run.
    rm ${LockFile} 1>/dev/null 2>&1
  fi
}   ## f_cleanup()
function f_convert()
{
  ## Get the filename
  ImageFile=$(mysql --batch --skip-column-names --database inventory -e "SELECT Filepath FROM tbl_image WHERE Processed=0 ORDER BY Image_ID ASC LIMIT 1;")
  if [ -z "${ImageFile}" ]; then
    ## If there are no unprocessed images, exit script.
    ErrorFlag=1
    return
  fi
  ## Get the compression option
  Compress=$(mysql --batch --skip-column-names --database inventory -e "SELECT Compress FROM tbl_image WHERE Processed=0 ORDER BY Image_ID ASC LIMIT 1;")
  ## Get the record ID
  ImageID=$(mysql --batch --skip-column-names --database inventory -e "SELECT Image_ID FROM tbl_image WHERE Processed=0 ORDER BY Image_ID ASC LIMIT 1;")
  if [ ! -f ${ImgDir}/${ImageFile} ]; then
    echo "[ERROR] ${ImageID} ${ImageFile} does NOT exist." >> ${LogFile}
    f_sendmail "[ERROR] Image-Conversion Failure - Missing image" "Image ID = ${ImageID}, Filename = ${ImgDir}/${ImageFile}\n\nImage processing cannot continue until this has been resolved manually."
    ErrorFlag=5
    return
  fi
  if [ "${ImageFile}" == "${ImageID}" ]; then
    echo "[ERROR] Image name already matches the record ID" >> ${LogFile}
    f_sendmail "[ERROR] Image-Conversion Failure - Unexpected case" "Image ID = ${ImageID}, Filename = ${ImgDir}/${ImageFile}\n\nImage seems to already be processed but the process flag in the table has not be set.  Image processing cannot continue until this has been resolved manually."
    ErrorFlag=6
    return
  fi
  if [ -f "${ImgDir}/${ImageID}.jpg" ]; then
    echo "[ERROR] ${ImageID}.jpg already exists." >> ${LogFile}
    f_sendmail "[ERROR] Image-Conversion Failure - Unexpected case" "Image ID = ${ImageID}, Filename = ${ImgDir}/${ImageID}.jpg\n\nTarget image already exists.  Image processing cannot continue until this has been resolved manually."
    ErrorFlag=7
    return
  fi
  ## Convert, compress and rename the image.
  cd ${ImgDir}
  if [ "${Compress}" -eq "1" ]; then
    ## Image should have compression applied.
    convert -quality 70 ${ImageFile} ${ImageID}.jpg
  else
    ## Do NOT apply compression.
    convert -quality 100 ${ImageFile} ${ImageID}.jpg
  fi
  if [ ! -f "${ImageID}.jpg" ]; then
    echo "[ERROR] ${ImageID}.jpg failed to be created." >> ${LogFile}
    f_sendmail "[ERROR] Image-Conversion Failure - convert error" "Image ID = ${ImageID}, Filename = ${ImgDir}/${ImageFile}\n\nCould not convert file to ${ImageID}.jpg.  Image processing cannot continue until this has been resolved manually."
    ErrorFlag=8
    return
  fi
  chown www-data:root ${ImageID}.jpg
  chmod 444 ${ImageID}.jpg
  ## Document the file sizes.
  SizeOrg=$(wc -c ${ImgDir}/${ImageFile} | awk '{print $1}')
  SizeNew=$(wc -c ${ImgDir}/${ImageID}.jpg | awk '{print $1}')
  echo " - ${ImageID}.jpg - O:${SizeOrg},N:${SizeNew}" >> ${LogFile}
  mysql --batch --database inventory -e "UPDATE tbl_image SET FilePath='${ImageID}.jpg',Processed=1 WHERE Image_ID=${ImageID};"
  ## Remove the old file.
  rm ${ImgDir}/${ImageFile}
}   ## f_convert()

#######################################
##       PREREQUISITE CHECKS         ##
#######################################

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo "[ERROR] Root user required to run this script."
  exit 2
fi
if [ -f ${LockFile} ]; then
  ## Program lock file detected.  Abort script.
  f_sendmail "${AppTitle} aborted - Lock File" "This script tried to run but detected the lock file: ${LockFile}\n\nPlease check to make sure the file does not remain when this script is not actually running."
  exit 3
else
  ## Create the lock file to ensure only one script is running at a time.
  echo "`date +%Y-%m-%d_%H:%M:%S` ${ScriptName}" > ${LockFile}
fi
## Make sure required tools are installed.
if [ ! -f "/usr/bin/convert" ]; then
  ## Required package (imagemagick) not installed.
  echo "`date +%Y-%m-%d_%H:%M:%S` [ERROR] imagemagick package not installed.  Please install by typing 'sudo apt install imagemagick'" >> ${LogFile}
  f_cleanup
  exit 4
fi
if [ ! -f "/usr/bin/mysql" ]; then
  ## Required package (mariadb) not installed.
  echo "`date +%Y-%m-%d_%H:%M:%S` [ERROR] database package not installed.  Please install by typing 'sudo apt install mariadb-server'" >> ${LogFile}
  f_cleanup
  exit 4
fi

#######################################
##           MAIN PROGRAM            ##
#######################################

echo "`date +%Y-%m-%d_%H:%M:%S` - ${AppTitle} started." >> ${LogFile}
ErrorFlag=0
while [ ${ErrorFlag} -eq 0 ]; do
  f_convert
done
echo "`date +%Y-%m-%d_%H:%M:%S` - ${AppTitle} completed." >> ${LogFile}
f_cleanup
exit ${ErrorFlag}
