extends Node

signal contact_incoming(contact_id: String, messages: PackedStringArray, source_contact_id: String)
signal unread_count_changed(contact_id: String, unread_count: int)
signal lock_state_changed(contact_id: String, is_locked: bool)

const STATUS_REJECTED := "rejected"
const STATUS_WRONG := "wrong"
const STATUS_SUCCESS := "success"

const ADD_FAILED_PLAYER_TOKENS := false
const ADD_FAIL_LINE_TOKENS := true

var _conversations: Dictionary = {} # contact_id -> {steps:Array, index:int, locked:bool}
var _history: Dictionary = {}       # contact_id -> Array[ {author,text} ]
var _chat_sources: Dictionary = {}  # contact_id -> Dictionary (raw JSON root)
var _unread_counts: Dictionary = {} # contact_id -> int

func load_conversation(contact_id: String, data: Dictionary, force: bool = false) -> void:
	if not force and _conversations.has(contact_id):
		return
	var steps: Array = []
	var preseed: Array = []
	var starts_locked := bool(data.get("locked", false))
	var vocab := get_node_or_null("/root/Vocabulary")
	if data.has("chat") and typeof(data.chat) == TYPE_ARRAY:
		var encountered_step := false
		for entry in data.chat:
			var t := typeof(entry)
			if t == TYPE_DICTIONARY:
				steps.append(_normalize_step(entry))
				encountered_step = true
			elif t == TYPE_STRING and not encountered_step:
				var text := str(entry)
				var display_text := text
				if vocab and vocab.has_method("highlight_new_words"):
					display_text = vocab.highlight_new_words(text)
				preseed.append({"author": "contact", "text": display_text})
				if vocab:
					vocab.add_words([text])
	_conversations[contact_id] = {"steps": steps, "index": 0, "locked": starts_locked}
	_history[contact_id] = preseed
	_chat_sources[contact_id] = data
	if not _unread_counts.has(contact_id):
		_unread_counts[contact_id] = 0
	unread_count_changed.emit(contact_id, int(_unread_counts.get(contact_id, 0)))
	lock_state_changed.emit(contact_id, starts_locked)

func get_state(contact_id: String) -> Dictionary:
	return _conversations.get(contact_id, {"steps": [], "index": 0})

func get_history(contact_id: String) -> Array:
	return _history.get(contact_id, [])

func get_unread_count(contact_id: String) -> int:
	return int(_unread_counts.get(contact_id, 0))

func is_locked(contact_id: String) -> bool:
	var convo: Variant = _conversations.get(contact_id, null)
	if convo != null and typeof(convo) == TYPE_DICTIONARY:
		return bool(convo.get("locked", false))
	return false

func clear_unread(contact_id: String) -> void:
	if not _unread_counts.has(contact_id):
		return
	if _unread_counts[contact_id] == 0:
		return
	_unread_counts[contact_id] = 0
	unread_count_changed.emit(contact_id, 0)

