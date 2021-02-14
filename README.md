# Manage Let's Encrypt certificates for Ubiquiti UbiOS firmwares

## Table of Contents

* [What it does](https://github.com/alxwolf/ubios-cert#what-it-does)
* [Why it exists](https://github.com/alxwolf/ubios-cert#why-it-exists)
* [What it requires](https://github.com/alxwolf/ubios-cert#what-it-requires)
* [Installation](lihttps://github.com/alxwolf/ubios-cert#installation)
* [Inspiration and Kudos](https://github.com/alxwolf/ubios-cert#inspired-by-sources-and-credits)
* [Known bugs / deficiencies](https://github.com/alxwolf/ubios-cert#known-bugs-and-unknowns)

## What it does

You will get rid of certificate errors when browsing to your UniFi Dream Machine (Pro).

This set of scripts is installed on devices with UbiOS, like the UniFi Dream Machine Pro (UDMP), and will

* issue [Let's Encrypt](https://letsencrypt.org) (LE) certificates for a domain you own,
* use the DNS-01 challenge provided by [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh), so you don't have be present on the Internet with open ports 80 and 443,
* renew your UDMP certificate every 60 days,
* survive device reboots and firmware upgrades thanks to the [boostchicken's udm-utilities](https://github.com/boostchicken/udm-utilities) using its `on_boot.d` extension.

## Currently supported DNS API providers

This script has been explicitly tested with

* [all-inkl.com](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#98-use-all-inklcom-domain-api-to-automatically-issue-cert)

Most other of the over 120 providers from [acme.sh DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) should work by simply adjusting these two variables in `ubios-cert.env`:

`````sh
DNS_API_PROVIDER="..."
DNS_API_ENV="..."
`````

Several of those may require some additional manual preparation.

## Why it exists - Motivation

In many (slightly more sophisticated) private installations, the UDMP will live behind a router / firewall provided by an ISP, and we don't want to open HTTP(S) ports 80 and 443 to the interested public.

[udm-le](https://github.com/kchristensen/udm-le), does provide a solution for this, yet... [LEGO](https://go-acme.github.io/lego/) does not support the German provider *all-inkl.com* (and in total less providers than acme.sh supports).

## What it requires - Prerequisites

* A UniFi Dream Machine (Pro),
* a registered domain where you have API access for running "Let's Encrypt"'s DNS-API challenge

## Preparation tasks - Installation

Have a look at the [Wiki article](https://github.com/alxwolf/ubios-cert/wiki/Installation,-first-run,-uninstall#installation).

## How it works

... to be done ...

## Inspired by - Sources and Credits

A huge "Thank You" goes to

* [kchristensen's lego for UDM](https://github.com/kchristensen/udm-le): his work provides the base for both structure of implementation and content.
* [Neilpang's acme.sh](https://github.com/acmesh-official/acme.sh): the probably most convenient and most supported interface for Let's Encrypt.

## Known bugs and unknowns

Status as of February 14, 2021:

* The automated certificate update has not been tested
* There is no e-Mail address being registered with the account, so you will not receive expiration emails from LE
