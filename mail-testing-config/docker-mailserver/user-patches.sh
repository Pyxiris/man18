#!/bin/bash
echo "Applying user patches..."

MAILBOX_USER=${MAILBOX_USER:-admin}
MAILBOX_DOMAIN=${MAILBOX_DOMAIN:-mailserver}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
SMTP_SERVICE_NAME=${SMTP_SERVICE_NAME:-smtp}
PORT=${MAILGATE_SMTP_PORT:-13525}
POSTFIX_DIR=/etc/postfix

# Port 25: redirect Mailpit (Odoo outgoing) into the Roundcube mailbox
CLIENT_ACCESS="${POSTFIX_DIR}/odoo-outgoing-client-access.cf"
: > "${CLIENT_ACCESS}"
echo "/${SMTP_SERVICE_NAME}/ REDIRECT ${MAILBOX_USER}@${MAILBOX_DOMAIN}" >> "${CLIENT_ACCESS}"
postconf -e "smtpd_client_restrictions = check_client_access regexp:${CLIENT_ACCESS}"

# Transport: Odoo domains -> mailgate; mailbox -> Dovecot LMTP; else discard
# (Mailpit traffic is redirected to the mailbox before transport lookup.)
TRANSPORT_MAP="${POSTFIX_DIR}/odoo-transport-map.cf"
: > "${TRANSPORT_MAP}"
echo "${MAILBOX_USER}@${MAILBOX_DOMAIN} lmtp:unix:/var/run/dovecot/lmtp" >> "${TRANSPORT_MAP}"
for domain in $(echo "${ODOO_RECEIVING_DOMAINS}" | tr ',' ' '); do
    echo "${domain} odoo_mailgate:" >> "${TRANSPORT_MAP}"
done
echo "* discard:" >> "${TRANSPORT_MAP}"
postconf -e "transport_maps = texthash:${TRANSPORT_MAP}"

postconf -e "relay_domains = ${ODOO_RECEIVING_DOMAINS}"

# Port 13525: Incoming to odoo from Roundcube — Odoo domains to mailgate, else to Dovecot
CANONICAL="${POSTFIX_DIR}/odoo-incoming-recipient-canonical.cf"
: > "${CANONICAL}"
# Catch ODOO_RECEIVING_DOMAINS addresses and map them to themselves.
# The rest goes to admin@mailserver
for domain in $(echo "${ODOO_RECEIVING_DOMAINS}" | tr ',' ' '); do
    domain_re=$(printf '%s' "${domain}" | sed 's/\./\\./g')
    echo "/(.*)@${domain_re}\$/ \$1@${domain}" >> "${CANONICAL}"
done
mailbox_re=$(printf '%s' "${MAILBOX_USER}@${MAILBOX_DOMAIN}" | sed 's/\./\\./g')
echo "/^(${mailbox_re})\$/ \$1" >> "${CANONICAL}"
echo "/.+/ ${MAILBOX_USER}@${MAILBOX_DOMAIN}" >> "${CANONICAL}"

postconf -Me "cleanup-odoo-incoming/unix=cleanup-odoo-incoming unix n - n - 0 cleanup"
postconf -Pe \
    "cleanup-odoo-incoming/unix/recipient_canonical_maps=regexp:${CANONICAL}" \
    "cleanup-odoo-incoming/unix/recipient_canonical_classes=envelope_recipient"

postconf -Me "${PORT}/inet=${PORT} inet n - n - - smtpd"
# Add configs to this new smtp service
postconf -Pe \
    "${PORT}/inet/syslog_name=postfix/smtpd-incoming-odoo" \
    "${PORT}/inet/cleanup_service_name=cleanup-odoo-incoming" \
    "${PORT}/inet/local_recipient_maps=" \
    "${PORT}/inet/smtpd_recipient_restrictions=permit_mynetworks,permit_auth_destination,reject"

postconf -Me "odoo_mailgate/unix=odoo_mailgate unix - n n - - pipe user=nobody argv=/usr/local/bin/odoo-mailgate-wrapper.py"

# Setup Odoo mailgate script
cp /tmp/mailgate/odoo-mailgate.py /usr/local/bin/odoo-mailgate.py
chmod 755 /usr/local/bin/odoo-mailgate.py
cat <<EOF > /usr/local/bin/odoo-mailgate-wrapper.py
#!/usr/bin/env python3
import sys
import subprocess

def log_message(level, message):
    """Logs a message to syslog via the logger command."""
    subprocess.run(['logger', '-t', 'odoo-mailgate', '-p', f'mail.{level}'], input=message.encode())

try:
    # Configuration from environment variables
    DB = "${ODOO_DB}"
    USER = "${ODOO_USER_ID}"
    PASSWORD = "${ADMIN_PASSWORD}"

    if not all([DB, USER, PASSWORD]):
        log_message("err", "Odoo mailgate: Missing one or more required environment variables.")
        sys.exit(78)  # EX_CONFIG

    # Pipe to odoo-mailgate
    cmd = [
        "/usr/bin/python3",
        "/usr/local/bin/odoo-mailgate.py",
        "-d", DB,
        "-u", USER,
        "-p", PASSWORD,
        "--host", "odoo",
        "--port", "8069",
    ]
    return_code = subprocess.run(cmd, stdin=sys.stdin.buffer).returncode

    if return_code != 0:
        log_message("warn", f"Odoo mailgate script failed with exit code {return_code}.")
        sys.exit(return_code)

except Exception as e:
    # Fail safe: log the error and exit with a temporary failure code
    # so the Mail Transfer Agent retries later.
    log_message("err", f"Odoo mailgate wrapper failed with an unexpected error: {e}")
    sys.exit(75) # EX_TEMPFAIL
EOF
chmod 755 /usr/local/bin/odoo-mailgate-wrapper.py
