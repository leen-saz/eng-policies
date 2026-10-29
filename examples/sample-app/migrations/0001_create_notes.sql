CREATE TABLE notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- The list query orders by created_at, so it gets an index (D1 bills rows read).
CREATE INDEX idx_notes_created_at ON notes (created_at);
