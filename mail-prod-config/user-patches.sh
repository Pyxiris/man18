echo "Applying user patches..."

# This lets postfix know that it is ok to relay these domains. Otherwise
# it would just reject the incoming mail with "Relay access denied".
postconf -e "relay_domains = $ODOO_RECEIVING_DOMAINS"

# Copy the standard smtp service and make a new one on port 12525
PORT=${MAILGATE_SMTP_PORT:-12525}

# Define a custom cleanup service that disables SRS (canonical maps)
# If we do not do this SRS rewrites the from emal making a bit of a mess.
# ** Note: This is only set on the smtpd-incoming-odoo service,
# so outgoing will continue to work with SRS. **
postconf -Me "cleanup-odoo/unix=cleanup-odoo unix n - n - 0 cleanup"
postconf -Pe \
    "cleanup-odoo/unix/sender_canonical_maps=" \
    "cleanup-odoo/unix/recipient_canonical_maps="

postconf -Me "$PORT/inet=$PORT inet n - n - - smtpd"
# Add configs to this new smtp service
postconf -Pe \
    "$PORT/inet/syslog_name=postfix/smtpd-incoming-odoo" \
    "$PORT/inet/cleanup_service_name=cleanup-odoo" \
    "$PORT/inet/smtpd_upstream_proxy_protocol=haproxy" \
    "$PORT/inet/content_filter=odoo_mailgate:dummy" \
    "$PORT/inet/local_recipient_maps=" \
    "$PORT/inet/smtpd_recipient_restrictions=permit_mynetworks,permit_auth_destination,reject"

postconf -Me "odoo_mailgate/unix=odoo_mailgate unix - n n - - pipe user=nobody argv=/usr/local/bin/odoo-mailgate-wrapper.sh"

# Setup Odoo mailgate script
cp /tmp/mailgate/odoo-mailgate.py /usr/local/bin/odoo-mailgate.py
chmod 755 /usr/local/bin/odoo-mailgate.py
cat <<EOF > /usr/local/bin/odoo-mailgate-wrapper.sh
#!/bin/sh
if ! /usr/bin/python3 /usr/local/bin/odoo-mailgate.py -d $ODOO_DB -u $ODOO_USER_ID -p $ADMIN_PASSWORD --host odoo --port 8069; then
    echo "Odoo mailgate failed. Discarding message." | logger -t odoo-mailgate -p mail.warn
    exit 0
fi
EOF
chmod 755 /usr/local/bin/odoo-mailgate-wrapper.sh
