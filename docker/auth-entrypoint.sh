#!/bin/bash
set -e
echo "Starting Auth Server Setup..."

if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB at ${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}..."
    source /app/.venv/bin/activate
    python3 <<'PYEOF'
import pymongo, os, time, sys
host = os.getenv('DOCUMENTDB_HOST', 'mongodb')
port = int(os.getenv('DOCUMENTDB_PORT', '27017'))
user = os.getenv('DOCUMENTDB_USERNAME', '')
pwd = os.getenv('DOCUMENTDB_PASSWORD', '')
backend = os.getenv('STORAGE_BACKEND', 'mongodb-ce')
use_tls = os.getenv('DOCUMENTDB_USE_TLS', 'false').lower() == 'true'
ca_file = os.getenv('DOCUMENTDB_TLS_CA_FILE', '/app/certs/global-bundle.pem')
if backend == 'mongodb-ce': use_tls = False
if use_tls and not os.path.exists(ca_file): use_tls = False
auth = 'SCRAM-SHA-256' if backend == 'mongodb-ce' else 'SCRAM-SHA-1'
if user and pwd:
    uri = f'mongodb://{user}:{pwd}@{host}:{port}/?authMechanism={auth}&authSource=admin'
else:
    uri = f'mongodb://{host}:{port}/'
tls_options = {'tls': use_tls}
if use_tls: tls_options['tlsCAFile'] = ca_file
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000, **tls_options)
        c.admin.command('ping')
        print('MongoDB is ready!')
        c.close(); break
    except Exception as e: print(f'MongoDB not ready yet: {e}')
    time.sleep(5)
PYEOF
    deactivate
fi

cd /app && source /app/.venv/bin/activate
python3 auth_server/server.py
