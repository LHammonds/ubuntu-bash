#!/bin/bash
#############################################################
## Name          : secure-nextcloud.sh
## Version       : 1.1
## Date          : 2018-03-29
## Author        : LHammonds
## Compatibility : Ubuntu Server 16.04 LTS, NextCloud 13.0.1
## Purpose       : Ensures ownership and permissions are set correctly.
## Run Frequency : Manual as needed or via crontab schedule.
## NOTE: These settings will prevent the updater from working.
## The only thing needed to change in order for the updater to
## work is to change the rootuser to be the same as webuser.
######################## CHANGE LOG #########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- -----------------------
## 2018-01-11 1.0 LTH Created script.
## 2018-03-29 1.1 LTH Improvements.
#############################################################
wwwdir='/var/www/nextcloud'
datadir='/var/www/nextcloud-data'
webuser='www-data'
webgrp='www-data'
rootuser='root'

if [ ! -f ${wwwdir}/.htaccess ]; then
  echo "ERROR: Missing critical file: ${wwwdir}/.htaccess"
  echo "This file should have been included in the app archive"
fi
if [ ! -f ${wwwdir}/config/.htaccess ]; then
  echo "ERROR: Missing critical file: ${wwwdir}/config/.htaccess"
  echo "This file should have been included in the app archive"
fi
if [ ! -f ${datadir}/.htaccess ]; then
  echo "WARNING: Missing potentially critical file: ${datadir}/.htaccess"
  echo "If the data folder is not directly inside the"
  echo "www folder, then it is not an issue."
fi
echo "Making folders if they are missing..."
if [ ! -d ${wwwdir}/apps ]; then
  mkdir -p ${wwwdir}/apps
fi
if [ ! -d ${wwwdir}/config ]; then
  mkdir -p ${wwwdir}/config
fi
if [ ! -d ${wwwdir}/themes ]; then
  mkdir -p ${wwwdir}/themes
fi
if [ ! -d ${datadir} ]; then
  mkdir -p ${datadir}
fi
echo "Setting Ownership..."
chown -R ${webuser}:${webgrp} ${wwwdir}/
chown -R ${webuser}:${webgrp} ${wwwdir}/apps/
chown -R ${webuser}:${webgrp} ${wwwdir}/config/
chown -R ${webuser}:${webgrp} ${wwwdir}/themes/
chown ${rootuser}:${webgrp} ${wwwdir}/.htaccess
chown ${rootuser}:${webgrp} ${wwwdir}/config/.htaccess
chown ${rootuser}:${webgrp} ${datadir}/.htaccess
echo "Setting Folder Permissions..."
find ${wwwdir}/ -type d -print0 | xargs -0 chmod 0750
find ${datadir}/ -type d -print0 | xargs -0 chmod 0750
echo "Setting File Permissions..."
find ${wwwdir}/ -type f -print0 | xargs -0 chmod 0640
find ${datadir}/ -type f -print0 | xargs -0 chmod 0640
chmod 0644 ${wwwdir}/.htaccess
chmod 0644 ${wwwdir}/config/.htaccess
chmod 0644 ${datadir}/.htaccess
echo "Permission change complete."
