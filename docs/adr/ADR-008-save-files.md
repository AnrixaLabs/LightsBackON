# ADR-008: Save file format and write protocol

- Status: Accepted (G06, cloud sprint B, 29 Oct 2026). Implements blueprint p.10 "Save and progression contract" and CLAUDE.md section 5.

## Decision
1. **Envelope** (one per file, canonical JSON per ADR-003, schema = `save_schema_version` in `content/versions.json`, now 1):
   `schema_version, build_id, content_revision, saved_at_utc, kind, record_id, payload, checksum` where checksum = SHA-256 of the canonical
   envelope without `checksum`. Payloads hold only ints, bools, printable-ASCII strings, arrays and objects (NOT_CANONICAL otherwise).
2. **Write**: refuse if the current file has a newer schema (TARGET_NEWER_SCHEMA, bytes untouched); if the current file is unreadable, rename it to
   `<name>.unreadable-<timestamp>` (never erased); write `<name>.tmp` in the same directory, flush, close, read back and verify; remove the old
   `<name>.bak`, rename the valid current to `<name>.bak`, rename the temp into place. No step renames onto an existing file, so the sequence
   behaves the same on Windows and Linux.
3. **Read**: current, then a complete temp, then backup. Any fallback adds an issue (`CURRENT_CORRUPT`, ...) the UI must show. A newer-schema file
   stops the read with NEWER_SCHEMA instead of falling back to an older copy (SAVE03: refuse, preserve bytes, offer another profile).
4. **Checkpoint payload** (`checkpoint_codec.gd`): grid causes (runtime flags, added edges, tick, overload counters), repair states, supplies,
   access flags, equipment anchors. Never derived power state; load recomputes it. Locks and carried state are session state: locks are dropped,
   carried items return to their last anchor. Meter snapshots are not saved, so panels read `?` after a load.
5. Paths: `user://profiles/<account_key>/{campaign,profile,receipts}.json` and `checkpoints/<campaign_id>.json`; account_key is a local random or
   hashed key (letters, digits, `_`, `-`, at most 64), never a raw Steam ID.
6. Limits: Godot offers flush but no fsync, so power-loss durability depends on the OS. SAVE01 here is fault injection at three crash points inside
   the writer, not a killed process; the real kill test runs on the exported build (H01 / local).
