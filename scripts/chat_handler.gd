extends ChatJsonView

# ChatHandler
# Listens for contact_card "contact_selected(chat_path)" signals, loads the
# referenced chat JSON (via inherited reload_with_path) and populates:
#  - Profile icon: $VBoxContainer/Profile_icon
#  - Message bubbles inside $ScrollContainer/VBoxContainer
#    * contact / other author -> res://scenes/npc_message_bubble.tscn
#    * player author          -> res://scenes/user_message_bubble.tscn
#
# This script purposefully overrides _ready WITHOUT calling the base implementation
# so that the default template JSON is NOT auto-loaded. Data only appears after
# the user selects a contact.

const NPC_BUBBLE_SCENE_PATH := "res://scenes/npc_message_bubble.tscn"
const PLAYER_BUBBLE_SCENE_PATH := "res://scenes/user_message_bubble.tscn"
const DEFAULT_PROFILE_ICON_PATH := "res://assets/profile_icons/placeholder.png"
const BUBBLE_WIDTH_RATIO := 0.75
const BUBBLE_WIDTH_FALLBACK := 480.0
const BUBBLE_WIDTH_MIN := 96.0
const BUBBLE_WIDTH_MAX := 380.0


var _npc_bubble_scene: PackedScene
var _player_bubble_scene: PackedScene
var _loaded_once: bool = false
var _bottom_sep: HSeparator
var _scroll_tween: Tween
var _notification_widget: Control
var _error_popup: Popup
var _error_popup_button: Button
var _tutorial_popup_shown: bool = false

# Public knobs
@export var scroll_ease_duration: float = 0.5

# Current contact context
var current_contact_path: String = ""
var _current_contact_card: Node

@onready var _profile_icon: TextureRect = $VBoxContainer/Profile_icon
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _messages_root: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var _message_input: LineEdit = $VBoxContainer/Message
@onready var send_audio:AudioStreamPlayer = $send_audio
@onready var recieve_audio:AudioStreamPlayer = $recieve_audio

func _ready() -> void:
	# Do not call super._ready(); we only load when a contact is clicked.
	_npc_bubble_scene = load(NPC_BUBBLE_SCENE_PATH)
	_player_bubble_scene = load(PLAYER_BUBBLE_SCENE_PATH)
	_connect_existing_contact_cards()
	_watch_for_new_contact_cards()
	_setup_notification_widget()
	_setup_error_popup()
	_connect_to_engine()
	# Disable input until a contact is selected
	if _message_input:
		_message_input.editable = false
		_message_input.placeholder_text = ""
	# No implicit auto-selection; user must click a contact

func _setup_notification_widget() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	_notification_widget = scene_root.get_node_or_null("notification") as Control
	if _notification_widget == null:
		return
	if _notification_widget.has_signal("notification_clicked") and not _notification_widget.is_connected("notification_clicked", Callable(self, "_on_notification_clicked")):
		_notification_widget.connect("notification_clicked", Callable(self, "_on_notification_clicked"))

func _setup_error_popup() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	_error_popup = scene_root.get_node_or_null("error_notification") as Popup
	if _error_popup == null:
		return
	_error_popup_button = _error_popup.get_node_or_null("panel/VBoxContainer/Button") as Button
	if _error_popup_button:
		if not _error_popup_button.is_connected("pressed", Callable(self, "_on_error_popup_button_pressed")):
			_error_popup_button.pressed.connect(Callable(self, "_on_error_popup_button_pressed"))

func _connect_to_engine() -> void:
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine == null:
		return
	if not engine.is_connected("contact_incoming", Callable(self, "_on_contact_incoming")):
		engine.contact_incoming.connect(Callable(self, "_on_contact_incoming"))
	if not engine.is_connected("unread_count_changed", Callable(self, "_on_unread_count_changed")):
		engine.unread_count_changed.connect(Callable(self, "_on_unread_count_changed"))

func _connect_existing_contact_cards() -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	for child in contact_list.get_children():
		_try_connect_card(child)

func _watch_for_new_contact_cards() -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	if not contact_list.is_connected("child_entered_tree", Callable(self, "_on_contact_list_child_entered")):
		contact_list.connect("child_entered_tree", Callable(self, "_on_contact_list_child_entered"))
	else:
		pass

