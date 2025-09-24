extends Control

class_name ChatJsonView

@export_file("*.json") var chat_json_path: String = "res://scripts/chats/template_chat.json"

var contact_name: String = ""
var profile_icon_path: String = ""
var profile_texture: Texture2D
var chat_history: Array[Dictionary] = []

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
		var err := "Failed to open chat JSON: %s" % chat_json_path
		push_error("ChatJsonView: %s" % err)
		emit_signal("chat_failed", err)
		return

	var text := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		var err2 := "Root of JSON must be an object/dictionary."
		push_error("ChatJsonView: %s" % err2)
		emit_signal("chat_failed", err2)
		return

	contact_name = str(data.get("name", "")).strip_edges()
	profile_icon_path = str(data.get("profile_icon_path", "")).strip_edges()

	var history = data.get("chat_history", [])
	if typeof(history) != TYPE_ARRAY:
		push_error("ChatJsonView: 'chat_history' must be an array.")
		history = []

	chat_history.clear()
	for entry in history:
		if typeof(entry) == TYPE_DICTIONARY:
			var author := str(entry.get("author", "contact"))
			var text_msg := str(entry.get("text", ""))
			chat_history.append({
				"author": author,
				"text": text_msg,
			})
		elif typeof(entry) == TYPE_STRING:
			chat_history.append({
				"author": "contact",
				"text": str(entry),
			})

	profile_texture = null
	if profile_icon_path != "":
		var res := load(profile_icon_path)
		if res is Texture2D:
			profile_texture = res
		else:
			push_warning("ChatJsonView: 'profile_icon_path' did not resolve to a Texture2D: %s" % profile_icon_path)

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
