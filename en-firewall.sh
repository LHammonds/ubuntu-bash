#!/bin/bash
#############################################################
## Name          : enable-firewall.sh
## Version       : 1.1
## Date          : 2017-04-13
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04 - 16.04 LTS
## Requirements  : Run as root
## Purpose       : Restore and enable firewall.
## Run Frequency : As needed
## Exit Codes    : None
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2015-08-28 1.0 LTH  Created script.
## 2017-04-13 1.1 LTH  Added comments in rules.
#############################################################

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "\nERROR: Root user required to run this script.\n"
  echo -e "Type 'sudo su' to temporarily become root user.\n"
  exit
fi

clear
echo ""
echo "Resetting Firewall to factory default"
echo y | ufw reset 1>/dev/null 2>&1
ufw default deny incoming 1>/dev/null 2>&1
ufw default allow outgoing 1>/dev/null 2>&1
echo "Allowing SSH from only LAN connections"
ufw allow from 192.168.1.0/24 to any port 22 comment 'SSH via LAN' 1>/dev/null 2>&1
echo "Allowing Samba file sharing connections"
ufw allow proto tcp to any port 135,139,445 comment 'Samba Share' 1>/dev/null 2>&1
ufw allow proto udp to any port 137,138 comment 'Samba Share' 1>/dev/null 2>&1
echo "Allowing Nagios connections"
ufw allow from 192.168.107.21 to any port 12489 comment 'Nagios' 1>/dev/null 2>&1
ufw allow from 192.168.107.21 proto tcp to any port 5666 comment 'Nagios' 1>/dev/null 2>&1
echo "Adding Application-specific rules"
#echo "Adding MySQL/MariaDB rules"
#ufw allow from 192.168.1.0/24 proto tcp to any port 3306 comment 'MariaDB via LAN' 1>/dev/null 2>&1
#ufw allow from 192.168.2.0/24 proto tcp to any port 3306 comment 'MariaDB via LAN' 1>/dev/null 2>&1
#echo "Adding FTP/FTPS rules"
#ufw allow proto tcp to any port 990 comment 'FTPS' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 21 comment 'FTP' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 2000:2020 comment 'FTP Passive' 1>/dev/null 2>&1
#echo "Adding Web Server rules"
#ufw allow proto tcp to any port 80 comment 'HTTP Service' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 8080 comment 'HTTP Service' 1>/dev/null 2>&1
#ufw allow proto tcp to any port 443 comment 'HTTPS Service' 1>/dev/null 2>&1
echo "Enabling firewall"
echo y | ufw enable 1>/dev/null 2>&1
echo "Firewall enabled and all rules have been configured."
