# ADR-014: Personal reward receipts and profile progression

- Status: Accepted (V08, cloud, 29 Oct 2026, under ADR-011). Implements blueprint p.10 (save and progression contract) and p.12 (economy, stars).

## Decision
1. **Results** (mission director, at completion): required restored, optional services, trips, preventable trips (trips beyond the contract's
   `tutorial_trip_allowance`; C01: 1, the sign warning), crew recoveries, ticks, equipment collected, stars (1 completion; 2 all optional
   services, automatic when the contract has none; 3 no preventable trips). No speed star.
2. **Credits** (`content/economy.json`): 500 base + 100 completion + 50 per optional service (cap 100) + 50 equipment restowed. C01 = 650.
3. **Receipts**: one per participant connected at completion; key = SHA-256 of `campaign_id|contract_instance_id|account_key`;
   `contract_instance_id` = `<campaign>_<contract>_R<run>` from the host campaign's run counter. A new run is a new receipt.
4. **Host queue** keeps receipts per account until the client acknowledges; reconnecting players get them again; re-issuing is idempotent.
5. **Client**: received receipts are written to `receipts.json` first; then every receipt not yet applied is applied to `profile.json`, which itself
   stores `applied_receipts`, in one atomic write (ADR-008). Replays, re-sends, reopening and a crash between the two writes never pay twice.
   A receipt for another account, or whose key does not match its own fields, is refused. An unreadable profile is never reset.
6. **Board**: completing contract N unlocks N and everything before it plus N+1 (`unlocked_through`), so prerequisites are never replayed;
   best stars per contract are kept. Receipts never touch any campaign file (a guest's own campaign keeps its state).
7. **Open for the owner / CT07**: every new run earns a fresh receipt, so credits from replaying a completed contract are unbounded until
   bounded progression (CT07) decides replay rewards. The checksum detects corruption; it is not anti-cheat (offline profiles can be edited).
