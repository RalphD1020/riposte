class_name GripHandsModifier3D
extends SkeletonModifier3D

## The last pass of the fighter's stack (PRES-GRIP-001): after the arm IK has
## brought each wrist to the wrist its grip frame implies, turn each hand to
## that frame. The IK never sees the hand's roll; this never moves a joint
## position, so the palm lands on the grip and the hand is turned around the
## handle the way the grip says. Bone indices cached; nothing allocated per
## frame.
##
## See also: /docs/concepts/presentation.md

## The hand bones, dominant then off hand.
var hand_bones: PackedStringArray = PackedStringArray()
## Each hand's grip frame node (on the displayed sword): its global basis is
## the hand's global orientation.
var frames: Array[Node3D] = []

var _bones := PackedInt32Array()


func _validate_bone_names() -> void:
	_bones = PackedInt32Array()


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or frames.size() != hand_bones.size():
		return
	if _bones.size() != hand_bones.size():
		_bones.resize(hand_bones.size())
		for index in hand_bones.size():
			_bones[index] = skeleton.find_bone(hand_bones[index])
	var into_skeleton := skeleton.global_transform.basis.inverse()
	for index in _bones.size():
		var bone := _bones[index]
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var wanted := (into_skeleton * frames[index].global_transform.basis).orthonormalized()
		skeleton.set_bone_pose_rotation(bone, (parent_basis.orthonormalized().inverse() * wanted).get_rotation_quaternion())
