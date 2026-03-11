#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

# Fix internal paths: ensure the loader can find scopes.yml
mkdir -p /app/auth_server
[ -f /app/scopes.yml ] && ln -sf /app/scopes.yml /app/auth_server/scopes.yml

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
export AUTH_SERVER_HOST=0.0.0.0
python3 server.py
