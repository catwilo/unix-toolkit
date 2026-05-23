use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::os::unix::net::UnixListener;
use std::io::{BufRead, BufReader, Write};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

// ── Types ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "lowercase")]
pub enum MemType {
    Pinned,
    Session,
    Project,
    Compressed,
    Auto,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MemoryEntry {
    pub id:         Option<String>,
    pub r#type:     MemType,
    pub scope:      String,
    pub content:    String,
    pub tokens_est: Option<i64>,
    pub pinned:     Option<bool>,
    pub ai_source:  Option<String>,
    pub account_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TransferBundle {
    pub pinned:        Vec<MemoryEntry>,
    pub objectives:    String,
    pub project_state: serde_json::Value,
    pub active_files:  Vec<String>,
    pub constraints:   Vec<String>,
    pub token_est:     i64,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "cmd")]
pub enum MemoryCmd {
    Store   { entry: MemoryEntry },
    Fetch   { scope: String, max_tokens: Option<i64> },
    Pin     { id: String },
    Unpin   { id: String },
    Delete  { id: String },
    Compress { session_id: String },
    Snapshot { session_id: String, reason: Option<String> },
    BuildTransferBundle { session_id: String, scope: String },
    Status,
}

// ── Database ──────────────────────────────────────────────────────────────────

fn open_db(path: &str) -> Connection {
    let conn = Connection::open(path).expect("cannot open SQLite database");
    conn.execute_batch("
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        PRAGMA cache_size=-64000;
        PRAGMA temp_store=MEMORY;
        PRAGMA mmap_size=268435456;
        PRAGMA wal_autocheckpoint=1000;
    ").expect("PRAGMA setup failed");
    conn
}

fn init_schema(conn: &Connection) {
    conn.execute_batch("
        CREATE TABLE IF NOT EXISTS memory (
            id          TEXT PRIMARY KEY,
            type        TEXT NOT NULL,
            scope       TEXT NOT NULL,
            content     TEXT NOT NULL,
            tokens_est  INTEGER,
            pinned      INTEGER DEFAULT 0,
            active      INTEGER DEFAULT 1,
            ai_source   TEXT,
            account_id  TEXT,
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sessions (
            id          TEXT PRIMARY KEY,
            account_id  TEXT NOT NULL,
            ai          TEXT NOT NULL,
            scope       TEXT NOT NULL,
            status      TEXT NOT NULL,
            started_at  TEXT NOT NULL,
            ended_at    TEXT,
            tokens_used INTEGER DEFAULT 0,
            msg_count   INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS messages (
            id          TEXT PRIMARY KEY,
            session_id  TEXT NOT NULL,
            role        TEXT NOT NULL,
            content     TEXT NOT NULL,
            tokens_est  INTEGER,
            deleted     INTEGER DEFAULT 0,
            created_at  TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        );

        CREATE TABLE IF NOT EXISTS snapshots (
            id          TEXT PRIMARY KEY,
            session_id  TEXT,
            scope       TEXT NOT NULL,
            data        TEXT NOT NULL,
            reason      TEXT,
            created_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS active_files (
            id          TEXT PRIMARY KEY,
            session_id  TEXT NOT NULL,
            path        TEXT NOT NULL,
            added_at    TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_memory_scope  ON memory(scope, active);
        CREATE INDEX IF NOT EXISTS idx_memory_pinned ON memory(pinned, active);
        CREATE INDEX IF NOT EXISTS idx_msgs_session  ON messages(session_id, deleted);
    ").expect("schema init failed");
}

// ── Token estimation ──────────────────────────────────────────────────────────

fn estimate_tokens(text: &str) -> i64 {
    // ~4 chars = 1 token (rough approximation, no external model needed)
    ((text.chars().count() + 3) / 4) as i64
}

fn now_ts() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    format!("{}", secs)
}

fn new_id() -> String {
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
    format!("{:x}", ts)
}

// ── Handlers ──────────────────────────────────────────────────────────────────

fn handle_store(conn: &Connection, mut entry: MemoryEntry) -> serde_json::Value {
    let id = entry.id.clone().unwrap_or_else(new_id);
    let now = now_ts();
    let tokens = entry.tokens_est.unwrap_or_else(|| estimate_tokens(&entry.content));
    let pinned = if entry.pinned.unwrap_or(false) { 1i64 } else { 0 };
    let type_str = format!("{:?}", entry.r#type).to_lowercase();

    conn.execute(
        "INSERT OR REPLACE INTO memory
         (id, type, scope, content, tokens_est, pinned, active, ai_source, account_id, created_at, updated_at)
         VALUES (?1,?2,?3,?4,?5,?6,1,?7,?8,?9,?9)",
        params![
            id, type_str, entry.scope, entry.content,
            tokens, pinned,
            entry.ai_source, entry.account_id, now
        ],
    ).expect("store failed");

    serde_json::json!({"ok": true, "id": id, "tokens_est": tokens})
}

fn handle_fetch(conn: &Connection, scope: &str, max_tokens: Option<i64>) -> serde_json::Value {
    let max = max_tokens.unwrap_or(8000);

    let mut stmt = conn.prepare(
        "SELECT id, type, scope, content, tokens_est, pinned
         FROM memory
         WHERE scope = ?1 AND active = 1
         ORDER BY pinned DESC, updated_at DESC"
    ).unwrap();

    let rows: Vec<serde_json::Value> = stmt.query_map(params![scope], |row| {
        Ok(serde_json::json!({
            "id":         row.get::<_, String>(0)?,
            "type":       row.get::<_, String>(1)?,
            "scope":      row.get::<_, String>(2)?,
            "content":    row.get::<_, String>(3)?,
            "tokens_est": row.get::<_, i64>(4)?,
            "pinned":     row.get::<_, i64>(5)? == 1,
        }))
    }).unwrap()
      .filter_map(|r| r.ok())
      .collect();

    // Respect token budget
    let mut budget = 0i64;
    let selected: Vec<_> = rows.into_iter().take_while(|r| {
        let t = r["tokens_est"].as_i64().unwrap_or(0);
        budget += t;
        budget <= max
    }).collect();

    serde_json::json!({"ok": true, "entries": selected, "tokens_total": budget})
}

fn handle_build_transfer_bundle(conn: &Connection, scope: &str) -> serde_json::Value {
    // 1. Pinned memory for this scope
    let mut stmt = conn.prepare(
        "SELECT id, type, scope, content, tokens_est FROM memory
         WHERE scope = ?1 AND pinned = 1 AND active = 1"
    ).unwrap();

    let pinned: Vec<serde_json::Value> = stmt.query_map(params![scope], |row| {
        Ok(serde_json::json!({
            "id":      row.get::<_, String>(0)?,
            "type":    row.get::<_, String>(1)?,
            "scope":   row.get::<_, String>(2)?,
            "content": row.get::<_, String>(3)?,
            "tokens_est": row.get::<_, i64>(4)?,
        }))
    }).unwrap().filter_map(|r| r.ok()).collect();

    // 2. Project-type entries (objectives, constraints)
    let mut stmt2 = conn.prepare(
        "SELECT content FROM memory
         WHERE scope = ?1 AND type = 'project' AND active = 1
         ORDER BY updated_at DESC LIMIT 5"
    ).unwrap();
    let project_entries: Vec<String> = stmt2.query_map(params![scope], |row| {
        row.get(0)
    }).unwrap().filter_map(|r| r.ok()).collect();

    let token_est: i64 = pinned.iter()
        .map(|e| e["tokens_est"].as_i64().unwrap_or(0))
        .sum::<i64>()
        + project_entries.iter().map(|s| estimate_tokens(s)).sum::<i64>();

    serde_json::json!({
        "ok": true,
        "bundle": {
            "pinned":        pinned,
            "objectives":    project_entries.first().cloned().unwrap_or_default(),
            "project_state": project_entries,
            "active_files":  [],
            "constraints":   project_entries.iter().skip(1).cloned().collect::<Vec<_>>(),
            "token_est":     token_est,
        }
    })
}

fn handle_snapshot(conn: &Connection, session_id: &str, reason: Option<&str>) -> serde_json::Value {
    let id = new_id();
    let now = now_ts();

    // Capture all active memory as JSON blob
    let data = handle_fetch(conn, "general", None);

    conn.execute(
        "INSERT INTO snapshots (id, session_id, scope, data, reason, created_at)
         VALUES (?1, ?2, 'general', ?3, ?4, ?5)",
        params![id, session_id, data.to_string(), reason.unwrap_or("manual"), now],
    ).expect("snapshot insert failed");

    serde_json::json!({"ok": true, "snapshot_id": id})
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn main() {
    let db_path  = std::env::var("DB_PATH").unwrap_or_else(|_| "/data/memory/aicli.db".into());
    let sock_path = std::env::var("MEMORY_SOCK").unwrap_or_else(|_| "/tmp/aicli/memory.sock".into());

    std::fs::create_dir_all(std::path::Path::new(&db_path).parent().unwrap()).ok();
    let _ = std::fs::remove_file(&sock_path);
    std::fs::create_dir_all("/tmp/aicli").ok();

    let conn = Arc::new(Mutex::new(open_db(&db_path)));
    {
        let guard = conn.lock().unwrap();
        init_schema(&guard);
    }
    eprintln!("memory-engine: ready at {}", sock_path);

    let listener = UnixListener::bind(&sock_path).expect("cannot bind socket");

    for stream in listener.incoming() {
        let conn = Arc::clone(&conn);
        match stream {
            Ok(stream) => {
                std::thread::spawn(move || {
                    let reader = BufReader::new(&stream);
                    let mut writer = &stream;
                    for line in reader.lines() {
                        let line = match line { Ok(l) => l, Err(_) => break };
                        let cmd: MemoryCmd = match serde_json::from_str(&line) {
                            Ok(c) => c,
                            Err(e) => {
                                let _ = writeln!(writer, "{{\"error\":\"{}\"}}", e);
                                continue;
                            }
                        };
                        let guard = conn.lock().unwrap();
                        let resp = match cmd {
                            MemoryCmd::Store  { entry }             => handle_store(&guard, entry),
                            MemoryCmd::Fetch  { scope, max_tokens } => handle_fetch(&guard, &scope, max_tokens),
                            MemoryCmd::Pin    { id }                => {
                                guard.execute("UPDATE memory SET pinned=1 WHERE id=?1", params![id]).ok();
                                serde_json::json!({"ok": true})
                            }
                            MemoryCmd::Unpin  { id }                => {
                                guard.execute("UPDATE memory SET pinned=0 WHERE id=?1", params![id]).ok();
                                serde_json::json!({"ok": true})
                            }
                            MemoryCmd::Delete { id }                => {
                                guard.execute("UPDATE memory SET active=0 WHERE id=?1", params![id]).ok();
                                serde_json::json!({"ok": true})
                            }
                            MemoryCmd::BuildTransferBundle { scope, .. } => {
                                handle_build_transfer_bundle(&guard, &scope)
                            }
                            MemoryCmd::Snapshot { session_id, reason } => {
                                handle_snapshot(&guard, &session_id, reason.as_deref())
                            }
                            MemoryCmd::Compress { session_id: _ } => {
                                serde_json::json!({"ok": true, "note": "delegate to compressor service"})
                            }
                            MemoryCmd::Status => {
                                let count: i64 = guard.query_row(
                                    "SELECT COUNT(*) FROM memory WHERE active=1", [], |r| r.get(0)
                                ).unwrap_or(0);
                                serde_json::json!({"ok": true, "active_entries": count})
                            }
                        };
                        let _ = writeln!(writer, "{}", resp);
                    }
                });
            }
            Err(e) => eprintln!("memory-engine: accept error: {}", e),
        }
    }
}
