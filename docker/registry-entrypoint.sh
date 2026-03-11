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

# --- Nginx Non-Root Permissions ---
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/run /tmp/nginx/log /etc/nginx/conf.d
rm -f /etc/nginx/conf.d/nginx_rev_proxy.conf

# --- Start Registry App ---
cd /app && source /app/.venv/bin/activate
echo "Starting Registry app..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# --- Wait for Valid Config ---
echo "Waiting for Registry to generate valid Nginx config..."
for i in {1..60}; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        # Check if placeholders are gone
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Config validated!"
            break
        fi
    fi
    [ $((i % 5)) -eq 0 ] && echo "Still waiting for config... ($i/60)"
    sleep 2
done

# Final fallback check
if grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf" 2>/dev/null; then
    echo "ERROR: Config still has placeholders. Nginx will likely fail."
    cat /etc/nginx/conf.d/nginx_rev_proxy.conf
fi

# Start Nginx with explicit PID override to ensure non-root success
echo "Starting Nginx..."
nginx -g "daemon off; pid /tmp/nginx/run/nginx.pid; error_log /tmp/nginx/log/error.log;"
