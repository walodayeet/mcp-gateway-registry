#!/bin/bash
set -e
echo "Starting Registry Service Setup..."

# --- DocumentDB CA Bundle Download ---
if [[ "${DOCUMENTDB_HOST}" == *"docdb-elastic.amazonaws.com"* ]]; then
    CA_BUNDLE_PATH="/app/certs/global-bundle.pem"
    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        curl -fsSL "https://www.amazontrust.com/repository/SFSRootCAG2.pem" -o "$CA_BUNDLE_PATH" || true
    fi
elif [[ "${DOCUMENTDB_HOST}" == *"docdb.amazonaws.com"* ]]; then
    CA_BUNDLE_PATH="/app/certs/global-bundle.pem"
    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o "$CA_BUNDLE_PATH" || true
    fi
fi

# --- Wait for MongoDB ---
if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB at ${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}..."
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
host = os.getenv('DOCUMENTDB_HOST', 'mongodb')
port = int(os.getenv('DOCUMENTDB_PORT', '27017'))
backend = os.getenv('STORAGE_BACKEND', 'mongodb-ce')
use_tls = os.getenv('DOCUMENTDB_USE_TLS', 'false').lower() == 'true'
ca_file = os.getenv('DOCUMENTDB_TLS_CA_FILE', '/app/certs/global-bundle.pem')
if backend == 'mongodb-ce' or not os.path.exists(ca_file): use_tls = False
auth = 'SCRAM-SHA-256' if backend == 'mongodb-ce' else 'SCRAM-SHA-1'
user = os.getenv('DOCUMENTDB_USERNAME', '')
pwd = os.getenv('DOCUMENTDB_PASSWORD', '')
uri = f'mongodb://{user}:{pwd}@{host}:{port}/?authMechanism={auth}&authSource=admin' if user else f'mongodb://{host}:{port}/'
tls_opts = {'tls': use_tls}
if use_tls: tls_opts['tlsCAFile'] = ca_file
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, **tls_opts)
        c.admin.command('ping')
        print('MongoDB is ready!')
        c.close(); break
    except Exception as e: print(f'MongoDB not ready: {e}')
    time.sleep(5)
PYEOF
    deactivate
fi

# Startup Configuration
mkdir -p /etc/nginx/lua /run/nginx /etc/nginx/conf.d
cp /app/docker/lua/*.lua /etc/nginx/lua/ 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default
sed -i 's|pid /run/nginx.pid;|pid /run/nginx/nginx.pid;|' /etc/nginx/nginx.conf 2>/dev/null || true

# Run Registry (Background) - This generates the Nginx config
cd /app && source /app/.venv/bin/activate
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# Wait for processed Nginx config
echo "Waiting for Registry app to generate Nginx config..."
TIMER=0
while [ $TIMER -lt 60 ]; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Nginx config is ready."
            break
        fi
    fi
    sleep 2
    TIMER=$((TIMER + 2))
done

echo "Starting Nginx..."
nginx
echo "Service fully started."
tail -f /dev/null
