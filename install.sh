#!/bin/bash


# Don't forget to set up the A/CNAME and MX DNS records.
# Don't forget to set /etc/hostname and /etc/hosts too.


# If this is set a catchall
# for MAIL_DOMAIN will redirect to this
# eg. mymail@gmail.com
echo "> Enter an email if you want everything"
echo "  redirected to your existing email:"
if [ ! "$FORWARD_EMAIL" ]; then read FORWARD_EMAIL; fi
echo -e "$FORWARD_EMAIL\n"


# The actual domain part of the emails
# eg. example.com
echo "> Enter the domain that will be used for your E-Mails:"
if [ ! "$MAIL_DOMAIN" ]; then read MAIL_DOMAIN; fi
echo -e "$MAIL_DOMAIN\n"


# The domain of the current server
# The domain which the MX record points to
# eg. mail.example.com
echo "> Enter the domain that will be set in your MX records:"
if [ ! "$SERVER_DOMAIN" ]; then read SERVER_DOMAIN; fi
echo -e "$SERVER_DOMAIN\n"


# Default UID and GID for the vmail user
DEFAULT_VMAIL_ID=5000


# Install Certbot for Let's Encrypt
if ! type "certbot" &> /dev/null; then
  apt -qq update
  apt install software-properties-common -y
  add-apt-repository universe
  add-apt-repository ppa:certbot/certbot
  apt -qq update
  apt install certbot -y
fi


# Setup Certbot
if [ ! -d "/etc/letsencrypt/live/$SERVER_DOMAIN" ]; then
  # Request only if it doesn't exist already
  certbot certonly --standalone -d $SERVER_DOMAIN
fi


# Setup the hook
# Will restart postfix and dovecot
HOOK_FILE=/etc/letsencrypt/renewal-hooks/post/postfix.sh
> $HOOK_FILE
echo '#!/bin/sh' >> $HOOK_FILE
echo 'service postfix reload' >> $HOOK_FILE
echo 'service dovecot reload' >> $HOOK_FILE
echo '' >> $HOOK_FILE


# Install Postfix
if ! typeof "postfix" &> /dev/null; then
  apt update
  DEBIAN_PRIORITY=low apt install mailutils
fi


# Configure Postfix

# Enable TLS for outgoing mails
# https://kofler.info/postfix-tls-optionen/

# Must use fullchain.pem
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtpd_tls_security_level = encrypt"
postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$SERVER_DOMAIN/privkey.pem"
postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$SERVER_DOMAIN/fullchain.pem"

postconf -e "myhostname = $SERVER_DOMAIN"
 
postconf -e 'smtp_tls_protocols = !SSLv2,!SSLv3,!TLSv1'
postconf -e 'smtp_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1'
postconf -e 'smtpd_tls_protocols = !SSLv2,!SSLv3,!TLSv1'
postconf -e 'smtpd_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1'
postconf -e 'smtpd_tls_exclude_ciphers = aNULL, LOW, EXP, MEDIUM, ADH, AECDH, MD5, DSS, ECDSA, CAMELLIA128, 3DES, CAMELLIA256, RSA+AES, eNULL'


# Forward all incoming E-Mails
# Don't overwrite an existing file
# See https://www.binarytides.com/postfix-mail-forwarding-debian/
if [ "$FORWARD_EMAIL" ] && [ ! -f /etc/postfix/virtual ]; then
  postconf -e "virtual_alias_domains = $MAIL_DOMAIN"
  postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"

  # Catchall
  echo "@$MAIL_DOMAIN $FORWARD_EMAIL" >> /etc/postfix/virtual

  postmap /etc/postfix/virtual
fi

