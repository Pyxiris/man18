echo "Applying user patches..."

# Copy the standard smtp service and make a new one on port 12525
PORT=${MAILGATE_SMTP_PORT:-12525}

# This lets postfix know that it is ok to relay these domains. Otherwise
# it would just reject the incoming mail with "Relay access denied".
postconf -e "relay_domains = ${ODOO_RECEIVING_DOMAINS}"

# Define a custom cleanup service that disables SRS (canonical maps)
# If we do not do this SRS rewrites the from emal making a bit of a mess.
# ** Note: This is only set on the smtpd-incoming-odoo service,
# so outgoing will continue to work with SRS. **
postconf -Me "cleanup-odoo-incoming/unix=cleanup-odoo-incoming unix n - n - 0 cleanup"
postconf -Pe \
    "cleanup-odoo-incoming/unix/sender_canonical_maps=" \
    "cleanup-odoo-incoming/unix/recipient_canonical_maps="

postconf -Me "${PORT}/inet=${PORT} inet n - n - - smtpd"
# Add configs to this new smtp service
postconf -Pe \
    "${PORT}/inet/syslog_name=postfix/smtpd-incoming-odoo" \
    "${PORT}/inet/cleanup_service_name=cleanup-odoo-incoming" \
    "${PORT}/inet/smtpd_upstream_proxy_protocol=haproxy" \
    "${PORT}/inet/content_filter=odoo_mailgate:dummy" \
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
import shutil
import os

def log_message(level, message):
    """Logs a message to syslog via the logger command."""
    subprocess.run(['logger', '-t', 'odoo-mailgate', '-p', f'mail.{level}'], input=message.encode())

try:
    # Configuration from environment variables
    DB = "${ODOO_DB}"
    USER = "${ODOO_USER_ID}"
    PASSWORD = "${ADMIN_PASSWORD}"
    SECRET = "${HEADER_SECRET}"

    if not all([DB, USER, PASSWORD, SECRET]):
        log_message("err", "Odoo mailgate: Missing one or more required environment variables.")
        sys.exit(78)  # EX_CONFIG

    if ':' not in SECRET:
        log_message("err", "Odoo mailgate: HEADER_SECRET format is invalid. Expected 'Key:Value'.")
        sys.exit(78)  # EX_CONFIG

    headers = []
    authorized = False
    input_stream = sys.stdin.buffer

    secret_key, secret_val = [part.strip() for part in SECRET.split(':', 1)]
    secret_key = secret_key.lower()

    # Read headers line by line to avoid loading full message
    while True:
        line = input_stream.readline()
        if not line:
            break
        # An empty line signifies the end of the headers
        if line.strip() == b'':
            headers.append(line)
            break

        try:
            # Decode safely to check string content
            line_str = line.decode('utf-8', errors='ignore')
            if ':' in line_str:
                key, val = line_str.split(':', 1)
                if key.strip().lower() == secret_key:
                    if val.strip() == secret_val:
                        authorized = True
                    continue
        except (ValueError, IndexError):
            pass
        headers.append(line)

    if not authorized:
        log_message("warn", "Odoo mailgate: Unauthorized email dropped (secret header not found or invalid).")
        sys.exit(0)

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
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, text=False)
    try:
        proc.stdin.writelines(headers)
        shutil.copyfileobj(input_stream, proc.stdin)
    except BrokenPipeError:
        pass
    finally:
        if proc.stdin:
            proc.stdin.close()

    return_code = proc.wait()

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
