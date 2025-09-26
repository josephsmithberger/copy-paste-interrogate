# copy-paste-interrogate

## Game Overview

- Jam: Xogot Game Jam 2 — Theme: “Liquid Glass”
- Visual direction: iMessage-inspired UI, aligning with Apple’s new “Liquid Glass” design language.
- Core concept: Words are keys and items; conversations are the dungeon.
- Rule: You can’t send words the system hasn’t verified yet — you can only use words you’ve seen from other people.
- How you unlock words: by chatting with other people (NPC contacts) and asking questions using your current, verified vocabulary. Their replies contain new words which become verified for future use.

Gameplay loop
- Chat with multiple contacts; each has different knowledge and vocabulary.
- Ask questions using only currently verified words; replies can include new words, which are then added to your verified arsenal.
- Use newly unlocked words to form better follow‑ups, open new branches, and gather more vocabulary.
- Solve dialogue puzzles by discovering the right words and sequencing them into effective prompts.

## Repository Structure

A quick map of key folders and files to help you navigate:

```
copy-paste-interrogate/
├─ project.godot
├─ README.md
├─ icon.svg
├─ assets/
│  ├─ profile_icons/
│  │  └─ placeholder.png
│  └─ ui/
│     ├─ styling.tres
│     ├─ contact_card_focus.tres
│     ├─ npc_message_bubble.png
│     ├─ user_message_bubble.png
│     ├─ window_falloff_blur.gdshader
│     ├─ symbols/
│     │  └─ Untitled-1.png
│     └─ liquid_glass/
│        ├─ liquid_glass.tres
│        ├─ liquid_glass.gdshader
│        └─ Inter-VariableFont_opsz,wght.ttf
├─ scenes/
│  ├─ main_window.tscn
│  ├─ contact_card.tscn
│  ├─ npc_message_bubble.tscn
│  └─ user_message_bubble.tscn
└─ scripts/
	├─ chat_json_view.gd
	├─ chat_handler.gd
	├─ contact_card.gd
	├─ contact_handler.gd
	├─ npc_message_bubble.gd
	├─ user_message_bubble.gd
	└─ chats/
		└─ template_chat.json
```

Notes:
- All resource paths are Godot-style (e.g., `res://assets/...`).
- Chat JSON files are placed under `res://scripts/chats/` and discovered automatically.
- UI themes, shaders, and textures live under `res://assets/ui/`.

## Contact Card JSON System

- Purpose: Modular contact cards (iMessage-style) that load their data from JSON files for name, profile icon, and chat history.

### File Locations
- Base class: `res://scripts/chat_json_view.gd`
- Contact card script: `res://scripts/contact_card.gd`
- Contact list handler: `res://scripts/contact_handler.gd`
- Chat view handler: `res://scripts/chat_handler.gd`
- Contact card scene: `res://scenes/contact_card.tscn`
- Main window scene: `res://scenes/main_window.tscn`
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
- Clicking a card emits a selection signal used by the chat view to load the conversation and apply a focused style.

## Chat List Population

- Script: `res://scripts/contact_handler.gd`
- Scene: `res://scenes/main_window.tscn` → node `Chatlist` (a `VBoxContainer`)
- Behavior: On ready, it auto-instances a `contact_card.tscn` for each `*.json` under `res://scripts/chats/`.
	- Sets each instance's exported `chat_json_path` to that file.
	- Inserts them below the `Search_padding2` separator node.
	- Adds an `HSeparator` between entries for spacing.
	- Clears previously added entries on refresh.
	- Sorts alphabetically by filename.
	- Filters by search text (case-insensitive) against the contact display name.

### Adding a New Contact
- Drop a `*.json` file into `res://scripts/chats/` (use the template as a starting point).
- Ensure any avatar path in `profile_icon_path` is a valid Godot resource path (e.g., `res://assets/.../icon.png`).
- Run the scene: entries appear automatically under the search field with separators.

