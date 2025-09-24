# copy-paste-interrogate

## Contact Card JSON System

- Purpose: Modular contact cards (iMessage-style) that load their data from JSON files for name, profile icon, and chat history.

### File Locations
- Script: `res://scripts/contact_card.gd`
- Scene: `res://scenes/contact_card.tscn`
- Template JSON: `res://scripts/chats/template_chat.json`

### JSON Schema
- `name`: String. Display name for the contact.
- `profile_icon_path`: String. Resource path to a `Texture2D` (e.g. PNG) used as the contact avatar.
- `chat_history`: Array of entries. Each entry can be:
	- Object: `{ "author": "contact" | "player", "text": "..." }`
	- String: shorthand for `{ "author": "contact", "text": "..." }`

Example (`scripts/chats/template_chat.json`):

```
{
	"name": "Apple Bot",
		"profile_icon_path": "res://template.PNG",
	"chat_history": [
		{ "author": "contact", "text": "Hey there! This is a template chat." },
		{ "author": "player", "text": "Cool, I'll use this as a starting point." },
		"You can also provide a simple string; defaults to contact",
		{ "author": "contact", "text": "Swap in your own messages and profile icon." }
	]
}
```

### Using the Contact Card
- Instance `scenes/contact_card.tscn` in your scene.
- In the Inspector, set `chat_json_path` (exported on `contact_card.gd`) to your JSON file path. Defaults to the template.
- On ready, the script parses the JSON, loads the avatar texture, and normalizes chat entries.

## Chat List Population

- Script: `res://scripts/chatlist_handler.gd`
- Scene: `res://scenes/main_window.tscn` → node `Chatlist` (a `VBoxContainer`)
- Behavior: On ready, it auto-instances a `contact_card.tscn` for each `*.json` under `res://scripts/chats/`.
	- Sets each instance's exported `chat_json_path` to that file.
	- Inserts them below the `Search_padding2` separator node.
	- Adds an `HSeparator` between entries for spacing.
	- Clears previously added entries on refresh.
	- Sorts alphabetically by filename.

### Adding a New Contact
- Drop a `*.json` file into `res://scripts/chats/` (use the template as a starting point).
- Ensure any avatar path in `profile_icon_path` is a valid Godot resource path (e.g., `res://assets/.../icon.png`).
- Run the scene: entries appear automatically under the search field with separators.

### Consuming Parsed Data
- `get_contact_display_name()` → String name.
- `get_profile_texture()` → `Texture2D` for avatar (may be null if path invalid).
- `get_chat_history()` → Array of `{ author, text }` dictionaries.
- Signal `chat_loaded` is emitted after parsing completes; connect this to update UI widgets.

### Notes
- Paths must be Godot resource paths (e.g. `res://...`).
- If `profile_icon_path` is invalid or not a texture, a warning is logged and avatar will be null.
- Non-array `chat_history` or non-dictionary root will log errors and safely fallback.
