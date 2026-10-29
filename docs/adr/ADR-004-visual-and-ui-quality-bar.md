# ADR-004: Visual and UI quality bar (owner direction)

- Status: Accepted (owner direction, 29 Oct 2026). Clarifies blueprint sections 9-10; changes no locked decision.

## Owner direction
"Design it in a bright and professional manner. All icons, characters and design elements should match the implementation and
match the industry standard. Having a nice design is important."

## Interpretation (binding for every UI, art, icon and VFX task)
1. **Bright means legible and inviting, not a light theme.** Keep the blueprint tokens (background #111B25, panel #1B2A38, elevated
   #243748, text #F3F5EF / #B9C6CF, restored teal #65D6B4, action amber #FFC86B, fault coral #F28B82, unknown gray-blue #7E93A3).
   Restored states read clearly warm and lit; the dark state still keeps navigation readable (sky fill, reflective labels, the van).
   No scene or screen relies on darkness to hide content (pillar 3). Moving to a light UI theme would need a new ADR from the owner.
2. **Icons match the implementation.** One icon per real game state or action; the icon set is defined from the actual state enums
   (repair states, supply states dark / temporary / restored, unknown `?`, lock owner, ping types, breaker tripped), never invented
   ahead of the code. Every status shows icon + text (no color-only meaning). One consistent family: same grid (24 px base at
   1920x1080, scaled by the UI scale slider), same stroke weight, rounded caps, flat fills from the tokens.
3. **Industry-standard conventions.** Platform input glyphs follow the device in use (keyboard/mouse vs controller), remappable labels
   update with bindings. Electrical-looking symbols stay recognizable (bolt for supply, breaker/fuse pictograms, meter readout) but
   remain the abstract PU puzzle, not an electrical simulator. WCAG 2.2 AA contrast (4.5:1 body text, 3:1 large text and icons) checked on
   the actual rendered background including translucent overlays; 48x48 px minimum targets; 80 px safe area.
4. **Characters and props match the blueprint.** One shared worker rig, four helmet/vest palettes, reflective workwear, chunky tools,
   rounded-but-grounded 4 m kit, warm cream windows vs cool blue street light. Visible tool and gloved hands in first person.
5. **Accuracy over decoration.** UI copies the layout of the five 1920x1080 reference pages (blueprint pp. 42-46): objective top-left,
   crew top-right, prompt below reticle, equipment bottom-left, events bottom-right. Text in localization keys, never baked into images.
6. **Licensing still applies.** Any font (Noto Sans preferred), icon pack, model, sound or image needs owner approval and recorded
   creator/source/license before it is added (CLAUDE.md section 6 stop-and-ask list).

## Consequences
UI/art tasks include a visual check against the reference page and a contrast check in their evidence file. Cloud sessions do not do
art/visual work (CLAUDE.md section 7); they may author token resources, theme data and the icon state list.

## Addendum F05 (29 Oct 2026): measured token contrast
`tools/check_contrast.py` (run by `tools/run_tests.sh`) checks every allowed foreground/background pair in `content/ui/tokens.json`, on opaque
surfaces and on HUD panels composited over a white (bright restored window) and a black backdrop. Findings:
1. The blueprint `unknown` gray-blue is **3.84:1 on the elevated panel**: allowed there only for icons and large text (>= 24 px), not body text.
2. At 92 % panel opacity over a white backdrop, `fault` on elevated (4.01:1) and `unknown` on panel (3.60:1) fail AA; `unknown` body text on the panel
   needs a fully opaque panel (99 % gives 4.46:1). Decision: **text-bearing HUD panels are opaque** (`panel_alpha_percent: 100`); translucency is for
   decorative frames only. Alternative for the owner: keep translucency and draw `?` values in `text_muted` with only the icon in `unknown`.
3. Status icon list (`content/ui/status_states.json`) is generated from the code state lists (repair STATES, meter FINDING_CODES) and a test fails if
   a state is added in code without an icon entry or an icon exists for a state the code does not have.

## Addendum F05 (30 Oct 2026): UI02 icon family and asset record
1. **Family rules (checked by `tests/unit/test_F05_icons.gd`):** one SVG per entry in `content/ui/status_states.json`, 24 px canvas, white ink
   only, 2 px stroke, rounded caps and joins, a 1 px clear margin, and 6-50 % ink coverage at 24 px. No text, scripts or external references.
   Color comes only from the token, applied at runtime (`self_modulate`). Any two icons must differ in at least 16 strongly inked pixels at 24 px,
   so no state relies on color. Exports are 24/32/48 px PNGs; `scripts/ui/icon_raster.gd` picks the smallest export at least as large as
   24 px x UI scale.
2. **Count:** blueprint UI02 says 24 families. The real state lists need 36 icons: 9 repair, 11 findings, 3 supply, 3 other, 4 pings, and the
   5 tools and 1 equipment kind that C01 content uses. Point 2 above (one icon per real state, nothing invented) takes precedence over the estimate.
3. **Sources:** the icons live in `art_source/ui_icons/` as small text SVG, exempt from the art_source LFS rule in `.gitattributes`.
4. **Asset record (blueprint p.40-41 pipeline step 1):** UI02 icons, 36 SVG.
   - Creator: original work drawn for this project in a Claude Code desktop session, 30 Oct 2026, for Anrixa Labs.
   - Source: `art_source/ui_icons/*.svg` at the commit that adds them.
   - License: project-owned. No third-party icon pack, font or image was used or traced.
   - Approval: approved by the owner (Levon), 30 Oct 2026, from the review sheet `docs/evidence/img/F05_icon_sheet.png`.

## Addendum F05 (30 Oct 2026): UI font
The owner chose **Noto Sans** (30 Oct 2026, desktop session), as the blueprint suggests on p.11.
1. **Asset record (blueprint p.40-41 step 1):**
   - File: `assets/fonts/noto_sans/NotoSans-Variable.ttf`, the upright variable font with `wdth` and `wght` axes, Noto Sans v2.015.
     Its original name is `NotoSans[wdth,wght].ttf`.
   - Source: google/fonts at commit 8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5 (`ofl/notosans/`). Upstream is notofonts/latin-greek-cyrillic
     at c4a321e.
   - Integrity: SHA-256 bfb7bb69...6b3d. The git blob hashes of the font and `OFL.txt` match the hashes GitHub's API reports for that commit.
   - Creator: "Copyright 2022 The Noto Project Authors".
   - License: **SIL Open Font License 1.1**. `OFL.txt` sits next to the font.
   - The record is in `content/ui/tokens.json` `font`. A test checks that the committed file still hashes to it.
2. **Use:** body text uses the default weight (400); buttons and headings use the same file at 600 through `FontVariation`. No italic file
   was added, because the UI has no italic style.
3. **OFL obligations for release:** ship `OFL.txt` with the font, so the export filter must include it (or put the license text in the credits).
   The font must not be sold on its own, and the reserved names do not apply because the font is not modified.
   The release checklist (R milestone) must check this.
4. **Not yet covered:** Simplified Chinese (blueprint p.11 release language) needs Noto Sans SC as a fallback font. That file is about 10x larger,
   so it waits for the localization task and the owner's go-ahead.

## Addendum V07 (30 Oct 2026): field HUD and network tablet
Decisions made while building S06/S07 (blueprint p.23, references p.42-43). None changes a locked decision.
1. **Objective status icons.** The objective card needs a status per row (mission_director STATUS_DONE / ACTIVE / PENDING), and point 2 says
   one icon per real state, so three icons were added: `icon_objective_done` (checked box), `icon_objective_active` (box with a play mark),
   `icon_objective_pending` (dashed box). They follow the F05 family rules and the tests check them like the others (39 icons now).
   - Creator: original work drawn for this project in a Claude Code desktop session, 30 Oct 2026, for Anrixa Labs. Source:
     `art_source/ui_icons/icon_objective_*.svg`. License: project-owned. No third-party icon was used or traced.
   - Approval: **provisionally approved by the owner, 30 Oct 2026** ("they can be reviewed later; consider approved for now"). The look at
     `docs/evidence/img/V07_objective_icons.png` is deferred and tracked in `docs/PC-WORK.md` section 5. The F05 approval covered the 36 icons at e5ab01e.
2. **UI scale.** Effective scale = slider (80-150 %) x how much of the 1920x1080 canvas the window shows, so 150 % on 1280x720 draws like
   100 % on 1080p. The theme is rebuilt at that scale (fonts, padding, icons from `export_px_for_scale`) so containers reflow; the canvas
   is never stretched. The 80 px safe area follows the screen size, not the slider.
3. **Reflow rules** that keep every region readable at 150 % and with the 35 % pseudo-locale (checked at 1280x720, 1920x1080, 1920x1200):
   - The prompt keeps the reference width on screen (560 px at 1080p) and wraps rather than widening.
   - The prompt sits 140 px below the reticle. When a bottom card under it is taller, it moves up toward the reticle but never covers it.
   - The tool bar shows number + icon + name per slot. If that would run under the prompt, it switches to number + icon, with the selected
     tool's name above the slots.
   - Crew rows are one line: name, then a task chip (lock icon + repair name, or equipment icon + item name).
   - The event card narrows instead of sliding under the prompt.
4. **The tablet may only inspect and ping.** It holds an intent-outbox gate that allows exactly `inspect` and `ping`; any other intent is
   refused before anything is sent. Accept on a node sends `inspect` for its meter panel and the host decides range; nodes without a
   panel only show what is visible. Values come only from current meter snapshots. Unmeasured values read "Unknown - inspect junction"
   (`?` in the meter), and a stale snapshot reads "Changed since inspection - inspect again".
5. **Tablet navigation.**
   - Left stick / D-pad moves between map nodes by adjacency, graph neighbours first. At the map's edges focus leaves to the tabs (up),
     the evidence panel (right) and the footer (down).
   - The right stick pans the map, or scrolls the evidence panel when that has focus. RT/LT zoom.
   - Zoom levels at which the biggest node would not fit the view are skipped.
   - The evidence panel scrolls with a visible bar, and Ping stays below it (never below the fold).
   - B / Esc / Tab (View) close the tablet and focus returns to the previous control.
   - Godot's built-in `ui_accept` / `ui_cancel` have no controller button, so A and B were added in `generate_input_map.gd`.
6. **Binding labels are text** (`[E]`, `[MMB]`, `[A]`, `[LB]`) read from the live InputMap, so remapping updates them. Controller glyph
   images (point 3) are a separate asset set for later; they need either original drawings or an approved third-party set.
7. **Strings.**
   - English UI strings live in `content/ui/strings/en.json` and are looked up by key.
   - A test fails if content or the UI uses a key without English text.
   - The pseudo-locale is generated from the English strings.
   - Simplified Chinese still waits for its fallback font (UI font addendum point 4).
8. **Rendered contrast (closes F05's last item).** `tools/godot/capture_hud.gd` draws the HUD over the V01 graybox on the GTX 1650 (dark and
   restored windows, 100 % and 150 %) and the tablet at 100 % and 150 %. Every frame is drawn twice, the second time with only the text and
   icons hidden, so each probe is measured against the pixels actually behind it. Result: 252 probes, none below AA. The tightest is the
   `unknown` gray-blue "Not measured" on the panel at 4.59:1, consistent with the F05 contrast addendum.
