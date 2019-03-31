#!/bin/bash

# Specify domain names to automatically update
#
# domains=("mydomain1.com" \
# "mydomain2.com" \
# "somedomain.com" \ 
# ... )

domains=("mydomain1.com" \
"mydomain2.com")

# DKIM key directory
keydir=/etc/opendkim/keys

# NSUPDATE config
# Your DNS server IP
dns_server=ns.mydomain1.com
# Your DNS server port
dns_port=53

# Command for generating DKIM keys
command="opendkim-genkey -D $keydir/ -s dkim -b 1024"

# Remove all old keys
echo "Removing old keys..."
rm $keydir/*

# Set up NSUPDATE batch update file
echo "server $dns_server $dns_port" > /etc/opendkim/dns_update.txt

# Add domain to NSUPDATE batch update file
update_ns() {
	
	# Get the TXT record of the new DKIM key
    txt=$(cat /etc/opendkim/keys/$1.txt | tr '\t' ' ' | tr -s ' ' | tr '\n' ' ' | sed 's/_domainkey/_domainkey.'$1'./m' | sed 's/IN/1200 IN/m' | sed 's/;[[:space:]]-\{5,\}.*//gm' | sed 's/"[[:space:]]*"//g' | sed 's/(//g' | sed 's/)//g')

	# Add DNS updating query to NSUPDATE batch update file
    echo "
zone $1
update delete dkim._domainkey.$1
send
update add $txt
send" >> /etc/opendkim/dns_update.txt

}

# Create new DKIM key for each domain
for index in ${!domains[*]}
do
    echo "Issuing DKIM for ${domains[$index]}"
    eval "$command -d ${domains[$index]}"
    mv $keydir/dkim.private $keydir/${domains[$index]}.private
    mv $keydir/dkim.txt $keydir/${domains[$index]}.txt

    update_ns ${domains[$index]}

done

# Execute NSUPDATE batch update for all domains
echo "Updating DNS entries..."
nsupdate -v -k /etc/opendkim/dkim_update.key /etc/opendkim/dns_update.txt

# Update file permissions
chown -R opendkim:opendkim $keydir
chmod -R 0600 $keydir
chmod 0700 $keydir

# Restart the OpenDKIM service to fetch the updated keys
echo "Reloading opendkim service..."
service opendkim restart

echo "Done."