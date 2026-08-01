# Devel mail testing (Stalwart + Bulwark)

## First-time setup

1. Download `stalwart-cli` for the bootstrap image (not committed):

   ```bash
   ./mail-testing-config/stalwart/prepare-stalwart-cli.sh
   ```

2. Start the stack (from repo root):

   ```bash
   docker compose -f devel.yaml up -d stalwart mailgate_hook webmail webmail_proxy smtp
   ```

## URLs and credentials (default `PORT_PREFIX=19`)

| Service                                    | URL                    |
| ------------------------------------------ | ---------------------- |
| Bulwark webmail (JMAP proxied same-origin) | http://localhost:19080 |
| Stalwart JMAP / admin (direct, curl/debug) | http://127.0.0.1:19825 |
| Mailpit UI                                 | http://127.0.0.1:19025 |

- Stalwart mailbox (Bulwark login): `admin@mail.test` / `develmail` (override with
  `STALWART_MAILBOX_PASSWORD`; Stalwart requires a strong password, 8+ characters)
- Stalwart recovery CLI user during bootstrap: `admin` / `admin`
  (`STALWART_RECOVERY_ADMIN`)
- `webmail_proxy` (Caddy) forwards `/.well-known/*` and `/jmap*` to Stalwart; Bulwark
  `/api/*` stays on the webmail app (do not route `/api` to Stalwart).
- Open **http://localhost:19080** (not `127.0.0.1` unless you change `JMAP_SERVER_URL`
  to match — CSP treats them as different origins)

## Mail flow (devel)

| Direction      | Path                                                                                                                          |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Odoo → Bulwark | Odoo → Mailpit (`smtp:1025`) → relay → Stalwart `:25` → Sieve redirects non-`@manmanufacturing.com` mail to `admin@mail.test` |
| Bulwark → Odoo | Bulwark JMAP send → Stalwart → MTA hook → `odoo-mailgate.py` → Odoo (only for `@manmanufacturing.com` recipients)             |

Mailpit must use a valid EHLO hostname (`mailpit.mail.test` on the `smtp` service). The
Stalwart MTA hook must reach `mailgate_hook` on the Docker network (service name
`mailgate_hook`, not `mailgate-hook`).

### Odoo inbound (required for Bulwark → Odoo)

Stalwart delivers `@manmanufacturing.com` mail to the mailgate hook. Odoo rejects it
with **“alias does not exist”** until inbound mail is configured:

1. In Odoo: **Settings → General Settings → Discuss** (or **Email**): set the
   **catch-all / custom domain** to `manmanufacturing.com` (and save).
2. Ensure a **mail alias** exists for the address you send to (e.g.
   `catchall@manmanufacturing.com` or `info@manmanufacturing.com`), or use the catch-all
   alias Odoo creates.
3. Send from Bulwark to that full address (not only the domain).

To verify the hook without the UI:

```bash
docker exec man18-19-mailgate_hook-1 python3 /mailgate/odoo-mailgate.py -d devel -u 2 -p admin --host odoo --port 8069 <<'EOF'
From: admin@mail.test
To: catchall@manmanufacturing.com
Subject: mailgate probe

test
EOF
echo "exit=$?"
```

Exit code `0` means Odoo accepted the message; `67` / “alias does not exist” means step
1–2 above is still missing.

### Odoo → Bulwark

Any Odoo email whose **To** is not `@manmanufacturing.com` (e.g. `admin@mail.test`)
should land in the Bulwark inbox after Mailpit relays to Stalwart. Check Mailpit logs
for `[relay] error` (EHLO/domain issues). Messages only in Mailpit UI were never relayed
to Stalwart.

## Reset Stalwart data

If bootstrap plans change, remove the Stalwart volumes and recreate:

```bash
docker compose -f devel.yaml rm -sf stalwart
docker volume rm man18-19_stalwart_etc man18-19_stalwart_data
docker compose -f devel.yaml up -d stalwart
```
