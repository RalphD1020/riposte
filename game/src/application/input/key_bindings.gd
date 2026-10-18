class_name KeyBindings
extends RefCounted

## The player's keyboard and mouse bindings for the gameplay actions (UX-001,
## full remapping). Input only: every binding drives the same `InputMap`
## action, so the simulation receives the same commands whatever is bound.
##
## Each action has `SLOTS` bindings; a binding is a code — a physical keycode
## (> 0, so layouts stay put), a mouse button as its negated index (< 0), or 0
## for an empty slot. Defaults are the actions authored in `project.godot`,
## read once, never repeated here. Binding a code that another action already
## uses swaps the two, so two actions never share an input — refused only when
## the swap would leave that other action with nothing at all, which would make
## it unreachable. A stored set is untrusted: any invalid, duplicated or empty
## action falls back to the defaults as a whole, because a partly merged set
## could double-bind.
##
## See also: /docs/concepts/controls.md

const SLOTS := 2
## The debug toggle is development-only and keeps its key.
const ACTIONS: Array[StringName] = [
	InputActions.MOVE_UP,
	InputActions.MOVE_DOWN,
	InputActions.MOVE_LEFT,
	InputActions.MOVE_RIGHT,
	InputActions.ATTACK,
	InputActions.DASH_MODIFIER,
	InputActions.PAUSE,
]
## A key is a printable codepoint, or one of the engine's named keys, which
## sit just above bit 22 (`KEY_ESCAPE` is its first). The engine names any
## number it is given, so its name alone does not prove a key exists.
const LAST_CODEPOINT := 0x10FFFF
const SPECIAL_KEYS := 1 << 22
const SPECIAL_SPAN := 0x200
## Mouse buttons a binding may use; the wheel is not a button to hold.
const MOUSE_BUTTONS: Array[int] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]

var _codes: Dictionary[StringName, PackedInt64Array] = {}


func _init() -> void:
	reset()


## Back to the authored defaults.
func reset() -> void:
	for action in ACTIONS:
		_codes[action] = defaults_for(action)


func codes(action: StringName) -> PackedInt64Array:
	return _codes[action].duplicate()


func code(action: StringName, slot: int) -> int:
	return _codes[action][slot]


func is_default() -> bool:
	for action in ACTIONS:
		if _codes[action] != defaults_for(action):
			return false
	return true


## Bind `binding` to `action`'s `slot`. Returns false and changes nothing when
## the request is invalid or the swap would leave another action unbound.
func bind(action: StringName, slot: int, binding: int) -> bool:
	if not ACTIONS.has(action) or slot < 0 or slot >= SLOTS or not is_valid_code(binding):
		return false
	var current := code(action, slot)
	if current == binding:
		return true
	var holder := owner_of(binding)
	if holder.x >= 0:
		var other := ACTIONS[holder.x]
		if other != action and current == 0 and _bound_count(other) == 1:
			return false
		_assign(other, holder.y, current)
	_assign(action, slot, binding)
	return true


## The (action index, slot) holding `binding`, or (-1, -1).
func owner_of(binding: int) -> Vector2i:
	for index in ACTIONS.size():
		var held := _codes[ACTIONS[index]]
		for slot in SLOTS:
			if held[slot] == binding:
				return Vector2i(index, slot)
	return Vector2i(-1, -1)


## Write these bindings into the `InputMap`. Key and mouse events are replaced.
## Pad events stay: they are not rebinding slots.
func apply() -> void:
	for action in ACTIONS:
		var pads: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				pads.append(event)
		InputMap.action_erase_events(action)
		for binding in _codes[action]:
			if binding != 0:
				InputMap.action_add_event(action, event_for(binding))
		for event in pads:
			InputMap.action_add_event(action, event)


func save_to(config: ConfigFile, section: String) -> void:
	for action in ACTIONS:
		config.set_value(section, String(action), _codes[action])


## Load from `config`, or keep the defaults if anything stored is unusable.
func load_from(config: ConfigFile, section: String) -> void:
	reset()
	if not config.has_section(section):
		return
	var loaded: Dictionary[StringName, PackedInt64Array] = {}
	var seen: Dictionary[int, bool] = {}
	for action in ACTIONS:
		var stored: Variant = config.get_value(section, String(action), null)
		var held := _sanitize(stored)
		if held.is_empty():
			return
		for binding in held:
			if binding != 0:
				if seen.has(binding):
					return
				seen[binding] = true
		loaded[action] = held
	_codes = loaded


static func is_valid_code(binding: int) -> bool:
	if binding > 0:
		var printable := binding >= KEY_SPACE and binding <= LAST_CODEPOINT
		var special := binding > SPECIAL_KEYS and binding < SPECIAL_KEYS + SPECIAL_SPAN
		return (printable or special) and OS.get_keycode_string(binding as Key) != ""
	if binding < 0:
		return MOUSE_BUTTONS.has(-binding)
	return false


## The binding an input event would make, or 0 when it cannot be bound.
static func code_of(event: InputEvent) -> int:
	if event is InputEventKey:
		var key := event as InputEventKey
		var physical := int(key.physical_keycode) if key.physical_keycode != KEY_NONE else int(key.keycode)
		return physical if is_valid_code(physical) else 0
	if event is InputEventMouseButton:
		var index := int((event as InputEventMouseButton).button_index)
		return -index if MOUSE_BUTTONS.has(index) else 0
	return 0


static func event_for(binding: int) -> InputEvent:
	if binding < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = (-binding) as MouseButton
		return mouse
	var key := InputEventKey.new()
	key.physical_keycode = binding as Key
	return key


## The authored defaults for `action`, from `project.godot`.
static func defaults_for(action: StringName) -> PackedInt64Array:
	var held := PackedInt64Array()
	held.resize(SLOTS)
	held.fill(0)
	var authored: Variant = ProjectSettings.get_setting("input/%s" % action, null)
	if typeof(authored) != TYPE_DICTIONARY:
		return held
	var slot := 0
	for event: Variant in (authored as Dictionary).get("events", []):
		var binding := code_of(event as InputEvent) if event is InputEvent else 0
		if binding != 0 and slot < SLOTS:
			held[slot] = binding
			slot += 1
	return held


func _assign(action: StringName, slot: int, binding: int) -> void:
	var held := _codes[action]
	held[slot] = binding
	_codes[action] = held


func _bound_count(action: StringName) -> int:
	var count := 0
	for binding in _codes[action]:
		if binding != 0:
			count += 1
	return count


## A stored slot list: exactly `SLOTS` valid-or-empty codes with at least one
## binding, else empty (unusable).
static func _sanitize(stored: Variant) -> PackedInt64Array:
	var none := PackedInt64Array()
	if typeof(stored) != TYPE_PACKED_INT64_ARRAY and typeof(stored) != TYPE_PACKED_INT32_ARRAY and typeof(stored) != TYPE_ARRAY:
		return none
	var values: Array = Array(stored)
	if values.size() != SLOTS:
		return none
	var held := PackedInt64Array()
	var bound := 0
	for value: Variant in values:
		if typeof(value) != TYPE_INT:
			return none
		var binding := int(value)
		if binding != 0 and not is_valid_code(binding):
			return none
		if binding != 0:
			bound += 1
		held.append(binding)
	return held if bound > 0 else none
