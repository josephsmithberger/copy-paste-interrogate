extends ChatJsonView

const NPC_BUBBLE_SCENE := "res://scenes/npc_message_bubble.tscn"
const PLAYER_BUBBLE_SCENE := "res://scenes/user_message_bubble.tscn"
const TYPING_INDICATOR_SCENE := "res://assets/ui/typing_message/typing_message.tscn"
const DEFAULT_PROFILE_ICON := "res://assets/profile_icons/placeholder.png"
const BUBBLE_WIDTH_RATIO := 0.75
const BUBBLE_WIDTH_DEFAULT := 480.0
const BUBBLE_WIDTH_MIN := 96.0
const BUBBLE_WIDTH_MAX := 380.0

@export var scroll_ease_duration: float = 0.5

var current_contact_path: String = ""

var _npc_bubble: PackedScene
var _player_bubble: PackedScene
var _typing_indicator: PackedScene
var _loaded_once: bool = false
var _bottom_sep: HSeparator
var _scroll_tween: Tween
var _notif_widget: Control
var _error_popup: Popup
var _tutorial_shown: bool = false
var _typing_row: HBoxContainer = null
var _current_card: Node

@onready var _profile_icon: TextureRect = $VBoxContainer/Profile_icon
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _messages: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var _input: LineEdit = $VBoxContainer/Message
@onready var send_audio: AudioStreamPlayer = $send_audio
@onready var recieve_audio: AudioStreamPlayer = $recieve_audio

func _ready() -> void:
	_debug_log("chat_handler initializing...")
	
	_npc_bubble = load(NPC_BUBBLE_SCENE)
	_player_bubble = load(PLAYER_BUBBLE_SCENE)
	_typing_indicator = load(TYPING_INDICATOR_SCENE)

	_debug_log("Bubbles loaded: NPC=%s Player=%s" % [_npc_bubble != null, _player_bubble != null])
	
	_setup_contacts()
	_setup_notifications()
	_setup_engine()
	_input.editable = false
	_input.placeholder_text = ""

func _debug_log(msg: String) -> void:
	# For web debugging - set placeholder text temporarily
	if _input:
		_input.placeholder_text = msg

func _setup_notifications() -> void:
	var root := get_tree().current_scene
	if not root: return
	
	_notif_widget = root.get_node_or_null("notification")
	if _notif_widget and _notif_widget.has_signal("notification_clicked"):
		_notif_widget.notification_clicked.connect(_on_notification_clicked)
	
	_error_popup = root.get_node_or_null("error_notification")
	if _error_popup:
		var btn := _error_popup.get_node_or_null("panel/VBoxContainer/Button") as Button
		if btn: btn.pressed.connect(_hide_error_popup)

func _setup_engine() -> void:
	var engine := get_node_or_null("/root/DialogueEngine")
	if not engine: return
	engine.contact_incoming.connect(_on_contact_incoming)
	engine.unread_count_changed.connect(_on_unread_count_changed)

func _setup_contacts() -> void:
	var list := _get_contact_list()
	if not list: return
	for child in list.get_children():
		_connect_card(child)
	list.child_entered_tree.connect(_connect_card)

func _connect_card(node: Node) -> void:
	if node.has_signal("contact_selected") and not node.is_connected("contact_selected", _on_contact_selected):
		node.contact_selected.connect(_on_contact_selected.bind(node))

func _get_contact_list() -> Node:
	return get_node_or_null("../PanelContainer/ScrollContainer/Chatlist")

func _on_contact_selected(chat_path: String, card: Node) -> void:
	if chat_path == chat_json_path and _loaded_once and card == _current_card:
		return
	
	reload_with_path(chat_path)
	current_contact_path = chat_path
	_current_card = card
	
	if card.has_method("clear_notifications"):
		card.clear_notifications()
	elif card.has_method("clear_notifcations"):
		card.clear_notifcations()
	
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine: engine.clear_unread(chat_path)
	_dismiss_notification(chat_path)
	
	for c in get_tree().get_nodes_in_group("contact_cards"):
		if c.has_method("set_selected"):
			c.set_selected(c == card)

