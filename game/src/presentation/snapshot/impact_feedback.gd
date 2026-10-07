class_name ImpactFeedback
extends RefCounted

## Typed read-only projection of contact event payloads into presentation-ready
## quantities. Presentation reads these instead of reaching into raw event
## dictionaries; the simulation never reads them back.
##
## See also: /docs/concepts/presentation.md

var impulse01: float = 0.0           ## Normalized impulse [0, 1]
var severity01: float = 0.0          ## Normalized kinetic severity [0, 1]
var blade_fraction: float = 0.0      ## 0 = hilt, 1 = tip
var edge_alignment: float = 0.0      ## 0 = flat, 1 = perfect edge
var attacker: int = DuelEvent.NONE
var target: int = DuelEvent.NONE
var contact_type: StringName = &""   ## DuelEventTypes: BODY_HIT, BLADE_CONTACT, BODY_PUSH
var point_x: float = 0.0
var point_y: float = 0.0
var normal_x: float = 0.0
var normal_y: float = 0.0


static func from_event(event: DuelEvent, tuning: CombatTuning) -> ImpactFeedback:
	var fb := ImpactFeedback.new()
	fb.contact_type = event.type
	fb.attacker = event.actor
	fb.target = event.target
	fb.impulse01 = SimMath.clamp01(event.number(DuelEventKeys.IMPULSE) / tuning.reference_impulse) if tuning.reference_impulse > 0.0 else 0.0
	fb.severity01 = SimMath.clamp01(event.number(DuelEventKeys.SEVERITY) / tuning.reference_severity) if tuning.reference_severity > 0.0 else 0.0
	fb.blade_fraction = event.number(DuelEventKeys.BLADE_FRACTION)
	fb.edge_alignment = event.number(DuelEventKeys.ALIGNMENT)
	fb.point_x = event.number(DuelEventKeys.X)
	fb.point_y = event.number(DuelEventKeys.Y)
	fb.normal_x = event.number(DuelEventKeys.NORMAL_X)
	fb.normal_y = event.number(DuelEventKeys.NORMAL_Y)
	return fb


static func is_contact_event(event: DuelEvent) -> bool:
	return event.type == DuelEventTypes.BODY_HIT or event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BODY_PUSH
