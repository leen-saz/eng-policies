-- Baseline migration. Placeholder that proves the migration pipeline works.
-- Never edit a migration after it is merged: add a new numbered file instead.
CREATE TABLE IF NOT EXISTS app_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR IGNORE INTO app_meta (key, value) VALUES ('schema', 'baseline');
