#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

# Wait for MongoDB
if [ -n "$DOCUMENTDB_HOST" ]; then
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
uri = f'mongodb://{os.getenv("DOCUMENTDB_HOST", "mongodb")}:27017/'
while True:
    try:
        pymongo.MongoClient(uri, serverSelectionTimeoutMS=2000).admin.command('ping')
        print('DB Ready')
        break
    except: time.sleep(2)
PYEOF
fi

cd /app && source /app/.venv/bin/activate
# server.py is in /app/ root because Dockerfile.auth copies auth_server/ content to /app/
if [ -f "/app/server.py" ]; then
    echo "Starting Auth Server at /app/server.py"
    python3 /app/server.py
else
    echo "Searching for server.py fallback..."
    FALLBACK=$(find /app -name "server.py" | head -n 1)
    if [ -n "$FALLBACK" ]; then
        python3 "$FALLBACK"
    else
        echo "FATAL: server.py not found!"
        ls -R /app
        exit 1
    fi
fi
