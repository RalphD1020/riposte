class_name VfxStyleKit
extends Resource

## The palette contact effects are drawn in. Changing a style recolours
## sparks, impact, dust, and flashes; it never changes how many there are or
## what they mean (PRES-KIT-001: cosmetic overrides only). Defaults are the
## theme's world tokens.
##
## See also: /docs/concepts/presentation.md

@export var style_id: StringName = &""
@export var spark: Color = RiposteTheme.SPARK
@export var spark_hot: Color = RiposteTheme.SPARK_HOT
@export var body_impact: Color = RiposteTheme.BODY_IMPACT
@export var dust: Color = RiposteTheme.WORLD_FLOOR_EDGE
@export var lethal_accent: Color = RiposteTheme.LETHAL_ACCENT
@export var grind: Color = RiposteTheme.GRIND
