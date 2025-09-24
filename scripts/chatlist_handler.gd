extends VBoxContainer


const CONTACT_CARD_SCENE_PATH := "res://scenes/contact_card.tscn"
const CHATS_DIR := "res://scripts/chats"

@onready var _anchor: Node = $Search_padding2

func _ready() -> void:
	call_deferred("_populate_chat_list")

func _populate_chat_list() -> void:
	if _anchor == null:
		push_error("chatlist_handler: 'Search_padding2' node not found.")
		return

	# Clear any previously added items below the anchor
	var anchor_index := _anchor.get_index()
	while get_child_count() > anchor_index + 1:
		var to_remove := get_child(anchor_index + 1)
		to_remove.queue_free()

	var card_scene := load(CONTACT_CARD_SCENE_PATH)
	if not (card_scene is PackedScene):
		push_error("chatlist_handler: Failed to load contact card scene: %s" % CONTACT_CARD_SCENE_PATH)
		return

	var files := DirAccess.get_files_at(CHATS_DIR)
	if files.is_empty():
		push_warning("chatlist_handler: No files found in %s" % CHATS_DIR)
	files.sort() # Stable order

	var insert_after: Node = _anchor
	var added := 0
	for f in files:
		if f.begins_with("."):
			continue
		if f.get_extension().to_lower() != "json":
			continue

		var card := (card_scene as PackedScene).instantiate()
		var json_path := CHATS_DIR + "/" + f

		# Set exported json path on the card's script
		card.chat_json_path = json_path

		print("chatlist_handler: Adding card for", json_path)

		add_child(card)
		move_child(card, insert_after.get_index() + 1)

		# Add a separator between entries
		var sep := HSeparator.new()
		add_child(sep)
		move_child(sep, card.get_index() + 1)
		insert_after = sep
		added += 1

	if added == 0:
		push_warning("chatlist_handler: No JSON chats found in %s" % CHATS_DIR)
	else:
		print("chatlist_handler: Added %d chat(s) from %s" % [added, CHATS_DIR])
