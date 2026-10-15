class_name PresentationContact
extends RefCounted

## One touching sword-contact point as presentation sees it: a read-only copy
## of a `SwordContactSet` point (CONTACT-PRESENTATION-001). Where it is on
## the combat plane and along each blade, its normal, the impulses the tick
## solved there, how fast it still slides, how long it has lasted, and its
## stable identity. Every point is blade on blade (STEEL-TOPOLOGY-001).
## Presentation reads these and never computes a contact of its own; nothing
## here is written back.
##
## See also: /docs/concepts/presentation.md

var x: float = 0.0
var y: float = 0.0
## Along fighter 0's / fighter 1's blade, 0 at the crossguard and 1 at the
## point.
var fraction_a: float = 0.0
var fraction_b: float = 0.0
## Unit normal from fighter 1's sword toward fighter 0's.
var normal_x: float = 0.0
var normal_y: float = 1.0
## Normal and tangent impulse solved at this point this tick (N·s).
var normal_impulse: float = 0.0
var tangent_impulse: float = 0.0
## How fast the point still slides after the hold (m/s); 0 on a first impact.
var slip: float = 0.0
## Ticks the contact has lasted before this one.
var age: int = 0
## Stable identity while the contact lasts (CONTACT-IDENTITY-001).
var contact_id: int = 0
