extends RefCounted
## Test process only. Production code never creates/rebinds InputMap actions.

static func configure() -> void:
	var keys := {"jump": [KEY_F, KEY_SPACE], "attack": [KEY_J, KEY_K], "restart": [KEY_R]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
