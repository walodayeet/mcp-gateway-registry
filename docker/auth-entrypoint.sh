#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

# --- Wait for MongoDB ---
if [ -n "$DOCUMENTDB_HOST" ]; then
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
uri = f"mongodb://{os.getenv('DOCUMENTDB_HOST', 'mongodb')}:27017/"
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=2000)
        c.admin.command('ping')
        print('MongoDB ready!')
        break
    except: time.sleep(2)
PYEOF
    deactivate
fi

cd /app && source /app/.venv/bin/activate
echo "Current directory: $(pwd)"
echo "Files in /app:"
ls -F /app

# Auth server is in /app root according to Dockerfile
if [ -f "/app/server.py" ]; then
    echo "Found server.py, starting..."
    python3 server.py
else
    echo "ERROR: server.py not found in /app! Check Dockerfile copy commands."
    exit 1
fi
