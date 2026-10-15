extends SceneTree

## Dev capture for the victory showcase: the Wolf's set victory stepped through
## its beats on the real `VictoryDirector`, saved to
## .reports/victory_<beat>.png — the loaded right guard, both quick cuts, the
## full shoulder charge, the heavy cut's impact, the push, and the settled hero
## frame. Checks the authored blade path and the camera, not timing.
##
##   godot --path game --rendering-method gl_compatibility --resolution 1280x720 -s res://tools/capture_victory.gd

const STEP := 1.0 / 60.0
## The three victory beats and the push (FighterVictoryProfile): the first
## quick cut through centre, the return cut, the load gathering, the held
## load at lock, mid-push, and the settled hero frame.
const BEATS := {
	"start": 0.02,
	"cut1": 0.22,
	"cut2": 0.48,
	"gather": 0.95,
	"hold": 1.25,
	"push": 1.6,
	"hero": 2.4,
}


func _init() -> void:
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var director := VictoryDirector.create(kits.combatant(0), DuelSide.Id.LIGHT_SOUTH, rules.combatant(0).fighter.push_radius, rules.combatant(0).weapon.blade_base_radius, rules.combatant(0).weapon.tip_radius)
	root.add_child(director)
	var card := VictoryCard.create()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(card)
	director.card_requested.connect(card.show_card)
	director.streak_requested.connect(card.set_streak)
	director.audio().caption_requested.connect(card.show_caption)
	await process_frame
	var clip := director.actor().current_clip()
	print("RIPOSTE_VICTORY clip=%s rides_mount=%s" % [clip, director.actor().rides_mount()])
	for beat: String in BEATS:
		var at := float(BEATS[beat])
		while director.elapsed() < at:
			director.advance(STEP)
			card.advance(STEP)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.reports/victory_%s.png" % beat)
		print("RIPOSTE_VICTORY %s t=%.2f sword=%s stage=%d" % [beat, director.elapsed(), director.actor().display_sword_angle(), director.stage()])
	director.queue_free()
	await process_frame
	quit()
