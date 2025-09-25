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

var _npc_bubble_scene: PackedScene
var _player_bubble_scene: PackedScene
var _loaded_once: bool = false

@onready var _profile_icon: TextureRect = $VBoxContainer/Profile_icon
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _messages_root: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	# Do not call super._ready(); we only load when a contact is clicked.
	_npc_bubble_scene = load(NPC_BUBBLE_SCENE_PATH)
	_player_bubble_scene = load(PLAYER_BUBBLE_SCENE_PATH)
	_connect_existing_contact_cards()
	_watch_for_new_contact_cards()

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

func _try_connect_card(node: Node) -> void:
	if node == null:
		return
	if not node.has_signal("contact_selected"):
		# Likely a separator or non-card.
		return
	if node.is_connected("contact_selected", Callable(self, "_on_contact_selected")):
		return
	node.connect("contact_selected", Callable(self, "_on_contact_selected"))

func _get_contact_list() -> Node:
	# ChatView (this) path: MarginContainer/HSplitContainer/ChatView
	# Contact list container node (named 'Chatlist' in the scene currently)
	var path := NodePath("../PanelContainer/ScrollContainer/Chatlist") # Keep node name until renamed in scene
	if has_node(path):
		return get_node(path)
	return null

func _on_contact_selected(chat_path: String) -> void:
	# If we have never loaded, force load even if path matches default.
	if chat_path == chat_json_path and _loaded_once:
		return
	reload_with_path(chat_path)

func _apply_to_ui() -> void:
	# Called after a successful load in reload_with_path().
	_apply_profile_icon()
	_rebuild_message_bubbles()
	_defer_scroll_to_bottom()
	_loaded_once = true

func _apply_profile_icon() -> void:
	if _profile_icon:
		_profile_icon.texture = profile_texture

func _rebuild_message_bubbles() -> void:
	if _messages_root == null:
		return
	# Clear existing bubbles
	for c in _messages_root.get_children():
		c.queue_free()

	for entry in chat_history:
		var author := str(entry.get("author", "contact"))
		var text := str(entry.get("text", ""))
		var scene: PackedScene = _npc_bubble_scene
		if author == "player":
			scene = _player_bubble_scene
		if scene == null:
			continue
		var bubble := scene.instantiate()
		var label := bubble.get_node_or_null("MarginContainer/message")
		if label is Label:
			label.text = text
		_messages_root.add_child(bubble)

func _defer_scroll_to_bottom() -> void:
	# Ensure layout updated before scrolling
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# ScrollContainer API: obtain v scroll bar value
	var vs := _scroll.get_v_scroll_bar()
	if vs:
		vs.value = vs.max_value
	else:
		pass
