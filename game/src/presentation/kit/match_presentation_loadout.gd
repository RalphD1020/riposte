class_name MatchPresentationLoadout
extends RefCounted

## The match-wide presentation layer: arena kit, announcer, HUD ornament
## theme, and VFX palette. Resolved once at mount; nothing here is gameplay.
##
## See also: /docs/concepts/presentation.md

var arena: PresentationKit
var announcer: AnnouncerKit
var ui_theme: UiThemeKit
var vfx_style: VfxStyleKit


static func of(arena_kit: PresentationKit, caster: AnnouncerKit, theme: UiThemeKit, style: VfxStyleKit) -> MatchPresentationLoadout:
	var loadout := MatchPresentationLoadout.new()
	loadout.arena = arena_kit
	loadout.announcer = caster if caster != null else AnnouncerKit.new()
	loadout.ui_theme = theme if theme != null else UiThemeKit.new()
	loadout.vfx_style = style if style != null else VfxStyleKit.new()
	return loadout
