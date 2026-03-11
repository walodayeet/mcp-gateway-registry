#!/bin/bash
set -e
echo "Starting Registry Service Setup..."

# --- Wait for MongoDB ---
if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB..."
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
uri = f'mongodb://{os.getenv("DOCUMENTDB_HOST", "mongodb")}:27017/'
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000)
        c.admin.command('ping')
        print('MongoDB ready!')
        break
    except: 
        print('Waiting for MongoDB...')
        time.sleep(5)
PYEOF
    deactivate
fi

# Clean up old configs to prevent Nginx from starting with broken data
rm -f /etc/nginx/conf.d/nginx_rev_proxy.conf
mkdir -p /etc/nginx/lua /run/nginx /etc/nginx/conf.d
cp /app/docker/lua/*.lua /etc/nginx/lua/ 2>/dev/null || true
sed -i 's|pid /run/nginx.pid;|pid /run/nginx/nginx.pid;|' /etc/nginx/nginx.conf 2>/dev/null || true

# Start Registry App in background
cd /app && source /app/.venv/bin/activate
echo "Starting Registry Python App..."
uvicorn registry.main:app --host 0.0.0.0 --port 7860 --proxy-headers --forwarded-allow-ips='*' &

# Wait for VALID Nginx config (no placeholders)
echo "Waiting for Registry to generate processed Nginx config..."
TIMER=0
while [ $TIMER -lt 60 ]; do
    if [ -f "/etc/nginx/conf.d/nginx_rev_proxy.conf" ]; then
        if ! grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf"; then
            echo "Validated Nginx config found!"
            break
        fi
    fi
    sleep 2
    TIMER=$((TIMER + 2))
done

if grep -q "{{" "/etc/nginx/conf.d/nginx_rev_proxy.conf" 2>/dev/null; then
    echo "ERROR: Nginx config is still a template. Check Registry app logs."
else
    echo "Starting Nginx..."
    nginx
fi

tail -f /dev/null