func _on_contact_list_child_entered(child: Node) -> void:
	_try_connect_card(child)
	# No auto-selection logic

func _try_connect_card(node: Node) -> void:
	if node == null:
		return
	if not node.has_signal("contact_selected"):
		# Likely a separator or non-card.
		return
	if node.is_connected("contact_selected", Callable(self, "_on_contact_selected")):
		return
	# Bind the node so the handler knows which card emitted the signal
	node.connect("contact_selected", Callable(self, "_on_contact_selected").bind(node))

func _get_contact_list() -> Node:
	# ChatView (this) path: MarginContainer/HSplitContainer/ChatView
	# Contact list container node (named 'Chatlist' in the scene currently)
	var path := NodePath("../PanelContainer/ScrollContainer/Chatlist") # Keep node name until renamed in scene
	if has_node(path):
		return get_node(path)
	return null

func _on_contact_selected(chat_path: String, card: Node) -> void:
	# If we have never loaded, force load even if path matches default.
	if chat_path == chat_json_path and _loaded_once and card == _current_contact_card:
		# Same card re-clicked; nothing to change.
		return
	reload_with_path(chat_path)
	current_contact_path = chat_path
	_current_contact_card = card
	if _current_contact_card:
		if _current_contact_card.has_method("clear_notifcations"):
			_current_contact_card.clear_notifcations()
		if _current_contact_card.has_method("clear_notifications"):
			_current_contact_card.clear_notifications()
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine:
		engine.clear_unread(chat_path)
	_dismiss_notification(chat_path)

	# Visual selection: unselect ALL existing cards via group (more robust than relying only on list hierarchy)
	for c in get_tree().get_nodes_in_group("contact_cards"):
		if c.has_method("set_selected"):
			c.set_selected(c == card)

	# (Optional) Fallback: if group was somehow empty, use the original contact list traversal
	if get_tree().get_nodes_in_group("contact_cards").is_empty():
		var contact_list := _get_contact_list()
		if contact_list:
			for child in contact_list.get_children():
				if child.has_method("set_selected"):
					child.set_selected(child == card)

