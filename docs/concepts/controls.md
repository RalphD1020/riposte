# Controls

> See also: [spec/invariants.md](../../spec/invariants.md) — CMD-001, MOVE-001, MOVE-002, SIDE-001, COMBAT-001
> See also: [docs/concepts/ux.md](./ux.md), [docs/concepts/combat.md](./combat.md)
> Source: `game/project.godot` `[input]`, `game/src/application/input/human_input_state.gd`, `game/src/application/app/screens/match_screen.gd`, `game/src/presentation/input/touch_controls.gd`

Two verbs on every device. All sources merge into one `HumanInputState`, consumed once per tick into a `PlayerCommand`. Action names come only from `InputActions` (`game/src/application/input/input_actions.gd`); APP-SHELL proves each one exists in the InputMap.

| Verb          | Desktop                        | Touch                                              |
| ------------- | ------------------------------ | -------------------------------------------------- |
| Move          | WASD or arrows (physical keys) | Floating joystick: anywhere in the lower-left zone |
| Burst         | Double-tap a move direction    | Double-deflect the joystick in one direction       |
| Attack        | Left mouse or Space            | Lower-right zone; hold to charge                   |
| Pause         | Esc or the HUD pause button    | HUD pause button                                   |
| Debug overlay | F3 (debug builds only)         | —                                                  |

The desktop column is the default. Every gameplay action except the debug overlay can be rebound.

## Rebinding

Settings → **Move keys** and **Action keys** list each action with two bindings. Choose one, then press the new key or mouse button; Esc stops waiting. `KeyBindings` (`game/src/application/input/key_bindings.gd`) owns the set, and it is input only: it rewrites the `InputMap` actions the game already reads, so the simulation receives the same commands whatever is bound and a replay cannot tell a remapped player from a default one.

- Defaults are the actions authored in `project.godot`, read at startup, never repeated in code. **Reset keys** restores them.
- Keys are physical, like the defaults, so a layout change never moves them. Mouse buttons are allowed; the wheel is not, because it cannot be held.
- No input does two things. Binding a key another action uses swaps the two; a swap that would leave that action with no binding at all is refused, and the page names the action that needs the key.
- The stored set is untrusted: a duplicate, an impossible code, a wrong shape or an action with nothing bound falls back to the defaults as a whole, because a partly merged set could double-bind.
- Touch controls are not rebindable; their zones are the layout.
- Help text (How to Play, the tutorial prompts) names the default keys.

## Semantics

- One logical attack button: held while any source holds it; press/release edges accumulate until the next tick, so a sub-frame tap still counts.
- **Toggle charge** (Settings → Controls, COMBAT-READABILITY-001): press once to begin a charge and press again to swing, so no hold is ever required. It emits exactly the press and release edges a hold does, so the simulation — and every replay — cannot tell the two apart.
- Touch moves override keys while a thumb is down. Fingers are tracked by index; two thumbs never steal from each other.
- Cancel without attacking: OS-canceled touches, pause, focus loss, and the rotate prompt call `cancel_all()` → `attack_cancel` edge (CMD-001).
- The HUD pause button is never keyboard-focusable, so Space always attacks. GUI focus is released when a duel starts and on resume.
- Touches over GUI exclusions (the pause button) belong to the GUI; `emulate_mouse_from_touch=false`, and Godot 4.7 `BaseButton` handles `ScreenTouch` natively.
- Whichever end of the arena you are given, you are always at the bottom of your own screen (SIDE-001). The world does not turn; only your camera does, so W is always up the screen and D is always right — for both sides.
- You turn to face your opponent (tracking), and footwork is relative to your **heading**, not to the arena (MOVE-001, MOVEMENT-FRAME-001). W drives down the line you face, S backs off it, A and D step to its sides. Against a settled opponent that line is them, so W closes the measure and A/D circle; world-axis movement would make the same key advance, retreat, or sidestep depending on where the pair had drifted.
- The heading is the same line your sword hangs on. Your opponent's bearing only turns it, at the turn rate your commitment leaves — so after a heavy swing, W keeps driving down the line you committed to while you come round, rather than steering your feet onto a target that has stepped aside. That lag is the opening a well-read attack concedes; there is no steering penalty and no running bonus on top of it.
- Every controller speaks this same language. The CPU's forward is its own heading too, so it gets no footwork a player cannot.
- The attack buffer is four ticks (about 67 ms), for discrete actions only — an attack press or release: one pending per action, it expires, it fires on the first legal tick and never cuts physical recovery short. Turning and footwork are never buffered. Deliberately short: a longer one fires an attack you have already mentally abandoned.
- A double tap in one duel direction buys a burst: a lunge forward, a leap back, or a hard slide-step sideways (MOVE-002). The two dashes along the line between you are stronger than the lateral step, because the whole body drives them. The HUD shows the stamina a dash spends. There is no separate cooldown — the limits are physical. The intent has to come genuinely to **rest** between the two taps, so holding a direction and then tapping it never dashes, and a thumb steering continuously around the stick never earns one it did not ask for.
- A burst commits to the heading it launched in and will not bend, so a lunge cannot chase an opponent who circles away. It _adds_ to your footwork rather than replacing it, so you keep your feet and can lean out of a dash while it carries you — reacting faster must never cost you anything. Bursting during a committed swing is exactly as sluggish as any other repositioning (PHYS-003): a dash is never an escape from a swing you already paid for.