### Consuming Parsed Data
- Provided by `chat_json_view.gd` and available to subclasses:
	- `get_contact_display_name()` → String name.
	- `get_profile_texture()` → `Texture2D` for avatar (may be null if path invalid).
	- `get_chat_history()` → Array of `{ author, text }` dictionaries.
	- `get_last_message_text()` → String last message or empty.
	- Signals: `chat_loaded`, `chat_failed(error)`.

### Reuse in Other UI (e.g., Message Chain)
- Create a new script that extends the base by path: `extends "res://scripts/chat_json_view.gd"`.
- Override `_apply_to_ui()` to bind `contact_name`, `profile_texture`, and `chat_history` into your specific node tree (e.g., generate message bubbles).
- Optionally call `reload_with_path(path)` at runtime to switch conversations.

### Notes
- Paths must be Godot resource paths (e.g. `res://...`).
- If `profile_icon_path` is invalid or not a texture, a warning is logged and avatar will be null.
- Non-array `chat_history` or non-dictionary root will log errors and safely fallback.

---

## Scene Structure

High-level node hierarchies for the provided scenes. This complements the API contracts below so you can quickly wire or extend nodes.

### `scenes/main_window.tscn`

```
Control
├─ ColorRect
└─ MarginContainer
	└─ HSplitContainer
		├─ PanelContainer                        # Left panel (contact list)
		│  └─ ScrollContainer
		│     └─ Chatlist (VBoxContainer)        # Script: scripts/contact_handler.gd
		│        ├─ Search_padding (HSeparator)
		│        ├─ search (LineEdit)
		│        └─ Search_padding2 (HSeparator) # Anchor: cards are inserted after this
		└─ ChatView (PanelContainer)             # Script: scripts/chat_handler.gd
			├─ ScrollContainer
			│  └─ VBoxContainer                   # Messages root (bubble rows are added here)
			├─ Fade (ColorRect)                   # Shader-based overlay
			└─ VBoxContainer
				├─ Profile_icon (TextureRect)      # Avatar set by chat handler
				└─ Message (LineEdit)              # Input field (presentational for now)
```

Expected node paths used by `chat_handler.gd`:
- Messages root: `ChatView/ScrollContainer/VBoxContainer`
- Profile icon: `ChatView/VBoxContainer/Profile_icon`
- Contact list lookup: `../PanelContainer/ScrollContainer/Chatlist` from `ChatView`

### `scenes/contact_card.tscn`

```
Panel (PanelContainer)                    # Script: scripts/contact_card.gd
└─ HBoxContainer
	├─ Icon (TextureRect)
	└─ VBoxContainer
		├─ Name (Label)
		└─ Last_message (Label)
```

`contact_card.gd` binds the avatar, name, and last message into these nodes and emits `contact_selected(chat_path)` on click. Selection styling uses `res://assets/ui/contact_card_focus.tres`.

### `scenes/npc_message_bubble.tscn`

```
npc_message_bubble (MarginContainer)      # Script: scripts/npc_message_bubble.gd
├─ bubble (NinePatchRect)                 # Background texture: assets/ui/npc_message_bubble.png
└─ MarginContainer
	└─ message (RichTextLabel)
```

### `scenes/user_message_bubble.tscn`

```
user_message_bubble (MarginContainer)     # Script: scripts/user_message_bubble.gd
├─ bubble (NinePatchRect)                 # Background texture: assets/ui/user_message_bubble.png
└─ MarginContainer
	└─ message (RichTextLabel)
```

Both bubble scripts size the NinePatch to tightly wrap the text. The chat view adds each bubble inside a horizontal row so left/right alignment doesn’t leave negative space on the opposite side.

## Runtime Architecture and APIs

This section documents the public-facing APIs (exports, signals, and methods) and the expected scene wiring.

### Base class: `ChatJsonView` (res://scripts/chat_json_view.gd)
- Extends: `Control`
- Exported properties:
	- `@export_file("*.json") var chat_json_path: String` — JSON source path. Defaults to the template.
- Signals:
	- `chat_loaded`
	- `chat_failed(error: String)`
- Properties (populated after load):
	- `contact_name: String`
	- `profile_icon_path: String`
	- `profile_texture: Texture2D` (nullable)
	- `chat_history: Array[Dictionary]` with `{ author: String, text: String }`
