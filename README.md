# Valid and free TLS / SSL certificates for UniFi Consoles V4.1.13 and V3.2.x

Last and final update: March 14, 2025.

OK folks, sorry to disappoint but I've had it, as with the introduction of new hardware (Dream Router etc.) the foundation has been broken - again. I'm not a professional user (or programmer) and neither have time or the need to help a commercial company fixing their security.

Thanks to all those who helped making this work! As of March 14, 2025, this is archived. I can only point you in the direction of Glenn R.'s [UniFi Easy Encrypt](https://glennr.nl/s/unifi-lets-encrypt) script.

## \### NO USER SERVICEABLE PARTS BEYOND THIS POINT \###

*Public Service Announcement:* In its best tradition, UI has established some new, of course undocumented, black magic around valid SSL certificates. This project here tries to cope with this new twist. Web frontend and Hotspot are covered now, and WiFiMan will be toasted as soon as you use custom SSL certificates. This has been officially acknowledged by UI. Right now, RADIUS ~~will still not work~~ can be fixed manually as described [here](https://github.com/alxwolf/ubios-cert/wiki/RADIUS-certificates).

With 4.1.x, UI has *again* changed the way they handle certificates, but still not implemented in a proper way. 4.1 is supported on UniFi OS - Dream Machines 4.1.13

I suggest you give Glenn R.'s [monster scripts](https://glennr.nl/s/unifi-lets-encrypt) a try - if you can. He's on the [UI community forums](https://community.ui.com/questions/UniFi-Installation-Scripts-or-UniFi-Easy-Update-Script-or-UniFi-Lets-Encrypt-or-UniFi-Easy-Encrypt-/ccbc7530-dd61-40a7-82ec-22b17f027776) and obviously knows extremely well what needs to be done, but is not willing to address the request for certificates issued with DNS-Challenge. Coincidently, he seems to work for UI and there is a UI team member called *UI-Glenn*.

If you're able to convince him or UI to provide proper, out of the box support for securing communication with UI devices beyond having a self-signed "unifi.local" certificate - I will archive this project the next minute. In the meantime...

## What it does

Spare you and your users from certificate errors when browsing to your UniFi Console's (Dream Machine Base / Pro / SE / R) administrative web frontend, Hotspot Portal ~~and RADIUS server~~.

**TL;DR** jump to [Installation](#installation)

It will install Neilpang's [`acme.sh`](https://github.com/acmesh-official/acme.sh), is extremely light as it runs on bare metal and survives (until further notice...) reboots and firmware upgrades (at least for minor revisions).

With that, it will

* issue TLS (aka SSL) certificates for a domain (with Subject Alternate Names or wildcards) you own, using ([Let's Encrypt](https://letsencrypt.org) (LE), and other [supported certification authorities](https://github.com/acmesh-official/acme.sh#supported-ca),
* use the DNS-01 challenge, so you don't have be present on the Internet with open ports 80 and 443,
* renew your certificate automatically every 60 days.

## Discontinued support for firmwares < v4.x

This branch serves the most current firmware(s).

If you're still running a V1.x (why would you...), please have a look at branch [v1.x](https://github.com/alxwolf/ubios-cert/blob/V1.x/README.md) - which is no longer supported (at least not by me due to lack of hardware).

If you're on V2.x to anything before V3.2.7, check branch [V2-to-V3.1](https://github.com/alxwolf/ubios-cert/tree/V2-to-V3.1).

## Currently supported DNS API providers

Over 150, check [acme.sh DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) Wiki for details.

## But why?

In most private installations, the UniFi console will live behind a router / firewall provided by an ISP, and we don't want to open HTTP(S) ports 80 and 443 to the interested public.

## What you need

* A UniFi Console with firmware V4.x,
* a registered domain where you have API access for running the DNS-01 API challenge,
* the awareness you might break something.

## Installation

### Download the package

* `ssh` into your UDM
* Download the archive to your home directory and unzip it

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
  cd /data/ubios-cert
  ./ubios-cert.sh initial
  ```

### Make your adjustments

Adjust file [`ubios-cert.env`](./ubios-cert/ubios-cert.env) to your needs.

First, define your certificate names and CA by adjusting

```sh
#######################################
# Configure certificates and provider #
#######################################

# The FQDN of your UniFi Console (comma separated fqdns and wildcards are supported)
CERT_HOSTS='domain.com,*.domain.com'

# Email address for registration
CA_REGISTRATION_EMAIL='user@domain.com'

# Default CA: https://github.com/alxwolf/ubios-cert/wiki/acme.sh:-choosing-the-default-CA
DEFAULT_CA="letsencrypt"
```

Second,

```sh
#################################################
# Select services to provide the certificate to #
#################################################

# Enable updating Hotspot Portal certificate 
# this will break WiFiMan 100% as of v3.2.7
# provide options 'yes' or 'no' in lowercase
ENABLE_HOTSPOT='yes'

# Enable updating Radius support
# provide options 'yes' or 'no' in lowercase
ENABLE_RADIUS='yes'

```

Third, select your DNS API provider by adjusting the variable `DNS_API_PROVIDER="dns_xxx"`.

`dns_xxx` must be replaced with the `--dns` parameter from your provider's [acme.sh DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) Wiki entry.

So for CloudFlare this would say

```sh
export DNS_API_PROVIDER="dns_cf"
```

Some APIs may require additional manual preparation, please check the [Wiki](https://github.com/alxwolf/ubios-cert/wiki).

Advanced: you can pass additional command line options to `acme.sh` by editing environment variable `ACMESH_CMD_PARAMS`.

## First Run

Consider making a backup copy of your [current certificate and key](https://github.com/alxwolf/ubios-cert/wiki/Certificate-locations-on-UDM(P)) before moving on.

```sh
mkdir /data/ubios-cert/certbackup
cd /data/ubios-cert/certbackup
cp /data/unifi-core/config/unifi-core.key ./unifi-core.key_orig
cp /data/unifi-core/config/unifi-core.crt ./unifi-core.crt_orig
cp /data/udapi-config/raddb/certs/server.pem ./raddb-server.pem
cp /data/udapi-config/raddb/certs/server-key.pem ./raddb-server-key.pem
```

Calling the script with `sh /data/ubios-cert/ubios-cert.sh initial` will

* setup up the trigger for persistence over reboot / firmware upgrades
* establish a cron job to take care about your certificate renewals
* register an account with your email
* issue a certificate (with SANs, if you like)
* deploy the certificate to your network controller (and captive portal, if you selected that)
* restart the unifi-os

## Certificate Renewal

Should be fully automated, done via a daily `cron` job. You can trigger a manual renewal by running `sh /data/ubios-cert/ubios-cert.sh renew`, which may be useful for debugging. If `acme.sh` fails, check if you hit the [rate limits](https://letsencrypt.org/docs/rate-limits/).

The certificate can be force-renewed by running `sh /data/ubios-cert/ubios-cert.sh force-renew`.

## Behaviour after firmware upgrade / reboot

Survived reboots and firmware updates, including release change from V3 to V4.

## De-installation and de-registration

`ssh` into your UDM. Calling the script with `sh /data/ubios-cert/ubios-cert.sh cleanup` will

* Remove the cron file from `/etc/cron.d`
* Remove the (most recently issued) domains from the Let's Encrypt account
* De-activate the Let's Encrypt account

Then, you can delete the script directory. As always, be careful with `rm`.

```sh
cd /data/
./ubios-cert/ubios-cert.sh cleanup
rm -irf ./ubios-cert
```

## Selecting the default CA

`acme.sh` can access different CAs. [You can select which CA you want it to use](https://github.com/alxwolf/ubios-cert/wiki/acme.sh:-choosing-the-default-CA). The keywords are listed [here](https://github.com/acmesh-official/acme.sh/wiki/Server). Adjust the value in `ubios-cert.env` first and then call the script with `ubios-cert.sh set-default-ca`. This CA will **from now on** be applied to newly issued certificates.

## Debugging

* Increase the log level in `ubios-cert.sh` by setting `LOGLEVEL="--log-level 2"`
* Run `tail -f ${DATA_DIR}/ubios-cert/acme.sh/acme.sh.log`in separate terminal while running `sh ubios-cert.sh initial`, `sh ubios-cert.sh renew` or `sh ubios-cert.sh force-renew` manually

## Inspired by - Sources and Credits

A huge "Thank You" goes to

* [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh): the probably most convenient and most supported interface for Let's Encrypt, ZeoSSL, Buypass and SSL.com.
* [llaforest](https://github.com/llaforest): for implementing the native / bare metal version of `acme.sh`
* [docholliday-sc001](https://github.com/docholliday-sc001): for coming up with a fix for RADIUS certificates
* [kchristensen's udm-le for UDM](https://github.com/kchristensen/udm-le): his work provides the base for both structure of implementation and content.
* [Glenn R.'s Easy Encrypt script](https://glennr.nl/s/unifi-lets-encrypt)

## Known bugs and unknowns

* For sure some. And a lack of tests, checks and cleanup. RADIUS certificates are still broken.

## UniFi OS and Network Controller Versions

Confirmed to work on UniFi OS Version 4.1.13 and Network Version 9.0.114
