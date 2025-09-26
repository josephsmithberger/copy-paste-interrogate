extends Node

const STATUS_REJECTED := "rejected"
const STATUS_WRONG := "wrong"
const STATUS_SUCCESS := "success"

# In-memory per-contact state (jam scope; no save)
# contact_id -> { steps: Array, index: int }
var _conversations: Dictionary = {}

func _ready() -> void:
	pass

func load_conversation(contact_id: String, data: Dictionary) -> void:
	var steps := []
	if data.has("steps"):
		var s: Variant = data.get("steps")
		if typeof(s) == TYPE_ARRAY:
			steps = s
	_conversations[contact_id] = {
		"steps": steps,
		"index": 0,
	}

func get_state(contact_id: String) -> Dictionary:
	return _conversations.get(contact_id, {"steps": [], "index": 0})

func process_input(contact_id: String, player_text: String) -> Dictionary:
	var convo: Variant = _conversations.get(contact_id, null)
	if convo == null or typeof(convo) != TYPE_DICTIONARY:
		return {
			"status": STATUS_WRONG,
			"npc_messages": ["..."],
			"unlock_words": [],
		}

	var steps: Array = convo.get("steps", [])
	var idx: int = int(convo.get("index", 0))

	# If out of steps, always respond with a generic wrong
	if idx >= steps.size():
		return _make_result(STATUS_WRONG, [], [], [], idx)

	var step = steps[idx]
	if typeof(step) != TYPE_DICTIONARY:
		# Malformed step; skip it safely
		convo["index"] = idx + 1
		_conversations[contact_id] = convo
		return _make_result(STATUS_WRONG, [], [], [], int(convo.get("index", 0)))

	var expected: Variant = step.get("expected", {})
	var on_wrong: Variant = step.get("on_wrong", {})
	var on_success: Variant = step.get("on_success", {})
	var reject_unknown := bool(step.get("reject_unknown_words", true))

	var vocab := get_node_or_null("/root/Vocabulary")
	var tokens: PackedStringArray = []
	if vocab and vocab.has_method("tokenize"):
		tokens = vocab.tokenize(player_text)

	if reject_unknown:
		var unknown: PackedStringArray = []
		for t in tokens:
			if vocab == null or not vocab.contains(t):
				unknown.append(t)
		if unknown.size() > 0:
			return _make_result(STATUS_REJECTED, unknown, [], [], idx)

	var matched := _match_expected(expected, player_text, tokens)
	if not matched:
		var wrong_lines := _extract_lines(on_wrong)
		if wrong_lines.is_empty():
			wrong_lines = ["Huh?"]
		return _make_result(STATUS_WRONG, [], wrong_lines, [], idx)

	# Success
	var npc_lines := _extract_lines(on_success)
	var unlock_words := _extract_unlock_words(on_success)

	convo["index"] = idx + 1
	_conversations[contact_id] = convo

	return _make_result(STATUS_SUCCESS, [], npc_lines, unlock_words, int(convo.get("index", 0)))

func _match_expected(expected: Variant, text: String, tokens: PackedStringArray) -> bool:
	if typeof(expected) != TYPE_DICTIONARY:
		return false
	var match_mode := str((expected as Dictionary).get("match", "exact"))

	if (expected as Dictionary).has("alternatives"):
		var alts: Variant = (expected as Dictionary).get("alternatives")
		if typeof(alts) == TYPE_ARRAY:
			for alt in alts:
				if _match_expected(alt, text, tokens):
					return true
		# fall through to other checks too

	if (expected as Dictionary).has("text"):
		var norm := _normalize(text)
		var exp_str := _normalize(str((expected as Dictionary).get("text")))
		if match_mode == "exact":
			return norm == exp_str
		elif match_mode == "contains":
			return norm.find(exp_str) != -1
		else:
			return norm == exp_str

	if (expected as Dictionary).has("tokens"):
		var exp_tokens: PackedStringArray = []
		var vocab := get_node_or_null("/root/Vocabulary")
		var toks_src: Variant = (expected as Dictionary).get("tokens")
		if typeof(toks_src) == TYPE_ARRAY:
			for e in toks_src:
				if vocab and vocab.has_method("tokenize"):
					exp_tokens.append_array(vocab.tokenize(str(e)))
		if match_mode == "exact":
			if exp_tokens.size() != tokens.size():
				return false
			for i in range(tokens.size()):
				if tokens[i] != exp_tokens[i]:
					return false
			return true
		else:
			# set/contains semantics: all expected tokens must be present in player's tokens
			for et in exp_tokens:
				if tokens.find(et) == -1:
					return false
			return true

	return false

func _normalize(s: String) -> String:
	var vocab := get_node_or_null("/root/Vocabulary")
	var toks: PackedStringArray = []
	if vocab and vocab.has_method("tokenize"):
		toks = vocab.tokenize(s)
	return " ".join(toks)

func _extract_lines(section: Variant) -> PackedStringArray:
	var lines: PackedStringArray = []
	if typeof(section) == TYPE_DICTIONARY:
		if (section as Dictionary).has("npc") and typeof((section as Dictionary).get("npc")) == TYPE_ARRAY:
			for v in (section as Dictionary).get("npc"):
				lines.append(str(v))
	elif typeof(section) == TYPE_ARRAY:
		for v in section:
			lines.append(str(v))
	elif typeof(section) == TYPE_STRING:
		lines.append(str(section))
	return lines

func _extract_unlock_words(section: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if typeof(section) == TYPE_DICTIONARY and (section as Dictionary).has("unlock_words") and typeof((section as Dictionary).get("unlock_words")) == TYPE_ARRAY:
		for w in (section as Dictionary).get("unlock_words"):
			out.append(str(w))
	return out

func _make_result(status: String, unknown_words: PackedStringArray, npc_lines: PackedStringArray, unlock_words: PackedStringArray, index_after: int) -> Dictionary:
	return {
		"status": status,
		"unknown_words": unknown_words,
		"npc_messages": npc_lines,
		"unlock_words": unlock_words,
		"step_index": index_after,
	}
 
