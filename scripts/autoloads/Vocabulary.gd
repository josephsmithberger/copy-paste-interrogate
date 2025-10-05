extends Node

signal words_unlocked(new_words: PackedStringArray)

var _words: Dictionary = {}

func _ready() -> void:
	# Jam scope: start empty; words are unlocked during play
	pass

# Public API
func tokenize(text: String) -> PackedStringArray:
	# Lowercase and extract alphanumeric tokens (allowing apostrophes)
	var lowered := text.to_lower()
	var re := RegEx.new()
	var err := re.compile("[A-Za-z0-9']+")
	if err != OK:
		# Fallback: split on whitespace
		return PackedStringArray(lowered.split(" ", false))
	var tokens: PackedStringArray = []
	for m in re.search_all(lowered):
		var t := m.get_string(0).strip_edges()
		if t != "":
			tokens.append(t)
	return tokens

func has_all(tokens: Array) -> bool:
	for t in tokens:
		var key := str(t).to_lower()
		if not _words.has(key):
			return false
	return true

func add_words(words: Array) -> void:
	var newly: PackedStringArray = []
	for w in words:
		var ws := str(w)
		# If a phrase is passed, break into tokens; single words will just yield one token
		var toks := tokenize(ws)
		for t in toks:
			if t == "":
				continue
			if _is_obfuscated(t):
				continue
			if not _words.has(t):
				_words[t] = true
				newly.append(t)
	if newly.size() > 0:
		words_unlocked.emit(newly)

func _is_obfuscated(token: String) -> bool:
	# Filter out l33t-speak and obfuscated tokens
	# Check for mixed letters and numbers (common in l33t-speak)
	var has_letter := false
	var has_number := false
	
	for i in range(token.length()):
		var c := token[i]
		if c >= '0' and c <= '9':
			has_number = true
		elif (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'):
			has_letter = true
	
	# If it has both letters and numbers mixed together, it's likely obfuscated
	if has_letter and has_number:
		return true
	
	# Check for l33t-speak patterns: words with 0, 1, 3, 4 as substitutes
	# But allow pure numbers (like "8921" employee ID)
	if has_number and not has_letter:
		return false
	
	# Check for random special characters in the middle of words
	if token.contains("%") or (token.contains("-") and token.length() > 2):
		# Allow hyphenated words like "un-obstructed" only if no numbers
		if token.contains("-") and not has_number:
			return false
		return true
	
	return false

func contains(word: String) -> bool:
	return _words.has(word.to_lower())

func all_words() -> PackedStringArray:
	var arr: PackedStringArray = []
	for k in _words.keys():
		arr.append(str(k))
	arr.sort()
	return arr

func highlight_new_words(text: String) -> String:
	# Wraps new (not yet seen) words in BBCode highlighting
	# Returns the text with [b][color=#007AFF]word[/color][/b] around new tokens
	var tokens := tokenize(text)
	var new_tokens := []
	
	# First pass: identify which tokens are new
	for token in tokens:
		if _is_obfuscated(token):
			continue
		if not _words.has(token):
			new_tokens.append(token)
	
	if new_tokens.is_empty():
		return text
	
	# Second pass: build highlighted version by finding word boundaries
	var result := ""
	var i := 0
	var lower_text := text.to_lower()
	
	while i < text.length():
		var current_char := text[i]
		var matched := false
		
		# Check if any new token starts at this position
		for token in new_tokens:
			var token_len: int = token.length()
			if i + token_len > text.length():
				continue
			
			# Check if this position matches the token (case-insensitive)
			var substr := lower_text.substr(i, token_len)
			if substr != token:
				continue
			
			# Verify word boundaries (not part of a larger word)
			var prev_is_boundary: bool = i == 0 or not _is_word_char(text[i - 1])
			var next_is_boundary: bool = (i + token_len >= text.length()) or not _is_word_char(text[i + token_len])
			
			if prev_is_boundary and next_is_boundary:
				# Found a match - wrap it
				var original_word := text.substr(i, token_len)
				result += "[color=#007AFF]" + original_word + "[/color]"
				i += token_len
				matched = true
				break
		
		if not matched:
			result += current_char
			i += 1
	
	return result

func _is_word_char(c: String) -> bool:
	if c.length() != 1:
		return false
	var code := c.unicode_at(0)
	# Check if alphanumeric or apostrophe
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or c == "'"


# Called when the node enters the scene tree for the first time.
func clear_all() -> void:
	_words.clear()