func _apply_to_ui() -> void:

	var engine := get_node_or_null("/root/DialogueEngine")
	if engine:
		var file := FileAccess.open(chat_json_path, FileAccess.READ)
		if file:
			var data: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if typeof(data) == TYPE_DICTIONARY:
				engine.load_conversation(chat_json_path, data, false)
			else:
				push_error("chat_handler: Failed to parse JSON from " + chat_json_path)
		else:
			push_error("chat_handler: Failed to open file " + chat_json_path)
	else:
		push_error("chat_handler: DialogueEngine not found!")
	
	_profile_icon.texture = profile_texture
	
	_rebuild_bubbles()
	_seed_vocab()
	_defer_scroll_instant()
	_loaded_once = true
	_input.editable = true
	_input.placeholder_text = "iMessage"

func _rebuild_bubbles() -> void:
	_debug_log("Rebuilding bubbles...")
	
	for c in _messages.get_children():
		c.queue_free()
	
	_add_spacer("TopSeparator")
	
	var engine := get_node_or_null("/root/DialogueEngine")
	var history: Array = engine.get_history(chat_json_path) if engine else []
	
	if history.is_empty(): 
		history = chat_history
		_debug_log("History: %d messages" % history.size())
	
	for entry in history:
		var is_player: bool = entry.get("author", "contact") == "player"
		var text := str(entry.get("text", ""))
		_add_bubble_to_history(text, is_player)
	
	_bottom_sep = _add_spacer("BottomSeparator")
	_update_bubble_widths()

	_debug_log("Built %d bubbles" % history.size())

func _add_spacer(spacer_name: String) -> HSeparator:
	var sep := HSeparator.new()
	sep.name = spacer_name
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.custom_minimum_size = Vector2(0, 100)
	sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
	_messages.add_child(sep)
	return sep

func _add_bubble_to_history(text: String, is_player: bool) -> void:
	var scene := _player_bubble if is_player else _npc_bubble
	if not scene: return
	
	var bubble := scene.instantiate()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	_messages.add_child(row)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if is_player:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	
	bubble.size_flags_horizontal = 0
	if bubble.has_method("set_max_content_width"):
		bubble.set_max_content_width(_get_bubble_width())
	if bubble.has_method("set_message_text"):
		bubble.set_message_text(text)
	else:
		var label := bubble.get_node_or_null("MarginContainer/message")
		if label is RichTextLabel:
			label.text = text

func _defer_scroll_instant() -> void:
	call_deferred("_scroll_async")

func _scroll_async() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _scroll_smooth(duration: float = 0.5) -> void:
	_do_scroll_smooth(duration)

func _do_scroll_smooth(duration: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var target := int(_scroll.get_v_scroll_bar().max_value)
	if target <= _scroll.scroll_vertical: return
	
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target, duration)


func _on_message_text_submitted(new_text: String) -> void:
	var text := new_text.strip_edges()
	if text.is_empty(): return
	
	if not _loaded_once or current_contact_path.is_empty():
		_show_no_contact_feedback()
		return
	
	var engine := get_node_or_null("/root/DialogueEngine")
	if not engine:
		push_error("chat_handler: DialogueEngine not found")
		return
	
	var res: Dictionary = engine.process_input(chat_json_path, text)
	var status := str(res.get("status", ""))
	
	# Check if contact is locked first - locked contacts accept any input silently
	if status == "locked":
		_append_player_bubble(text)
		_input.clear()
		_scroll_smooth(scroll_ease_duration)
		return
	
	# Only block messages with unknown words (for unlocked contacts)
	if status == "rejected":
		_show_reject_feedback(res.get("unknown_words", []))
		_show_tutorial_popup()
		return
	
	# For all other statuses (success, wrong), send the message
	_append_player_bubble(text)
	_input.clear()
	
	# Get response lines (if any)
	var lines: Array = res.get("npc_messages", [])
	if lines.size() > 0:
		await _append_npc_with_delay(lines)
		_update_contact_preview(chat_json_path, str(lines.back()))
	
	_scroll_smooth(scroll_ease_duration)

