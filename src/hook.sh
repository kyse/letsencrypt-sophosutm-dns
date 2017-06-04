#!/usr/bin/env bash

# acme dns-01 challenge hook script v0.0.2

# This script has been modified 6/4/2017 by Jared Fisher - kyse@kyse.us
# - Added ability to speficy an external dns server for dig lookups to avoid split brain DNS issues.
# - Updated to only require a TSIG file for the zone, not for each individual FQDN.
# - Added support to match up domains to UTM REF_ object names.
# - Added support to call a specified UTM update certificate hook.

# Publish an acme challenge in DNS. This script is made to work with letsencrypt.sh by lukas2511.
# You need a Bind DNS Server you can publish records using nsupdate. The script was written and
# tested in Debian GNU/Linux, it uses the GNU versions of sed, grep, date, etc. You need dig to be
# installed. Version 0.0.2 of this script works only with TSIG keys (not with SIG(0) key pairs).

# You need to fill in the DNS server you want to send your nsupdate commands to in the variable
# SERVER below the introductory remarks. Also set KEYPATH to point to your TSIG key directory.

# You need to create a TSIG key for each domain you want to publish an acme dns challenge
# with this script. The script calls the nsupdate command to publish the challenge in your
# Bind DNS Server. Nsupdate needs the TSIG key in order to be authenticated on Bind. You need
# to configure Bind to know this key and you need to grant access for nsupdate to alter the 
# _acme-challenge record for every host you include in the let's encrypt certificate. There are
# several tutorials how to set this up, e.g. see the first part of the following page to get an
# idea: 
#    https://www.kirya.net/articles/running-a-secure-ddns-service-with-bind/
#
# You need to configure this on the master DNS server!
#
# Restrict the updating of the _acme-challenge record as much as possible. Use a statement like
# the following inside your zone section:
#    update-policy {
#        grant _acme-challenge.domain.tld. name _acme-challenge.host.domain.tld. TXT;
#        };
# ...where the first part after grant is your key name and the part before TXT a host you request
# the certificate for. Put one grant line like this for each host you include in the cert!
# If you connect to a secondary DNS with this script, in addition to the above on the master, configure
# on the slave inside the slave zone section a statement 
#    allow-update-forwarding { secondary; };
# ...where "secondary" is an ACL (that could be named as you like) and has to be defined in its own
# section:
#    acl secondary {
#         1.2.3.4/32;
#         127.0.0.1/32;
#    };

# If you have many domains on your server you should not need to do all this manually. I may release some
# more scripts to assisst you with the job. Unfortunately they are not releasable in their current state.

# Comments and corrections welcome.

# (c) 2016 under GPL v2 by Adrian Zaugg <adi@ente.limmat.ch>.



# Path to the directory where your nsupdate keys are stored (one for each domain,
# named K_acme-challenge.domain.tld.+157+<...>.private)
KEYPATH="`dirname $0`/tsig"

# DNS Server to update
SERVER="update.dyndns.com"

# Time To Live to set for the challenge
TTL=10

# Max time to try to check the challenge on all authoritative name servers for the domain
CHECK_NS_TIMEOUT=10

# If your using this script behind a split brain DNS, specify a DNS server here to use to retrieve
# authenticated server info for confrming DNS-01 challenge deployment.
#EXTERNALNS="ns1.mydyndns.org"

# Path to hook used to update UTM certificates.
UPDATECERTHOOK="`dirname $0`/utm_update_certificate.pl"

# Path to the directory where your REF_ names are stored (one for each cert.
REFPATH="`dirname $0`/refs"


# ------- do not edit below this line -------

ACME_STRING="_acme-challenge"
reason="$1"
#HOST="$2"
#CHALLENGE="$4"


# execute nsupdate update function
update_dns() {
	echo -n " + Updating DNS $SERVER: $reason for $HOST... " >&2
	ERR="$(nsupdate -k "$KEYFILE" 2>&1 << \
EOF
server $SERVER
zone $ZONE
$1
send
EOF
	)"

	if [ $? -ne 0 ]; then
   		echo "$ERR" >&2
   		exit 1
	else
		echo "ok." >&2
	fi
}

