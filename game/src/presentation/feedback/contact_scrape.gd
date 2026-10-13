class_name ContactScrape
extends RefCounted

## The scrape of swords held against each other, as a projection of the
## friction the solver already applied (7C, COMBAT-READABILITY-001). Pure.
##
## What a held contact sounds like is how much work friction does there each
## tick: the tangent impulse times how fast the point still slides,
## `|J_t|·v_t` (J). A blade pressed still does no friction work, so it makes no
## scrape at all; a light slide is a faint one; a hard drag along the steel is
## loud. Nothing about a timer, a contact's age past its first tick, or how
## charged a swing was enters — loudness follows the physics continuously, so
## a small slide never sounds like a big one.
##
## A first impact is not a scrape (its sound is the clash's, read from its own
## impulse); a point solved for the first time this tick (`age` 0) is left
## out. The take is keyed by the scraping point's `contact_id`, so one contact
## keeps one take for as long as it lasts and never re-triggers; a new contact
## starts a new take.
##
## See also: /docs/concepts/presentation.md

## Friction work per tick (J) that reads as a full-strength scrape.
const POWER_FULL := 0.5
## Friction work (J) per grind spark.
const SPARK_ENERGY := 0.08
## Most grind sparks one tick may throw.
const SPARKS_PER_TICK := 4


## The work friction did at a held point this tick (J); 0 on a first impact.
static func power(row: PresentationContact) -> float:
	if row.age <= 0:
		return 0.0
	return absf(row.tangent_impulse) * maxf(row.slip, 0.0)


## The held point doing the most friction work this tick, or −1 when no point
## is held. A held point doing none (pressed still) is still the scraping
## contact — silent, keeping its take.
static func dominant(contacts: Array[PresentationContact]) -> int:
	var best := -1
	var best_power := -1.0
	for i in contacts.size():
		var row := contacts[i]
		if row.age <= 0:
			continue
		var work := power(row)
		if work > best_power:
			best = i
			best_power = work
	return best


## Total friction work over every held point this tick (J).
static func total_power(contacts: Array[PresentationContact]) -> float:
	var total := 0.0
	for row in contacts:
		total += power(row)
	return total


## Loudness in [0, 1] for `work` J per tick: amplitude goes as the square root
## of power, so twice the friction work is not twice as loud.
static func level(work: float) -> float:
	return clampf(sqrt(maxf(work, 0.0) / POWER_FULL), 0.0, 1.0)
