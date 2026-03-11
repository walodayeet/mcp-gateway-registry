#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB..."
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
uri = f"mongodb://{os.getenv('DOCUMENTDB_HOST', 'mongodb')}:27017/"
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000)
        c.admin.command('ping')
        print('MongoDB ready!')
        c.close(); break
    except: time.sleep(5)
PYEOF
    deactivate
fi

cd /app && source /app/.venv/bin/activate
# According to Dockerfile.auth, server.py is moved from auth_server/ to /app/
python3 server.py
