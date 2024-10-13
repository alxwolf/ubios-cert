#!/bin/bash

#
# based on the fine work of kchristensen/udm-le
# https://github.com/kchristensen/udm-le
# and
# Glenn Rietveld https://GlennR.nl
#

# Foreground colors
#  0;30   Black          1;30   Dark Gray
#  0;34   Blue           1;34   Light Blue
#  0;32   Green          1;32   Light Green
#  0;36   Cyan           1;36   Light Cyan
#  0;31   Red            1;31   Light Red
#  0;35   Purple         1;35   Light Purple
#  0;33   Brown          1;33   Yellow
#  0;37   Light Gray     1;37   White

RESET='\e[0m'
YELLOW='\e[1;33m'
GRAY='\e[0;37m'
BLUE='\e[0;34m'
RED='\e[1;31m'
GREEN='\e[1;32m'

unifi_core_device=$(grep -io "welcome.*" /etc/motd | sed -e 's/Welcome //g' -e 's/to //g' -e 's/the //g' -e 's/!//g');

set -e

# Load environment variables
. /data/ubios-cert/ubios-cert.env

# Setup variables for later for those who want to tinker around
LOGFILE="--log ${ACMESH_ROOT}/acme.sh.log"
LOGLEVEL='--log-level 1' # default is 1, can be increased to 2
LOG="${LOGFILE} ${LOGLEVEL}"

NEW_CERT='no'

# identify device firmware version: <2 is legacy (podman), 2+ is current (baremetal)

IS_UNIFI_4='false'
FIRMWARE_VER=$(ubnt-device-info firmware)
if [ $(ubnt-device-info firmware | sed 's#\..*$##g' || true) -gt 1 ]
 then
	IS_UNIFI_4='true'
	echo -e "${GREEN}SUCCESS${RESET} Supported firmware: ${FIRMWARE_VER} on ${unifi_core_device}. Moving on."
 else
	echo -e "${RED}FAILED ${RESET} Unsupported firmware: ${FIRMWARE_VER} on ${unifi_core_device}. Stopping."
	exit 1
fi

deploy_cert() {
	echo -e "${GRAY}INFO   ${RESET} New certificate was generated, time to deploy it"
	if [ "$(find -L "${ACMESH_ROOT}" -type f -name fullchain.cer -mmin -5)" ]; then
		copy_and_link

		# funny enough, this still seems to be required by UniFi Protect to be able to boot up
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/fullchain.cer ${UNIFIOS_CERT_PATH}/unifi-core.crt
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/${CERT_NAME}.key ${UNIFIOS_CERT_PATH}/unifi-core.key

		NEW_CERT='yes'
		echo -e "${GREEN}# SUCCESS${RESET} Certifcate deployed to UniFi OS, service not yet restarted."
	else
		echo -e  "${BLUE}# INFO    ${RESET} No new certificate was found."
	fi
}

copy_and_link() {
	if [[ ! -d ${UBIOS_CERT_ROOT}/certificates/ ]]; then
		mkdir -p ${UBIOS_CERT_ROOT}/certificates/;
		echo -e "${BLUE}# INFO    ${RESET} Created directory for certificates"
	fi
	# beginning with 3.2.7, no need to copy the cert and key, but point in the right direction via a YAML file
	if [[ ! -f "${UNIFI_CORE_SSL_CONFIG}" ]]; then
		tee "${UNIFI_CORE_SSL_CONFIG}" &>/dev/null << SSL
# File created by ubios-cert (certificates for Unifi Dream Machines).
ssl:
  crt: '${UBIOS_CERT_ROOT}/certificates/unifi-core.crt'
  key: '${UBIOS_CERT_ROOT}/certificates/unifi-core.key'
SSL
	fi

	# copy cert and key to a more convenient place so we can use fixed path names
	if [[ -f "${ACMESH_ROOT}/${CERT_NAME}/fullchain.cer" ]]; then
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/fullchain.cer ${UBIOS_CERT_ROOT}/certificates/unifi-core.crt
	fi
	if [[ -f "${ACMESH_ROOT}/${CERT_NAME}/${CERT_NAME}.key" ]]; then
		cp -f ${ACMESH_ROOT}/${CERT_NAME}/${CERT_NAME}.key ${UBIOS_CERT_ROOT}/certificates/unifi-core.crt
	fi
}

