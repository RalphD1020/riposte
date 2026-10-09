class_name PresentationPhysicsLayers
extends RefCounted

## Godot physics layers for presentation-only bodies. Riposte's authoritative
## combat is a custom deterministic 2D solver and uses no Godot physics at all;
## these layers exist so that presentation physics (a dropped sword now, a
## ragdoll later) only ever touches other presentation geometry. They sit well
## above the default layer 1, so nothing that defaults its layer can collide
## with them by accident. A presentation body never reports back.
##
## See also: /docs/concepts/presentation.md

## The arena floor as a presentation surface (the platform top, to its edge).
const PRESENTATION_GROUND := 1 << 9
## A sword that has left the hands.
const DROPPED_WEAPON := 1 << 10
