#!/bin/sh
set -e
SCRIPT_DIR=$(dirname ${0})

# Get the firmware version
export FIRMWARE_VER=$(ubnt-device-info firmware || true)
# Get the Harware Model
export MODEL="$(ubnt-device-info model || true)"

deploy_acmesh() {
	echo "acme.sh will be deployed inside ubios-cert to persist firmware updates"
	ACME_URL=$(curl -s https://api.github.com/repos/acmesh-official/acme.sh/releases/latest | grep tarball_url | awk '{ print $2 }' | sed 's/,$//' | sed 's/"//g')
	echo "Fetching latest ACME from ${ACME_URL}"
	curl -L "${ACME_URL}" > acmesh.tar.gz 
	echo "Extracting ACME ${SCRIPT_DIR}/ubios-cert/acme.sh"
	mkdir -p "${SCRIPT_DIR}/ubios-cert/acme.sh"
	tar -xvf acmesh.tar.gz --directory="${SCRIPT_DIR}/ubios-cert/acme.sh" --strip-components=1 
}

if [ $(echo ${FIRMWARE_VER} | sed 's#\..*$##g') -gt 1 ]
	then
        export DATA_DIR="/data"
	else
		echo "Unsupported firmware: ${FIRMWARE_VER}"
		exit 1
fi

case "${MODEL}" in
	"UniFi Dream Machine Pro"|"UniFi Dream Machine"|"UniFi Dream Router"|"UniFi Dream Machine SE")
	echo "${MODEL} running firmware ${FIRMWARE_VER} detected, installing ubios-cert in ${DATA_DIR}..."
	;;
	*)
	echo "Unsupported model: ${MODEL}"
	exit 1
	;;
esac
echo

deploy_acmesh
chmod +x ${SCRIPT_DIR}/ubios-cert/ubios-cert.sh
mv "${SCRIPT_DIR}/ubios-cert/" "${DATA_DIR}/ubios-cert/"
rm -rf ${SCRIPT_DIR}/../ubios-cert-main ~/ubios-cert.zip
echo "Deployed with success in ${DATA_DIR}/ubios-cert"
cd ${DATA_DIR}/ubios-cert
