#!/bin/bash
set -e
echo "Starting Registry Service Setup... (Build Version: ${BUILD_VERSION})"

# --- Wait for MongoDB ---
if [ -n "$DOCUMENTDB_HOST" ]; then
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
host = os.getenv('DOCUMENTDB_HOST', 'mongodb')
uri = f'mongodb://{host}:27017/'
while True:
    try:
        pymongo.MongoClient(uri, serverSelectionTimeoutMS=2000).admin.command('ping')
        print('MongoDB ready!')
        break
    except: 
        print('Waiting for MongoDB...')
        time.sleep(2)
PYEOF
    deactivate
fi

# Prepare config directory
mkdir -p /etc/nginx/conf.d /run/nginx /etc/nginx/lua
rm -f /etc/nginx/conf.d/nginx_rev_proxy.conf

# Start Registry in background
cd /app && source /app/.venv/bin/activate
echo "Launching Registry app..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# Wait for VALID Nginx config (Placeholder-free)
echo "Waiting for Registry to generate processed Nginx config..."
for i in {1..45}; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        # Check for {{ placeholders using extended regex
        if ! grep -qE '\{\{' "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Validated Nginx config found!"
            break
        fi
    fi
    sleep 2
done

if grep -qE '\{\{' "/etc/nginx/conf.d/nginx_rev_proxy.conf" 2>/dev/null; then
    echo "FATAL: Nginx config still contains placeholders after 90s!"
    cat /etc/nginx/conf.d/nginx_rev_proxy.conf
    exit 1
fi

echo "Starting Nginx..."
nginx
tail -f /dev/null