func process_input(contact_id: String, player_text: String) -> Dictionary:
	var convo: Variant = _conversations.get(contact_id, null)
	if convo == null or typeof(convo) != TYPE_DICTIONARY:
		return _make_result(STATUS_WRONG, [], [], [], 0)
	
	var steps: Array = convo.get("steps", [])
	var idx: int = int(convo.get("index", 0))
	var vocab := get_node_or_null("/root/Vocabulary")
	var tokens: PackedStringArray = []
	if vocab and vocab.has_method("tokenize"):
		tokens = vocab.tokenize(player_text)
	
	# Always check vocabulary first, even for locked contacts
	var unknown := _unknown_tokens(tokens, vocab)
	if unknown.size() > 0:
		return _make_result(STATUS_REJECTED, unknown, [], [], idx)
	
	# Check if contact is locked (hasn't been triggered yet)
	if bool(convo.get("locked", false)):
		return _make_result("locked", [], [], [], 0)

	if idx >= steps.size():
		if vocab:
			vocab.add_words([player_text])
		_append_history(contact_id, "player", player_text)
		return _make_result(STATUS_SUCCESS, [], [], [], idx)

	var step: Dictionary = steps[idx]

	var matched := _match_step(step, player_text, tokens, vocab)
	if not matched:
		if ADD_FAILED_PLAYER_TOKENS and vocab:
			vocab.add_words([player_text])
		_append_history(contact_id, "player", player_text)
		var fail_lines := _to_lines(step.get("fail", []))
		if fail_lines.is_empty():
			return _make_result(STATUS_WRONG, [], [], [], idx)
		for fl in fail_lines:
			_append_history_with_highlight(contact_id, "contact", fl, vocab)
			if vocab and ADD_FAIL_LINE_TOKENS:
				vocab.add_words([fl])
		return _make_result(STATUS_WRONG, [], fail_lines, [], idx)

	if vocab:
		vocab.add_words([player_text])
	_append_history(contact_id, "player", player_text)
	var success_lines := _to_lines(step.get("success", []))
	for sl in success_lines:
		_append_history_with_highlight(contact_id, "contact", sl, vocab)
		if vocab:
			vocab.add_words([sl])
	convo.index = idx + 1
	# Check if this step locks the conversation after success
	if step.has("lock") and bool(step.lock):
		convo.locked = true
		lock_state_changed.emit(contact_id, true)
	_conversations[contact_id] = convo
	var triggered := _process_step_triggers(contact_id, step)
	return _make_result(STATUS_SUCCESS, [], success_lines, [], convo.index, triggered)

func _append_history(contact_id: String, author: String, text: String) -> void:
	var arr: Array = _history.get(contact_id, [])
	arr.append({"author": author, "text": text})
	_history[contact_id] = arr

func _append_history_with_highlight(contact_id: String, author: String, text: String, vocab: Node) -> void:
	var arr: Array = _history.get(contact_id, [])
	var display_text := text
	
	# Highlight new words for NPC messages BEFORE adding to vocabulary
	if author == "contact":
		if vocab and vocab.has_method("highlight_new_words"):
			display_text = vocab.highlight_new_words(text)
	
	arr.append({"author": author, "text": display_text})
	_history[contact_id] = arr

