#!/bin/bash
set -e
echo "Starting Registry Service Setup..."

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
uri = f'mongodb://{host}:{port}/'
tls_opts = {'tls': use_tls}
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, **tls_opts)
        c.admin.command('ping')
        print('MongoDB is ready!')
        c.close(); break
    except Exception as e: print(f'Waiting: {e}')
    time.sleep(5)
PYEOF
    deactivate
fi

# Setup directories
mkdir -p /etc/nginx/lua /run/nginx /etc/nginx/conf.d
cp /app/docker/lua/*.lua /etc/nginx/lua/ 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default
sed -i 's|pid /run/nginx.pid;|pid /run/nginx/nginx.pid;|' /etc/nginx/nginx.conf 2>/dev/null || true

# Start Registry in background - it generates the Nginx config
cd /app && source /app/.venv/bin/activate
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# Wait for processed Nginx config (no placeholders)
echo "Waiting for Registry to generate Nginx config..."
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

nginx
echo "Registry and Nginx started."
tail -f /dev/null
