#############################################################
## Name          : servicestart.sh
## Version       : 1.1
## Date          : 2018-04-19
## Author        : LHammonds
## Compatibility : Ubuntu Server 16.04 thru 20.04 LTS
## Requirements  : None
## Purpose       : Start primary services.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2018-04-19 1.0 LTH  Created script.
## 2018-04-19 1.1 LTH  Replaced service with systemctl.
#############################################################
## NOTE: Add whatever services you need started here.
echo "Starting services..."
#systemctl start mariadb
#systemctl start apache2
#systemctl start nagios
#systemctl start vsftpd
sleep 1
