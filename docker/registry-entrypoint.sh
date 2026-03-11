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

# --- Nginx Non-Root Fix ---
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/run /tmp/nginx/log /etc/nginx/conf.d
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

# Start Registry App
cd /app && source /app/.venv/bin/activate
echo "Starting Registry app..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# Wait for config
echo "Waiting for Registry to generate Nginx config..."
for i in {1..60}; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Config ready!"
            break
        fi
    fi
    sleep 2
done

echo "Starting Nginx..."
nginx

# CRITICAL: Wait for PID file to be populated and valid to prevent reload crashes
echo "Validating Nginx PID..."
for i in {1..20}; do
    if [ -s "/tmp/nginx/run/nginx.pid" ] && [ -n "$(cat /tmp/nginx/run/nginx.pid | tr -d '[:space:]')" ]; then
        echo "Nginx PID validated: $(cat /tmp/nginx/run/nginx.pid)"
        break
    fi
    echo "Waiting for Nginx PID file..."
    sleep 1
done

tail -f /dev/null
