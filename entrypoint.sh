#!/bin/sh
# WriteFreely entrypoint: generate the config from Railway's environment,
# initialize the SQLite database and seed the admin account exactly once
# per volume, then serve.
#
# Upstream facts (writefreely/writefreely v0.17.3, verified in source):
# - The server refuses to start without a config file (app.go Initialize
#   errors "No configuration file yet"), and the only non-interactive way
#   to make one is `writefreely --create-config` (writes config.New()
#   defaults: port 8080, bind localhost, MySQL). The wrapper instead writes
#   /data/config.ini directly every boot, so PORT and the public host always
#   track the live Railway environment.
# - Config sections are [server] (port, bind, keys_parent_dir), [database]
#   (type, filename), [app] (host, site_name, theme, single_user,
#   open_registration, federation). Defaults come from config.New().
# - `writefreely -c <config> --init-db` creates the schema (app.go
#   CreateSchema); `--create-admin user:pass` creates an admin user
#   (CreateUser, isAdmin=true). Both are plain CLI flags, no web wizard.
# - Keys live under the configured keys_parent_dir; the stock image's
#   VOLUME /go/keys is bypassed by pointing it at /data/keys.
# - Single-user mode (single_user=true, max_blogs=1 default) makes the
#   seeded admin's blog the site's landing page; open registration stays off.
set -e

WF_BIN="/go/cmd/writefreely/writefreely"
CONFIG="/data/config.ini"
DB="/data/writefreely.db"
PORT="${PORT:-8080}"

mkdir -p /data/keys

# The public host is derived at boot from the live Railway domain — never a
# baked template expression (a ${{RAILWAY_PUBLIC_DOMAIN}} set before the
# domain exists resolves to a bare https:// and breaks federation links).
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    WF_HOST="https://${RAILWAY_PUBLIC_DOMAIN}"
else
    WF_HOST="http://localhost:${PORT}"
fi

cat > "$CONFIG" <<EOF
[server]
port = ${PORT}
bind = 0.0.0.0
keys_parent_dir = /data/keys

[database]
type = sqlite3
filename = /data/writefreely.db

[app]
host = ${WF_HOST}
site_name = WriteFreely
theme = write
single_user = true
open_registration = false
federation = true
EOF

# The binary reads templates/static/pages relative to its working directory,
# so run everything from the stock WORKDIR /go.
cd /go

# Initialize the database once per volume (guarded by the DB file itself;
# --init-db errors if the schema already exists).
if [ ! -f "$DB" ]; then
    echo "entrypoint: initializing database"
    "$WF_BIN" -c "$CONFIG" --init-db
fi

# Seed the admin account once per volume. The username is `owner`, NOT
# `admin`: upstream reserves "admin" (author/author.go reservedUsernames)
# and --create-admin fails with "Username admin is invalid, reserved...".
# The generated password comes from the template variable; changing it
# later does NOT reset the admin password (use the in-app account
# settings instead). The password must not contain a colon —
# --create-admin parses "username:password" on the first colon.
if [ ! -f /data/.admin-created ]; then
    if [ -z "${WRITEFREELY_ADMIN_PASSWORD:-}" ]; then
        echo "entrypoint: admin not seeded and WRITEFREELY_ADMIN_PASSWORD is not set — failing loud"
        exit 1
    fi
    case "$WRITEFREELY_ADMIN_PASSWORD" in
        *:*)
            echo "entrypoint: WRITEFREELY_ADMIN_PASSWORD must not contain a colon — failing loud"
            exit 1
            ;;
    esac
    echo "entrypoint: creating admin account"
    "$WF_BIN" -c "$CONFIG" --create-admin "owner:${WRITEFREELY_ADMIN_PASSWORD}"
    touch /data/.admin-created
else
    echo "entrypoint: admin account already seeded, skipping"
fi

# Generate the encryption keys (email, session, CSRF) under /data/keys.
# Serve-time InitKeys does NOT create them — it fails loud with "Missing
# encryption keys ... run: writefreely keys generate". --gen-keys is
# idempotent (generateKey skips files that already exist), so it is safe
# to run on every boot; keys are created once per volume and survive
# redeploys on the volume.
"$WF_BIN" -c "$CONFIG" --gen-keys

# Serve in the foreground.
exec "$WF_BIN" -c "$CONFIG"
