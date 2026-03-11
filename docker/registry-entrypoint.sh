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

# --- Comprehensive Nginx Non-Root Fix ---
# Create writable directories for Nginx in /tmp
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi /tmp/nginx/run /tmp/nginx/log

# Force Nginx to use writable paths for everything
cat << 'NGINX_CONF' > /tmp/nginx.conf
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
NGINX_CONF

# Backup and overwrite main nginx.conf
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak || true
cp /tmp/nginx.conf /etc/nginx/nginx.conf

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

# Start Nginx in foreground
echo "Starting Nginx (Non-Root)..."
nginx -g 'daemon off;'
