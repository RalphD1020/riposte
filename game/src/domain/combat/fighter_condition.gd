class_name FighterCondition
extends RefCounted

## Coarse health band for presentation and CPU. The simulation never reads
## this — it is a downstream projection of continuous health, just as the HUD
## shows a coloured badge rather than a raw number.
##
## Monotone: every threshold is strictly above the one below it, so condition
## can only improve with healing and only degrade with damage.
##
## See also: /docs/concepts/combat.md

enum Id { HEALTHY, HURT, WOUNDED, CRITICAL }

const HEALTHY_THRESHOLD := 0.75
const HURT_THRESHOLD := 0.50
const WOUNDED_THRESHOLD := 0.25


static func classify(health: float, max_health: float) -> Id:
	if max_health <= 0.0:
		return Id.CRITICAL
	var ratio := health / max_health
	if ratio > HEALTHY_THRESHOLD:
		return Id.HEALTHY
	if ratio > HURT_THRESHOLD:
		return Id.HURT
	if ratio > WOUNDED_THRESHOLD:
		return Id.WOUNDED
	return Id.CRITICAL


static func label(condition: Id) -> String:
	match condition:
		Id.HEALTHY:
			return "HEALTHY"
		Id.HURT:
			return "HURT"
		Id.WOUNDED:
			return "WOUNDED"
		Id.CRITICAL:
			return "CRITICAL"
	return "UNKNOWN"
