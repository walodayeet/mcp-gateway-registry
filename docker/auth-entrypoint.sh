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
# Dynamically find server.py to avoid path errors
SERVER_PATH=$(find /app -name "server.py" | head -n 1)
if [ -n "$SERVER_PATH" ]; then
    echo "Starting Auth Server: $SERVER_PATH"
    python3 "$SERVER_PATH"
else
    echo "FATAL: Could not find server.py in /app"
    ls -R /app
    exit 1
fi
