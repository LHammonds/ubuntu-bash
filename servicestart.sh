#!/bin/bash
#############################################################
## Name          : servicestart.sh
## Version       : 1.2
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : None
## Purpose       : Start primary services.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2018-04-19 1.0 LTH Created script.
## 2019-09-24 1.1 LTH Switched "service" to "systemctl" format.
## 2022-05-31 1.2 LTH Replaced echo statements with printf.
#############################################################
## NOTE: Add whatever services you need started here.
printf "Starting services...\n"
#systemctl start mysql
#systemctl start apache2
#systemctl start nagios
#systemctl start vsftpd
sleep 1
