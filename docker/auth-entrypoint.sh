#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB..."
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time
host = os.getenv('DOCUMENTDB_HOST', 'mongodb')
port = int(os.getenv('DOCUMENTDB_PORT', '27017'))
backend = os.getenv('STORAGE_BACKEND', 'mongodb-ce')
use_tls = os.getenv('DOCUMENTDB_USE_TLS', 'false').lower() == 'true'
ca_file = os.getenv('DOCUMENTDB_TLS_CA_FILE', '/app/certs/global-bundle.pem')
if backend == 'mongodb-ce' or not os.path.exists(ca_file): use_tls = False
uri = f'mongodb://{host}:{port}/'
tls_opts = {'tls': use_tls}
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, **tls_opts)
        c.admin.command('ping')
        print('MongoDB ready!')
        c.close(); break
    except Exception as e: print(f'Waiting: {e}')
    time.sleep(5)
PYEOF
    deactivate
fi

cd /app && source /app/.venv/bin/activate
# server.py is in /app root according to Dockerfile.auth
python3 server.py
