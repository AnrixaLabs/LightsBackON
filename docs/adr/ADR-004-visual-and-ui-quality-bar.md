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
