#!/bin/bash
#############################################################
## Name          : le-symlink-create.sh
## Version       : 1.2
## Date          : 2022-08-10
## Author        : LHammonds
## Purpose       : Recreate Let's Encrypt symlinks to
##                 certificates after a server migration.
## Compatibility : Verified on Ubuntu Server 18.04 thru 22.04 LTS
## Run Frequency : Once after migration to new machine.
## Parameters    : None
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2020-05-19 1.0 LTH Created script.
## 2020-10-05 1.1 LTH "If (not) exist" logic added.
## 2022-08-10 1.2 LTH Better automation. Only need to set BaseDir.
#############################################################

BaseDir="/etc/letsencrypt"
ArchiveDir="${BaseDir}/archive"
LiveDir="${BaseDir}/live"

function f_remove () {
  if [ -e ${1} ]; then
    rm ${1}
  fi
} ## f_remove() ##

function f_fixkey () {
  ## Param 1 = Web Folder
  ## Param 2 = Filename
  ## Param 3 = Keyname
  f_remove ${LiveDir}/${1}/${3}
  ln -s ${ArchiveDir}/${1}/${2} ${LiveDir}/${1}/${3}
} ## f_fixkey() ##

function f_getlatest () {
  ## Param 1 = Directory ##
  ## Param 2 = File pattern ##
  ## Output = Newest file matching pattern ##
  unset -v latest
  for file in ${1}/${2}; do
    [[ $file -nt $latest ]] && latest=$file
  done
  ## Remove parent path from filename and return value ##
  printf "${latest#${1}/}"
} ## f_getlatest() ##

## Loop through every folder in BaseDir ##
find ${ArchiveDir} -maxdepth 1 -mindepth 1 -type d | while read CurrentDir; do
  ## Remove the parent path from the current directory ##
  WebDir=${CurrentDir#${ArchiveDir}/}
  if [ ! -d ${LiveDir}/${WebDir} ]; then
    mkdir -p ${LiveDir}/${WebDir}
  fi
  printf "Fixing certs for ${WebDir}\n"
  f_fixkey "${WebDir}" "$(f_getlatest "${ArchiveDir}/${WebDir}" "cert*.pem")" "cert.pem"
  f_fixkey "${WebDir}" "$(f_getlatest "${ArchiveDir}/${WebDir}" "chain*.pem")" "chain.pem"
  f_fixkey "${WebDir}" "$(f_getlatest "${ArchiveDir}/${WebDir}" "fullchain*.pem")" "fullchain.pem"
  f_fixkey "${WebDir}" "$(f_getlatest "${ArchiveDir}/${WebDir}" "privkey*.pem")" "privkey.pem"
done
