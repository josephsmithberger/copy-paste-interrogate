extends Control

class_name ChatJsonView

@export_file("*.json") var chat_json_path: String = "" # Intentionally empty: set explicitly before ready

# Public fields consumed by subclasses / handlers
var contact_name: String = ""
var icon_path: String = ""
var profile_texture: Texture2D
var chat_history: Array[Dictionary] = [] # Only pre-step NPC lines

signal chat_loaded
signal chat_failed(error: String)

func _ready() -> void:
	load_chat_from_json()

func load_chat_from_json() -> void:
	if chat_json_path.is_empty():
		var msg := "No chat JSON path set."
		push_warning("ChatJsonView: %s" % msg)
		emit_signal("chat_failed", msg)
		return

	var file := FileAccess.open(chat_json_path, FileAccess.READ)
	if file == null:
		var err := "Failed to open chat JSON: %s (Error: %d)" % [chat_json_path, FileAccess.get_open_error()]
		push_error("ChatJsonView: %s" % err)
		emit_signal("chat_failed", err)
		return
	var text := file.get_as_text()
	file.close()
	
	var root: Variant = JSON.parse_string(text)
	if typeof(root) != TYPE_DICTIONARY:
		var err2 := "Root of JSON must be an object/dictionary."
		push_error("ChatJsonView: %s" % err2)
		emit_signal("chat_failed", err2)
		return

	# REQUIRED FIELDS: name, icon, chat
	contact_name = str(root.get("name", "")).strip_edges()
	icon_path = str(root.get("icon", "")).strip_edges()
	var chat_array: Variant = root.get("chat", [])
	if typeof(chat_array) != TYPE_ARRAY:
		push_error("ChatJsonView: 'chat' must be an array in simplified format.")
		chat_array = []

	chat_history.clear()
	var encountered_step := false
	for entry in chat_array:
		if typeof(entry) == TYPE_STRING and not encountered_step:
			var line := str(entry).strip_edges()
			if line == "":
				continue
			# Pre-seeded NPC line
			chat_history.append({"author": "contact", "text": line})
		elif typeof(entry) == TYPE_DICTIONARY:
			# First dictionary signals start of steps region
			encountered_step = true
		else:
			# Ignore any strings after steps (authors must move them into step.success)
			if typeof(entry) == TYPE_STRING:
				push_warning("ChatJsonView: Ignoring NPC line after first step (move into prior step.success)")
	
	# Load texture
	profile_texture = null
	if icon_path != "":
		var res := load(icon_path)
		if res is Texture2D:
			profile_texture = res
		else:
			push_warning("ChatJsonView: 'icon' did not resolve to a Texture2D: %s" % icon_path)

	_apply_to_ui()
	emit_signal("chat_loaded")

func get_contact_display_name() -> String:
	return contact_name

func get_profile_texture() -> Texture2D:
	return profile_texture

func get_chat_history() -> Array[Dictionary]:
	return chat_history

func get_last_message_text() -> String:
	if chat_history.is_empty():
		return ""
	return str(chat_history.back().get("text", ""))

func reload_with_path(new_path: String) -> void:
	chat_json_path = new_path
	load_chat_from_json()

# To be overridden by subclasses to bind parsed data to specific UI nodes.
func _apply_to_ui() -> void:
	pass