- Methods:
	- `load_chat_from_json()` — Loads, parses, and emits `chat_loaded` or `chat_failed`.
	- `reload_with_path(new_path: String)` — Sets `chat_json_path` then calls `load_chat_from_json()`.
	- `get_contact_display_name() -> String`
	- `get_profile_texture() -> Texture2D`
	- `get_chat_history() -> Array[Dictionary]`
	- `get_last_message_text() -> String`
	- `_apply_to_ui()` — Intentionally empty; subclasses override to bind parsed data to their UI.

Scene/node contracts expected by subclasses are documented below.

### Contact card: `contact_card.gd` (res://scripts/contact_card.gd)
- Extends: `ChatJsonView`
- Scene: `res://scenes/contact_card.tscn`
- Signals:
	- `contact_selected(chat_path: String)` — Emitted on left click; `chat_path` equals `chat_json_path`.
- Methods:
	- `set_selected(selected: bool)` — Visually marks the card as focused (selected) or default (unselected).
- Selection/focus styling:
	- Selected: applies `res://assets/ui/contact_card_focus.tres` as the panel style.
	- Unselected: restores the default panel style (empty) as set in the editor.
- Input behavior:
	- The root node is a `PanelContainer`. It stops mouse input so `_gui_input` receives clicks.
	- Common child controls are set to pass mouse input so they don’t swallow the click.
	- On left mouse button press, emits `contact_selected(chat_json_path)`.
- Node paths used by `_apply_to_ui()`:
	- Avatar: `HBoxContainer/Icon` (`TextureRect`)
	- Name: `HBoxContainer/VBoxContainer/Name` (`Label`)
	- Last message: `HBoxContainer/VBoxContainer/Last_message` (`Label`)

### Contact list handler: `contact_handler.gd` (res://scripts/contact_handler.gd)
- Extends: `VBoxContainer`
- Responsibilities:
	- Populate the contact list under the `Chatlist` node from JSON files in `res://scripts/chats`.
	- Insert an `HSeparator` between entries.
	- Provide search filtering via the `LineEdit` named `search`.
- Key constants:
	- `CONTACT_CARD_SCENE_PATH := "res://scenes/contact_card.tscn"`
	- `CHATS_DIR := "res://scripts/chats"`
- Important nodes (onready):
	- `_anchor: Node = $Search_padding2` — Items are inserted after this separator.
	- `_search: LineEdit = $search` — Search box; filters by contact display name.
- Behavior:
	- On ready, defers `_populate_contact_list()` to allow the scene tree to settle.
	- For each `*.json` file, instances a card and sets `card.chat_json_path` to that file.
	- Keeps the list stable and clears old instances on refresh.
	- `_filter_contacts()` shows/hides cards and their immediate separators based on the query.

### Chat view handler: `chat_handler.gd` (res://scripts/chat_handler.gd)
- Extends: `ChatJsonView` — The chat view itself binds to parsed data after a selection is made.
- Responsibilities:
	- Connect to `contact_selected` from contact cards in the `Chatlist` and call `reload_with_path(chat_path)`.
	- Apply the avatar to its own `Profile_icon`.
	- Build message bubbles under its own messages container.
	- Manage scrolling to the bottom after layout updates.
	- Toggle visual selection on cards (calls each card’s `set_selected`) so only the clicked card is focused.
- Scenes used for message bubbles:
	- NPC/Contact: `res://scenes/npc_message_bubble.tscn`
	- Player: `res://scenes/user_message_bubble.tscn`
- Node paths expected in `main_window.tscn` under the ChatView:
	- Avatar: `$VBoxContainer/Profile_icon` (`TextureRect`)
	- Scroll container: `$ScrollContainer`
	- Messages root: `$ScrollContainer/VBoxContainer`
- Contact list lookup:
	- Resolves the list node at relative path `../PanelContainer/ScrollContainer/Chatlist` from the ChatView.

### Scene wiring assumptions
- `main_window.tscn` contains:
	- Left panel: `PanelContainer/ScrollContainer/Chatlist` (with `contact_handler.gd` attached to `Chatlist`).
	- Right panel: `ChatView` (with `chat_handler.gd` attached), which finds and connects to the `Chatlist` at runtime.
