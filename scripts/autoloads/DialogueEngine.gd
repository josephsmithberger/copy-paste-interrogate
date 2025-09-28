extends Node

const STATUS_REJECTED := "rejected"
const STATUS_WRONG := "wrong"
const STATUS_SUCCESS := "success"

# Config knobs
const ADD_FAILED_PLAYER_TOKENS := false
const ADD_FAIL_LINE_TOKENS := true
const ACCEPT_UNKNOWN_AFTER_ALL_STEPS := false

# contact_id -> { steps:Array, index:int }
var _conversations: Dictionary = {}
var _history: Dictionary = {} # contact_id -> Array[Dictionary{author:String, text:String}]

func load_conversation(contact_id: String, data: Dictionary, force: bool = false) -> void:
	# If already loaded and not forcing, do nothing (prevents progress reset when switching contacts)
	if not force and _conversations.has(contact_id):
		return

	# Parse simplified schema: data.chat = [ pre-seed strings..., step dicts... ]
	var steps: Array = []
	var preseed: Array = []
	if data.has("chat") and typeof(data.chat) == TYPE_ARRAY:
		var encountered_step := false
		for entry in data.chat:
			match typeof(entry):
				TYPE_DICTIONARY:
					steps.append(_normalize_step(entry))
					encountered_step = true
				TYPE_STRING:
					if not encountered_step:
						preseed.append({"author": "contact", "text": str(entry)})
					else:
						# Strings after first step should live inside step.success; ignore for engine purposes
						pass

	_conversations[contact_id] = {"steps": steps, "index": 0}
	# Initialize history only if not forcing or overwriting explicitly
	_history[contact_id] = preseed

func get_history(contact_id: String) -> Array:
	return _history.get(contact_id, [])

func _append_history(contact_id: String, author: String, text: String) -> void:
	var arr: Array = _history.get(contact_id, [])
	arr.append({"author": author, "text": text})
	_history[contact_id] = arr

func get_state(contact_id: String) -> Dictionary:
	return _conversations.get(contact_id, {"steps": [], "index": 0})

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

	if idx >= steps.size():
		# Post-steps free mode
		if not ACCEPT_UNKNOWN_AFTER_ALL_STEPS:
			var unknown_after: PackedStringArray = _unknown_tokens(tokens, vocab)
			if unknown_after.size() > 0:
				return _make_result(STATUS_REJECTED, unknown_after, [], [], idx)
		# Accept but no NPC response by default
		if vocab:
			vocab.add_words([player_text])
		_append_history(contact_id, "player", player_text)
		return _make_result(STATUS_SUCCESS, [], [], [], idx)

	var step: Dictionary = steps[idx]
	var allow_unknown: bool = bool(step.get("allow_unknown", false))
	if not allow_unknown:
		var unknown := _unknown_tokens(tokens, vocab)
		if unknown.size() > 0:
			return _make_result(STATUS_REJECTED, unknown, [], [], idx)

	var matched := _match_step(step, player_text, tokens, vocab)
	if not matched:
		# Wrong attempt; optionally add player tokens
		if ADD_FAILED_PLAYER_TOKENS and vocab:
			vocab.add_words([player_text])
		# Record player attempt in history even if wrong (matches on-screen behavior)
		_append_history(contact_id, "player", player_text)
		var fail_lines: PackedStringArray = _to_lines(step.get("fail", []))
		if fail_lines.is_empty():
			return _make_result(STATUS_WRONG, [], [], [], idx)
		if vocab and ADD_FAIL_LINE_TOKENS:
			for l in fail_lines:
				vocab.add_words([l])
		for fl in fail_lines:
			_append_history(contact_id, "contact", fl)
		return _make_result(STATUS_WRONG, [], fail_lines, [], idx)

	# Success path
	if vocab:
		vocab.add_words([player_text])
	_append_history(contact_id, "player", player_text)
	var success_lines: PackedStringArray = _to_lines(step.get("success", []))
	if vocab:
		for sl in success_lines:
			vocab.add_words([sl])
	for sl in success_lines:
		_append_history(contact_id, "contact", sl)
	convo["index"] = idx + 1
	_conversations[contact_id] = convo
	return _make_result(STATUS_SUCCESS, [], success_lines, [], convo["index"])

func _unknown_tokens(tokens: PackedStringArray, vocab: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for t in tokens:
		if vocab == null or not vocab.contains(t):
			out.append(t)
	return out

func _normalize_step(step: Dictionary) -> Dictionary:
	# Keep only allowed keys; ignore legacy
	var cleaned: Dictionary = {}
	var keys := ["expect", "expect_tokens", "any_of", "match", "success", "fail", "allow_unknown"]
	for k in keys:
		if step.has(k):
			cleaned[k] = step[k]
	return cleaned

func _match_step(step: Dictionary, player_text: String, tokens: PackedStringArray, vocab: Node) -> bool:
	if step.has("any_of") and typeof(step.any_of) == TYPE_ARRAY:
		for alt in step.any_of:
			if typeof(alt) == TYPE_DICTIONARY:
				if _match_step(_normalize_step(alt), player_text, tokens, vocab):
					return true
		# Fall through to direct keys if not matched

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
			# Compare as sets
			for t in exp_tokens:
				if tokens.find(t) == -1:
					return false
			return true
		elif mode2 == "contains":
			for t in exp_tokens:
				if tokens.find(t) == -1:
					return false
			return true
		else: # exact fallback—order & length must match
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

func _make_result(status: String, unknown_words: PackedStringArray, npc_lines: PackedStringArray, _unused_unlock: PackedStringArray, index_after: int) -> Dictionary:
	# unlock_words retained as unused param for call-site signature stability; legacy mechanic removed
	return {"status": status, "unknown_words": unknown_words, "npc_messages": npc_lines, "step_index": index_after}
 
