-- ============================================================================
-- Seed data dla LiteLLM Postgres
-- Klucze wirtualne, teamy, rate limity
-- Uruchamiane po starcie bazy przez init container
-- ============================================================================

-- Team: demo-team z budżetem
INSERT INTO "LiteLLM_TeamTable" (team_id, team_alias, max_budget, tpm_limit, rpm_limit)
VALUES (
  'team-demo-001',
  'demo-team',
  10.0,       -- max $10 budżetu
  100000,     -- 100k TPM
  60          -- 60 RPM
)
ON CONFLICT (team_id) DO NOTHING;

-- Klucz wirtualny: demo-user (rate limited)
INSERT INTO "LiteLLM_VerificationToken" (token, team_id, max_budget, tpm_limit, rpm_limit, metadata)
VALUES (
  'sk-aigw-demo-user-001',
  'team-demo-001',
  5.0,        -- max $5 budżetu per key
  50000,      -- 50k TPM
  30,         -- 30 RPM
  '{"use_case": "demo", "data_class": "K1"}'
)
ON CONFLICT (token) DO NOTHING;

-- Klucz wirtualny: test-unlimited (bez limitów – do testowania)
INSERT INTO "LiteLLM_VerificationToken" (token, team_id, metadata)
VALUES (
  'sk-aigw-test-unlimited',
  'team-demo-001',
  '{"use_case": "testing", "data_class": "K0"}'
)
ON CONFLICT (token) DO NOTHING;
