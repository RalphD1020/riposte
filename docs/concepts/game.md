# Game

> See also: [README.md](../../README.md), [spec/invariants.md](../../spec/invariants.md)
> See also: [docs/reference/godot.md](../reference/godot.md)
> Source: `game/`

Riposte is a physics-driven 1v1 sword duel for the browser: two verbs (move, attack), real steel, and the timing between them. MVP-0 is single player: Quick Play against a CPU (Easy, Medium, Hard) and Training with a dummy and coaching prompts.

## Product loop

`website → Play → Godot loading shell → main menu → Quick Play → duel → results → rematch or menu` ([docs/concepts/ux.md](./ux.md)). Matches are best of five rounds; a round ends on a kill, a double kill (draw), or time (more health wins).

## Where to read next

| Topic                                                         | Doc                                  |
| ------------------------------------------------------------- | ------------------------------------ |
| Deterministic simulation, ticks, replay, sessions, clock      | [simulation.md](./simulation.md)     |
| Footwork, attack language, collision, parry, damage           | [combat.md](./combat.md)             |
| CPU perception, decisions, difficulty                         | [cpu.md](./cpu.md)                   |
| Snapshots, presenter, kits (art/animation/sound in one place) | [presentation.md](./presentation.md) |
| Screens, layout, accessibility, settings                      | [ux.md](./ux.md)                     |
| Devices → commands                                            | [controls.md](./controls.md)         |
| Product vs duel events                                        | [telemetry.md](./telemetry.md)       |
| Website and play admission                                    | [web.md](./web.md)                   |

## Runtime

- Godot **4.7.2-stable**, Compatibility renderer, single-threaded Web export (WEB-001, WEB-003).
- Entry: `game/src/main/main.tscn` → `RiposteMain` → `RiposteApp` (composition root).
- itch.io hosts the Godot Web export `dist/game/web/` (WEB-004); the website is a gateway ([web.md](./web.md)).

## Future seams (not in MVP-0)

Server authority (re-simulate commands, compare hashes), share-link play, matchmaking, accounts, ranked/ELO. Each wraps `DuelSimulation`, `PlayerCommand`, `ReplayRecord`, and `TelemetrySink` rather than replacing them.
