#!/bin/bash
#############################################################
## Name : le-symlink-create.sh
## Version : 1.0
## Date : 2020-05-19
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
#############################################################

function f_site () {
  certdir="/etc/letsencrypt"
  rm ${certdir}/live/${1}/cert.pem
  rm ${certdir}/live/${1}/chain.pem
  rm ${certdir}/live/${1}/fullchain.pem
  rm ${certdir}/live/${1}/privkey.pem
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
