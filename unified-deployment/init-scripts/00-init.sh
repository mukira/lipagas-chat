#!/bin/bash
set -e

echo "=== Initializing LipaGas Databases ==="

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'chatwoot') THEN
            CREATE ROLE chatwoot WITH LOGIN SUPERUSER PASSWORD 'postgres_password';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'typebot') THEN
            CREATE ROLE typebot WITH LOGIN SUPERUSER PASSWORD 'postgres_password';
        END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE chatwoot_production OWNER chatwoot'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'chatwoot_production')\gexec

    SELECT 'CREATE DATABASE typebot OWNER typebot'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'typebot')\gexec
EOSQL

echo "Restoring Chatwoot snapshot into chatwoot_production..."
gunzip -c /docker-entrypoint-initdb.d/01-chatwoot.dump.gz | psql --username "$POSTGRES_USER" --dbname "chatwoot_production" || true

echo "Restoring Typebot snapshot into typebot..."
gunzip -c /docker-entrypoint-initdb.d/02-typebot.dump.gz | psql --username "$POSTGRES_USER" --dbname "typebot" || true

echo "=== LipaGas Database Initialization Complete ==="
