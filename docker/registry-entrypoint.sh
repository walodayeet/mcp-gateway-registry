#!/bin/bash
set -e
echo "Starting Registry Service Setup..."

# --- Wait for MongoDB ---
if [ -n "$DOCUMENTDB_HOST" ]; then
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
uri = f'mongodb://{os.getenv("DOCUMENTDB_HOST", "mongodb")}:27017/'
while True:
    try:
        pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000).admin.command('ping')
        print('MongoDB ready!')
        break
    except: 
        print('Waiting for MongoDB...')
        time.sleep(5)
PYEOF
    deactivate
fi

# --- Nginx Non-Root Hardening ---
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/run /tmp/nginx/log /etc/nginx/conf.d
# Create a wrapper for nginx to force writable paths even when called by Python
mkdir -p /app/bin
cat << 'WRAPPER' > /app/bin/nginx
#!/bin/bash
/usr/sbin/nginx -g "pid /tmp/nginx/run/nginx.pid; error_log /tmp/nginx/log/error.log;" "$@"
WRAPPER
chmod +x /app/bin/nginx
export PATH="/app/bin:$PATH"

# Remove 'user' directive from global config
sed -i 's/^user /#user /g' /etc/nginx/nginx.conf 2>/dev/null || true

# --- Start Registry App ---
cd /app && source /app/.venv/bin/activate
echo "Starting Registry app..."
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

# Start Nginx using our wrapper
echo "Starting Nginx..."
nginx -g "daemon off;"