# Creates virtual mailboxes
# So there won't be a need for multiple UNIX users
if [ "$MAILBOX_DOMAIN" ] && [ ! -f /etc/postfix/vmailbox ] && [ ! -f /etc/postfix/virtual ]; then

  # Createa the vmail user and group
  VMAIL=$(id -g vmail)

  if [ "$?" = "1" ]; then
    groupadd -g $DEFAULT_VMAIL_ID vmail
    useradd -u $DEFAULT_VMAIL_ID -g $DEFAULT_VMAIL_ID vmail
    mkdir /home/vmail
    chown -R vmail:vmail /home/vmail
    VMAIL=$DEFAULT_VMAIL_ID
  fi

  # Make sure to create the subdirectories
  # for every domain in /home/vmail as well!
  echo "Make sure to create a folder for every domain in /home/vmail!"

  # virtual_mailbox_domains and virtual_alias_domains should not contain equal values
  postconf -e "virtual_mailbox_domains = $MAILBOX_DOMAIN"
  postconf -e "virtual_mailbox_base = /home/vmail"
  postconf -e "virtual_mailbox_maps = hash:/etc/postfix/vmailbox"
  postconf -e "virtual_minimum_uid = $VMAIL"
  postconf -e "virtual_uid_maps = static:$VMAIL"
  postconf -e "virtual_gid_maps = static:$VMAIL"
  postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"

  # This file maps all mailboxes to folders
  # Example: info@example.com example.com/info
  echo "" > /etc/postfix/vmailbox

  # This file allows to create redirects
  # to local UNIX users or external services
  # See the Catchall example in the $FORWARD_EMAIL section
  echo "" > /etc/postfix/virtual

  postmap /etc/postfix/virtual
  postmap /etc/postfix/vmailbox
fi


# Enable Dovecot SMTP
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"

postconf -e "smtpd_tls_auth_only = yes"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_tls_security_level = encrypt"

# This is required, otherwise the server will reject everything incoming
postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"


# Enable Submission SMTP with SASL
POSTFIX_MASTER_FILE=/etc/postfix/master.cf

if ! grep "^submission" $POSTFIX_MASTER_FILE > /dev/null; then
cat >> $POSTFIX_MASTER_FILE <<- EOM
# Adds the submission SMTP service on port 587
submission inet n - y - - smtpd
  -o syslog_name=postfix/submission
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject

EOM
fi


# Install Dovecot
# For SASL (SMTP and IMAP)
if ! type "dovecot" &> /dev/null; then
  apt install dovecot-core dovecot-imapd
  cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.$(date -I)
fi


# Update the Dovecot config
# <<- The "-" ignores leading tabs
DOVECOT_CONFIG_FILE=/etc/dovecot/dovecot.conf

cat > $DOVECOT_CONFIG_FILE <<- EOM
mail_privileged_group = mail

# Depending on what you specified in
# /etc/postfix/vmailboxe
# If the paths end with a "/" they will use maildir otherwise it will be mailbox.
# This assumes somthing like this "info@mail.com /home/vmail/mail.com/info/mail"
mail_location = maildir:~/mail

protocols = imap

# ensures ipv4 and ipv6
# some clients might not use ipv6
listen = 0.0.0.0 ::

ssl = required
ssl_key = </etc/letsencrypt/live/$SERVER_DOMAIN/privkey.pem
ssl_cert = </etc/letsencrypt/live/$SERVER_DOMAIN/fullchain.pem

ssl_protocols = !SSLv3
#auth_verbose=yes
#auth_debug_passwords=yes

disable_plaintext_auth = yes
auth_mechanisms = plain login

passdb {
  driver = passwd-file
  args = username_format=%u /etc/postfix/users.passwd
}

userdb {
  driver = passwd-file
  args = username_format=%u /etc/postfix/users.passwd
  default_fields = uid=vmail gid=vmail home=/home/vmail/%d/%n
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}

namespace {
  inbox = yes
  separator = /
}

EOM


# Fixing a Dovecot Config
# https://blog.dhampir.no/content/dovecot-master-error-systemd-listens-on-port-143-but-its-not-configured-in-dovecot-closing
systemctl disable dovecot.socket


# Reload the services
service dovecot reload
service postfix reload
