#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

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
    deactivate
fi

cd /app && source /app/.venv/bin/activate
export AUTH_SERVER_HOST=0.0.0.0
python3 server.py