add_captive() {
	echo 'Checking if Guest Hotspot Portal and WiFiman certificate needs update.'
	# Import the certificate for the captive portal
	if [ "${ENABLE_CAPTIVE}" = 'yes' ] && [ "$(find -L ${ACMESH_ROOT} -type f -name fullchain.cer -mmin -5)" ]; then
		echo 'New certificate was generated, time to deploy it to Guest Portal'

		# should we provide the full chain or only server cert to Guest Portal
		if [ "${CAPTIVE_FULLCHAIN}" == 'no' ]; then
			# add a single certificate without chain (this is required by WiFiMan and Guest Portal to work since 1.11 or so)
			echo 'Import server certificate only, enabling WiFiman'

			# get the full chain certifcate out of the way
			mv ${UNIFIOS_CERT_PATH}/unifi-core.crt ${UNIFIOS_CERT_PATH}/unifi-core-fullchain.crt
			# extract just the server certificate			
			openssl x509 -in ${UNIFIOS_CERT_PATH}/unifi-core-fullchain.crt -out ${UNIFIOS_CERT_PATH}/unifi-core.crt
		else
			echo 'Import full certificate chain, breaking WiFiman'
		fi

		# mangle cert and key into P12 format
		openssl pkcs12 -export -inkey ${UNIFIOS_CERT_PATH}/unifi-core.key -in ${UNIFIOS_CERT_PATH}/unifi-core.crt -out ${UNIFIOS_CERT_PATH}/unifi-core.p12 -name unifi -password pass:aircontrolenterprise
		
		# make a backup copy of keystore
		cp /usr/lib/unifi/data/keystore /usr/lib/unifi/data/keystore.backup

		# remove the existing key called 'unifi'
		keytool -delete -alias unifi -keystore /usr/lib/unifi/data/keystore -deststorepass aircontrolenterprise

		# finally, import the p12 formatted cert+key of server only into keystore
		keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore /usr/lib/unifi/data/keystore -srckeystore ${UNIFIOS_CERT_PATH}/unifi-core.p12 -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi -noprompt

		# new since V3.2.7 - some flags must be set if ECDSA certificate 
		if openssl pkcs12 -in "${UNIFIOS_CERT_PATH}/unifi-core.p12" -password pass:aircontrolenterprise -nokeys ${openssl_legacy_flag} | openssl x509 -text -noout | grep -i signature | grep -iq ecdsa &> /dev/null; then
		echo "unifi.https.ciphers=ECDHE-ECDSA-AES256-GCM-SHA384,ECDHE-RSA-AES128-GCM-SHA256" &>> /usr/lib/unifi/data/system.properties
		echo "unifi.https.sslEnabledProtocols=TLSv1.3,TLSv1.2" &>> /usr/lib/unifi/data/system.properties
		fi

		if [[ -f "${UNIFIOS_CERT_PATH}/unifi-core.p12" ]]; then
			cp -f ${UNIFIOS_CERT_PATH}/unifi-core.p12 ${UBIOS_CERT_ROOT}/certificates/unifi-core.p12
		fi

	fi
}

add_radius() {
 	echo "Checking if RADIUS server certificate needs update."
 	# Import the certificate for the RADIUS server
 	if [ "$ENABLE_RADIUS" == "yes" ] \
 		&& [ "$(find -L ${ACMESH_ROOT} -type f -name fullchain.cer -mmin -5)" ]; \
 		then
 		echo "New certificate was generated, time to deploy to RADIUS server"
		# copy key
 		cp -f ${ACMESH_ROOT}/${CERT_NAME}/${CERT_NAME}.key ${UBIOS_RADIUS_CERT_PATH}/server-key.pem
		# copy certificate with full chain
 		cp -f ${ACMESH_ROOT}/${CERT_NAME}/fullchain.cer ${UBIOS_RADIUS_CERT_PATH}/server.pem
 		chmod 600 ${UBIOS_RADIUS_CERT_PATH}/server.pem ${UBIOS_RADIUS_CERT_PATH}/server-key.pem
 		echo "New RADIUS certificate deployed."
		echo "Please wait while restarting udapi-server using 'systemctl restart udapi-server'"
		systemctl restart udapi-server
		echo "RADIUS server restarted."
 	fi
}

unifios_restart () {
	echo "Please wait while restarting unifi-core using 'systemctl restart unifi-core'"
	if systemctl restart unifi-core; then 
		echo -e "${GREEN}# SUCCESS${RESET} Restarted UniFi OS on ${unifi_core_device}!"
	else 
		echo -e "${RED}# FAILED ${RESET} Restarted UniFi OS on ${unifi_core_device}..."
	fi
	 sleep 2;
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
	echo -e "${GREEN}SUCCESS${RESET} Removed certificates from acme.sh renewal. The certificate files can now manually be removed."
}

######################
# 
# "main" starts here
#
######################

# Check openSSL version, if version 3.x.x, use -legacy for pkcs12 - with UDM V4.x, we're still on OpenSSL v1.1
openssl_version="$(openssl version | awk '{print $2}' | sed -e 's/[a-zA-Z]//g')"
first_digit_openssl="$(echo "${openssl_version}" | cut -d'.' -f1)"
if [[ "${first_digit_openssl}" -ge "3" ]]; then openssl_legacy_flag="-legacy"; fi

