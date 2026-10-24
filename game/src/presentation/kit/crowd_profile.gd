class_name CrowdProfile
extends Resource

## The audience a stage seats: the figure meshes and the palettes each seat is
## tinted from. A stage profile without one seats nobody. Where the seats are
## is the bowl's layout (`ArenaSection`), not this. Presentation only.
##
## See also: /docs/concepts/presentation.md

## Exported figure scenes. Each joined layer (`skin`, `fabric`, `leather`)
## is a mesh named for its material, already in the figure's frame.
@export_file("*.glb") var seated_scene: String = ""
@export_file("*.glb") var cheer_scene: String = ""
## The eyes and brow, one mesh named `face`.
@export_file("*.glb") var face_scene: String = ""
## One scene per hairstyle, each with its own `hair` mesh. No style wears
## another's.
@export var hair_scenes: PackedStringArray = PackedStringArray()
@export var skin: PackedColorArray = PackedColorArray()
@export var cloth: PackedColorArray = PackedColorArray()
@export var leather: PackedColorArray = PackedColorArray()
@export var hair: PackedColorArray = PackedColorArray()
## The eyes and brow are the dark ink, not a dyed hair.
@export var face_ink: Color = Color(0.03, 0.03, 0.035)


func part(cheer: bool, slot: String) -> Mesh:
	return CrowdMeshes.named(cheer_scene if cheer else seated_scene, slot)


func face() -> Mesh:
	return CrowdMeshes.named(face_scene, "face")


func hair_style(index: int) -> Mesh:
	return CrowdMeshes.named(hair_scenes[wrapi(index, 0, hair_scenes.size())], "hair")


func pose_scene(cheer: bool) -> PackedScene:
	var path := cheer_scene if cheer else seated_scene
	return load(path) as PackedScene if ResourceLoader.exists(path) else null


## Every scene the crowd draws must exist, and every hairstyle must be its own
## file, so a missing look fails here instead of drawing another one.
func problem() -> String:
	for path: String in [seated_scene, cheer_scene, face_scene]:
		if not ResourceLoader.exists(path):
			return "a crowd scene is missing: %s" % path
	if hair_scenes.is_empty():
		return "a crowd needs at least one hairstyle"
	var seen := {}
	for path: String in hair_scenes:
		if not ResourceLoader.exists(path):
			return "a hairstyle is missing: %s" % path
		if seen.has(path):
			return "a hairstyle is listed twice: %s" % path
		seen[path] = true
	if skin.is_empty() or cloth.is_empty() or leather.is_empty() or hair.is_empty():
		return "a crowd needs a skin, cloth, leather and hair palette"
	return ""
