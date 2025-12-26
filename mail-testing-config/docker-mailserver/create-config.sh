#!/bin/sh

# Setup postfix/dovecot account
echo "$MAILBOX_USER@$MAILBOX_DOMAIN|{PLAIN}$ADMIN_PASSWORD" >> /tmp/docker-mailserver/postfix-accounts.cf

# Set up client access to redirect outgoing from odoo (through mailpit) to dovecot
: > /tmp/docker-mailserver/postfix-client-access.cf
echo "/$SMTP_SERVICE_NAME/ REDIRECT $MAILBOX_USER@$MAILBOX_DOMAIN" >> /tmp/docker-mailserver/postfix-client-access.cf

# Setup postfix transport map
: > /tmp/docker-mailserver/postfix-transport-map.cf
## Mail coming from odoo is delivered to roundcube's mailbox in dovecot
echo "$MAILBOX_USER@$MAILBOX_DOMAIN lmtp:unix:/var/run/dovecot/lmtp" >> /tmp/docker-mailserver/postfix-transport-map.cf
## Mail for the receiving domains is handled by odoo's mailgate without being redirected to an alias
for domain in $(echo "$ODOO_RECEIVING_DOMAINS" | tr ',' ' '); do
    echo "$domain odoo_mailgate:" >> /tmp/docker-mailserver/postfix-transport-map.cf
done
## Discard everything else
echo "* discard:" >> /tmp/docker-mailserver/postfix-transport-map.cf

# Define the 'odoo_mailgate' service in master.cf
# Note that we must do this in /etc/postfix/master.cf directly as docker-mailserver does not support
# defining custom services in /tmp/docker-mailserver/postfix-master.cf
echo "" >> /etc/postfix/master.cf
echo "odoo_mailgate unix  -       n       n       -       -       pipe" >> /etc/postfix/master.cf
echo "  user=nobody argv=/usr/local/bin/odoo-mailgate-wrapper.sh" >> /etc/postfix/master.cf

# Setup Odoo mailgate script
cp /tmp/odoo-mailgate.py /usr/local/bin/odoo-mailgate.py
chmod 755 /usr/local/bin/odoo-mailgate.py
echo '#!/bin/sh' > /usr/local/bin/odoo-mailgate-wrapper.sh
echo "/usr/bin/python3 /usr/local/bin/odoo-mailgate.py -d $ODOO_DB -u $USER_ID -p $ADMIN_PASSWORD --host odoo --port 8069" >> /usr/local/bin/odoo-mailgate-wrapper.sh
chmod 755 /usr/local/bin/odoo-mailgate-wrapper.sh
