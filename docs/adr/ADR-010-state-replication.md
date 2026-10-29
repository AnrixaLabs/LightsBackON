# ADR-010: Authoritative state replication (deltas, snapshots, hashes)

- Status: Accepted as a draft on in-process delivery (G07, 29 Oct 2026). Implements blueprint p.10 (join/reconnect) and step 8 of the grid tick.
  Re-confirm on real peers (F06/G08).

## Decision
1. **Authoritative state** = `{grid, repairs, equipment, meter}` canonical states (ADR-003 bytes). Its SHA-256 is the state hash every peer compares.
2. **Host loop**: `session_host.tick(now)` at 10 Hz runs the grid step (trips), records trip reasons on the meter, times out locks and emits
   `checkpoint_due` every `checkpoint_interval_ticks` (600 = 60 s); a reply whose repair reached `restored` carries `checkpoint_due: true`.
   Any change to the authoritative state advances the single host revision (the grid tick counter is part of the state, so a tick is a change).
3. **Deltas**: `publish()` diffs the last published state against the current one into `set`/`del` ops on key paths, tagged `from`/`to` revision and
   the resulting hash. Durable deltas go over the reliable ordered channel.
4. **Snapshots**: `snapshot()` flushes a delta, then sends a manifest (revision, hash, byte length, chunk count, protocol and content revision) and
   chunks of `snapshot_chunk_bytes`. Deltas published after it start at the snapshot revision.
5. **Client mirror** (`session_client.gd`): `joining` while the snapshot arrives (UI freezes the player), deltas queued; snapshot verified by length,
   hash and content revision; queued deltas newer than it applied in revision order; gaps wait, duplicates are ignored; a delta whose result does not
   hash to the host's hash is rejected (`desync`, request a fresh snapshot); the queue is bounded by `max_queued_deltas`. Clients read supply only
   from the mirror; they never evaluate the grid.
6. Full-state diffing per publish is fine at C01 scale; if profiling shows cost, keep the same wire format and track dirty paths instead.

## Addendum V04 (29 Oct 2026): four-player join flow
7. **Content handshake** uses the real content hash (`content_hash.gd`, same algorithm and bytes as `build_manifest.py` content_revision; the
   cross-check compares them). A peer with any different content byte is refused (CONTENT_MISMATCH) before spawning.
8. **Capacity** `max_players` 4 (`content/network.json`); a fifth join is SESSION_FULL.
9. **Reconnect admission**: identity comes from the transport, so the same player on a new connection replaces a stale connection that is still
   registered (its locks release, carried items return). The authoritative state includes the sorted `crew` list, so a duplicate actor would
   show up as a hash mismatch.
10. **Revision barrier**: a remote peer is admitted as joining; its commands are refused (NOT_SYNCED) until it confirms a snapshot revision at or
   after its admission revision (`confirm_synced`; older ones are STALE_SNAPSHOT). The host player (peer 1) is synced at admission.
11. **Chunk bound**: snapshot chunks bound the *encoded* message (escaped JSON) to `snapshot_chunk_bytes`, not just the raw slice.