func _unknown_tokens(tokens: PackedStringArray, vocab: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for t in tokens:
		if vocab == null or not vocab.contains(t):
			out.append(t)
	return out

func _normalize_step(step: Dictionary) -> Dictionary:
	var cleaned: Dictionary = {}
	var keys := ["expect", "expect_tokens", "any_of", "match", "success", "fail", "notify", "lock"]
	for k in keys:
		if step.has(k):
			cleaned[k] = step[k]
	return cleaned

func _process_step_triggers(origin_contact_id: String, step: Dictionary) -> Array:
	var triggered: Array = []
	if not step.has("notify"):
		return triggered
	var raw: Variant = step.get("notify", [])
	if typeof(raw) != TYPE_ARRAY:
		return triggered
	var raw_array: Array = raw
	for entry in raw_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var target := str(entry.get("chat", "")).strip_edges()
		if target == "":
			continue
		var lines := _to_lines(entry.get("messages", []))
		if lines.is_empty():
			continue
		_ensure_conversation_loaded(target)
		var info := {"contact": target, "messages": lines.duplicate(), "source": origin_contact_id}
		triggered.append(info)
		# Delay the entire notification process by 2-5 seconds to simulate another contact taking time to respond
		_delayed_notification(target, lines.duplicate(), origin_contact_id)
	return triggered

func _delayed_notification(target: String, lines: PackedStringArray, source: String) -> void:
	var delay := randf_range(2.0, 5.0)
	await get_tree().create_timer(delay).timeout
	# Unlock the contact if they were locked
	var convo: Variant = _conversations.get(target, null)
	if convo != null and typeof(convo) == TYPE_DICTIONARY:
		if bool(convo.get("locked", false)):
			convo.locked = false
			_conversations[target] = convo
			lock_state_changed.emit(target, false)
	# Now append to history and add vocabulary after the delay
	var vocab := get_node_or_null("/root/Vocabulary")
	for line in lines:
		_append_history_with_highlight(target, "contact", line, vocab)
		if vocab:
			vocab.add_words([line])
	_mark_unread(target, lines.size())
	emit_signal("contact_incoming", target, lines, source)

func _ensure_conversation_loaded(contact_id: String) -> void:
	if _conversations.has(contact_id):
		return
	var data: Dictionary = _chat_sources.get(contact_id, {})
	if data.is_empty():
		data = _load_chat_dict(contact_id)
	if data.is_empty():
		return
	load_conversation(contact_id, data, true)

func _load_chat_dict(contact_id: String) -> Dictionary:
	var file := FileAccess.open(contact_id, FileAccess.READ)
	if file == null:
		push_warning("DialogueEngine: Unable to open chat file %s for trigger notification" % contact_id)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("DialogueEngine: Chat file %s has invalid root for trigger notification" % contact_id)
		return {}
	var parsed_dict: Dictionary = parsed
	_chat_sources[contact_id] = parsed_dict
	return parsed_dict

func _mark_unread(contact_id: String, amount: int) -> void:
	var current := int(_unread_counts.get(contact_id, 0))
	current += max(amount, 0)
	_unread_counts[contact_id] = current
	unread_count_changed.emit(contact_id, current)

func _match_step(step: Dictionary, player_text: String, tokens: PackedStringArray, vocab: Node) -> bool:
	if step.has("any_of") and typeof(step.any_of) == TYPE_ARRAY:
		for alt in step.any_of:
			if typeof(alt) == TYPE_DICTIONARY:
				if _match_step(_normalize_step(alt), player_text, tokens, vocab):
					return true

	if step.has("expect"):
		var exp_norm := _normalize_text(step.expect, vocab)
		var player_norm := _normalize_text(player_text, vocab)
		var mode := str(step.get("match", "exact"))
		match mode:
			"exact":
				return player_norm == exp_norm
			"contains":
				return player_norm.find(exp_norm) != -1
			_:
				return player_norm == exp_norm

	if step.has("expect_tokens") and typeof(step.expect_tokens) == TYPE_ARRAY:
		var exp_tokens: PackedStringArray = []
		for e in step.expect_tokens:
			if vocab and vocab.has_method("tokenize"):
				exp_tokens.append_array(vocab.tokenize(str(e)))
		var mode2 := str(step.get("match", "set"))
		if mode2 == "set":
			if exp_tokens.size() != tokens.size():
				return false
			for t in exp_tokens:
				if tokens.find(t) == -1:
					return false
			return true
		elif mode2 == "contains":
			for t in exp_tokens:
				if tokens.find(t) == -1:
					return false
			return true
		else:
			if exp_tokens.size() != tokens.size():
				return false
			for i in range(tokens.size()):
				if tokens[i] != exp_tokens[i]:
					return false
			return true

	return false

func _normalize_text(s: String, vocab: Node) -> String:
	if vocab and vocab.has_method("tokenize"):
		var toks: PackedStringArray = vocab.tokenize(s)
		return " ".join(toks)
	return s.to_lower().strip_edges()

func _to_lines(v: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if typeof(v) == TYPE_STRING:
		out.append(str(v))
	elif typeof(v) == TYPE_ARRAY:
		for e in v:
			out.append(str(e))
	return out

func _make_result(status: String, unknown_words: PackedStringArray, npc_lines: PackedStringArray, _unused_unlock: PackedStringArray, index_after: int, triggered: Array = []) -> Dictionary:
	return {
		"status": status,
		"unknown_words": unknown_words,
		"npc_messages": npc_lines,
		"step_index": index_after,
		"triggered": triggered
	}
