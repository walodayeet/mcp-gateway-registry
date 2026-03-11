#!/bin/bash
set -e
echo "Starting Auth Server Setup..."
echo "KEYCLOAK_ENABLED is set to: ${KEYCLOAK_ENABLED}"
echo "AUTH_PROVIDER is set to: ${AUTH_PROVIDER}"

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
SERVER_PATH=$(find /app -name "server.py" | head -n 1)
echo "Executing Auth Server: $SERVER_PATH"
python3 "$SERVER_PATH"