# Check for and if it not exists create acme.sh directory so the container can write to it - owner "nobody"
if [ ! -d "${ACMESH_ROOT}" ]; then
	mkdir "${ACMESH_ROOT}"
	chmod 700 "${ACMESH_ROOT}"
	echo -e "${GRAY}INFO   ${RESET} Created directory 'acme.sh'"
fi

# Check for correct permissions and adjust if necessary
if [ "$(stat -c '%u:%g' "${ACMESH_ROOT}")" != "65534:65534" ]; then
	chown 65534:65534 "${ACMESH_ROOT}"
	echo -e "${GRAY}INFO   ${RESET} Adjusted permissions for 'acme.sh'"
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

# confirm if 'account.conf' exists and can only be accessed by owner (nobody / nogroup)
if [ -f "${ACMESH_ROOT}/account.conf" ]; then
	if [ "$(stat -c '%a' "${ACMESH_ROOT}/account.conf")" != "600" ]; then
		chmod 600 ${ACMESH_ROOT}/account.conf
	fi
fi

# Setup nightly cron job
CRON_FILE='/etc/cron.d/ubios-cert'
if [ ! -f "${CRON_FILE}" ]; then
	# V2.x and later requires username
	echo "0 3 * * * root ${UBIOS_CERT_ROOT}/ubios-cert.sh renew" >${CRON_FILE}

	chmod 644 ${CRON_FILE}

	if [ -f /etc/init.d/cron ]; then
		/etc/init.d/cron reload ${CRON_FILE}
	else
		echo -e -e "${RED}FAILED ${RESET} Could not find cron service at /etc/init.d/cron" >&2
		exit 1
	fi
	echo -e "${GREEN}SUCCESS${RESET} Restored cron file"
fi

case $1 in
initial)
	remove_old_log
	echo "${GRAY}INFO   ${RESET} Setting default CA to ${DEFAULT_CA}"
	${ACME_CMD} --set-default-ca --server ${DEFAULT_CA}
	echo "${GRAY}INFO   ${RESET} Attempting initial certificate generation"
	${ACME_CMD} --register-account --email ${CA_REGISTRATION_EMAIL}
	${ACME_CMD} --issue ${DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOG}
	deploy_cert
	add_captive
	add_radius
	unifios_restart
	;;
renew)
	remove_old_log
	echo -e "${GRAY}INFO   ${RESET} Attempting acme.sh upgrade"
	${ACME_CMD} --upgrade
	echo -e "${GRAY}INFO   ${RESET} Attempting certificate renewal"
	${ACME_CMD} --renew ${DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOG} && deploy_cert
	if [ "${NEW_CERT}" = "yes" ]; then
		add_captive
		add_radius
		nifios_restart
	fi
	;;
forcerenew)
	echo "Forcing certificate renewal"
	remove_old_log
	${ACME_CMD} --renew ${DOMAINS} --force --dns ${DNS_API_PROVIDER} --keylength 2048 ${LOG} && deploy_cert
	if [ "${NEW_CERT}" = "yes" ]; then
		add_captive
		add_radius
		unifios_restart
	fi
	;;
deploy)
	echo "Deploying certificates and restarting UniFi OS"
	deploy_cert
	add_captive
	add_radius
	unifios_restart
	;;
deploy-core)
	echo -e "${GRAY}INFO   ${RESET} Deploying certificate to unifi-core and restarting UniFi OS"
	deploy_cert
	unifios_restart
	;;
deploy-networkapp)
	echo -e "${GRAY}INFO   ${RESET} Deploying certificate to Network Application and restarting UniFi OS"
	add_captive
	unifios_restart
	;;
deploy-radius)
	echo -e "${GRAY}INFO   ${RESET} Deploying certificate to RADIUS server and restarting UniFi OS"
	add_radius
	unifios_restart
	;;
setdefaultca)
	echo -e "${GRAY}INFO   ${RESET}Setting default CA to ${DEFAULT_CA}"
	remove_old_log
	${ACME_CMD} --set-default-ca --server ${DEFAULT_CA}
	;;
cleanup)
	if [ -f "${CRON_FILE}" ]; then
		rm "${CRON_FILE}"
		echo "Removed cron file"
	fi

	if [ -f "${ACMESH_ROOT}/account.conf" ]; then
		remove_old_log
		remove_cert
		echo -e "${GRAY}INFO   ${RESET} Executing: ${ACME_CMD} --deactivate-account"
		${ACME_CMD} --deactivate-account
		echo -e "${GRAY}INFO   ${RESET} Deactivated LE account"
	fi
	;;
esac
