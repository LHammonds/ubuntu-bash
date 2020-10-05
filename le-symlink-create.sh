#!/bin/bash
#############################################################
## Name : le-symlink-create.sh
## Version : 1.1
## Date : 2020-10-05
## Author : LHammonds
## Purpose : Recreate Let's Encrypt symlinks to certificates after a server migration.
## Compatibility : Verified on Ubuntu Server 18.04 thru 20.04 LTS
## Run Frequency : Once after migration to new machine.
## Parameters : None
## Exit Codes : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2020-05-19 1.0 LTH Created script.
## 2020-10-05 1.1 LTH "If (not) exist" logic added.
#############################################################

function f_remove () {
  if [ -e ${1} ]; then
    rm ${1}
  fi
}

function f_site () {
  certdir="/etc/letsencrypt"
  if [ ! -d ${certdir}/live/${1} ]; then
    mkdir -p ${certdir}/live/${1}
  fi
  f_remove ${certdir}/live/${1}/cert.pem
  f_remove ${certdir}/live/${1}/chain.pem
  f_remove ${certdir}/live/${1}/fullchain.pem
  f_remove ${certdir}/live/${1}/privkey.pem
  ln -s ${certdir}/archive/${1}/cert${2}.pem ${certdir}/live/${1}/cert.pem
  ln -s ${certdir}/archive/${1}/chain${2}.pem ${certdir}/live/${1}/chain.pem
  ln -s ${certdir}/archive/${1}/fullchain${2}.pem ${certdir}/live/${1}/fullchain.pem
  ln -s ${certdir}/archive/${1}/privkey${2}.pem ${certdir}/live/${1}/privkey.pem
}

f_site "files.mydomain.com" "1"
f_site "images.mydomain.com" "4"
f_site "forum.mydomain.com" "1"
f_site "games.mydomain.com" "5"
f_site "kvm.mydomain.com" "1"
f_site "tv.mydomain.com" "3"