setup_cmd() {
  # select nsupdate key and get its zone
  ZONE="$HOST"
  TLD="$(echo "$ZONE" | sed -e "s/^.*\.//")"

  until [ "${ZONE}" = "$TLD" ]; do
	  KEYFILE="$(ls -1 "${KEYPATH}/K${ACME_STRING}.${ZONE}.+157+"*.private 2>/dev/null)"
	  if [ $? -eq 0 ]; then break; fi
	  ZONE="$(echo "$ZONE" | sed -e "s/^[^.]*\.//")"
  done
  if [ $(echo "$KEYFILE" | wc -l) -gt 1 ]; then
	  echo " ERROR: Multiple nsupdate key files for $HOST found. Please correct!" >&2
  	exit 1
  elif [ -z "$KEYFILE" ]; then
  	echo " ERROR: No nsupdate key file for zone $HOST found. Can't publish challenge without." >&2
  	exit 1
  fi

  # construct line to update dns zone with
  update_data="${ACME_STRING}.${HOST}.	$TTL	IN	TXT	\"$CHALLENGE\""
  
  # get all authoritative name servers
  nslookup=""
  [ ! -z ${EXTERNALNS} ] && nslookup="@${EXTERNALNS}"
  nsservers="$(dig +noall +authority ${HOST} ${nslookup})"
  if [ $(echo "$nsservers" | egrep -c "[ \t]*SOA[ \t]*") -eq 1 ]; then
  	# it seems the parent zone knows about the name servers
  	auth_zone="$(echo "$nsservers" | sed -e "s/[ \t]\+.*$//" -e "s/\.$//")"
  	nsservers="$(dig +noall +authority ${auth_zone} ${nslookup})"
  fi
  nsservers="$(echo "$nsservers" | sed -e "s/^.*\t//g" -e "s/\.$//")"
}

get_ref() {
  if [ -z "${REFPATH}/${DOMAIN}" ]; then
    echo " ERROR: No ref file for domain '$DOMAIN'.  Please provide a file containing the REF_ string."
    exit 1
  fi
  DOMAINREF="$(cat "${REFPATH}/${DOMAIN}")"
  if [ -z "${DOMAINREF}" ]; then
    echo " ERROR: ref file appears empty.  Please correct."
    exit 1
  fi
}

case "$reason" in

	deploy_challenge)
    HOST="$2"
    CHALLENGE="$4"
    
    setup_cmd

		# delete any previous challenge
		old_challenges="$(dig +short ${ACME_STRING}.${HOST}. TXT ${nslookup})"
		for old_challenge in $old_challenges; do
			reason="deleting previous challenge"
			update_dns "update delete ${ACME_STRING}.${HOST}.    $TTL    IN      TXT	$old_challenge"
		done
		
		# publish challenge
		reason="publishing acme challenge"
		update_dns "update add $update_data"

		# ensure all NS got the challenge
		let -i ns_ok_cnt=0
		let -i ns_cnt=0

		# test challenge on each name server
		for ns in $nsservers; do
			timestamp=$(date "+%s")
			dig_result="failed."
			echo -ne "\t+ Checking challenge on $ns.. " >&2
			# try max. CHECK_NS_TIMEOUT seconds
			while [ $(($(date "+%s")-$timestamp)) -lt $CHECK_NS_TIMEOUT ]; do
				msg="$(dig +short "${ACME_STRING}.${HOST}" TXT @${ns} 2>&1)"
				if [ $? -eq 0 -a "$msg" = "\"$CHALLENGE\"" ]; then
					dig_result="ok."
					let "ns_ok_cnt+=1"
					break;
				elif [ $? -gt 0 -a -n "$msg" ]; then
					dig_result="failed: $(echo "$msg" | sed -e "s/^;; //")"
				fi
				sleep 0.5
			done
			echo "$dig_result" >&2
			let "ns_cnt+=1"
		done
		# if there was no answer or just errors from dig exit non-zero
		[ $ns_ok_cnt -eq 0 ] && echo -e "\tERROR: None of the name server\(s\) answer the challenge correctly." >&2 && exit 1
		# Report some NS failed
		[ $ns_ok_cnt -lt $ns_cnt ] && echo -e "\tWARNING: Only $ns_ok_cnt out of $ns_cnt name servers do answer the challenge correctly." >&2
		;;

	clean_challenge)
		HOST="$2"
    CHALLENGE="$4"
    setup_cmd
    reason="removing acme challenge"
		update_dns "update delete $update_data"
		;;

  deploy_cert)
    DOMAIN="${2}"
    KEYFILE="${3}"
    CERTFILE="${4}"
    FULLCHAINFILE="${5}"
    CHAINFILE="${6}"
    TIMESTAMP="${7}"
    reason="deploy_cert"
    #echo "Args for $reason"
    #echo "DOMAIN: $DOMAIN"
    #echo "KEYFILE: $KEYFILE"
    #echo "CERTFILE: $CERTFILE"
    #echo "FULLCHAINFILE: $FULLCHAINFILE"
    #echo "CHAINFILE: $CHAINFILE"
    #echo "TIMESTAMP: $TIMESTAMP"

    if [ -z "${UPDATECERTHOOK}" ]; then
      echo " ERROR: UTM Certificate update hook couldn't be found." >&2
      exit 1
    fi

    get_ref
    
    echo "Args: $DOMAINREF $CERTFILE $KEYFILE"
    "${UPDATECERTHOOK}" "${DOMAINREF}" "${CERTFILE}" "${KEYFILE}"
    ;;

	unchanged_cert)
		HOST="$2"
    reason="nothing to do!"
		;;
  
  exit_hook)
    reason="nothing to do!"
    ;;

	*)
		echo "Unknown hook: ${reason}"
		exit 1
		;;
esac

exit 0
