# Telemetry

> See also: [docs/concepts/simulation.md](./simulation.md), [docs/architecture/SECURITY.md](../architecture/SECURITY.md)
> Source: `game/src/application/telemetry/`

Two event families that never mix:

- **Duel events** (`DuelEventTypes`): what happened in a fight. Authoritative, returned by `DuelSimulation.step`, logged by `MatchSession`, replayable.
- **Product events** (`ProductEvents`): how people use the app (game loaded, quick play, difficulty changed, tutorial started/completed, settings opened, match started/finished/exited, rematch, community clicked, orientation prompt seen, fullscreen entered).

`TelemetrySink` is the seam: the default keeps a bounded in-memory product log (`PRODUCT_LIMIT`) plus a duel-event count and sends nothing anywhere. A vendor, network, or replay sink replaces it without touching the simulation. Product event properties carry ids and enums only, never personal data; their keys are `ProductEvents.PROP_*` (duel payload keys are `DuelEventKeys`).

| Concept                               | Code                                               |
| ------------------------------------- | -------------------------------------------------- |
| Product event names and property keys | `game/src/application/telemetry/product_events.gd` |
| Sink                                  | `game/src/application/telemetry/telemetry_sink.gd` |
