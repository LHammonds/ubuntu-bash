#!/bin/bash
#############################################################
## Name          : enable-firewall.sh
## Version       : 1.2
## Date          : 2022-05-31
## Author        : LHammonds
## Compatibility : Verified on Ubuntu Server 22.04 LTS
## Requirements  : Run as root
## Purpose       : Restore and enable firewall.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2015-08-28 1.0 LTH Created script.
## 2017-04-13 1.1 LTH Added comments in rules.
## 2022-05-31 1.2 LTH Replaced echo statements with printf.
#############################################################

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  printf "\nERROR: Root user required to run this script.\n"
  printf "Type 'sudo su' to temporarily become root user.\n"
  exit
fi

clear
printf "\nResetting Firewall to factory default\n"
printf "y\n" | ufw reset 1>/dev/null 2>&1
ufw default deny incoming 1>/dev/null 2>&1
ufw default allow outgoing 1>/dev/null 2>&1
printf "Allowing SSH from only LAN connections\n"
ufw allow from 192.168.107.0/24 to any port 22 comment 'SSH via LAN' 1>/dev/null 2>&1
ufw allow from 192.168.108.0/24 to any port 22 comment 'SSH via LAN' 1>/dev/null 2>&1
printf "Allowing Samba file sharing connections\n"
ufw allow proto tcp to any port 135,139,445 comment 'Samba Share' 1>/dev/null 2>&1
ufw allow proto udp to any port 137,138 comment 'Samba Share' 1>/dev/null 2>&1
printf "Allowing NFS Sharing\n"
ufw allow proto tcp to any port 2049 comment 'NFS Share' 1>/dev/null 2>&1
ufw allow proto udp to any port 2049 comment 'NFS Share' 1>/dev/null 2>&1
printf "Allowing Nagios connections\n"
#ufw allow from 192.168.107.21 to any port 12489 comment 'Nagios' 1>/dev/null 2>&1
#ufw allow from 192.168.107.21 proto tcp to any port 5666 comment 'Nagios' 1>/dev/null 2>&1
printf "Adding Application-specific rules\n"
#printf "Adding MariaDB/MySQL rules\n"
#ufw allow from 192.168.107.0/24 proto tcp to any port 3306 comment 'MariaDB via LAN' 1>/dev/null 2>&1
#ufw allow from 192.168.108.0/24 proto tcp to any port 3306 comment 'MariaDB via LAN' 1>/dev/null 2>&1
#printf "Adding FTP/FTPS rules\n"
#ufw allow proto tcp to any port 990 comment 'FTPS' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 21 comment 'FTP' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 2000:2020 comment 'FTP Passive' 1>/dev/null 2>&1
#printf "Adding Web Server rules\n"
#ufw allow proto tcp to any port 80 comment 'HTTP Service' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 8080 comment 'HTTP ALT Service' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 443 comment 'HTTP Service' 1>/dev/null 2>&1
printf "Enabling firewall\n"
printf "y\n" | ufw enable 1>/dev/null 2>&1
printf "Firewall enabled and all rules have been configured.\n"
exit 0
