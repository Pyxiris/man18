#!/bin/sh
# Declarative bootstrap for devel Stalwart (mail.test + Odoo mailgate routing).
set -eu

export HOME=/tmp

DATA_DIR=/var/lib/stalwart
MARKER="${DATA_DIR}/.bootstrap-applied"
PLAN_DIR=/etc/stalwart-bootstrap
STALWART_BIN=/usr/local/bin/stalwart
STALWART_CLI=/usr/local/bin/stalwart-cli
STALWART_CFG=/etc/stalwart/config.json
LOCAL_URL=http://127.0.0.1:8080

log() { printf '[stalwart-bootstrap] %s\n' "$*" >&2; }

wait_for_http() {
  for _ in $(seq 1 90); do
    if curl -fsS -u "admin:${ADMIN_PASS}" "${LOCAL_URL}/jmap/session" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  log "Stalwart HTTP on :8080 did not come up in time"
  return 1
}

run_stalwart_bg() {
  "${STALWART_BIN}" --config "${STALWART_CFG}" &
  STALWART_PID=$!
}

stop_stalwart_bg() {
  if [ -n "${STALWART_PID:-}" ]; then
    kill -TERM "${STALWART_PID}" 2>/dev/null || true
    wait "${STALWART_PID}" 2>/dev/null || true
    STALWART_PID=
  fi
}

cli() {
  STALWART_URL=${LOCAL_URL} STALWART_USER=admin STALWART_PASSWORD=${ADMIN_PASS} "${STALWART_CLI}" "$@"
}

destroy_non_mail_listeners() {
  cli query NetworkListener 2>/dev/null | awk 'NR>1 && $2 !~ /^(smtp-inbound|submission|http-jmap)$/ {print $1, $2}' \
    | while read -r lid lname; do
      [ -n "${lid}" ] || continue
      log "Destroying listener ${lname} (${lid})"
      cli delete NetworkListener --ids "${lid}" >/dev/null 2>&1 || true
    done
}

disable_inbound_throttles() {
  for tid in $(cli query MtaInboundThrottle --json 2>/dev/null \
    | sed -E 's/.*"id":"([^"]+)".*/\1/' || true); do
    [ -n "${tid}" ] || continue
    log "Disabling MtaInboundThrottle ${tid}"
    cli update MtaInboundThrottle "${tid}" --field enable=false >/dev/null 2>&1 || true
  done
}

configure_devel_submission_auth() {
  log "Enabling cleartext SMTP AUTH on submission port (devel only)"
  cli update MtaStageAuth --field \
    'saslMechanisms={"match":{"0":{"if":"local_port != 25","then":"[plain, login]"}},"else":"false"}' \
    >/dev/null 2>&1 || log "WARNING: could not tune MtaStageAuth (continuing)"
}

configure_http_access() {
  log "Blocking WebDAV paths on the HTTP listener"
  cli update Http --json \
    '{"allowedEndpoints":{"match":[{"if":"!starts_with(url_path, '\''/dav'\'')","then":"200"}],"else":"403"}}' \
    >/dev/null 2>&1 || log "WARNING: could not set Http.allowedEndpoints (continuing)"
}

configure_data_stage_routing() {
  log "Attaching devel-routing Sieve script to SMTP DATA stage"
  cli update MtaStageData --json '{"script":{"else":"'"'"'devel-routing'"'"'"}}' >/dev/null 2>&1 \
    || log "WARNING: could not attach DATA stage Sieve script (continuing)"
}

configure_odoo_mailgate_hook() {
  HOOK_URL="http://mailgate_hook:8765/mta-hook"
  log "Registering Odoo mailgate MTA hook"
  hook_id=$(cli query MtaHook 2>/dev/null | awk 'NR>1 { print $1; exit }')
  if [ -n "${hook_id}" ]; then
    cli update MtaHook "${hook_id}" --field "url=${HOOK_URL}" >/dev/null 2>&1 \
      || log "WARNING: could not update MTA hook URL (continuing)"
    return 0
  fi
  cli create MtaHook --json \
    '{"url":"http://mailgate_hook:8765/mta-hook","stages":{"data":true},"enable":{"else":"true"},"httpAuth":{"@type":"Unauthenticated"},"tempFailOnError":true,"timeout":"60s"}' \
    >/dev/null 2>&1 || log "WARNING: could not register MTA hook (continuing)"
}

set_devel_mailbox_password() {
  account_id=$(cli query Account 2>/dev/null | awk '$2 == "admin@mail.test" { print $1; exit }')
  [ -n "${account_id}" ] || return 0
  log "Syncing mailbox password for admin@mail.test (ADMIN_PASSWORD, min 8 chars)"
  cli update Account "${account_id}" --json \
    "{\"credentials\":{\"0\":{\"@type\":\"Password\",\"secret\":\"${ADMIN_PASSWORD}\"}}}" \
    >/dev/null 2>&1 || log "WARNING: could not set mailbox password (Stalwart requires 8+ characters)"
}

reconcile_devel_tuning() {
  log "Reconciling devel MTA/JMAP settings"
  set_devel_mailbox_password
  configure_devel_submission_auth
  configure_http_access
  configure_data_stage_routing
  configure_odoo_mailgate_hook
}

if [ ! -f "${MARKER}" ]; then
  : "${STALWART_RECOVERY_ADMIN:?must be set for first-run bootstrap}"
  : "${ADMIN_PASSWORD:?must be set for first-run bootstrap}"
  if [ "${#ADMIN_PASSWORD}" -lt 8 ]; then
    log "ADMIN_PASSWORD must be at least 8 characters for Stalwart mailbox login"
    exit 1
  fi

  ADMIN_PASS=${STALWART_RECOVERY_ADMIN#*:}

  if [ -f "${STALWART_CFG}" ] && [ ! -f "${MARKER}" ]; then
    log "Removing incomplete configuration from a prior bootstrap attempt"
    rm -f "${STALWART_CFG}"
  fi

  log "Phase 1: starting Stalwart in bootstrap mode"
  run_stalwart_bg
  wait_for_http

  log "Applying plan-bootstrap.ndjson"
  cli apply --file "${PLAN_DIR}/plan-bootstrap.ndjson" --quiet

  log "Restarting Stalwart to leave bootstrap mode"
  stop_stalwart_bg
  run_stalwart_bg
  wait_for_http

  log "Applying plan-config.ndjson"
  if ! cli apply --file "${PLAN_DIR}/plan-config.ndjson" --quiet; then
    log "plan-config apply failed; wiping config so the next start can re-bootstrap"
    stop_stalwart_bg
    rm -f "${STALWART_CFG}"
    exit 1
  fi

  reconcile_devel_tuning
  destroy_non_mail_listeners
  disable_inbound_throttles

  log "Stopping bootstrap instance, marking complete"
  stop_stalwart_bg
  touch "${MARKER}"
fi

if [ -f "${MARKER}" ]; then
  ADMIN_PASS=${STALWART_RECOVERY_ADMIN#*:}
  : "${ADMIN_PASSWORD:?must be set}"
  run_stalwart_bg
  if wait_for_http; then
    reconcile_devel_tuning
    destroy_non_mail_listeners
  fi
  stop_stalwart_bg
fi

log "Starting Stalwart (final, foreground)"
exec "${STALWART_BIN}" --config "${STALWART_CFG}"
