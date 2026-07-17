CREATE ROLE chatwoot WITH LOGIN SUPERUSER PASSWORD 'postgres_password';
CREATE ROLE typebot WITH LOGIN SUPERUSER PASSWORD 'postgres_password';
CREATE DATABASE chatwoot_production OWNER chatwoot;
CREATE DATABASE typebot OWNER typebot;
