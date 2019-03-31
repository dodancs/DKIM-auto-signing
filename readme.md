# DKIM Auto-signing script tutorial

**DKIM Auto-signing script** is a Bash script which allows you to automatically refresh DKIM signing keys on your mail server and also update the DNS TXT records without any struggle and a drop of sweat.

Made by Dominik Dancs



## Prerequisites

This section of the tutorial covers the preparation for implementing my auto-signing solution for your e-mail server.



### Prepare Bind9 DNS server

Before you do anything, you will need to set up remote updating of your DNS records.

This section covers how to set up Bind9 DNS server to accept DNS record updates using [nsupdate](https://linux.die.net/man/8/nsupdate).



> __NOTE:__ If you do not host your own DNS server, please look at your DNS provider's API solutions.



#### Step 1: Generating TSIG key pair

SSH into your server where you have your DNS server and generate a key pair with *dnssec-keygen*:

```bash
dnssec-keygen -a HMAC-SHA512 -b 128 -n HOST <KEY NAME>
```

Replace *<KEY NAME>* with any name you would like e.g. **dkim_update_key**.



This command will generate a key and private pair which will look something like this:

**Kdkim_update_key.+165+46961.key**

```
dkim_update_key. IN KEY 512 3 165 ITrrJVXiESWS3UwM7z9wOw==
```

**Kdkim_update_key.+165+46961.private**

```
Private-key-format: v1.3
Algorithm: 165 (HMAC_SHA512)
Key: ITrrJVXiESWS3UwM7z9wOw==
Bits: AAA=
Created: 20190331085930
Publish: 20190331085930
Activate: 20190331085930
```

> You can rename these files to dkim_update_key.key and dkim_update_key.private.



From these files you will need the actual *secret* which is next to the Key: notation in the .private file:

**ITrrJVXiESWS3UwM7z9wOw==**



#### Step 2: Adding TSIG key to Bind9

First, you need to find your *named.conf* configuration file for the Bind9 DNS server.

After locating this file use any text editor you like and add these lines at the begining of the file:

```ini
key "dkim_update_key" {

    algorithm hmac-md5;
    secret "<YOUR KEY HERE>";

};
```

Replace `<YOUR KEY HERE>` with the secret you obtained in the previous step:

```
key "dkim_update_key" {

    algorithm hmac-md5;
    secret "ITrrJVXiESWS3UwM7z9wOw==";
    
};
```

Save the configuration file.



#### Step 3: Allow updating zones with this key

In this step we are going to tell Bind9 to allow certain zones to update with this TSIG key we just created.

Locate your *zone configuration file* for Bind9 and open it in any favourite editor. The contents should look something like this:

```ini
zone "mydomain1.com" { type master; file "named.mydomain1.com"; };
zone "mydomain2.com" { type master; file "named.mydomain2.com"; };
zone "myotherdomain.com" { type master; file "named.myotherdomain.com"; };
...
```

Locate *zone* segments for the zones you want to enable DKIM auto-signing.

Into each of these zones, we are going to add the following line at the end **allow-update { key "dkim_update_key"; };**. Your zone config file should now look like this:

```ini
zone "mydomain1.com" { type master; file "named.mydomain1.com"; allow-update { key "dkim_update_key"; }; };
zone "mydomain2.com" { type master; file "named.mydomain2.com"; allow-update { key "dkim_update_key"; }; };
zone "myotherdomain.com" { type master; file "named.myotherdomain.com"; };
...
```



**You can now restart Bind9 DNS server and continue onto the next step.**



> **NOTE:** Download your TSIG key and private pair for later use in another part of this tutorial!



### Prepare Postfix server for DKIM

This section covers preparing the mailing server for accepting DKIM and signing your e-mails.



#### Step 1: Update Postfix configuration

Locate the main Postfix configuration file which should be located under `/etc/postfix/main.cf`.

Make sure to add or uncomment these lines in the configuration file:

```
milter_protocol = 2
milter_default_action = accept
```



Next if the following parameters are present, just append the *opendkim milter to them* (milters are separated by a comma), the port number should be the same as in `opendkim.conf` (from next part of the tutorial):

```
smtpd_milters = unix:/spamass/spamass.sock, inet:localhost:12301
non_smtpd_milters = unix:/spamass/spamass.sock, inet:localhost:12301
```



If these parameters **were not present** then add the following lines:

```
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
```



### Set up OpenDKIM

This section covers setting up the OpenDKIM service on your mailing server and also introducing the **auto-signing script**.



#### Step 1: Before we start

Before we can do anything, you will need to install [**opendkim**](http://opendkim.org/) & [**nsupdate**](https://linux.die.net/man/8/nsupdate) packages on your server if they are not installed already.



After opendkim is installed, download the [**auto-signing script**](/projects/MOOWDESIGN/repos/dkmi-auto-signing/browse/dkim-autosigning.sh) from this repository into `/etc/opendkim/`. Also copy over the **TSIG key and private pair** from the previous chapter.



#### Step 2: Set up OpenDKIM

Locate OpenDKIM default config file which should be located under: `/etc/default/opendkim`. 

Comment out any *SOCKET* notation in the code, as we are going to use a different socket configuration.

Now add these configuration lines at the bottom of the file:

```ini
SOCKET="inet:12301@localhost"
USER=opendkim
GROUP=opendkim
PIDFILE=$RUNDIR/$NAME.pid
EXTRAAFTER=
```

This tells the OpenDKIM server to accept connections on **localhost** on port number **12301**.



Now locate the second OpenDKIM config file which should be located under: `/etc/opendkim.conf` and add these lines at the bottom of the configuration file:

```ini
UserID                  opendkim

AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  yes
SyslogSuccess           Yes
LogWhy                  Yes

Canonicalization        relaxed/simple

ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256

UserID                  opendkim:opendkim

Socket                  inet:12301@localhost
```



> **NOTE:** At the bottom, there is the Socket notation which specifies the socket on which the service listens. If you changed this in the previous step, replace the setting also here.



#### Step 3: Create TrustedHosts file

Under `/etc/opendkim/` create a new file called **TrustedHosts** and add all domain names you want to sign in here like so:

```ini
127.0.0.1
localhost
192.168.1.1/24

mydomain1.com
*.mydomain1.com
mydomain2.com
*.mydomain2.com
...
```



> **NOTE:** Do not replace the first 3 lines! These allow the local machine which hosts the Postfix mail service to communicate with OpenDKIM.
>
> The third line can be changed to the local IP address. e.g.: 10.0.0.15/24



#### Step 4: Create SigningTable file

Under `/etc/opendkim/` create a new file called **SigningTable**. This file will tell the OpenDKIM service which *signing domain to choose* when receiving an e-mail signing request.

Add all your domains in here as follows:

> Explanation: `<ANY USER>` @ `<YOUR DOMAIN>`  dkim._domainkey . `<YOUR DOMAIN>`

```ini
*@mydomain1.com dkim._domainkey.mydomain1.com
*@mydomain2.com dkim._domainkey.mydomain2.com
```



> **NOTE:** We are using `dkim._domainkey.` on all domains: as the `dkim` is the *DKIM identifier* and ` _domainkey` is the required subdomain used by the service
>
> You can also use a different *DKIM identifier* like any alpha-numeric string: `421378yr48firss._domainkey.` - but this tutorial and script uses **dkim** as the DKIM identifier for ease of use and not requiring complicated implementation.



If you want to also support e-mail addresses with **subdomains** add the following line:

> Explanation: `<ANY USER>` @ `<ANY SUBDOMAIN> `.` <YOUR DOMAIN>`  dkim._domainkey . `<YOUR DOMAIN>`

```ini
*@*.mydomain1.com dkim._domainkey.mydomain1.com
```



#### Step 5: Create KeyTable file

Under `/etc/opendkim/` create a new file called **KeyTable**. In here you will specify the *DKIM identifiers* for each domain and which key they are tied to like follows:

```ini
dkim._domainkey.mydomain1.com mydomain1.com:dkim:/etc/opendkim/keys/mydomain1.com.private
dkim._domainkey.mydomain2.com mydomain2.com:dkim:/etc/opendkim/keys/mydomain2.com.private
...
```

> Explanaton: `<DKIM IDENTIFIER>`._domainkey.`<YOUR DOMAIN>`   `<YOUR DOMAIN>`:`<DKIM IDENTIFIER>`:`<SIGNING KEY LOCATION>`



> **NOTE:** The file `/etc/opendkim/keys/mydomain1.com.private` is the signing key location which we have not yet created - but be sure to **keep the format like it is**!
>
> `/etc/opendkim/keys/<YOUR DOMAIN>.private`



> **NOTE:** If you were to use different *DKIM identifiers* for each domain, the file would look something like this:

```ini
421378yr48firss._domainkey.mydomain1.com mydomain1.com:421378yr48firss:/etc/opendkim/keys/mydomain1.com.private

1jh9d7hs99976ed._domainkey.mydomain2.com mydomain2.com:1jh9d7hs99976ed:/etc/opendkim/keys/mydomain2.com.private
...
```



For the sake of this tutorial, we are going to use the standardized *DKIM identifiers* - **dkim**. This also needs to be like this in order for the auto-signing script to work.



#### Step 6: Running the script

After setting up OpenDKIM you are now ready to use the auto-signing script.



First, let's look at it's code as we will need to add domains which we want to automatically update:

```bash
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
```



**Do not forget** to update the domains section on top of the script.



#### That's it! You've officially configured DKIM e-mail signing!

Now run the `dkim-autosigning.sh` script to generate your first DKIM keys!



To make things easy, you can now add this script into your **crontab** and run it on monthly bases.



### Thank you-s

- A huge thanks goes to DigitalOcean as they have awesome well-documented tutorials (https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-dkim-with-postfix-on-debian-wheezy)