- `contact_card.tscn` root node is a `PanelContainer` with an `HBoxContainer` child holding the icon and text.

---

## Unlockable Steps (Linear progression)

Jam-scoped linear gating that controls what players can send and how new words are unlocked. Initial `chat_history` renders at load; progression happens through `steps`.

Schema additions in each chat JSON:
- `steps`: Array of steps evaluated in order; no branching and no save system.
	- `expected`: How the player must respond.
		- `text`: exact string match after normalization.
		- `tokens`: array of tokens that must be present; matching controlled by `match`.
		- `alternatives`: array of `expected` objects; any match succeeds.
		- `match`: "exact" | "contains" | "set" (default: "exact").
	- `reject_unknown_words`: bool (default true) — if true, player messages using words not in the global vocabulary are rejected before sending.
	- `on_wrong.npc`: array of strings — NPC fallback lines when input doesn’t match.
	- `on_success.npc`: array of strings — NPC reply when input matches.
	- `on_success.unlock_words`: array of strings — words to add to the global vocabulary immediately upon success.

Matching & vocabulary rules:
- Normalization lowercases and strips punctuation; tokenization accepts alphanumerics plus apostrophes.
- If `reject_unknown_words` is true and the input uses any words not unlocked (or seen from `chat_history`), the message is rejected (no player bubble). Feedback is shown in the UI.
- Steps are strictly linear; wrong inputs do not advance the index.

Example (aligned with the current `scripts/chats/template_chat.json`):

```
{
	"name": "Apple Bot",
	"profile_icon_path": "res://assets/profile_icons/placeholder.png",
	"chat_history": [
		{ "author": "contact", "text": "Welcome. Read carefully and answer using only words you've seen." },
		{ "author": "contact", "text": "Fact: The safe color is green." },
		{ "author": "contact", "text": "Question: What is the safe color?" }
	],
	"steps": [
		{
			"expected": { "tokens": ["green"], "match": "set" },
			"reject_unknown_words": true,
			"on_wrong": { "npc": ["Huh?", "Answer with a word you've seen."] },
			"on_success": {
				"npc": ["Correct.", "Now, ask me for the door code using words you've seen."],
				"unlock_words": ["door", "code"]
			}
		},
		{
			"expected": { "tokens": ["door", "code"], "match": "set" },
			"on_wrong": { "npc": ["That's not it."] },
			"on_success": {
				"npc": ["It's 1234."],
				"unlock_words": ["1234"]
			}
		}
	]
}
```

Authoring tips:
- Keep `chat_history` short so you don’t over-seed vocabulary.
- Put facts in `chat_history` and require players to echo keywords back via `steps`.
- Unlock numeric codes or special terms only after the player asks about them.
- If you want an exploratory step, set `reject_unknown_words: false` for that step only.


## Extending and Reuse
- To build other UI on top of the parsed data, create a script that extends `ChatJsonView` and override `_apply_to_ui()` to bind your nodes.
- You can switch conversations at runtime by calling `reload_with_path(path)`; the base class handles parsing and then calls your `_apply_to_ui()`.

## Troubleshooting
- Clicking a contact doesn’t load the chat:
	- Ensure `contact_card.gd` is attached to the root `PanelContainer` of the card.
	- Verify child nodes use `MOUSE_FILTER_PASS` and the panel uses `MOUSE_FILTER_STOP` (handled automatically in `_ready()`).
	- Confirm `chat_handler.gd` is present on `ChatView` and can find `../PanelContainer/ScrollContainer/Chatlist`.
- Focus style not applied:
	- Ensure `res://assets/ui/contact_card_focus.tres` exists.
	- Confirm the card’s `set_selected(true)` is being called (handled by `chat_handler.gd` on selection).
- Avatar not showing:
	- Check `profile_icon_path` resolves to a `Texture2D` and the resource exists.
- No chats appear:
	- Ensure your JSON files are in `res://scripts/chats/` and end with `.json`.
	- Filenames starting with `.` are ignored.