func _apply_to_ui() -> void:
	# Called after a successful load in reload_with_path().
	# Inform DialogueEngine about the loaded conversation so it can track steps
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine:
		# Re-open the JSON to get the raw dictionary used by the engine
		var file := FileAccess.open(chat_json_path, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var data: Variant = JSON.parse_string(text)
			if typeof(data) == TYPE_DICTIONARY:
				# Do not force reload if already present; preserves step index & history
				engine.load_conversation(chat_json_path, data, false)
	_apply_profile_icon()
	_rebuild_message_bubbles()
	_seed_vocabulary_from_history()
	_defer_scroll_to_bottom()
	_loaded_once = true
	# Enable input once a chat is loaded
	if _message_input:
		_message_input.editable = true
		_message_input.placeholder_text = "iMessage"

func _apply_profile_icon() -> void:
	if _profile_icon:
		_profile_icon.texture = profile_texture

func _rebuild_message_bubbles() -> void:
	if _messages_root == null:
		return
	# Clear existing bubbles
	for c in _messages_root.get_children():
		c.queue_free()

	# Add a top separator so there's always scrollable space above the first message
	var top_sep := HSeparator.new()
	top_sep.name = "TopSeparator"
	top_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Provide 50px vertical space at the top for scroll offset purposes
	top_sep.custom_minimum_size = Vector2(0, 100)
	# Make the separator invisible by using an empty style box
	top_sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
	_messages_root.add_child(top_sep)

	# Prefer full persistent history from DialogueEngine if available
	var engine := get_node_or_null("/root/DialogueEngine")
	var display_history: Array = []
	if engine and engine.has_method("get_history"):
		display_history = engine.get_history(chat_json_path)
	if display_history.is_empty():
		display_history = chat_history

	for entry in display_history:
		var author := str(entry.get("author", "contact"))
		var text := str(entry.get("text", ""))
		var scene: PackedScene = _npc_bubble_scene
		if author == "player":
			scene = _player_bubble_scene
		if scene == null:
			continue
		var bubble := scene.instantiate()

		# Create a horizontal row container to control alignment & eliminate opposite-side negative space
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_FILL  # Row spans width; bubble won't
		_messages_root.add_child(row)

		# Spacer logic: left-aligned (NPC) -> spacer AFTER bubble; right-aligned (player) -> spacer BEFORE bubble
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if author == "player":
			# Right aligned: push bubble to the right by putting expandable spacer first
			row.add_child(spacer)
			row.add_child(bubble)
		else:
			# Left aligned: bubble first, spacer after
			row.add_child(bubble)
			row.add_child(spacer)

		var soft_width: float = _get_bubble_soft_width()
		if bubble.has_method("set_max_content_width"):
			bubble.set_max_content_width(soft_width)

		# Ensure bubble itself does NOT expand horizontally so it shrinks to its content
		if bubble is Control:
			bubble.size_flags_horizontal = 0

		# Populate text using helper if available
		if bubble.has_method("set_message_text"):
			bubble.set_message_text(text)
		else:
			var label := bubble.get_node_or_null("MarginContainer/message")
			if label is RichTextLabel:
				label.text = text

	# Add and cache a bottom separator so it's always the last child
	_bottom_sep = HSeparator.new()
	_bottom_sep.name = "BottomSeparator"
	_bottom_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_sep.custom_minimum_size = Vector2(0, 100)
	_bottom_sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
	_messages_root.add_child(_bottom_sep)
	_update_message_width_limits()

func _defer_scroll_to_bottom() -> void:
	# Ensure layout updates settle over a couple of frames, then scroll
	call_deferred("_scroll_to_bottom_async")

func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# Use scroll_vertical property directly instead of scrollbar value
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _scroll_to_bottom_async() -> void:
	# Wait two frames to allow fonts/layout to settle, then scroll
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll_to_bottom()

func _scroll_to_bottom_smooth(duration: float = 0.5) -> void:
	if _scroll == null:
		return
	# Run async to avoid blocking callers; fire-and-forget
	_call_deferred_scroll_smooth(duration)

func _call_deferred_scroll_smooth(duration: float) -> void:
	_scroll_smooth_async(duration)

func _scroll_smooth_async(duration: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame # two frames for font wrap/layout stability
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	var target := int(bar.max_value)
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	var start := _scroll.scroll_vertical
	if target <= start:
		return
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target, duration)


func _on_message_text_submitted(new_text: String) -> void:
	var text := new_text.strip_edges()
	if text == "":
		return
	# Don’t allow sending if no contact is open
	if current_contact_path == "" or not _loaded_once:
		_show_no_contact_feedback()
		return
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine == null:
		push_error("chat_handler: DialogueEngine autoload not found")
		return
	# Process via engine; contact_id is the current chat_json_path
	var res: Dictionary = engine.process_input(chat_json_path, text)
	var status := str(res.get("status", ""))
	match status:
		"rejected":
			var unknown: Array = res.get("unknown_words", [])
			_show_reject_feedback(unknown)
			_maybe_show_tutorial_popup(unknown)
			return
		"success":
			_append_player_bubble(text)
			var lines_s: Array = res.get("npc_messages", [])
			await _append_npc_messages_with_delay(lines_s)
			var last_text_success := ""
			if lines_s.size() > 0:
				last_text_success = str(lines_s.back())
			_update_contact_last_message(chat_json_path, last_text_success)
			# Clear only when accepted
			if _message_input:
				_message_input.clear()
			_scroll_to_bottom_smooth(scroll_ease_duration)
		"wrong":
			_append_player_bubble(text)
			var lines: Array = res.get("npc_messages", [])
			await _append_npc_messages_with_delay(lines)
			var last_text_wrong := ""
			if lines.size() > 0:
				last_text_wrong = str(lines.back())
			_update_contact_last_message(chat_json_path, last_text_wrong)
			_scroll_to_bottom_smooth(scroll_ease_duration)
		_:
			# Fallback: treat as wrong
			_append_player_bubble(text)
			await _append_npc_messages_with_delay(["Huh?"])
			_update_contact_last_message(chat_json_path, "Huh?")
			_scroll_to_bottom_smooth(scroll_ease_duration)

# _try_autoselect_template removed (legacy template loading)

func _append_player_bubble(text: String) -> void:
	send_audio.play()
	_append_bubble(text, true)
	_scroll_to_bottom_smooth(scroll_ease_duration)

func _append_npc_bubble(text: String) -> void:
	recieve_audio.play()
	_append_bubble(text, false)

func _append_npc_messages_with_delay(lines: Array, _unused_delay: float = 0.3) -> void:
	for l in lines:
		var message_text := str(l)
		# Calculate delay based on message length: ~15-30ms per character + random 200-600ms base
		var base_delay := randf_range(0.2, 0.6)
		var char_delay := message_text.length() * randf_range(0.015, 0.03)
		var total_delay := minf(base_delay + char_delay, 2.5)  # Cap at 2.5 seconds
		await get_tree().create_timer(total_delay).timeout
		_append_npc_bubble(message_text)
		_scroll_to_bottom_smooth(scroll_ease_duration)

func _append_bubble(text: String, is_player: bool) -> void:
	if _messages_root == null:
		return
	var scene: PackedScene = _player_bubble_scene if is_player else _npc_bubble_scene
	if scene == null:
		return
	var bubble := scene.instantiate()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	# Ensure we insert above the bottom separator if it exists
	if _bottom_sep and _bottom_sep.get_parent() == _messages_root:
		_messages_root.add_child(row)
		_messages_root.move_child(row, _bottom_sep.get_index())
	else:
		_messages_root.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_player:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	var soft_width: float = _get_bubble_soft_width()
	if bubble.has_method("set_max_content_width"):
		bubble.set_max_content_width(soft_width)
	if bubble is Control:
		bubble.size_flags_horizontal = 0
	if bubble.has_method("set_message_text"):
		bubble.set_message_text(text)
	else:
		var label := bubble.get_node_or_null("MarginContainer/message")
		if label is RichTextLabel:
			label.text = text
	# Keep bottom separator as last child
	if _bottom_sep and _bottom_sep.get_parent() == _messages_root:
		_messages_root.move_child(_bottom_sep, _messages_root.get_child_count() - 1)
	else:
		pass

func _update_contact_last_message(contact_path: String, last_text: String) -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	for child in contact_list.get_children():
		if child is ChatJsonView and child.chat_json_path == contact_path and child.has_method("refresh_last_message"):
			child.refresh_last_message(last_text)
			break

func _on_contact_incoming(contact_path: String, lines: PackedStringArray, _source: String) -> void:
	var preview_text := ""
	if lines.size() > 0:
		preview_text = str(lines[lines.size() - 1])
	_update_contact_last_message(contact_path, preview_text)
	if contact_path == current_contact_path and _loaded_once:
		for line in lines:
			_append_npc_bubble(str(line))
		_scroll_to_bottom_smooth(scroll_ease_duration)
		var engine := get_node_or_null("/root/DialogueEngine")
		if engine:
			engine.clear_unread(contact_path)
		if _current_contact_card:
			if _current_contact_card.has_method("clear_notifcations"):
				_current_contact_card.clear_notifcations()
			if _current_contact_card.has_method("clear_notifications"):
				_current_contact_card.clear_notifications()
		_dismiss_notification(contact_path)
		return
	if _notification_widget and _notification_widget.has_method("notification_in"):
		var contact_display := _get_contact_display_name(contact_path)
		var trimmed := preview_text
		if trimmed.length() > 64:
			trimmed = trimmed.substr(0, 61) + "..."
		var profile_path := _get_contact_profile_path(contact_path)
		_notification_widget.call("notification_in", profile_path, contact_display, trimmed, contact_path)

func _on_unread_count_changed(contact_path: String, unread: int) -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	for child in contact_list.get_children():
		if child is ChatJsonView and child.chat_json_path == contact_path:
			if unread > 0:
				if child.has_method("unread_message"):
					child.unread_message()
			else:
				if child.has_method("clear_notifcations"):
					child.clear_notifcations()
				if child.has_method("clear_notifications"):
					child.clear_notifications()
			break

func _get_contact_display_name(contact_path: String) -> String:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return contact_path
	for child in contact_list.get_children():
		if child is ChatJsonView and child.chat_json_path == contact_path:
			return child.get_contact_display_name()
	return contact_path

func _maybe_show_tutorial_popup(_unknown_words: Array) -> void:
	if _tutorial_popup_shown:
		return
	if _error_popup == null:
		return
	_tutorial_popup_shown = true
	_error_popup.popup_centered_ratio(0.4)

func _on_error_popup_button_pressed() -> void:
	if _error_popup == null:
		return
	_error_popup.hide()
	_error_popup.queue_free()
	_error_popup = null
	_error_popup_button = null

func _get_contact_profile_path(contact_path: String) -> String:
	var contact_list := _get_contact_list()
	if contact_list:
		for child in contact_list.get_children():
			if child is ChatJsonView and child.chat_json_path == contact_path:
				var value := str(child.icon_path)
				if value != "":
					return value
	return DEFAULT_PROFILE_ICON_PATH

func _on_notification_clicked(chat_path: String) -> void:
	_dismiss_notification()
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	for child in contact_list.get_children():
		if child is ChatJsonView and child.chat_json_path == chat_path:
			_on_contact_selected(chat_path, child)
			return

func _dismiss_notification(target_path: String = "") -> void:
	if _notification_widget == null:
		return
	var current_target := ""
	if _notification_widget.has_method("get_target_chat_path"):
		current_target = str(_notification_widget.call("get_target_chat_path"))
	if target_path != "" and current_target != target_path:
		return
	if _notification_widget.has_method("notification_out"):
		_notification_widget.call("notification_out")

func _seed_vocabulary_from_history() -> void:
	var vocab := get_node_or_null("/root/Vocabulary")
	if vocab == null:
		return
	# Add tokens from contact-authored history entries so the player can reuse seen words
	for entry in chat_history:
		var author := str(entry.get("author", "contact"))
		if author == "contact":
			var text := str(entry.get("text", ""))
			vocab.add_words([text])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_message_width_limits()

func _get_bubble_soft_width() -> float:
	var base_width: float = 0.0
	if _scroll:
		base_width = _scroll.size.x
		if base_width <= 0.0:
			base_width = _scroll.get_rect().size.x
	if base_width <= 0.0 and _messages_root:
		base_width = _messages_root.size.x
	if base_width <= 0.0:
		base_width = BUBBLE_WIDTH_FALLBACK
	var target: float = base_width * BUBBLE_WIDTH_RATIO
	if target <= 0.0:
		target = BUBBLE_WIDTH_FALLBACK * BUBBLE_WIDTH_RATIO
	return clamp(target, BUBBLE_WIDTH_MIN, BUBBLE_WIDTH_MAX)

func _update_message_width_limits() -> void:
	if _messages_root == null:
		return
	var soft_width: float = _get_bubble_soft_width()
	for child in _messages_root.get_children():
		if child is HBoxContainer:
			for node in child.get_children():
				if node.has_method("set_max_content_width"):
					node.set_max_content_width(soft_width)

func _show_reject_feedback(_unknown_words: Array) -> void:
	# Minimal feedback: flash the input field red via a modulate tween
	var input := $VBoxContainer/Message as LineEdit
	if input == null:
		return
	var tween := create_tween()
	var orig := input.modulate
	input.modulate = Color(1, 0.7, 0.7)
	tween.tween_property(input, "modulate", orig, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _show_no_contact_feedback() -> void:
	var input := $VBoxContainer/Message as LineEdit
	if input == null:
		return
	var orig_placeholder := input.placeholder_text
	input.placeholder_text = "Select a contact first"
	var tween := create_tween()
	var orig_pos := input.position
	var shake := 6.0
	tween.tween_property(input, "position", orig_pos + Vector2(shake, 0), 0.05)
	tween.tween_property(input, "position", orig_pos - Vector2(shake, 0), 0.05)
	tween.tween_property(input, "position", orig_pos, 0.05)
	await tween.finished
	input.placeholder_text = orig_placeholder
