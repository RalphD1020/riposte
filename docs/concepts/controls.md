# Controls

> See also: [spec/invariants.md](../../spec/invariants.md) — CMD-001, COMBAT-001
> See also: [docs/concepts/ux.md](./ux.md), [docs/concepts/combat.md](./combat.md)
> Source: `game/project.godot` `[input]`, `game/src/application/input/human_input_state.gd`, `game/src/application/app/screens/match_screen.gd`, `game/src/presentation/input/touch_controls.gd`

Two verbs on every device. All sources merge into one `HumanInputState`, consumed once per tick into a `PlayerCommand`. Action names come only from `InputActions` (`game/src/application/input/input_actions.gd`); APP-SHELL proves each one exists in the InputMap.

| Verb          | Desktop                        | Touch                                              |
| ------------- | ------------------------------ | -------------------------------------------------- |
| Move          | WASD or arrows (physical keys) | Floating joystick: anywhere in the lower-left zone |
| Attack        | Left mouse or Space            | Lower-right zone; hold to charge                   |
| Pause         | Esc or the HUD pause button    | HUD pause button                                   |
| Debug overlay | F3 (debug builds only)         | —                                                  |

## Semantics

- One logical attack button: held while any source holds it; press/release edges accumulate until the next tick, so a sub-frame tap still counts.
- Touch moves override keys while a thumb is down. Fingers are tracked by index; two thumbs never steal from each other.
- Cancel without attacking: OS-canceled touches, pause, focus loss, and the rotate prompt call `cancel_all()` → `attack_cancel` edge (CMD-001).
- The HUD pause button is never keyboard-focusable, so Space always attacks. GUI focus is released when a duel starts and on resume.
- Touches over GUI exclusions (the pause button) belong to the GUI; `emulate_mouse_from_touch=false`, and Godot 4.7 `BaseButton` handles `ScreenTouch` natively.
- You always face your opponent (tracking); movement is relative to the fixed camera (screen up = arena +y).
