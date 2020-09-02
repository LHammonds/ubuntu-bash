#############################################################
## Name          : servicestop.sh
## Version       : 1.1
## Date          : 2018-04-19
## Author        : LHammonds
## Compatibility : Ubuntu Server 16.04 thru 20.04 LTS
## Requirements  : None
## Purpose       : Stop primary services.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-08 1.0 LTH  Created script.
## 2018-04-19 1.1 LTH  Replaced service with systemctl.
#############################################################
## NOTE: Configure whatever services you need stopped here.
echo "Stopping services..."
#systemctl stop vsftpd
#systemctl stop nagios
#systemctl stop apache2
#systemctl stop mariadb
sleep 1
