#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "Starting Auth Server Setup..."

# --- DocumentDB CA Bundle Download ---
if [[ "${DOCUMENTDB_HOST}" == *"docdb-elastic.amazonaws.com"* ]]; then
    echo "Detected DocumentDB Elastic cluster"
    echo "Downloading DocumentDB Elastic CA bundle..."
    CA_BUNDLE_URL="https://www.amazontrust.com/repository/SFSRootCAG2.pem"
    CA_BUNDLE_PATH="/app/certs/global-bundle.pem"
    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        curl -fsSL "$CA_BUNDLE_URL" -o "$CA_BUNDLE_PATH"
        echo "DocumentDB Elastic CA bundle (SFSRootCAG2.pem) downloaded successfully to $CA_BUNDLE_PATH"
    fi
elif [[ "${DOCUMENTDB_HOST}" == *"docdb.amazonaws.com"* ]]; then
    echo "Detected regular DocumentDB cluster"
    echo "Downloading regular DocumentDB CA bundle..."
    CA_BUNDLE_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
    CA_BUNDLE_PATH="/app/certs/global-bundle.pem"
    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        curl -fsSL "$CA_BUNDLE_URL" -o "$CA_BUNDLE_PATH"
        echo "DocumentDB CA bundle (global-bundle.pem) downloaded successfully to $CA_BUNDLE_PATH"
    fi
else
    echo "No DocumentDB host detected or DOCUMENTDB_HOST is empty - skipping CA bundle download"
fi

# --- Wait for MongoDB Replica Set ---
if [ -n "$DOCUMENTDB_HOST" ]; then
    echo "Waiting for MongoDB replica set at ${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}..."
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
print(f'Connecting to MongoDB at {host}:{port} (TLS: {use_tls}, Backend: {backend})')
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000, **tls_options)
        c.admin.command('ping')
        print('MongoDB is ready!')
        c.close(); break
    except Exception as e: print(f'MongoDB not ready yet: {e}')
    time.sleep(5)
PYEOF
host = os.getenv('DOCUMENTDB_HOST', 'mongodb')
port = int(os.getenv('DOCUMENTDB_PORT', '27017'))
user = os.getenv('DOCUMENTDB_USERNAME', '')
pwd = os.getenv('DOCUMENTDB_PASSWORD', '')
backend = os.getenv('STORAGE_BACKEND', 'mongodb-ce')
use_tls = os.getenv('DOCUMENTDB_USE_TLS', 'false').lower() == 'true'
ca_file = os.getenv('DOCUMENTDB_TLS_CA_FILE', '/app/certs/global-bundle.pem')
# Force disable TLS for mongodb-ce or if cert is missing
if backend == 'mongodb-ce': use_tls = False
if use_tls and not os.path.exists(ca_file): use_tls = False
auth = 'SCRAM-SHA-256' if backend == 'mongodb-ce' else 'SCRAM-SHA-1'
if user and pwd:
    uri = f'mongodb://{user}:{pwd}@{host}:{port}/?authMechanism={auth}&authSource=admin'
else:
    uri = f'mongodb://{host}:{port}/'
tls_options = {}
if use_tls:
    tls_options['tls'] = True
    tls_options['tlsCAFile'] = ca_file
while True:
    try:
        c = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000, **tls_options)
        c.admin.command('ping')
        print('MongoDB is ready')
        c.close()
        break
    except Exception as e:
        print(f'MongoDB not ready yet: {e}')
    deactivate
    echo "MongoDB is ready."
fi

echo "Starting Auth Server..."
cd /app
source .venv/bin/activate
exec uvicorn server:app --host 0.0.0.0 --port 8888 --proxy-headers --forwarded-allow-ips='*'
