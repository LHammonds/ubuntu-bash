#!/bin/bash
#############################################################
## Name          : servicerestart.sh
## Version       : 1.0
## Date          : 2013-01-08
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04 LTS
## Requirements  : None
## Purpose       : Cleanly stop/start primary services.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-08 1.0 LTH Created script.
#############################################################
## Import standard variables and functions. ##
source /var/scripts/common/standard.conf
clear
${ScriptDir}/prod/servicestop.sh
${ScriptDir}/prod/servicestart.sh
