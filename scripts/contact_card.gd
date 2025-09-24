extends Control

@export_file("*.json") var chat_json_path: String = "res://scripts/chats/template_chat.json"

var contact_name: String = ""
var profile_icon_path: String = ""
var profile_texture: Texture2D
var chat_history: Array[Dictionary] = []

signal chat_loaded

func _ready() -> void:
	_load_chat_from_json()
	_apply_to_ui()

func _load_chat_from_json() -> void:
	if chat_json_path.is_empty():
		push_warning("contact_card: No chat JSON path set.")
		return

	var file := FileAccess.open(chat_json_path, FileAccess.READ)
	if file == null:
		push_error("contact_card: Failed to open chat JSON: %s" % chat_json_path)
		return

	var text := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("contact_card: Root of JSON must be an object/dictionary.")
		return

	# Required fields with basic validation
	contact_name = str(data.get("name", "")).strip_edges()
	profile_icon_path = str(data.get("profile_icon_path", "")).strip_edges()

	var history = data.get("chat_history", [])
	if typeof(history) != TYPE_ARRAY:
		push_error("contact_card: 'chat_history' must be an array.")
		history = []

	# Normalize chat history entries to a consistent shape: { author: String, text: String }
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
			# Allow simple string entries; default author is 'contact'
			chat_history.append({
				"author": "contact",
				"text": str(entry),
			})

	# Load texture if provided
	profile_texture = null
	if profile_icon_path != "":
		var res := load(profile_icon_path)
		if res is Texture2D:
			profile_texture = res
		else:
			push_warning("contact_card: 'profile_icon_path' did not resolve to a Texture2D: %s" % profile_icon_path)

	# Apply parsed data to UI if nodes exist
	_apply_to_ui()
	emit_signal("chat_loaded")

func _apply_to_ui() -> void:
	var name_label := get_node_or_null("VBoxContainer/Name")
	if name_label and name_label is Label:
		name_label.text = contact_name if contact_name != "" else "Unnamed"

	var last_label := get_node_or_null("VBoxContainer/Last_message")
	if last_label and last_label is Label:
		var preview := ""
		if chat_history.size() > 0:
			var last := chat_history[chat_history.size()-1]
			if typeof(last) == TYPE_DICTIONARY:
				preview = str(last.get("text", ""))
		last_label.text = preview

	var icon_rect := get_node_or_null("Icon")
	if icon_rect and icon_rect is TextureRect:
		if profile_texture:
			icon_rect.texture = profile_texture

func get_contact_display_name() -> String:
	return contact_name

func get_profile_texture() -> Texture2D:
	return profile_texture

func get_chat_history() -> Array[Dictionary]:
	return chat_history
