#!/bin/bash
set -e
echo "Starting Registry Service Setup..."

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

# --- Nginx Non-Root Permission Fix ---
# Create writable directories for Nginx
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi /tmp/nginx/run

# Modify main nginx.conf to use writable paths and remove root-only directives
if [ -f /etc/nginx/nginx.conf ]; then
    # Remove user directive
    sed -i 's/^user /#user /g' /etc/nginx/nginx.conf
    # Change pid location to /tmp
    sed -i 's|pid /run/nginx.pid;|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf
    sed -i 's|pid /var/run/nginx.pid;|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf
fi

# --- Registry App Startup ---
cd /app && source /app/.venv/bin/activate
echo "Launching Registry app..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# --- Wait for Config and Start Nginx ---
echo "Waiting for Registry to generate processed Nginx config..."
for i in {1..45}; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -qE '\{\{' "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Validated Nginx config found!"
            break
        fi
    fi
    sleep 2
done

# Start Nginx using the validated config
echo "Starting Nginx..."
nginx -g 'daemon off;'
