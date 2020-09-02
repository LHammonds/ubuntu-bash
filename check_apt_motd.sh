#!/bin/sh
#
# check_apt_packages - nagios plugin
#
# Checks for any packages to be applied
# Built for Ubuntu 10 (LTS), see following URL for further info
# - http://www.sandfordit.com/vwiki/index.php/Nagios#Ubuntu_Software_Updates_Monitor
#
# By Simon Strutt
# Version 1 - Jan 2012
# Include standard Nagios library
. /usr/lib/nagios/plugins/utils.sh || exit 3
if [ ! -f /usr/lib/update-notifier/apt-check ]; then
        exit $STATE_UNKNOWN
fi
APTRES=$(/usr/lib/update-notifier/apt-check 2>&1)
PKGS=$(echo $APTRES | cut -f1 -d';')
SEC=$(echo $APTRES | cut -f2 -d';')
if [ -f /var/run/reboot-required ]; then
        REBOOT=1
        TOAPPLY=`cat /var/run/reboot-required.pkgs`
else
        REBOOT=0
fi
if [ "${PKGS}" -eq 0 ]; then
        if [ "${REBOOT}" -eq 1 ]; then
                RET=$STATE_WARNING
                RESULT="Reboot required to apply ${TOAPPLY}"
        else
                RET=$STATE_OK
                RESULT="No packages to be updated"
        fi
elif [ "${SEC}" -eq 0 ]; then
        RET=$STATE_WARNING
        RESULT="${PKGS} packages to update (no security updates)"
else
        RET=$STATE_CRITICAL
        RESULT="${PKGS} packages (including ${SEC} security) packages to update"
fi
echo $RESULT
exit $RET
