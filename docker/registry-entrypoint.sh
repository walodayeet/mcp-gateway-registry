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
        pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000).admin.command('ping')
        print('MongoDB ready!')
        break
    except: 
        print('Waiting for MongoDB...')
        time.sleep(2)
PYEOF
    deactivate
fi

# --- Global Nginx Non-Root Permissions Fix ---
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/run /tmp/nginx/log /etc/nginx/conf.d

# Overwrite the system-wide nginx.conf to use /tmp for everything (PID, Temp folders)
cat << 'NGINX_GLOBAL' > /etc/nginx/nginx.conf
worker_processes auto;
pid /tmp/nginx/run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /tmp/nginx/log/access.log;
    error_log /tmp/nginx/log/error.log;

    client_body_temp_path /tmp/nginx/body;
    proxy_temp_path /tmp/nginx/proxy;
    fastcgi_temp_path /tmp/nginx/fastcgi;
    uwsgi_temp_path /tmp/nginx/uwsgi;
    scgi_temp_path /tmp/nginx/scgi;

    include /etc/nginx/conf.d/*.conf;
}
NGINX_GLOBAL

# Remove old configs
rm -f /etc/nginx/conf.d/nginx_rev_proxy.conf
rm -f /etc/nginx/sites-enabled/default

# --- Start Registry App ---
cd /app && source /app/.venv/bin/activate
echo "Launching Registry app..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# --- Wait for Valid Config ---
echo "Waiting for Registry to generate Nginx config..."
for i in {1..60}; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Validated config found."
            break
        fi
    fi
    sleep 2
done

# Start Nginx
echo "Starting Nginx (Non-Root, Global Override)..."
nginx -g "daemon off;"
