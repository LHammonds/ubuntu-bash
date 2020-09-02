#!/bin/bash
#############################################
## Name          : secure-mysite.mydomain.com.sh
## Version       : 1.1
## Date          : 2019-09-03
## Author        : LHammonds
## Compatibility : Ubuntu Server 18.04 - 20.04 LTS
## Requirements  : Run as root user
## Purpose       : Ensures ownership and permissions are set correctly.
## Run Frequency : Manual as needed or via crontab schedule.
################ CHANGE LOG #################
## DATE       WHO WHAT WAS CHANGED
## ---------- --- ----------------------------
## 2019-07-23 LTH Created script.
## 2019-09-03 LTH Added full path to executables.
#############################################
wwwdir='/var/www/mysite.mydomain.com'
webuser='www-data'
webgrp='www-data'
rootuser='root'

echo "Setting Ownership..."
/bin/chown -R ${webuser}:${webgrp} ${wwwdir}/
/bin/echo "Setting Folder Permissions..."
/usr/bin/find ${wwwdir}/ -type d -print0 | /usr/bin/xargs -0 /bin/chmod 0750
/bin/echo "Setting File Permissions..."
/usr/bin/find ${wwwdir}/ -type f -print0 | /usr/bin/xargs -0 /bin/chmod 0640
if [ -f ${wwwdir}/.htaccess ]; then
  /bin/chmod 0644 ${wwwdir}/.htaccess
fi
/bin/echo "Permission change complete."
