#!/bin/bash
set -e
echo "Starting Registry Service Setup..."

# --- DocumentDB CA Bundle Download ---
if [[ "${DOCUMENTDB_HOST}" == *"docdb-elastic.amazonaws.com"* ]]; then
    CA_BUNDLE_URL="https://www.amazontrust.com/repository/SFSRootCAG2.pem"
    CA_BUNDLE_PATH="/app/certs/global-bundle.pem"
    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        curl -fsSL "$CA_BUNDLE_URL" -o "$CA_BUNDLE_PATH" || echo "Warning: Failed to download CA bundle"
    fi
elif [[ "${DOCUMENTDB_HOST}" == *"docdb.amazonaws.com"* ]]; then
    CA_BUNDLE_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
    CA_BUNDLE_PATH="/app/certs/global-bundle.pem"
    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        curl -fsSL "$CA_BUNDLE_URL" -o "$CA_BUNDLE_PATH" || echo "Warning: Failed to download CA bundle"
    fi
fi

if [ "$RUN_INIT_SCRIPTS" = "true" ]; then
    echo "Running in init mode..."
    exec "$@"
fi

if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB at ${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}..."
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time, sys
host = os.getenv('DOCUMENTDB_HOST', 'mongodb')
port = int(os.getenv('DOCUMENTDB_PORT', '27017'))
user = os.getenv('DOCUMENTDB_USERNAME', '')
pwd = os.getenv('DOCUMENTDB_PASSWORD', '')
backend = os.getenv('STORAGE_BACKEND', 'mongodb-ce')
use_tls = os.getenv('DOCUMENTDB_USE_TLS', 'false').lower() == 'true'
ca_file = os.getenv('DOCUMENTDB_TLS_CA_FILE', '/app/certs/global-bundle.pem')
if backend == 'mongodb-ce': use_tls = False
if use_tls and not os.path.exists(ca_file): use_tls = False
auth = 'SCRAM-SHA-256' if backend == 'mongodb-ce' else 'SCRAM-SHA-1'
if user and pwd:
    uri = f'mongodb://{user}:{pwd}@{host}:{port}/?authMechanism={auth}&authSource=admin'
else:
    uri = f'mongodb://{host}:{port}/'
tls_options = {'tls': use_tls}
if use_tls: tls_options['tlsCAFile'] = ca_file
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000, **tls_options)
        c.admin.command('ping')
        print('MongoDB is ready!')
        c.close(); break
    except Exception as e: print(f'MongoDB not ready yet: {e}')
    time.sleep(5)
PYEOF
    deactivate
fi

# Startup Registry
SECRET_KEY="${SECRET_KEY:-$(python3 -c 'import secrets; print(secrets.token_hex(32))')}"
echo "SECRET_KEY=${SECRET_KEY}" > /app/registry/.env

# Nginx Setup
mkdir -p /etc/nginx/lua /run/nginx /etc/nginx/conf.d
cp /app/docker/lua/*.lua /etc/nginx/lua/ 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default
sed -i 's|pid /run/nginx.pid;|pid /run/nginx/nginx.pid;|' /etc/nginx/nginx.conf || true

# Run Registry - it will generate the processed nginx config
cd /app && source /app/.venv/bin/activate
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# Wait for the Registry app to generate the Nginx config (without placeholders)
echo "Waiting for Registry to generate processed Nginx configuration..."
MAX_WAIT=60
TIMER=0
while [ $TIMER -lt $MAX_WAIT ]; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Nginx configuration ready."
            break
        fi
    fi
    sleep 2
    TIMER=$((TIMER + 2))
done

echo "Starting Nginx..."
nginx
echo "Registry fully operational."
tail -f /dev/null
