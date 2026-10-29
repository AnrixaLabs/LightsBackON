# ADR-009: Command envelope and host validation order (protocol_version 1)

- Status: Accepted as a draft on the development transport (F03, 29 Oct 2026). Implements blueprint p.9-10 and CLAUDE.md section 4.
  Must be re-confirmed on the Steam peer once F02 qualifies a tuple.

## Decision
1. **Envelope** (UTF-8 JSON object, exactly these keys): `session` (string), `seq` (int >= 1, per sender, increasing), `type` (intent),
   `entity` (stable content ID), `payload` (flat object of bools, numbers and strings up to `max_string_length`; at most `max_payload_keys`).
   No identity, role or authority fields: the sender is the transport peer ID. Limits live in `content/network.json`.
2. **Validation order** (first failure wins, nothing mutates before the last step): size (TOO_LARGE) -> parse/shape (MALFORMED) -> membership
   (UNKNOWN_PEER) -> session (WRONG_SESSION) -> sequence (duplicate or STALE_SEQUENCE) -> rate (RATE_LIMITED, per sender, sliding window in
   ticks) -> intent (UNKNOWN_INTENT / UNSUPPORTED_INTENT for ping, ready, request_extract until V02/V06) -> entity (UNKNOWN_ENTITY) -> host range
   check (NOT_IN_RANGE) -> owning service rules (locks, isolation, tools, grid validation).
3. **Dedupe**: a sequence is consumed once it passes the rate check, whatever the outcome; any later message with that `(sender, seq)` gets the
   cached reply with `duplicate: true` and is never applied, even if its body differs. Replies are cached for `dedupe_window` sequences.
4. **Revision**: one host revision counter, returned on every reply. It advances once per accepted command that changes the canonical
   authoritative state (grid, repairs, equipment, meter snapshots), and on admission, removal and lock timeouts. Refusals and duplicates never advance it.
5. **Admission** (NET08 logic): protocol_version (`content/versions.json`, now 1) and content_revision must match the host's, otherwise the join is
   refused with a reason before any player is spawned. The host player is admitted like everyone else (peer 1) and uses the same path.
6. **Intents mapped**: toggle_switch -> content switches (C01: SW_SIGN); inspect -> meter; request_lock/release/heartbeat/repair_step/equip ->
   interaction service; place_item with payload `action` -> equipment service.
7. **Transport**: `transport_adapter.gd` offers offline, ENet (development only) and Steam (refused STEAM_NOT_QUALIFIED until F02); one reliable
   ordered channel 0 is the baseline.
