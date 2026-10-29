# ADR-013: Crew communication (pings, phrases, text chat)

- Status: Accepted (V06, cloud, 29 Oct 2026, under ADR-011). Implements CLAUDE.md sections 1 (no voice chat; completable with pings alone) and 9.

## Decision
1. **Four context pings** (`content/comms.json`): PING_LOOK, PING_HELP, PING_FAULT, PING_EQUIPMENT, each with a text key, an icon id and a token
   color (listed in `content/ui/status_states.json`). A ping carries the targeted content ID (or none) and the **host's** position for the player.
   Lifetime 80 ticks (8 s); at most 3 active per player (the oldest is replaced); 4 pings per 20 ticks per player.
2. **Radial phrases** are fixed IDs mapped to localization keys (8 phrases), so they need no escaping and read in every language.
3. **Text chat** (intent `chat`, payload `text`): the host collapses whitespace, removes control and format characters (including bidi overrides
   and zero-width characters), refuses empty lines and lines over 120 characters, and allows 3 lines (phrases included) per 50 ticks per player.
   Printable characters of every script are kept (Simplified Chinese is a release language). Clients show the text in a plain Label, or in a
   RichTextLabel only after `display_text()` escapes every `[` as `[lb]`, so no BBCode tag can form and chat never launches a URL.
4. **Mute** is per viewer and client-side: it hides chat and phrases from the muted player; pings stay visible so the crew can always coordinate.
5. Comms are ephemeral events relayed by the host: not part of the authoritative state hash, not saved, not a durable revision change. A leaving
   player's pings are removed.
6. Envelope `max_string_length` is 128 so a 120-character line fits. `ready` remains UNSUPPORTED_INTENT until the lobby task.
