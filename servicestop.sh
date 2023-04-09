#!/bin/bash
#############################################################
## Name          : servicestop.sh
## Version       : 1.2
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : None
## Purpose       : Stop primary services.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ----------------------------
## 2013-01-08 1.0 LTH Created script.
## 2019-09-24 1.1 LTH Switched "service" to "systemctl" format.
## 2022-05-31 1.2 LTH Replaced echo statements with printf.
#############################################################
## NOTE: Configure whatever services you need stopped here.
printf "Stopping services...\n"
#systemctl stop vsftpd
#systemctl stop nagios
#systemctl stop apache2
#systemctl stop mysql
sleep 1
