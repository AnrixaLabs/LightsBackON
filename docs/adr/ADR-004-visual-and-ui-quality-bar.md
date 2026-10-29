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
