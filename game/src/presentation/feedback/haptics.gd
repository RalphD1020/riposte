class_name Haptics
extends RefCounted

## Optional touch-device pulses (UX §40). Never the only channel for any
## information; off when the setting is off. A no-op where unsupported.
##
## See also: /docs/concepts/ux.md

const ATTACK := &"attack"
const BLADE := &"blade"
const BODY := &"body"
const CRITICAL := &"critical"

const _PULSES := {
	ATTACK: [12, 0.25],
	BLADE: [25, 0.5],
	BODY: [40, 0.7],
	CRITICAL: [70, 1.0],
}

var enabled: bool = false
var last_kind: StringName = &""


func pulse(kind: StringName) -> void:
	if not enabled or not _PULSES.has(kind):
		return
	var pattern: Array = _PULSES[kind]
	Input.vibrate_handheld(int(pattern[0]), float(pattern[1]))
	last_kind = kind