func _append_player_bubble(text: String) -> void:
	send_audio.play()
	_append_bubble(text, true)
	_scroll_smooth(scroll_ease_duration)

func _append_npc_bubble(text: String) -> void:
	recieve_audio.play()
	_append_bubble(text, false)

func _append_npc_with_delay(lines: Array) -> void:
	for l in lines:
		var msg := str(l)
		var delay := minf(randf_range(0.2, 0.6) + msg.length() * randf_range(0.015, 0.03), 2.5)
		
		_show_typing()
		await get_tree().create_timer(delay).timeout
		_hide_typing()
		
		_append_npc_bubble(msg)
		_scroll_smooth(scroll_ease_duration)

func _append_bubble(text: String, is_player: bool) -> void:
	var scene := _player_bubble if is_player else _npc_bubble
	if not scene: return
	
	var bubble := scene.instantiate()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	
	if _bottom_sep and _bottom_sep.get_parent() == _messages:
		_messages.add_child(row)
		_messages.move_child(row, _bottom_sep.get_index())
	else:
		_messages.add_child(row)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if is_player:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	
	bubble.size_flags_horizontal = 0
	if bubble.has_method("set_max_content_width"):
		bubble.set_max_content_width(_get_bubble_width())
	if bubble.has_method("set_message_text"):
		bubble.set_message_text(text)
	else:
		var label := bubble.get_node_or_null("MarginContainer/message")
		if label is RichTextLabel:
			label.text = text
	
	if _bottom_sep and _bottom_sep.get_parent() == _messages:
		_messages.move_child(_bottom_sep, _messages.get_child_count() - 1)

func _update_contact_preview(contact_path: String, last_text: String) -> void:
	var list := _get_contact_list()
	if not list: return
	for child in list.get_children():
		if child is ChatJsonView and child.chat_json_path == contact_path:
			if child.has_method("refresh_last_message"):
				child.refresh_last_message(last_text)
			break

func _on_contact_incoming(contact_path: String, lines: PackedStringArray, _source: String) -> void:
	var preview := str(lines[lines.size() - 1]) if lines.size() > 0 else ""
	_update_contact_preview(contact_path, preview)
	
	if contact_path == current_contact_path and _loaded_once:
		for line in lines:
			_append_npc_bubble(str(line))
		_scroll_smooth(scroll_ease_duration)
		
		var engine := get_node_or_null("/root/DialogueEngine")
		if engine: engine.clear_unread(contact_path)
		
		if _current_card:
			if _current_card.has_method("clear_notifications"):
				_current_card.clear_notifications()
			elif _current_card.has_method("clear_notifcations"):
				_current_card.clear_notifcations()
		
		_dismiss_notification(contact_path)
		return
	
	if _notif_widget and _notif_widget.has_method("notification_in"):
		var cname := _get_contact_name(contact_path)
		var msg := preview.substr(0, 61) + "..." if preview.length() > 64 else preview
		var icon := _get_contact_icon(contact_path)
		_notif_widget.call("notification_in", icon, cname, msg, contact_path)
		_dim_icon()

func _on_unread_count_changed(contact_path: String, unread: int) -> void:
	var list := _get_contact_list()
	if not list: return
	for child in list.get_children():
		if child is ChatJsonView and child.chat_json_path == contact_path:
			if unread > 0 and child.has_method("unread_message"):
				child.unread_message()
			elif unread == 0:
				if child.has_method("clear_notifications"):
					child.clear_notifications()
				elif child.has_method("clear_notifcations"):
					child.clear_notifcations()
			break

func _get_contact_name(contact_path: String) -> String:
	var list := _get_contact_list()
	if list:
		for child in list.get_children():
			if child is ChatJsonView and child.chat_json_path == contact_path:
				return child.get_contact_display_name()
	return contact_path

