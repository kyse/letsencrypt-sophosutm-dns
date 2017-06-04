# letsencrypt-sophosutm-dns
Let's Encrypt ssl cert management via Dehydrated with tsig dns-01 verification and Sophos UTM update hooks.
## Disclaimer
USE AT YOUR OWN RISK!

This package is not meant to be used on production servers or by inexperienced users.  I assume no liability if something goes wrong while you use this package.  I am not responsible for any damages you may incur using these scripts.  I suggest you read through the scripts dehydrated, hook.sh, and utm-update-certificate.pl to know what they are doing.
## Contents
- [Description](#description)
- [Usage](#usage)
  - [Setup](#setup)
  - [Automate](#automate)
  - [Notes](#notes)
- [Dependencies](#dependencies)
- [Contributing](#contributing)
  - [Development Setup](#development-setup)
## Description
This package is setup to provide an automated way to keep updated Let's Encrypt ssl certs on your UTM without dealing with SSH key's, SCP file transfers, etc.  Everything happens on the UTM and stays on the UTM.  It will work well in scenarios where you intend to perform SSL termination at the UTM WAF and intend to use DNS-01 acme-challenge verifications of your domains.  Some modifications have been made to Dehydrated and the hooks to ensure things work properly on the UTM shell.
## Usage
### Setup
1. SSH into your UTM shell: `ssh -l loginuser utm.domain.local`
2. Become root: `su`, enter root password
3. Change directory to root home or wherever you intend to host this package: `cd ~`
4. Grab the package: `wget https://github.com/kyse/letsencrypt-sophosutm-dns/raw/develop/dist/leutmdns.tar.gz`
5. Unzip the package: `tar -xzvf leutmdns.tar.gz`
6. Edit ~/leutmdns/config: `vi ~/leutmdns/config`
   - To start with, ensure you are using the LE staging servers until you've tested everything.  Then switch the commeted lines for CA and CA_TERMS.
   - Update CONTACT_EMAIL to your LE account email.
7. Edit ~/leutmdns/hook.sh: `vi ~/leutmdns/hook.sh`
   - Update SERVER to your dns tsig update endpoint.
   - If your UTM is behind a split brain DNS, uncomment EXTERNALNS to point to a name server on the outside.  This will allow the script to ensure external name servers have received the updated TXT challenge records before asking LE to validate.
8. Edit ~/leutmdns/domains.txt: `vi ~/leutmdns/domains.txt`
   - Standard Dehydrated proecdure here... enter primary domain with any additional SAN domains space seperated.  1 line per certificatee.
9. Create tsig key files in the ~/leutmdns/tsig/ folder.
   - File name format: K_acme-challenge.zone.tld.+157+random.private - zone.tld = your DNS zone your updating, no need for 1 file per FQDN, just the zone being targeted for that FQDN.  Random can be anything.
   - File content format (the keyname and secret will come from your DNS provider):
     ```
     key "keyname" {
       algorithm hmac-md5;
       secret "secret";
     };
     ```
10. Create ref files in the ~/leutmdns/refs/ folder.
    - First, you'll need to ensure you have existing certificates created that you want to target for updates from the LE cert renewals.
      ```
      cc
      OBJS
      ca
      host_key_cert
      tab tab (hit it twice to list existing REF_* for each cert).
      exit
      ```
    - Create a file named after the primary domain (first domein on each line of ~/leutmdns/domains.txt).  If your domains.txt file contains domain.com www.domain.com on line 1, and www.domain.net www2.domain.net on line 2:
      ```bash
      cd ~/leutmdns/refs
      echo REF_123456789 >> domain.com
      echo REF_987654321 >> www.domain.net
      ```
11. Run a test!
    - Again ensure you're targeting the staging LE servers.
    - Probably a good idea not to target any active certs in the UTM, so create a fake one to test with.
    - Kick off the proces (in ~/leutmdns folder): `./dehydrated -c`
12. Update domains.txt, REF_ files, and switch staging urls to prod urls in the config file and go live with it.
### Automate
TODO: Create steps to add this as a cron to the UTM box.
### Notes
- UTM uses a customized openssl.cnf file in /etc/ssl that doesn't work well unless provided proper ENV variables.  Dehydrated stock script didn't provide the --cert flag during the certificate request which caused openssl to try and load up the UTM openssl.cnf file.  I've updated the dehydrated script on line 619 to include the flag to the openssl.cnf file path provided in the ~/leutmdns/config file to resolve.
- Ensure you have a file for each DNS zone you will be updating using the proper naming scheme in the tsig folder.
- Ensure you have a file for each certificate named after the domain (the first domain per line/cert in domains.txt file) containing the REF_* to your UTM certificate object.
## Dependencies
We make use of the following submodule dependencies so as not to reinvent the wheel.
- [Dehydrated](https://github.com/lukas2511/dehydrated) - Modified
- [utm-update-certificate](https://github.com/mbunkus/utm-update-certificate.git)
- [Dehydrated Hook Example](https://ente.limmat.ch/ftp/pub/software/bash/letsencrypt/letsencrypt_acme_dns-01_challenge_hook) - Modified
## Contributing
### Development Setup
1. Download the git repo to your local environment and load the submodules.
   ```bash
   git clone --recursive https://github.com/kyse/letsencrypt-sophosutm-dns.git leutmdns
   ```

