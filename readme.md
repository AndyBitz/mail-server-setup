# Mail Server Setup

Sets up a Postfix mail server on Ubuntu.

> Please let me know if you find any mistakes.


## Usage
Run the script `install.sh` to install postfix and dovecot.
Take a look at the source code to understand what happens and
how to configure it.

#### Add a new Domain
* Add the MX and TXT spf record
* Open the file `/etc/postfix/main.cf`
* Add the domain to `virtual_mailbox_domains`
* Add the account to `/etc/postfix/vmailbox`
* Reload the database with `postmap /etc/postfix/vmailbox`
* Add a new user to `/etc/postfix/users.passwd`
* Add the domain to the DKIM trusted list `/etc/opendkim/trusted`
* Add the domain to the Signing table `/etc/opendkim/signing.table`
* Reload postfix and opendkim

#### Setup server for another domain (not yet tested)
* Create a subdomain that points to the server A and AAAA
* Add another domain to the letsencrypt key
* Create an extra DKIM Key like in `dkim.sh` for the domain
* Don't forget to add the public key to the DNS records
* Follow the steps in `Add a new Domain`

#### Add DMARC
Add this DNS record: `_dmarc TXT v=DMARC1; p=quarantine; sp=quarantine;`

#### Add new users
> Only applicable to some configurations
* Create a hashed password with this command: `doveadm pw -s SHA512-CRYPT`.
* Add the new user and the hashed password to `/etc/postfix/users.passwd`.
* Make sure the new mailbox exists in either `/etc/postfix/virtual` for forwarding or `/etc/postfix/vmailbox` for vmailboxes.
* Run `postmap /etc/postfix/virtual` or `postmap /etc/postfix/vmailbox` depending on which file you changed.
* The new mailbox should just work without restarting the postfix or dovecot.

###### Resources

* [DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-postfix-on-ubuntu-18-04)
* [Kofler](https://kofler.info/dkim-konfiguration-fuer-postfix/)
* [Dovecot Docs](https://wiki2.dovecot.org)
* [Postfix Docs](http://www.postfix.org/documentation.html)
