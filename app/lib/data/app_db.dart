import 'package:sqflite/sqflite.dart';

/// `moneylens.db`: everything Dart owns (accounts, transactions, parse
/// results, settings). Raw notifications live in Kotlin's `capture.db`.
Future<Database> openAppDb(String path, {DatabaseFactory? factory}) {
  return (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final sql in _schemaV1) {
          await db.execute(sql);
        }
      },
    ),
  );
}

const _schemaV1 = [
  '''
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY,
  bank_code TEXT,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  last4 TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE (bank_code, last4)
)''',
  '''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  raw_event_id INTEGER UNIQUE,
  ref TEXT,
  source TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0),
  direction TEXT NOT NULL CHECK (direction IN ('in', 'out')),
  balance_after INTEGER,
  description TEXT NOT NULL DEFAULT '',
  excluded INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (account_id, ref)
)''',
  // Without a Ref, the same amount + time + balance is the same transaction.
  // A NULL balance never matches, so uncertain duplicates are kept.
  '''
CREATE UNIQUE INDEX tx_noref_dedup
  ON transactions (account_id, occurred_at, amount, balance_after)
  WHERE ref IS NULL''',
  '''
CREATE TABLE raw_parse (
  raw_event_id INTEGER PRIMARY KEY,
  parse_status TEXT NOT NULL CHECK (parse_status IN ('parsed', 'ignored', 'failed')),
  parse_error TEXT,
  rules_version INTEGER NOT NULL,
  parsed_at INTEGER NOT NULL
)''',
  'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
];
