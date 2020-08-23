#!/bin/bash
#############################################################
## Name          : opm.sh
## Version       : 1.1
## Date          : 2017-03-17
## Author        : LHammonds
## Compatibility : Ubuntu Server 12.04 - 16.04 LTS
## Requirements  : dialog (apt-get dialog) and root privileges
## Purpose       : Display menu to control the server
## Run Frequency : As needed
## Exit Codes    : None
## SymLink Cmd   : ln -s /var/scripts/prod/opm.sh /usr/sbin/opm
###################### CHANGE LOG ###########################
## DATE       VER WHO WHAT WAS CHANGED
## ---------- --- --- ---------------------------------------
## 2013-01-07 1.0 LTH Created script.
## 2017-03-17 1.1 LTH Changed variables to CamelCase.
#############################################################

## Store menu options selected by the user.
TempDir="/tmp"
ScriptDir="/var/scripts/prod"
Input="${TempDir}/opm-input.$$"

## Storage file for displaying cal and date command output.
Output="${TempDir}/opm-output.$$"

## Get text editor or fall back to vi_editor.
vi_editor=${EDITOR-vi}

## Requirement Check: Script must run as root user.
if [ "$(id -u)" != "0" ]; then
  ## FATAL ERROR DETECTED: Document problem and terminate script.
  echo -e "\nERROR: Root user required to run this script.\n"
  echo -e "Type 'sudo su' to temporarily become root user.\n"
  exit
fi

## Trap and delete temp files.
trap "rm $Output; rm $Input; exit" SIGHUP SIGINT SIGTERM

function f_display_output(){
  ## Purpose - display output using msgbox
  ##  $1 -> set msgbox height
  ##  $2 -> set msgbox width
  ##  $3 -> set msgbox title
  local h=${1-10}     ## box height default 10
  local w=${2-41}     ## box width default 41
  local t=${3-Output} ## box title
  dialog --backtitle "Operator Menu for $(hostname -f)" --title "${t}" --clear --msgbox "$(<$Output)" ${h} ${w}
}

function f_showdate(){
  ## Purpose - display current system date & time
  echo "Today is $(date) @ $(hostname -f)." >$Output
  f_display_output 6 60 "Date and Time"
}

function f_checkdisk(){
  ## Purpose: Display disk status.
  clear
  echo -e "df --block-size=M\n"
  df --block-size=M
  echo ""
  read -p "Press [Enter] key to continue..."
}

## Loop the menu display.
while true
do
  ## Display main menu.
  dialog --clear  --no-cancel --backtitle "Operator Menu for $(hostname -f)" \
  --title "[ M A I N - M E N U ]" \
  --menu "You can use the UP/DOWN arrow keys, the first \n\
  letter of the choice as a hot key, or the \n\
  number keys 1-9 to choose an option.\n\
  Choose the TASK" 19 50 7 \
  Exit "Exit menu" \
  OSUpdate "Update Operating System" \
  CheckDisk "Check Disk Status" \
  MEMCheck "Look at running processes" \
  ServiceRestart "Stop/Start Main Services" \
  Reboot "Cleanly reboot server" \
  Date/time "Displays date and time" 2>"${Input}"

  menuitem=$(<"${Input}")

  ## Make decision.
  case $menuitem in
    OSUpdate) ${ScriptDir}/apt-upgrade.sh;;
    CheckDisk) f_checkdisk;;
    MEMCheck) htop;;
    Reboot) ${ScriptDir}/reboot.sh;;
    ServiceRestart) ${ScriptDir}/servicerestart.sh;;
    Date/time) f_showdate;;
    Exit) clear; echo "Clean menu exit."; break;;
  esac
done

## Delete temp files.
[ -f $Output ] && rm $Output
[ -f $Input ] && rm $Input
