#!/bin/sh

#
# based on the fine work of kchristensen/udm-le
# https://github.com/kchristensen/udm-le
#

set -e

# Load environment variables
. /mnt/data/ubios-cert/ubios-cert.env

# Setup variables for later for those who want to tinker around
PODMAN_VOLUMES="-v ${ACMESH_ROOT}:/acme.sh"
PODMAN_ENV="${DNS_API_ENV}"
PODMAN_IMAGE="neilpang/acme.sh:latest"
PODMAN_LOGFILE="--log /acme.sh/acme.sh.log"
PODMAN_LOGLEVEL="--log-level 1" # default is 1, can be increased to 2
PODMAN_LOG="${PODMAN_LOGFILE} ${PODMAN_LOGLEVEL}"

NEW_CERT=""

pull_latest() {
	podman pull ${PODMAN_IMAGE}
}

deploy_cert() {
#	if [ "$(find -L "${ACMESH_ROOT}" -type f -name "${ACME_CERT_NAME}".cer -mmin -5)" ]; then
	if [ "$(find -L "${ACMESH_ROOT}" -type f -name fullchain.cer -mmin -5)" ]; then
		echo "New certificate was generated, time to deploy it"
		# Controller certificate - copy the full chain certificates to unifi-core.crt to avoid Java cert store command error
		#cp -f ${ACMESH_ROOT}/${ACME_CERT_NAME}/${ACME_CERT_NAME}.cer ${UBIOS_CERT_PATH}/unifi-core.crt
		cp -f ${ACMESH_ROOT}/${ACME_CERT_NAME}/fullchain.cer ${UBIOS_CERT_PATH}/unifi-core.crt
		cp -f ${ACMESH_ROOT}/${ACME_CERT_NAME}/${ACME_CERT_NAME}.key ${UBIOS_CERT_PATH}/unifi-core.key
		chmod 644 ${UBIOS_CERT_PATH}/unifi-core.crt
		chmod 600 ${UBIOS_CERT_PATH}/unifi-core.key
		NEW_CERT="yes"
	else
		echo "No new certificate was found, exiting without restart"
	fi
}

add_captive() {
	echo "Checking if Captive Portal certificate needs update."
	# Import the certificate for the captive portal
	if [ "$ENABLE_CAPTIVE" == "yes" ] \
		&& [ "$(find -L "${ACMESH_ROOT}" -type f -name fullchain.cer -mmin -5)" ]; \
		then
		echo "New certificate was generated, time to deploy it"
		# add key and full chain (sic!) to avoid getting the "no issuer certificate found" error from Java
		podman exec -it unifi-os ${CERT_IMPORT_CMD} ${UNIFIOS_CERT_PATH}/unifi-core.key ${UNIFIOS_CERT_PATH}/unifi-core.crt
	fi
}

remove_old_log() {
	# Trash the previous logfile
	if [ -f "${UBIOS_CERT_ROOT}/acme.sh/acme.sh.log" ]; then
		rm "${UBIOS_CERT_ROOT}/acme.sh/acme.sh.log"
		echo "Removed old logfile"
	fi
}

remove_cert() {
	echo "Executing: ${PODMAN_CMD} --remove ${PODMAN_DOMAINS}"
	remove_old_log
	${PODMAN_CMD} --remove ${PODMAN_DOMAINS}
	echo "Removed certificates from acme.sh renewal. The certificate files can now manually be removed."
}

# Check for and if not exists create acme.sh directory so the container can write to it - owner "nobody"
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
for DOMAIN in $(echo $CERT_HOSTS | tr "," "\n"); do
	if [ -z "$CERT_NAME" ]; then
		CERT_NAME=$DOMAIN
	fi
	PODMAN_DOMAINS="${PODMAN_DOMAINS} -d ${DOMAIN}"
done

# Re-write CERT_NAME if it is a wildcard cert. Replace '*' with '_'
ACME_CERT_NAME=${CERT_NAME/\*/_}

PODMAN_CMD="podman run --env-file=${UBIOS_CERT_ROOT}/ubios-cert.env -it --net=host --rm ${PODMAN_VOLUMES} ${PODMAN_ENV} ${PODMAN_IMAGE}"

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
	echo "0 6 * * * sh ${UBIOS_CERT_ROOT}/ubios-cert.sh renew" >${CRON_FILE}
	chmod 644 ${CRON_FILE}
	/etc/init.d/crond reload ${CRON_FILE}
	echo "Restored cron file"
fi

# confirm if 'account.conf' exists and can only be accessed by owner (nobody / nogroup)
if [ -f "${ACMESH_ROOT}/account.conf" ]; then
	if [ "$(stat -c '%a' "${ACMESH_ROOT}/account.conf")" != "600" ]; then
		chmod 600 ${ACMESH_ROOT}/account.conf
	fi
fi

# pull the latest image
echo "Attempting to pull most recent container image"
pull_latest

case $1 in
initial)
	echo "Attempting initial certificate generation"
	remove_old_log
	${PODMAN_CMD} --register-account --email ${CA_REGISTRATION_EMAIL}
	${PODMAN_CMD} --issue ${PODMAN_DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${PODMAN_LOG} && deploy_cert && add_captive && unifi-os restart
	;;
renew)
	echo "Attempting certificate renewal"
	remove_old_log
	${PODMAN_CMD} --renew ${PODMAN_DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${PODMAN_LOG} && deploy_cert
	if [ "${NEW_CERT}" = "yes" ]; then
		add_captive && unifi-os restart
	fi
	;;
forcerenew)
	echo "Forcing certificate renewal"
	remove_old_log
	${PODMAN_CMD} --renew ${PODMAN_DOMAINS} --force --dns ${DNS_API_PROVIDER} --keylength 2048 ${PODMAN_LOG} && deploy_cert
	if [ "${NEW_CERT}" = "yes" ]; then
		add_captive && unifi-os restart
	fi
	;;
bootrenew)
	echo "Attempting certificate renewal after boot"
	remove_old_log
	${PODMAN_CMD} --renew ${PODMAN_DOMAINS} --dns ${DNS_API_PROVIDER} --keylength 2048 ${PODMAN_LOGFILE} ${PODMAN_LOGLEVEL} && deploy_cert && add_captive && unifi-os restart
	;;
deploy)
	echo "Deploying certificates and restarting UniFi OS"
	deploy_cert && 	add_captive && unifi-os restart
	;;
setdefaultca)
	echo "Setting default CA to ${DEFAULT_CA}"
	remove_old_log
	${PODMAN_CMD} --set-default-ca --server ${DEFAULT_CA}
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
		echo "Executing: ${PODMAN_CMD} --deactivate-account"
		${PODMAN_CMD} --deactivate-account
		echo "Deactivated LE account"
	fi
	;;
esac
