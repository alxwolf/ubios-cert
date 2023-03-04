#!/bin/sh

#
# based on the fine work of kchristensen/udm-le
# https://github.com/kchristensen/udm-le
#

set -e

# Load environment variables
. /mnt/data/ubios-cert/ubios-cert.env

# Setup variables for later for those who want to tinker around
LOGFILE="--log ${ACMESH_ROOT}/acme.sh.log"
LOGLEVEL='--log-level 1' # default is 1, can be increased to 2
LOG="${LOGFILE} ${LOGLEVEL}"

NEW_CERT='no'

# identify device firmware version: <2 is legacy (podman), 2+ is current (baremetal)

IS_UNIFI_2='false'
if [ $(ubnt-device-info firmware | sed 's#\..*$##g' || true) -gt 1 ]
 then
	 IS_UNIFI_2='true'
fi

deploy_cert() {
	if [ "$(find -L "${ACMESH_ROOT}" -type f -name fullchain.cer -mmin -5)" ]; then
		echo 'New certificate was generated, time to deploy it'
		# Controller certificate - copy the full chain certificates to unifi-core.crt to avoid Java cert store command error
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/fullchain.cer ${UNIFIOS_CERT_PATH}/unifi-core.crt
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/fullchain.cer ${UNIFIOS_CERT_PATH}/unifi-core-direct.crt
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/${CERT_NAME}.key ${UNIFIOS_CERT_PATH}/unifi-core.key
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/${CERT_NAME}.key ${UNIFIOS_CERT_PATH}/unifi-core-direct.key
		chmod 644 ${UNIFIOS_CERT_PATH}/unifi-core.crt ${UNIFIOS_CERT_PATH}/unifi-core-direct.crt
		chmod 644 ${UNIFIOS_CERT_PATH}/unifi-core.key ${UNIFIOS_CERT_PATH}/unifi-core-direct.key
		NEW_CERT='yes'
	else
		echo 'No new certificate was found, exiting without restart'
	fi
}

add_captive() {
	echo 'Checking if Guest Hotspot Portal and WiFiman certificate needs update.'
	# Import the certificate for the captive portal
	if [ "${ENABLE_CAPTIVE}" = 'yes' ] && [ "$(find -L ${ACMESH_ROOT} -type f -name fullchain.cer -mmin -5)" ]; then
		echo 'New certificate was generated, time to deploy it'

		# Add a prefix to run the command in podman only if the system is not native UNIFI_OS
		if [ "${IS_UNIFI_2}" = 'false' ]; then PODMAN_PREFIX='podman exec -it unifi-os '; else PODMAN_PREFIX=''; fi

		# should we provide the full chain or only server cert to Guest Portal
		if [ "${CAPTIVE_FULLCHAIN}" != 'yes' ]; then
			# add a single certificate without chain (this is required by WiFiMan and Guest Portal to work since 1.11 or so)

			# get the full chain certifcate out of the way
			mv {UNIFIOS_CERT_PATH}/unifi-core.crt ${UNIFIOS_CERT_PATH}/unifi-core-fullchain.crt
			# extract just the server certificate			
			${PODMAN_PREFIX}openssl x509 -in ${UNIFIOS_CERT_PATH}/unifi-core-fullchain.crt -out ${UNIFIOS_CERT_PATH}/unifi-core.crt
		fi

		# mangle cert and key into P12 format
		${PODMAN_PREFIX}openssl pkcs12 -export -inkey ${UNIFIOS_CERT_PATH}/unifi-core.key -in ${UNIFIOS_CERT_PATH}/unifi-core.crt -out ${UNIFIOS_CERT_PATH}/unifi-core.p12 -name unifi -password pass:aircontrolenterprise
		
		# make a backup copy of keystore
		${PODMAN_PREFIX}cp /usr/lib/unifi/data/keystore /usr/lib/unifi/data/keystore.backup

		# remove the existing key called 'unifi'
		${PODMAN_PREFIX}keytool -delete -alias unifi -keystore /usr/lib/unifi/data/keystore -deststorepass aircontrolenterprise

		# finally, import the p12 formatted cert+key of server only into keystore
		${PODMAN_PREFIX}keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore /usr/lib/unifi/data/keystore -srckeystore ${UNIFIOS_CERT_PATH}/unifi-core.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt
	fi
}

unifos_restart () {
	if [ "${IS_UNIFI_2}" = 'false' ]; then
		echo "Please wait while restarting unifi using 'unifios restart'"
		unifi-os restart
	else 
		echo "Please wait while restarting unifi-core using 'systemctl restart unifi-core'"
		# Restarting the network app with 'restart unifi' has no effect on cert. The whole unifi-os has to be reloaded.
		systemctl restart unifi-core
	fi
}

remove_old_log() {
	# Trash the previous logfile
	if [ -f "${ACMESH_ROOT}/acme.sh.log" ]; then
		rm ${ACMESH_ROOT}/acme.sh.log
		echo "Removed old logfile"
	fi
}

remove_cert() {
	echo "Executing: ${ACME_CMD} --remove ${DOMAINS}"
	remove_old_log
	${ACME_CMD} --remove ${DOMAINS}
	echo "Removed certificates from acme.sh renewal. The certificate files can now manually be removed."
}

# Check for and if it not exists create acme.sh directory so the container can write to it - owner "nobody"
if [ ! -d "${ACMESH_ROOT}" ]; then
	mkdir "${ACMESH_ROOT}"
	chmod 700 "${ACMESH_ROOT}"
	echo "Created directory 'acme.sh'"
