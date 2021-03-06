# Manage SSL / TLS certificates (Let's Encrypt, ZeroSSL, Buypass) with acme.sh and DNS API for Ubiquiti UbiOS

**TL;DR** jump to [Installation](#Installation)

## What it does

Spare you from certificate errors when browsing to your UniFi Dream Machine (Pro).

This set of scripts is installed on devices with UbiOS, like the UniFi Dream Machine Pro (UDMP), and will

* issue SSL / TLS certificates for a domain you own ([Let's Encrypt](https://letsencrypt.org) (LE), ZeroSSL or Buypass),
* use the DNS-01 challenge provided by [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh), so you don't have be present on the Internet with open ports 80 and 443,
* renew your UDMP certificate,
* survive device reboots and firmware upgrades thanks to [boostchicken's udm-utilities](https://github.com/boostchicken/udm-utilities) using its `on_boot.d` extension.

This is valid as long as Ubiquiti does not change something in their config. Use at your own risk, you have been warned.

## Currently supported DNS API providers

Adjusting two variables in `ubios-cert.env` should allow access to many of more than 120 providers from [acme.sh DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi). Adjust

`````sh
DNS_API_PROVIDER="..."
DNS_API_ENV="..."
`````

to your liking and feel free to add to this repo. Some APIs may require additional manual preparation.

This script has been explicitly tested with

* [all-inkl.com](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#98-use-all-inklcom-domain-api-to-automatically-issue-cert)

Send a note if you succeeded with a different provider and I will list it here.

## But why?

In private installations, the UDM(P) will live behind a router / firewall provided by an ISP, and we don't want to open HTTP(S) ports 80 and 443 to the interested public.

[udm-le](https://github.com/kchristensen/udm-le) has a solution, but [LEGO](https://go-acme.github.io/lego/) does not support the German provider [all-inkl.com](https://all-inkl.com). This script does, and builds on kchristensen's work.

## What you need

* A UniFi Dream Machine (Pro),
* a registered domain where you have API access for running "Let's Encrypt"'s DNS-API challenge
* a sense of adventure

## Inspired by - Sources and Credits

A huge "Thank You" goes to

* [kchristensen's udm-le for UDM](https://github.com/kchristensen/udm-le): his work provides the base for both structure of implementation and content.
* [boostchicken's udm-utilites](https://github.com/boostchicken/udm-utilities): the way to run stuff on UbiOS while surviving upgrades and reboots
* [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh): the probably most convenient and most supported interface for Let's Encrypt.

## Known bugs and unknowns

Status as of February 15, 2021:

* There is no email address being registered with the LE account, so you will not receive expiration emails from LE. As they will renew automatically, this should have no effect.

## Installation

### Download the package

* `ssh` into your UDMP
* Download the archive to your home directory
* Unzip it

````sh
# cd
# curl -JLO https://github.com/alxwolf/ubios-cert/archive/main.zip
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   121    0   121    0     0    489      0 --:--:-- --:--:-- --:--:--   489
100  5877    0  5877    0     0  12167      0 --:--:-- --:--:-- --:--:-- 12167
curl: Saved to filename 'ubios-cert-main.zip'
# unzip ubios-cert-main.zip 
Archive:  ubios-cert-main.zip
   creating: ubios-cert-main/
  inflating: ubios-cert-main/LICENSE
  inflating: ubios-cert-main/README.md
   creating: ubios-cert-main/ubios-cert/
   creating: ubios-cert-main/ubios-cert/on_boot.d/
  inflating: ubios-cert-main/ubios-cert/on_boot.d/99-ubios-cert.sh
  inflating: ubios-cert-main/ubios-cert/ubios-cert.env
  inflating: ubios-cert-main/ubios-cert/ubios-cert.sh
````

* [Make your adjustments](#make-your-adjustments) to `ubios-cert.env`
* Move (or copy) the files to their proper place
* Enter the directory /mnt/data/ubios-cert
* Issue your certificate for the first time

````sh
# mv ubios-cert-main/ubios-cert /mnt/data/
# rm -irf ubios-cert-main*
# cd /mnt/data/ubios-cert/
````

### Make your adjustments

Adjust file `ubios-cert.env` to your liking. You typically only need to touch environment variables `CERT_HOSTS`, `DNS_API_PROVIDER` and `DNS_API_ENV`.

## First Run

Consider making a backup copy of your [current certificate and key](https://github.com/alxwolf/ubios-cert/wiki/Certificate-locations-on-UDM(P)) before moving on.

````sh
mkdir /mnt/data/ubioscert/certbackup
cd /mnt/data/ubioscert/certbackup
cp /mnt/data/unifi-os/unifi-core/config/unifi-core.key ./unifi-core.key_orig
cp /mnt/data/unifi-os/unifi-core/config/unifi-core.crt ./unifi-core.crt_orig
````

Calling the script with `sh /mnt/data/ubios-cert/ubios-cert.sh initial` will

* setup up the trigger for persistence over reboot / firmware upgrades
* establish a cron job to take care about your certificate renewals
* create a directory for `acme.sh`
* issue a certificate (with SANs, if you like)
* deploy the certificate to your network controller (and captive portal, if you selected that)
* restart the unifi-os

## Certificate Renewal

Should be fully automated, done via a daily `cron` job. You can trigger a manual renewal by running `sh /mnt/data/ubios-cert/ubios-cert.sh renew`, which may be useful for debugging. If `acme.sh`fails, check if you hit the [rate limits](https://letsencrypt.org/docs/rate-limits/).

## Behaviour after firmware upgrade / reboot

Here the script in `on_boot.d` will trigger execution of `sh /mnt/data/ubios-cert/ubios-cert.sh initial`, with a friendly delay of five minutes after boot.

## De-installation and de-registration

`ssh` into your UDMP. Calling the script with parameter `cleanup` will

* Remove the cron file from `/etc/cron.d´
* Remove the boot trigger from `/mnt/data/on_boot.d/´
* Remove the (most recently issued) domains from the Let's Encrypt account
* De-activate the Let's Encrypt account

Then, you can delete the script directory. As always, be careful with `rm`.

````sh
cd /mnt/data/
./ubios-cert/ubios-cert.sh cleanup
rm -irf ./ubios-cert

````

## Selecting the default CA

`acme.sh`can access different CAs, at time of writing this includes Let's Encrypt, ZeroSSL and Buypass. [You can select which CA you want it to use](https://github.com/alxwolf/ubios-cert/wiki/acme.sh:-choosing-the-default-CA).

## Debugging

* Increase the log level in `ubios-cert.sh` by setting `PODMAN_LOGLEVEL="--log-level 2"`
* Run `tail -f /mnt/data/ubios-cert/acme.sh/acme.sh.log`in separate terminal while running `sh ubios-cert.sh initial`, `sh ubios-cert.sh renew` or `sh ubios-cert.sh bootrenew` manually
