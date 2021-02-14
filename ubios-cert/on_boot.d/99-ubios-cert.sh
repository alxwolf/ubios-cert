#!/bin/sh

#Load environment variables
. /mnt/data/ubios-cert/ubios-cert.env

if [ ! -f /etc/cron.d/ubios-cert ]; then
	# Sleep for 5 minutes to avoid restarting
	# services during system startup.
	sleep 300
	sh ${UBIOS_CERT_ROOT}/ubios-cert.sh bootrenew
fi