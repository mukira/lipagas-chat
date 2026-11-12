CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE channel_twilio_sms ADD COLUMN IF NOT EXISTS provider_config jsonb DEFAULT '{}';
ALTER TABLE categories ADD COLUMN IF NOT EXISTS icon_color varchar DEFAULT '';

CREATE TABLE IF NOT EXISTS user_sessions (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id),
    client_id varchar NOT NULL,
    ip_address varchar,
    user_agent varchar,
    browser_name varchar,
    browser_version varchar,
    device_name varchar,
    platform_name varchar,
    platform_version varchar,
    city varchar,
    country varchar,
    country_code varchar,
    last_activity_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS index_user_sessions_on_user_id_and_client_id ON user_sessions (user_id, client_id);
CREATE INDEX IF NOT EXISTS index_user_sessions_on_user_id ON user_sessions (user_id);

ALTER TABLE teams ADD COLUMN IF NOT EXISTS icon varchar DEFAULT '';
ALTER TABLE teams ADD COLUMN IF NOT EXISTS icon_color varchar DEFAULT '';
ALTER TABLE assignment_policies ADD COLUMN IF NOT EXISTS exclude_older_than_hours integer DEFAULT 168;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS draft_title varchar;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS draft_content text;

CREATE TABLE IF NOT EXISTS captain_message_reports (
    id bigserial PRIMARY KEY,
    account_id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    message_id bigint NOT NULL,
    user_id bigint NOT NULL,
    report_reason varchar NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE INDEX IF NOT EXISTS index_messages_on_sender_and_created ON messages (sender_type, sender_id, created_at);

ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS name varchar;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS source_type varchar;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS source_provider varchar;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS import_types jsonb DEFAULT '[]' NOT NULL;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS initiated_by_id integer;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS access_token text;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS source_metadata jsonb DEFAULT '{}' NOT NULL;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS stats jsonb DEFAULT '{}' NOT NULL;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS cursor jsonb DEFAULT '{}' NOT NULL;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS started_at timestamp without time zone;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS completed_at timestamp without time zone;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS abandoned_at timestamp without time zone;
ALTER TABLE data_imports ADD COLUMN IF NOT EXISTS last_error_at timestamp without time zone;

CREATE TABLE IF NOT EXISTS data_import_items (
    id bigserial PRIMARY KEY,
    data_import_id bigint NOT NULL,
    source_provider varchar NOT NULL,
    source_object_type varchar NOT NULL,
    source_object_id varchar NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    chatwoot_record_type varchar,
    chatwoot_record_id bigint,
    attempt_count integer DEFAULT 0 NOT NULL,
    last_error_code varchar,
    last_error_message text,
    metadata jsonb DEFAULT '{}' NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS data_import_mappings (
    id bigserial PRIMARY KEY,
    account_id integer NOT NULL,
    data_import_id bigint NOT NULL,
    source_provider varchar NOT NULL,
    source_object_type varchar NOT NULL,
    source_object_id varchar NOT NULL,
    chatwoot_record_type varchar NOT NULL,
    chatwoot_record_id bigint NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS data_import_errors (
    id bigserial PRIMARY KEY,
    data_import_id bigint NOT NULL,
    data_import_item_id bigint,
    source_object_type varchar,
    source_object_id varchar,
    error_code varchar NOT NULL,
    message text,
    details jsonb DEFAULT '{}' NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE email_templates ADD COLUMN IF NOT EXISTS inbox_id integer;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS feature_flags_ext_1 bigint DEFAULT 0 NOT NULL;
ALTER TABLE automation_rules ADD COLUMN IF NOT EXISTS execution_delay integer;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS status_changed_at timestamp without time zone;

CREATE TABLE IF NOT EXISTS automation_rule_pending_executions (
    id bigserial PRIMARY KEY,
    automation_rule_id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    account_id bigint NOT NULL,
    message_id bigint,
    due_at timestamp without time zone NOT NULL,
    episode_key varchar NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    skip_reason varchar,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);
CREATE INDEX IF NOT EXISTS index_automation_rule_pending_executions_on_status_and_due_at ON automation_rule_pending_executions (status, due_at);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_automation_pending_execution_episode ON automation_rule_pending_executions (automation_rule_id, conversation_id, episode_key);
CREATE INDEX IF NOT EXISTS index_automation_pending_executions_on_status_and_updated_at ON automation_rule_pending_executions (status, updated_at);

CREATE TABLE IF NOT EXISTS agent_sessions (
    id bigserial PRIMARY KEY,
    session_type integer NOT NULL,
    subject_type varchar NOT NULL,
    subject_id bigint NOT NULL,
    result_type varchar,
    result_id bigint,
    account_id bigint NOT NULL,
    assistant_id bigint NOT NULL,
    user_id bigint,
    llm_model varchar,
    credits_consumed double precision,
    faq_ids jsonb DEFAULT '[]',
    document_ids jsonb DEFAULT '[]',
    scenario_ids jsonb DEFAULT '[]',
    run_context jsonb DEFAULT '{}',
    cited_document_ids jsonb DEFAULT '[]' NOT NULL,
    used_faq_ids jsonb DEFAULT '[]' NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS captain_faq_suggestions (
    id bigserial PRIMARY KEY,
    question varchar NOT NULL,
    answer text NOT NULL,
    embedding vector(1536),
    assistant_id bigint NOT NULL,
    account_id bigint NOT NULL,
    language varchar DEFAULT 'en' NOT NULL,
    source_count integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS captain_faq_observations (
    id bigserial PRIMARY KEY,
    account_id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    faq_suggestion_id bigint,
    generated_question varchar NOT NULL,
    generated_answer text NOT NULL,
    language varchar DEFAULT 'en' NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE applied_slas ADD COLUMN IF NOT EXISTS completed_at timestamp without time zone;
ALTER TABLE channel_whatsapp ADD COLUMN IF NOT EXISTS phone_number_health jsonb DEFAULT '{}' NOT NULL;
ALTER TABLE channel_whatsapp ADD COLUMN IF NOT EXISTS phone_number_health_checked_at timestamp without time zone;
ALTER TABLE channel_whatsapp ADD COLUMN IF NOT EXISTS phone_number_health_error varchar(500);
ALTER TABLE channel_whatsapp ADD COLUMN IF NOT EXISTS business_management_token text;

CREATE TABLE IF NOT EXISTS conversation_outcomes (
    id bigserial PRIMARY KEY,
    account_id bigint NOT NULL,
    assistant_id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    inbox_id bigint NOT NULL,
    first_captain_reply_at timestamp without time zone,
    last_captain_reply_at timestamp without time zone,
    captain_reply_count integer DEFAULT 0 NOT NULL,
    first_human_reply_at timestamp without time zone,
    handoff_at timestamp without time zone,
    handoff_reason_category varchar,
    resolved_at timestamp without time zone,
    csat_rating integer,
    csat_received_at timestamp without time zone,
    episode_trigger varchar DEFAULT 'initial' NOT NULL,
    started_at timestamp without time zone NOT NULL,
    ended_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS campaign_recipients (
    id bigserial PRIMARY KEY,
    account_id bigint NOT NULL,
    campaign_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    inbox_id bigint NOT NULL,
    source_id varchar,
    status integer DEFAULT 0 NOT NULL,
    error_code varchar,
    error_title varchar,
    error_message text,
    message_content text,
    sent_at timestamp without time zone,
    delivered_at timestamp without time zone,
    read_at timestamp without time zone,
    failed_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS started_at timestamp without time zone;
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS completed_at timestamp without time zone;

INSERT INTO schema_migrations (version) VALUES
('20260604000000'),('20260610000000'),('20260611184600'),('20260616120000'),
('20260617000000'),('20260618000000'),('20260620000000'),('20260622000000'),
('20260623000000'),('20260629000000'),('20260630000000'),('20260702000000'),
('20260702000001'),('20260702000002'),('20260702000003'),('20260706000000'),
('20260706000001'),('20260706215758'),('20260709060000'),('20260709060100'),
('20260709060200'),('20260709091147'),('20260710000000'),('20260713184351'),
('20260714123000'),('20260715000000'),('20260718000000'),('20260724000100'),
('20260728000001'),('20260729051500'),('20260731140853'),('20260803000000'),
('20260803130000'),('20260804000000'),('20260804000001'),('20260804000002'),
('20260804000003'),('20260806000000'),('20260807101420'),('20260807133000'),
('20260814000000')
ON CONFLICT DO NOTHING;

-- Ensure Inbox 10 (+254143043073 Influence AI) and internal Docker AgentBot URLs are configured
INSERT INTO channel_whatsapp (id, account_id, phone_number, provider, provider_config, message_templates, created_at, updated_at)
VALUES (
  8,
  1,
  '+254143043073',
  'whatsapp_cloud',
  '{"api_key":"EAAUbTMY5PfMBSEszVg4HAZA1aOZCcea5VBmZBEGMYIxOMnx1u0m4cbEJZAsIpQe6ZAHGu9cHCfm5dffeCXldFX1A28bErrqXMZCxDhGVAXUYexKSAWBpT8w2048naM0SF55x1DTiZBeqpLLQwrMoFqj9QJt0bpjhZBhsKnVAHctNjNoj3O0Eh5gdnZBZAhPZAdpoA06yBga4QeSHxz31vZBXqQagYmjBOiBlt9hmkVOrts6UfZAenFKZCDnVUgmuQdGfoeSHElW4CKmmlgQFL0jzBZAnIO110ou2IOKiD0HbSZAUOgsSvE0ErJDJ1dsMEUHNhV6zB883dcrLe2oZD","phone_number_id":"1156689577536011","business_account_id":"1034661355742761","webhook_verify_token":"lipagas_secure_meta_token"}'::jsonb,
  '[]'::jsonb,
  NOW(),
  NOW()
) ON CONFLICT (id) DO UPDATE SET
  phone_number = EXCLUDED.phone_number,
  provider_config = EXCLUDED.provider_config;

INSERT INTO inboxes (id, channel_id, account_id, name, created_at, updated_at, channel_type, enable_auto_assignment)
VALUES (10, 8, 1, 'Influence AI', NOW(), NOW(), 'Channel::Whatsapp', true)
ON CONFLICT (id) DO UPDATE SET
  channel_id = EXCLUDED.channel_id,
  name = EXCLUDED.name,
  channel_type = EXCLUDED.channel_type;

INSERT INTO inbox_members (user_id, inbox_id, created_at, updated_at)
SELECT u.id, 10, NOW(), NOW() FROM users u WHERE u.id IN (1, 2)
  AND NOT EXISTS (SELECT 1 FROM inbox_members im WHERE im.user_id = u.id AND im.inbox_id = 10);

UPDATE agent_bots SET outgoing_url = 'http://lipagas-bridge:4000/webhook' WHERE id = 1;

INSERT INTO agent_bots (id, name, description, outgoing_url, created_at, updated_at, account_id, bot_type, bot_config)
VALUES (2, 'Presidential AI', 'Presidential Bridge Typebot Handler', 'http://presidential-bridge:4002/webhook', NOW(), NOW(), 1, 0, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
  outgoing_url = EXCLUDED.outgoing_url;

INSERT INTO access_tokens (owner_type, owner_id, token, created_at, updated_at)
SELECT 'AgentBot', 2, 'zXDW1wqKjXqH2uZmR7rZSDi5', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM access_tokens WHERE owner_type = 'AgentBot' AND owner_id = 2);

INSERT INTO agent_bot_inboxes (inbox_id, agent_bot_id, status, created_at, updated_at, account_id)
SELECT 10, 2, 0, NOW(), NOW(), 1
WHERE NOT EXISTS (SELECT 1 FROM agent_bot_inboxes WHERE inbox_id = 10);

UPDATE conversations SET status = 0, assignee_id = 1 WHERE account_id = 1 AND (status = 2 OR assignee_id IS NULL);



