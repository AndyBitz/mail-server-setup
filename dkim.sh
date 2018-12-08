#!/bin/bash

# Installs opendkim
# and tells how to configure it.


# The actual domain part of the emails
# eg. example.com
echo "> Enter the domain that will be used for your E-Mails:"
if [ ! "$MAIL_DOMAIN" ]; then read MAIL_DOMAIN; fi
echo -e "$MAIL_DOMAIN\n"


# Install opendkim
apt -qq update
apt install opendkim opendkim-tools -y


# Creates directory to store keys
echo -e "> Create directory /etc/opendkim/keys\n"
mkdir /etc/opendkim > /dev/null 2>&1
mkdir /etc/opendkim/keys > /dev/null 2>&1

# Set the rights for the directory
# User and group get created when installing
chown -R opendkim:opendkim /etc/opendkim
chmod go-rw /etc/opendkim/keys


# Backup the default config
cp /etc/opendkim.conf /root/opendkim.conf-$(date -I)

# Configure the installation
cat > /etc/opendkim.conf <<- EOM

# s = signer, v = verifier
Mode sv

# With inet: Socket inet:12301@localhost
# Socket local:/var/run/opendkim.sock
Socket inet:12301@localhost

# OpenDKIM default user
UserID opendkim:opendkim
UMask 002
PidFile /var/run/opendkim/opendkim.pid

# Restart OpenDKIM on errors
# But max. 10 times in an hour
AutoRestart yes
AutoRestartRate 10/1h

# Logging  
Syslog yes
#LogWhy yes
#SyslogSuccess yes

# How OpenDKIM processes the mail
Canonicalization relaxed/simple

# Ignore internal mails
ExternalIgnoreList refile:/etc/opendkim/trusted
InternalHosts refile:/etc/opendkim/trusted

# Which keys for which domains
# (refile: regex files)
SigningTable refile:/etc/opendkim/signing.table
KeyTable /etc/opendkim/key.table       

# Use this algorithm
SignatureAlgorithm rsa-sha256

# Always oversign From (sign using actual From and a null From to prevent
# malicious signatures header fields (From and/or others) between the signer
# and the verifier.  From is oversigned by default in the Debian pacakge
# because it is often the identity key used by reputation systems and thus
# somewhat security sensitive.
OversignHeaders From

EOM


# Which hosts are trusted
cat > /etc/opendkim/trusted <<- EOM
127.0.0.1
::1
localhost
$MAIL_DOMAIN

EOM


# Create a table that tells which key to use for which domain.
# The default will use a key with the same as the domain for
# every email on that domain.
cat > /etc/opendkim/signing.table <<- EOM
*@$MAIL_DOMAIN $MAIL_DOMAIN

EOM

# Uses the current year and month as keyname
DATE=$(date +"%Y%m")

# Table that tells where the key file is.
# The default key will have the domain name as name.
cat > /etc/opendkim/key.table <<- EOM
$MAIL_DOMAIN $MAIL_DOMAIN:$DATE:/etc/opendkim/keys/$MAIL_DOMAIN.private

EOM


# Create the default key pair
opendkim-genkey \
  --domain=$MAIL_DOMAIN \
  --bits=2048 \
  --restrict \
  --directory=/etc/opendkim \
  --selector=$DATE


# Move the keys to the correct location
mv /etc/opendkim/$DATE.private /etc/opendkim/keys/$MAIL_DOMAIN.private
mv /etc/opendkim/$DATE.txt /etc/opendkim/keys/$MAIL_DOMAIN.txt
chown -R opendkim:opendkim /etc/opendkim
chmod -R go-rwx /etc/opendkim/keys


# Show the TXT record
echo "> Add this TXT entry to your domains"
cat /etc/opendkim/keys/$MAIL_DOMAIN.txt
echo -e "\n"

# Verify the key
echo "> After adding the TXT record you can run"
echo "opendkim-testkey -d $MAIL_DOMAIN -s $DATE -vvv"
echo -e "\n"


# Update the postconf config
echo "> Enter the following commands to update postfix"

cat <<- EOM
  postconf -e "milter_protocol = 6"
  postconf -e "milter_default_action = accept"
  postconf -e "smtpd_milters = inet:localhost:12301"
  postconf -e "non_smtpd_milters = inet:localhost:12301"

EOM

# Restart the service
echo "> Restart the service then"
echo "service opendkim reload"
echo "service postfix reload"
