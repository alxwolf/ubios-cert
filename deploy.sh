#!/bin/sh
set -e
SCRIPT_DIR=$(dirname ${0})

deploy_acmesh() {
	echo "acme.sh will be deployed inside ubios-cert to persist firmware updates"
	ACME_URL=$(curl -s https://api.github.com/repos/acmesh-official/acme.sh/releases/latest | grep tarball_url | awk '{ print $2 }' | sed 's/,$//' | sed 's/"//g')
	echo "Fetching latest ACME from ${ACME_URL}"
	curl -L "${ACME_URL}" > acmesh.tar.gz 
	echo "Extracting ACME ${SCRIPT_DIR}/ubios-cert/acme.sh"
	mkdir -p "${SCRIPT_DIR}/ubios-cert/acme.sh"
	tar -xvf acmesh.tar.gz --directory="${SCRIPT_DIR}/ubios-cert/acme.sh" --strip-components=1 
}

case "$(ubnt-device-info model || true)" in
	"UniFi Dream Machine Pro"|"UniFi Dream Machine")
	echo "UDM/UDM Pro detected, installing ubios-cert in /mnt/data..."
	DATA_DIR="/mnt/data"
	;;
	"UniFi Dream Router"|"UniFi Dream Machine SE")
	echo "UDR/UDM SE detected, installing ubios-cert in /data..."
	sed -i 's#/mnt/data#/data#g' "${SCRIPT_DIR}/ubios-cert/ubios-cert.env" "${SCRIPT_DIR}/ubios-cert/ubios-cert.sh" "${SCRIPT_DIR}/ubios-cert/on_boot.d/99-ubios-cert.sh"
	DATA_DIR="/data"
	export DATA_DIR
	;;
	*)
	echo "Unsupported model: $(ubnt-device-info model)" 1>&2
	exit 1
	;;
esac
echo

deploy_acmesh
chmod +x ${SCRIPT_DIR}/ubios-cert/ubios-cert.sh ${SCRIPT_DIR}/ubios-cert/on_boot.d/99-ubios-cert.sh
mv "${SCRIPT_DIR}/ubios-cert/" "${DATA_DIR}/ubios-cert/"
rm -rf ${SCRIPT_DIR}/../ubios-cert-main ubios-cert.zip
echo "Deployed with success in ${DATA_DIR}/ubios-cert"