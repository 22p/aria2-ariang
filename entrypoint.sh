#!/bin/sh
set -eu

WEB_PARENT=/www
WEBROOT=$WEB_PARENT/default.website
PRISTINE=/usr/share/aria2-ariang/web
CONF_DIR=/aria2/conf
DATA_DIR=/aria2/data
CONF_FILE=$CONF_DIR/aria2.conf
RPC_PORT=${ARIA2_RPC_PORT:-6800}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] error: %s\n' "$*" >&2; exit 1; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

is_uint "$PUID" || die "PUID must be a non-negative integer"
is_uint "$PGID" || die "PGID must be a non-negative integer"
is_uint "$RPC_PORT" || die "ARIA2_RPC_PORT must be a non-negative integer"
[ "$PUID" -ne 0 ] || die "PUID=0 is not supported: althttpd cannot serve requests as root"

ARIA2_UID=$PUID
ARIA2_GID=$PGID
case "${ARIA2_RUN_AS_ROOT:-}" in
    1)
        ARIA2_UID=0
        ARIA2_GID=0
        ;;
esac

# ---------------------------------------------------------------- aria2 ----
mkdir -p "$CONF_DIR" "$DATA_DIR"

if [ ! -f "$CONF_FILE" ]; then
    cp /etc/aria2/aria2.conf "$CONF_FILE"
    log "created default aria2 config at $CONF_FILE"
fi

if [ -n "${RPC_SECRET:-}" ]; then
    sed -i '/^[[:space:]]*rpc-secret[[:space:]]*=/d' "$CONF_FILE"
    printf 'rpc-secret=%s\n' "$RPC_SECRET" >>"$CONF_FILE"
else
    log "warning: RPC_SECRET is not set, the RPC endpoint is unauthenticated"
fi

if [ -n "${ARIA2_RPC_PORT:-}" ]; then
    sed -i '/^[[:space:]]*rpc-listen-port[[:space:]]*=/d' "$CONF_FILE"
    printf 'rpc-listen-port=%s\n' "$RPC_PORT" >>"$CONF_FILE"
fi

touch "$CONF_DIR/aria2.session"
chown "$PUID:$PGID" "$CONF_DIR" "$DATA_DIR" "$CONF_FILE" "$CONF_DIR/aria2.session"

# ------------------------------------------------------------------ web ----
# Rebuild the document root from the pristine copy so that restarts are
# idempotent (the AriaNg bundle is patched below with runtime values).
rm -rf "$WEBROOT"
mkdir -p "$WEBROOT"
cp -a "$PRISTINE/." "$WEBROOT/"
install -m 0755 /usr/local/share/aria2-ariang/jsonrpc "$WEBROOT/jsonrpc"

# AriaNg always talks to the same origin; althttpd proxies /jsonrpc to aria2.
for js in "$WEBROOT"/js/aria-ng-*.min.js; do
    [ -f "$js" ] || continue
    if grep -q 'rpcPort:"6800"' "$js"; then
        sed -i 's#rpcPort:"6800"#rpcPort:(window.location.port||(window.location.protocol==="https:"?"443":"80"))#g' "$js"
    else
        log "warning: could not patch the AriaNg RPC port, check the bundle layout"
    fi
    if [ -n "${EMBED_RPC_SECRET:-}" ] && [ -n "${RPC_SECRET:-}" ]; then
        if grep -q 'secret:""' "$js"; then
            secret_b64=$(printf '%s' "$RPC_SECRET" | base64 | tr -d '\r\n')
            sed -i "s#secret:\"\"#secret:\"${secret_b64}\"#g" "$js"
            log "embedded the RPC secret into the web UI"
        else
            log "warning: could not embed the RPC secret, check the bundle layout"
        fi
    fi
done

if [ -n "${BASIC_AUTH_USERNAME:-}" ] || [ -n "${BASIC_AUTH_PASSWORD:-}" ]; then
    [ -n "${BASIC_AUTH_USERNAME:-}" ] && [ -n "${BASIC_AUTH_PASSWORD:-}" ] \
        || die "BASIC_AUTH_USERNAME and BASIC_AUTH_PASSWORD must be set together"
    case "$BASIC_AUTH_USERNAME$BASIC_AUTH_PASSWORD" in
        *[[:space:]]*) die "basic auth credentials must not contain whitespace" ;;
    esac
    auth_file=$(mktemp)
    printf 'realm %s\nuser %s %s:%s\n' \
        "${BASIC_AUTH_REALM:-Aria2}" "$BASIC_AUTH_USERNAME" "$BASIC_AUTH_USERNAME" "$BASIC_AUTH_PASSWORD" \
        >"$auth_file"
    # althttpd only honours -auth for the directory that contains it.
    find "$WEBROOT" -type d -exec cp "$auth_file" '{}/-auth' \;
    find "$WEBROOT" -type d -exec chmod 0600 '{}/-auth' \;
    rm -f "$auth_file"
    log "HTTP basic auth enabled for user $BASIC_AUTH_USERNAME"
fi

# althttpd serves NAME.gz when the client supports gzip.
find "$WEBROOT" -type f \
    \( -name '*.html' -o -name '*.js' -o -name '*.css' -o -name '*.svg' -o -name '*.txt' \) \
    -exec sh -c 'gzip -9 -c "$1" >"$1.gz"' _ {} \;

chown -R "$PUID:$PGID" "$WEB_PARENT"

# -------------------------------------------------------------- servers ----
log "starting althttpd on :8080 (uid=$PUID gid=$PGID)"
su-exec "$PUID:$PGID" althttpd -root "$WEB_PARENT" -port 8080 --jail 0 &
althttpd_pid=$!

sleep 1
kill -0 "$althttpd_pid" 2>/dev/null || die "althttpd failed to start"

log "starting aria2c as $ARIA2_UID:$ARIA2_GID"
if [ "$ARIA2_UID" -eq 0 ]; then
    [ "$(id -u)" -eq 0 ] || die "ARIA2_RUN_AS_ROOT requires the container to start as root"
    exec aria2c "$@"
fi
exec su-exec "$ARIA2_UID:$ARIA2_GID" aria2c "$@"
