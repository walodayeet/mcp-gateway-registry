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

# --- Nginx Non-Root Hardening ---
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/run /tmp/nginx/log /etc/nginx/conf.d
rm -f /etc/nginx/conf.d/nginx_rev_proxy.conf

# Force global Nginx config to use /tmp
cat << 'NGINX_GLOBAL' > /etc/nginx/nginx.conf
worker_processes auto;
pid /tmp/nginx/run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 768; }
http {
    sendfile on;
    include /etc/nginx/mime.types;
    access_log /tmp/nginx/log/access.log;
    error_log /tmp/nginx/log/error.log;
    client_body_temp_path /tmp/nginx/body;
    proxy_temp_path /tmp/nginx/proxy;
    include /etc/nginx/conf.d/*.conf;
}
NGINX_GLOBAL

# --- Start Registry App ---
cd /app && source /app/.venv/bin/activate
echo "Launching Registry app..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# --- Wait for Config and VALID PID ---
echo "Waiting for Registry to generate Nginx config..."
for i in {1..45}; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Validated config found."
            break
        fi
    fi
    sleep 2
done

echo "Starting Nginx..."
nginx &

# CRITICAL: Wait for Nginx to write its PID before continuing
echo "Waiting for Nginx PID file..."
for i in {1..10}; do
    if [ -s "/tmp/nginx/run/nginx.pid" ]; then
        echo "Nginx PID detected: $(cat /tmp/nginx/run/nginx.pid)"
        break
    fi
    sleep 1
done

echo "Registry Setup Complete."
tail -f /dev/null
