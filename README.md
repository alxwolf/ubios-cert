# Manage SSL / TLS certificates (Let's Encrypt, ZeroSSL, Buypass) with acme.sh and DNS API for Ubiquiti UbiOS

**TL;DR** jump to [Installation](#installation)

## What it does

Spare you from certificate errors when browsing to your UniFi Dream Machine (Base / Pro / SE / R)'s administrative page and guest portal.

This set of scripts is installed on devices with UbiOS, like the UniFi Dream Machine Pro (UDMP), and will

* issue SSL / TLS certificates for a domain you own ([Let's Encrypt](https://letsencrypt.org) (LE), and others like ZeroSSL, Buypass, SSL.com),
* use the DNS-01 challenge provided by [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh), so you don't have be present on the Internet with open ports 80 and 443,
* renew your UDMP certificate,
* survive device reboots and firmware upgrades thanks to [boostchicken's udm-utilities](https://github.com/boostchicken/udm-utilities) using its `on_boot.d` extension.

This is valid as long as Ubiquiti does not change something in their config. Use at your own risk, you have been warned.

## Currently supported DNS API providers

Adjusting variables in `ubios-cert.env` should allow access to many of more than 120 providers from [acme.sh DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi). Adjust

```sh
export DNS_API_PROVIDER="..."
```

and corresponding other environment variables to your liking and feel free to add to this repo. Some APIs may require additional manual preparation, please check the [Wiki](https://github.com/alxwolf/ubios-cert/wiki).

This script has been explicitly tested with

* [all-inkl.com](https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#98-use-all-inklcom-domain-api-to-automatically-issue-cert)
* [Cloudflare](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#1-cloudflare-option)
* [GoDaddy](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#4-use-godaddycom-domain-api-to-automatically-issue-cert5)
* [OVH](https://github.com/acmesh-official/acme.sh/wiki/How-to-use-OVH-domain-api)
* [Route53](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#10-use-amazon-route53-domain-api)

Send a note if you succeeded with a different provider and I will list it here.

**Potentially breaking change:** all-inkl.com has decided to end support of `sha1`authentication, so password must be provided (and stored...) in clear text now. I don't judge...

## But why?

In private installations, the UDM(P) will live behind a router / firewall provided by an ISP, and we don't want to open HTTP(S) ports 80 and 443 to the interested public.

## What you need

* A UniFi Dream Machine / Pro / SE / UDR,
* a registered domain where you have API access for running "Let's Encrypt"'s DNS-API challenge

## Inspired by - Sources and Credits

A huge "Thank You" goes to

* [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh): the probably most convenient and most supported interface for Let's Encrypt, ZeoSSL, Buypass and SSL.com.
* [llaforest](https://github.com/llaforest): for implementing the native / bare metal version of `acme.sh`
* [boostchicken's udm-utilites](https://github.com/boostchicken/udm-utilities): the way to run stuff on UbiOS while surviving upgrades and reboots
* [kchristensen's udm-le for UDM](https://github.com/kchristensen/udm-le): his work provides the base for both structure of implementation and content.


## Known bugs and unknowns

* For sure some, but no known.

## UniFi OS and Network Controller Versions

Confirmed to work on UniFi OS Version 1.11.4, 1.12.33, 2.5.11 and Network Version 7.0.23, 7.2.95

## Installation

## Location of `${DATA_DIR}`

On unifi-os 1.x machines such as Dream Machine and Dream Machine Pro, the data folder is `/mnt/data`
On unifi-os 2.x machines such as Dream Machine SE and Dream Router, the data folder is `/data/`

This behavior is handled once by the `deploy.sh` script which will replace in files occurences of it.
This folder will be referred as `${DATA_DIR}` in the examples below.

### Download the package

* `ssh` into your UDM
* Download the archive to your home directory
* Unzip it

  ```sh
  cd
  curl -L https://github.com/alxwolf/ubios-cert/archive/main.zip > ubios-cert.zip
  unzip ubios-cert.zip
  cd ubios-cert-main
  chmod +x deploy.sh
  ```

* [Make your adjustments](#make-your-adjustments) to `ubios-cert.env`
  
  ```sh
  vi ubios-cert/ubios-cert.env
  ```

* Deploy the files to their proper place

  ```sh
  ./deploy.sh
  ```

* Navigate to the deployment folder and issue your certificate for the first time

  ```sh
  cd ${DATA_DIR}/ubios-cert
  ./ubios-cert.sh initial
  ```

### Make your adjustments

Adjust file `ubios-cert.env` to your liking. You typically only need to touch environment variables `CERT_HOSTS`, `CA_REGISTRATION_EMAIL`, `DNS_API_PROVIDER` and the specific exports related to your dns provider.

Advanced: you can pass additional command line options to `acme.sh` by editing environment variable `ACMESH_CMD_PARAMS`.

## First Run

Consider making a backup copy of your [current certificate and key](https://github.com/alxwolf/ubios-cert/wiki/Certificate-locations-on-UDM(P)) before moving on.

```sh
mkdir ${DATA_DIR}/ubios-cert/certbackup
cd ${DATA_DIR}/ubios-cert/certbackup
cp /data/unifi-core/config/unifi-core.key ./unifi-core.key_orig
cp /data/unifi-core/config/unifi-core.crt ./unifi-core.crt_orig
cp /data/udapi-server/raddb/certs/server.pem ./raddb-server.pem
cp /data/udapi-server/raddb/certs/server-key.pem ./raddb-server-key.pem
```

Calling the script with `sh ${DATA_DIR}/ubios-cert/ubios-cert.sh initial` will

* setup up the trigger for persistence over reboot / firmware upgrades
* establish a cron job to take care about your certificate renewals
* register an account with your email
* issue a certificate (with SANs, if you like)
* deploy the certificate to your network controller (and captive portal, if you selected that)
* restart the unifi-os

## Certificate Renewal

Should be fully automated, done via a daily `cron` job. You can trigger a manual renewal by running `sh ${DATA_DIR}/ubios-cert/ubios-cert.sh renew`, which may be useful for debugging. If `acme.sh`fails, check if you hit the [rate limits](https://letsencrypt.org/docs/rate-limits/).

The certificate can be force-renewed by running `sh ${DATA_DIR}/ubios-cert/ubios-cert.sh forcerenew`.

## Behaviour after firmware upgrade / reboot

Here the script in `on_boot.d` will trigger execution of `sh ${DATA_DIR}/ubios-cert/ubios-cert.sh bootrenew`, with a friendly delay of five minutes after boot.

## De-installation and de-registration

`ssh` into your UDM. Calling the script with parameter `cleanup` will

* Remove the cron file from `/etc/cron.d`
* Remove the boot trigger from `${DATA_DIR}/on_boot.d/`
* Remove the (most recently issued) domains from the Let's Encrypt account
* De-activate the Let's Encrypt account

Then, you can delete the script directory. As always, be careful with `rm`.

```sh
cd ${DATA_DIR}/
./ubios-cert/ubios-cert.sh cleanup
rm -irf ./ubios-cert
```

## Selecting the default CA

`acme.sh` can access different CAs, at time of writing this includes Let's Encrypt, ZeroSSL, Buypass, SSL.com and Google. [You can select which CA you want it to use](https://github.com/alxwolf/ubios-cert/wiki/acme.sh:-choosing-the-default-CA). The keywords are listed [here](https://github.com/acmesh-official/acme.sh/wiki/Server). Adjust the value in `ubios-cert.env` first and then call the script with `ubios-cert.sh setdefaultca`. This CA will **from now on** be applied to newly issued certificates.

## Debugging

* Increase the log level in `ubios-cert.sh` by setting `LOGLEVEL="--log-level 2"`
* Run `tail -f ${DATA_DIR}/ubios-cert/acme.sh/acme.sh.log`in separate terminal while running `sh ubios-cert.sh initial`, `sh ubios-cert.sh renew` or `sh ubios-cert.sh bootrenew` manually

## Branches

`main`- this branch, serving the most current firmware(s)
[v1.x](https://github.com/alxwolf/ubios-cert/blob/V1.x/README.md) - applicable to V1.x firmwares only, no longer supported (by me at least due to lack of hardware)

