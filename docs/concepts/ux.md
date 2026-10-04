# UX

> See also: [spec/invariants.md](../../spec/invariants.md) — UX-001, WEB-006
> See also: [docs/concepts/controls.md](./controls.md), [docs/concepts/presentation.md](./presentation.md), [docs/concepts/web.md](./web.md)
> Source: `game/src/application/app/`, `game/src/presentation/theme/riposte_theme.gd`, `apps/web/src/app/globals.css`

Apple-style minimal, light-only, mobile-first, accessible by construction (UX-001).

## Palette (shared by game and website)

| Role            | Color                       | Use                                                                  |
| --------------- | --------------------------- | -------------------------------------------------------------------- |
| Dark Steel Gray | `#404548`                   | Frame, primary actions, text on light                                |
| White           | `#ffffff`                   | Surfaces, text on steel                                              |
| Mauve           | `#b6aeb3`                   | Decorative accents, opponent HUD fill                                |
| Sage            | `#797e71` / light `#aeb2a9` | Decorative; sage-light is the only accent allowed as text (on steel) |

Game tokens: `RiposteTheme`. Web tokens: `@theme` in `globals.css`. Both are contrast-tested pair by pair.

## Screens

```text
MAIN_MENU ─Quick Play─▶ MATCH ─▶ RESULTS ─Rematch─▶ MATCH
    │                     │ Esc / ‖ / focus loss → PAUSE (Resume · Settings · How to Play · Quit)
    ├─How to Play─▶ HOW_TO_PLAY ─Start Training─▶ MATCH (training + coaching prompts)
    └─Settings─▶ SETTINGS (Audio · Display · Gameplay · Controls drill-down)
```

| Concept                                                                 | Code                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------ |
| Composition root (settings, telemetry, kits, camera, router, actions)   | `game/src/application/app/riposte_app.gd`              |
| One screen at a time; old screen leaves the tree before the next builds | `game/src/application/app/screen_router.gd`            |
| Menu frame (safe area, two-column compact landscape, focus, Escape)     | `game/src/application/app/screens/screen_base.gd`      |
| Screens                                                                 | `game/src/application/app/screens/`                    |
| Settings panel, pause overlay, how-to-play content                      | `game/src/application/app/panels/`                     |
| Builders for every menu control                                         | `game/src/application/app/ui_kit.gd`                   |
| Menu and coaching copy (HUD copy lives in `HudCopy`)                    | `game/src/application/app/app_copy.gd`                 |
| UI scale and safe area                                                  | `game/src/application/app/ui_scale.gd`, `safe_area.gd` |

## Layout rules

- **One UI unit ≥ one CSS pixel** (`UiScale`): `canvas_items` stretch from 1280×720 alone would shrink phone targets below 48 CSS px. 3D renders at ≤ 2× CSS resolution.
- Menus fit a 360 px-tall landscape phone without scrolling: short landscape screens put `lead` (title) and `body` (actions) side by side (proven by APP-SHELL); settings drill into one short section at a time.
- **Styles live in `RiposteTheme`** (the game's stylesheet): container defaults (column `STACK_GAP`, row `CONTROL_GAP`) and type variations (`PageColumns`, `PageStack`, `SheetMargin`, `SectionLabel`, `CaptionLabel`, `FieldLabel`, `HeadingLabel`, `TitleLabel`, …). `UiKit` builders and screens pick variations; the only per-node override is runtime safe-area margins (`RiposteTheme.apply_insets`).
- Safe-area insets come from the Web export's head include (`window.riposteSafeAreaJson`) or the display server.
- Touch devices on portrait get a rotate prompt (dismissable); it pauses the clock.

## Accessibility

- Contrast: text ≥ 4.5:1, essential boundaries ≥ 3:1 (tests: `game/tests/presentation/test_theme.gd`, `apps/web/src/app/theme.test.ts`).
- Targets ≥ 48 UI units; visible focus ring (3 px + 3 px gap); keyboard focus starts on the primary action (touch devices: on first navigation key, so no ring sits under a thumb).
- Selection shown by fill **and** a drawn marker; pips are shapes; switches move the knob. Never color alone.
- Live regions announce banners, coaching prompts, pause, and results; health bars expose "N of M".
- Reduced Motion, Reduced Flash, Screen Shake, High Contrast Weapons, Charge Indicator, touch opacity, and Haptics are settings.
- Every shipped string renders in the shipped font (test: `game/tests/application/test_app_shell.gd`).

## Settings persistence

`PlayerSettings` → `user://settings.cfg` (IndexedDB on Web; file layout in `SECTION_*` / `KEY_*`). Loaded values are sanitized; failures degrade to defaults and show "could not be saved". Toggles save immediately; volume drags save once when the panel closes. Volumes scale the `AudioBuses` defined by `game/default_bus_layout.tres`.
