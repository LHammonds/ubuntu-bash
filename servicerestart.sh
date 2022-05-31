#!/bin/bash
#############################################################
## Name          : servicerestart.sh
## Version       : 1.1
## Date          : 2018-04-19
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : None
## Purpose       : Stop/Start primary services.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-08 1.0 LTH Created script.
## 2018-04-19 1.1 LTH Spit stop/start code into individual scripts.
#############################################################
## Import standard variables and functions. ##
source /var/scripts/common/standard.conf
clear
${ScriptDir}/prod/servicestop.sh
${ScriptDir}/prod/servicestart.sh