func _get_contact_icon(contact_path: String) -> String:
	var list := _get_contact_list()
	if list:
		for child in list.get_children():
			if child is ChatJsonView and child.chat_json_path == contact_path:
				if child.icon_path != "":
					return child.icon_path
	return DEFAULT_PROFILE_ICON

func _show_tutorial_popup() -> void:
	if _tutorial_shown or not _error_popup: return
	_tutorial_shown = true
	_error_popup.popup_centered_ratio(0.4)

func _hide_error_popup() -> void:
	if _error_popup:
		_error_popup.queue_free()
		_error_popup = null

func _on_notification_clicked(chat_path: String) -> void:
	_dismiss_notification()
	var list := _get_contact_list()
	if not list: return
	for child in list.get_children():
		if child is ChatJsonView and child.chat_json_path == chat_path:
			_on_contact_selected(chat_path, child)
			return

func _dismiss_notification(target_path: String = "") -> void:
	if not _notif_widget: return
	if target_path != "" and _notif_widget.has_method("get_target_chat_path"):
		if str(_notif_widget.call("get_target_chat_path")) != target_path:
			return
	if _notif_widget.has_method("notification_out"):
		_notif_widget.call("notification_out")
		_restore_icon()

func _seed_vocab() -> void:
	var vocab := get_node_or_null("/root/Vocabulary")
	if not vocab: return
	for entry in chat_history:
		if entry.get("author", "contact") == "contact":
			vocab.add_words([str(entry.get("text", ""))])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_bubble_widths()

func _get_bubble_width() -> float:
	var base := _scroll.size.x if _scroll else 0.0
	if base <= 0.0:
		base = _messages.size.x if _messages else BUBBLE_WIDTH_DEFAULT
	var target := base * BUBBLE_WIDTH_RATIO
	return clamp(target, BUBBLE_WIDTH_MIN, BUBBLE_WIDTH_MAX)

func _update_bubble_widths() -> void:
	if not _messages: return
	var width := _get_bubble_width()
	for child in _messages.get_children():
		if child is HBoxContainer:
			for node in child.get_children():
				if node.has_method("set_max_content_width"):
					node.set_max_content_width(width)

func _show_reject_feedback(_unknown: Array) -> void:
	var tween := create_tween()
	var orig := _input.modulate
	_input.modulate = Color(1, 0.7, 0.7)
	tween.tween_property(_input, "modulate", orig, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _show_no_contact_feedback() -> void:
	var orig_placeholder := _input.placeholder_text
	_input.placeholder_text = "Select a contact first"
	var tween := create_tween()
	var orig_pos := _input.position
	tween.tween_property(_input, "position", orig_pos + Vector2(6, 0), 0.05)
	tween.tween_property(_input, "position", orig_pos - Vector2(6, 0), 0.05)
	tween.tween_property(_input, "position", orig_pos, 0.05)
	await tween.finished
	_input.placeholder_text = orig_placeholder

func _show_typing() -> void:
	_hide_typing()
	if not _typing_indicator: return
	
	var indicator := _typing_indicator.instantiate()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	_typing_row = row
	
	if _bottom_sep and _bottom_sep.get_parent() == _messages:
		_messages.add_child(row)
		_messages.move_child(row, _bottom_sep.get_index())
	else:
		_messages.add_child(row)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(indicator)
	row.add_child(spacer)
	indicator.size_flags_horizontal = 0
	
	if _bottom_sep and _bottom_sep.get_parent() == _messages:
		_messages.move_child(_bottom_sep, _messages.get_child_count() - 1)
	
	_scroll_smooth(scroll_ease_duration)

func _hide_typing() -> void:
	if _typing_row and is_instance_valid(_typing_row):
		_typing_row.queue_free()
		_typing_row = null

func _dim_icon() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_profile_icon, "modulate:a", 0.5, 0.3)

func _restore_icon() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_profile_icon, "modulate:a", 1.0, 0.3)