fi

# Check for correct permissions and adjust if necessary
if [ "$(stat -c '%u:%g' "${ACMESH_ROOT}")" != "65534:65534" ]; then
	chown 65534:65534 "${ACMESH_ROOT}"
	echo "Adjusted permissions for 'acme.sh'"
fi

# Support multiple certificate SANs
# Subject Alternative Name (SAN)
for DOMAIN in $(echo $CERT_HOSTS | tr "," "\n"); do
	# Store the certificate under 'first entry' of CERT_HOSTS list 
	if [ -z "$CERT_NAME" ]; then
		CERT_NAME=$DOMAIN
	fi
	DOMAINS="${DOMAINS} -d ${DOMAIN}"
done

ACME_HOME="--config-home ${ACMESH_ROOT} --cert-home ${ACMESH_ROOT} --home ${ACMESH_ROOT}"
ACME_CMD="${ACMESH_ROOT}/acme.sh ${ACMESH_CMD_PARAMS} ${ACME_HOME}"


# Setup persistent on_boot.d trigger
ON_BOOT_DIR='/mnt/data/on_boot.d'
ON_BOOT_FILE='99-ubios-cert.sh'
if [ -d "${ON_BOOT_DIR}" ] && [ ! -f "${ON_BOOT_DIR}/${ON_BOOT_FILE}" ]; then
	cp "${UBIOS_CERT_ROOT}/on_boot.d/${ON_BOOT_FILE}" "${ON_BOOT_DIR}/${ON_BOOT_FILE}"
	chmod 755 ${ON_BOOT_DIR}/${ON_BOOT_FILE}
	echo "Restored 'on_boot.d' trigger"
fi

# Setup nightly cron job
CRON_FILE='/etc/cron.d/ubios-cert'
if [ ! -f "${CRON_FILE}" ]; then
	if [ "${IS_UNIFI_2}" = 'false' ]; then
		# Pre-V2.x requires no user
		echo "0 3 * * * ${UBIOS_CERT_ROOT}/ubios-cert.sh renew" >${CRON_FILE}
	else # V2.x and later requires username
		echo "0 3 * * * root ${UBIOS_CERT_ROOT}/ubios-cert.sh renew" >${CRON_FILE}
	fi
	chmod 644 ${CRON_FILE}
	if [ -f /etc/init.d/crond ]; then
		/etc/init.d/crond reload ${CRON_FILE}
	elif [ -f /etc/init.d/cron ]; then
		/etc/init.d/cron reload ${CRON_FILE}
	else
		echo "ERROR: Could not find cron service at /etc/init.d/crond or /etc/init.d/cron" >&2
		exit 1
	fi
	echo "Restored cron file"
fi

# confirm if 'account.conf' exists and can only be accessed by owner (nobody / nogroup)
if [ -f "${ACMESH_ROOT}/account.conf" ]; then
	if [ "$(stat -c '%a' "${ACMESH_ROOT}/account.conf")" != "600" ]; then
		chmod 600 ${ACMESH_ROOT}/account.conf
	fi
fi

case $1 in
initial)
	remove_old_log
	echo "Setting default CA to ${DEFAULT_CA}"
	${ACME_CMD} --set-default-ca --server ${DEFAULT_CA}
	echo "Attempting initial certificate generation"
	${ACME_CMD} --register-account --email ${CA_REGISTRATION_EMAIL}
	${ACME_CMD} --issue ${DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOG} && deploy_cert && add_captive && unifos_restart
	;;
renew)
	remove_old_log
	echo "Attempting acme.sh upgrade"
	${ACME_CMD} --upgrade
	echo "Attempting certificate renewal"
	${ACME_CMD} --renew ${DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOG} && deploy_cert
	if [ "${NEW_CERT}" = "yes" ]; then
		add_captive && unifos_restart
	fi
	;;
forcerenew)
	echo "Forcing certificate renewal"
	remove_old_log
	${ACME_CMD} --renew ${DOMAINS} --force --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOG} && deploy_cert
	if [ "${NEW_CERT}" = "yes" ]; then
		add_captive && unifos_restart
	fi
	;;
bootrenew)
	echo "Attempting certificate renewal after boot"
	remove_old_log
	${ACME_CMD} --renew ${DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOGFILE} ${LOGLEVEL} && deploy_cert && add_captive && unifos_restart
	;;
deploy)
	echo "Deploying certificates and restarting UniFi OS"
	deploy_cert && 	add_captive && unifos_restart
	;;
setdefaultca)
	echo "Setting default CA to ${DEFAULT_CA}"
	remove_old_log
	${ACME_CMD} --set-default-ca --server ${DEFAULT_CA}
	;;
cleanup)
	if [ -f "${CRON_FILE}" ]; then
		rm "${CRON_FILE}"
		echo "Removed cron file"
	fi

	if [ -d "${ON_BOOT_DIR}" ] && [ -f "${ON_BOOT_DIR}/${ON_BOOT_FILE}" ]; then
		rm "${ON_BOOT_DIR}/${ON_BOOT_FILE}"
		echo "Removed on_boot.d trigger"
	fi

	if [ -f "${ACMESH_ROOT}/account.conf" ]; then
		remove_old_log
		remove_cert
		echo "Executing: ${ACME_CMD} --deactivate-account"
		${ACME_CMD} --deactivate-account
		echo "Deactivated LE account"
	fi
	;;
esac
