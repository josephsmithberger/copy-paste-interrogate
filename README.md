# copy-paste-interrogate

## Game Overview

- Jam: Xogot Game Jam 2 — Theme: “Liquid Glass”
- Visual direction: iMessage-inspired UI, aligning with Apple’s new “Liquid Glass” design language.
- Core concept: Words are keys and items; conversations are the dungeon.
- Rule:### Chat view handler: `chat_handler.gd` (res://scripts/chat_handler.gd)
- Extends: `ChatJsonView` — The chat view itself binds to parsed data after a selection is made.
- Responsibilities:
	- Connect to `contact_selected` from contact cards in the `Chatlist` and call `reload_with_path(chat_path)`.
	- Apply the avatar to its own `Profile_icon`.
	- Build message bubbles under its own messages container.
	- Manage scrolling to the bottom after layout updates (smooth tween-based scrolling).
	- Toggle visual selection on cards (calls each card's `set_selected`) so only the clicked card is focused.
	- Process player input via `DialogueEngine.process_input()` on message submission.
	- Show rejection feedback (red flash) when player uses unknown words.
	- Display tutorial popup on first rejection.
	- Play audio for sent/received messages.
	- Connect to `DialogueEngine.contact_incoming` signal to handle cross-contact notifications.
	- Show toast notifications via `notification.gd` when messages arrive for inactive contacts.
	- Update contact card last message and unread badges via `DialogueEngine.unread_count_changed` signal.
	- Seed vocabulary from pre-step history on load.’t send words the system hasn’t verified yet — you can only use words you’ve seen from other people.
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

### Simplified JSON Schema (Current)
Minimal required fields:
- `name`: String — Contact display name.
- `icon`: String — Resource path to avatar texture.
- `locked`: Boolean (optional) — If true, contact starts locked and won't respond to messages until unlocked via `notify` trigger.
- `chat`: Array — Ordered mix of:
	- String: NPC (contact) line shown immediately at load (pre-seed vocabulary) until the first step object appears.
	- Step object: defines a gating expectation for the player's next input.

Step object keys (all optional except one expectation key):
- `expect`: Exact phrase match (normalized tokens).
- `expect_tokens`: Array of tokens (order-insensitive if `match: "set"`, subset if `match: "contains"`).
- `any_of`: Array of mini step objects (supports alternative expectations).
- `match`: `"exact" | "set" | "contains"` (defaults: `exact` for `expect`, `set` for `expect_tokens`).
- `success`: String or array of NPC lines appended on success (these lines also seed vocabulary).
- `fail`: String or array of NPC lines on mismatch (optional; tokens from fail messages are added to vocabulary based on `DialogueEngine.ADD_FAIL_LINE_TOKENS`).
- `lock`: Boolean (optional) — If true, locks the conversation after this step succeeds (contact stops responding until unlocked).
- `notify`: Array of trigger dictionaries fired after a success. Each entry needs a `chat` path (target contact JSON) and `messages` (string or array) to append to that contact.

Automatic Vocabulary Rule:
All tokens from displayed NPC lines and accepted player inputs become usable immediately in future messages. Players can NEVER use words they haven't seen. No manual `unlock` arrays or `allow_unknown` flags.

### Contact Locking System
Contacts can be locked to gate story progression and force players to interact with multiple contacts:

**Initial Lock State:**
- Set `"locked": true` at the root level of the contact's JSON to start them locked.
- Locked contacts appear in the contact list and can be opened.
- Pre-step messages (strings before first step) are still visible in locked chats.
- When player tries to message a locked contact, input silently clears with no response.

**Mid-Conversation Locking:**
- Add `"lock": true` to any step object to lock the conversation after that step succeeds.
- The contact will display their success messages, then stop responding to further input.
- Useful for creating "waiting" states where the player must talk to someone else to progress.

**Unlocking via Notifications:**
- When a locked contact receives a `notify` trigger from another contact, they automatically unlock.
- The triggered messages appear after a 2-5 second delay (simulating response time).
- Once unlocked, the contact can be interacted with normally.

**Example Flow:**
```json
// Security.json - starts locked
{
  "name": "Security",
  "locked": true,
  "chat": [
    { "expect_tokens": ["green"], "success": "Access granted." }
  ]
}

// Lucy.json - locks after triggering Security
{
  "name": "Lucy",
  "chat": [
    "The safe is green.",
    {
      "expect_tokens": ["security"],
      "success": "I'll contact them for you.",
      "lock": true,
      "notify": [{
        "chat": "res://scripts/chats/Security.json",
        "messages": "Lucy vouched for you. What's the safe color?"
      }]
    }
  ]
}
```
In this example: Security is initially locked. After mentioning "security" to Lucy, she locks herself and triggers Security. Security unlocks and messages the player. Lucy remains locked until potentially unlocked by another contact.

Cross-contact notifications:
- Triggered via the `notify` array on a successful step.
- The Dialogue Engine automatically loads the target contact (if it hasn't been opened yet), appends the supplied messages, and unlocks their vocabulary.
- Contact cards use `unread_message()` / `clear_notifications()` to show or clear the badge, and the main window reuses `error_notification.tscn` to pop a toast preview. Opening the chat (or pressing the toast button) clears the unread state.
- Reference contacts by their JSON path (e.g. `res://scripts/chats/Lucy.json`).
- Example in practice: `Lucy.json` now pings `Security.json` once the player mentions "security clearance," prompting Security to ask for the safe color.

Example (`scripts/chats/template_chat.json`):

```
{
	"name": "Apple Bot",
	"icon": "res://assets/profile_icons/placeholder.png",
	"chat": [
		"Welcome. Read carefully and answer using only words you've seen.",
		"Fact: The safe color is green.",
		"Question: What is the safe color?",
		{ "expect_tokens": ["green"], "match": "set", "success": ["Correct.", "Now ask me for the door code using words you've seen."], "fail": ["Huh?", "Answer using only known words."] },
		{ "expect_tokens": ["door", "code"], "match": "set", "success": "It's 1234.", "fail": "That's not it.", "notify": [{ "chat": "res://scripts/chats/Security.json", "messages": "Security just texted you." }] }
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
- Ensure the `icon` field is a valid Godot resource path (e.g., `res://assets/.../icon.png`).
- Run the scene: entries appear automatically under the search field with separators.

### Consuming Parsed Data
- Provided by `chat_json_view.gd` and available to subclasses:
  - `get_contact_display_name()` → String name.
  - `get_profile_texture()` → `Texture2D` for avatar (may be null if path invalid).
  - `get_chat_history()` → Array of pre-seeded NPC `{ author, text }` dictionaries (only lines before first step).
  - `get_last_message_text()` → String last message or empty.
- Signals: `chat_loaded`, `chat_failed(error)`.
	- Gameplay simplification: Players can NEVER use words they haven't seen. The former `allow_unknown` flag & free-form unlocking have been removed to reduce noise and keep the puzzle focused.
### Reuse in Other UI (e.g., Message Chain)
- Create a new script that extends the base by path: `extends "res://scripts/chat_json_view.gd"`.
	- Keep pre-step NPC lines tight so players discover words in a controlled order.
	- Phrase success lines to introduce only the next required vocabulary.
	- Use `match: "contains"` when allowing polite extras (e.g., "door code please").
	- Avoid injecting large batches of new vocabulary at once; gradual trickle is more readable.
- Paths must be Godot resource paths (e.g. `res://...`).
- If `icon` is invalid or not a texture, a warning is logged and avatar will be null.
- Legacy fields (`profile_icon_path`, `chat_history`, `steps`, `unlock_words`, etc.) are no longer supported. Use only `name`, `icon`, and unified `chat` entries (strings + step objects).

---

## Scene Structure

High-level node hierarchies for the provided scenes. This complements the API contracts below so you can quickly wire or extend nodes.

### `scenes/main_window.tscn`

```
Control
├─ ColorRect
├─ notification (Control)                    # Script: scripts/notification.gd (toast popup)
├─ error_notification (Popup)                 # Tutorial/error popup
│  └─ panel
│     └─ VBoxContainer
│        └─ Button                            # Dismiss button
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
			├─ send_audio (AudioStreamPlayer)     # Sound effect for sending messages
			├─ recieve_audio (AudioStreamPlayer)  # Sound effect for receiving messages
			└─ VBoxContainer
				├─ Profile_icon (TextureRect)      # Avatar set by chat handler
				└─ Message (LineEdit)              # Input field with text_submitted signal
```

Expected node paths used by `chat_handler.gd`:
- Messages root: `ChatView/ScrollContainer/VBoxContainer`
- Profile icon: `ChatView/VBoxContainer/Profile_icon`
- Contact list lookup: `../PanelContainer/ScrollContainer/Chatlist` from `ChatView`

### `scenes/contact_card.tscn`

```
Panel (PanelContainer)                    # Script: scripts/contact_card.gd
└─ HBoxContainer
	├─ notification (Control)                # Badge shown when contact has unread messages
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

## Message Timing & Animation Systems

These systems add natural, human-like timing and visual feedback to NPC responses and cross-contact notifications.

### Dynamic Message Delay System
- **Location**: `chat_handler.gd` → `_append_npc_with_delay()`
- **Purpose**: Makes NPC responses feel more realistic by varying delay based on message length.
- **How it works**:
	- Base delay: Random 0.2-0.6 seconds (simulates "thinking" before typing)
	- Character delay: 15-30ms per character (simulates typing speed)
	- Maximum cap: 2.5 seconds (keeps responses snappy)
	- Formula: `total_delay = min(base_delay + char_delay, 2.5)`
- **Example timings**:
	- Short (10 chars): ~0.35-0.9 seconds
	- Medium (50 chars): ~0.95-2.1 seconds
	- Long (100 chars): ~1.7-2.5 seconds (capped)
- **Customization**: Adjust `randf_range(0.2, 0.6)` for base delay and `randf_range(0.015, 0.03)` for typing speed multiplier.

### Typing Indicator System
- **Location**: `chat_handler.gd` → `_show_typing()` / `_hide_typing()`
- **Scene**: `res://assets/ui/typing_message/typing_message.tscn`
- **Purpose**: Shows animated "..." bubble while NPC is "typing" (during message delay).
- **How it works**:
	1. Before each NPC message delay, typing indicator appears in chat (left-aligned like NPC bubbles)
	2. Indicator plays its built-in animation (bubble + pulsing dots)
	3. After delay completes, indicator is removed and replaced with actual message
	4. Process repeats for each line in multi-line responses
- **Implementation details**:
	- Indicator is wrapped in `HBoxContainer` with spacer for proper alignment
	- Inserted above bottom separator to maintain scroll position
	- Automatically triggers smooth scroll to show indicator
	- Stored in `_typing_row` variable for cleanup

### Cross-Contact Notification Delay
- **Location**: `DialogueEngine.gd` → `_delayed_notification()`
- **Purpose**: Simulates other contacts taking time to read messages and respond.
- **How it works**:
	- When a step's `notify` array triggers messages to another contact
	- Random delay of 2-5 seconds before notification appears
	- Delay applies to:
		- History append (messages won't show in chat until delay completes)
		- Vocabulary unlock (new words unavailable until delay)
		- Unread count increment
		- Toast notification display
- **User experience**: If player switches to notified contact before delay completes, messages haven't arrived yet. They appear after delay, making it feel like the contact is actually responding to events.
- **Customization**: Adjust `randf_range(2.0, 5.0)` in `_delayed_notification()` to change delay range.

### Notification Opacity Effect
- **Location**: `chat_handler.gd` → `_dim_icon()` / `_restore_icon()`
- **Purpose**: Visual feedback that draws attention to incoming notifications from other contacts.
- **How it works**:
	- When toast notification appears: Current contact's profile icon fades to 50% opacity over 0.3 seconds
	- When notification dismissed: Profile icon fades back to 100% opacity over 0.3 seconds
	- Uses sine ease in/out for smooth, natural animation
	- Dismissal triggers:
		- Clicking the notification
		- Switching to the notified contact
		- Notification timeout
- **Implementation**: Tweens the `modulate:a` (alpha) property of `$VBoxContainer/Profile_icon`

### Scroll Behavior Optimization
- **Location**: `chat_handler.gd` → `_defer_scroll_instant()` / `_scroll_smooth()`
- **Purpose**: Different scroll behaviors for different contexts.
- **Modes**:
	- **Instant scroll** (`_defer_scroll_instant()`): When opening/switching contacts
		- No animation, jumps directly to bottom after layout settles
		- Prevents distracting scroll animation during navigation
	- **Smooth scroll** (`_scroll_smooth()`): When sending/receiving messages
		- 0.5 second tween animation (configurable via `scroll_ease_duration`)
		- Sine ease out for natural deceleration
		- Used for player messages, NPC responses, and typing indicator appearance
- **Technical note**: Both modes wait 2 frames for layout/font rendering before scrolling to ensure accurate positioning.

---

## Runtime Architecture and APIs

This section documents the public-facing APIs (exports, signals, and methods) and the expected scene wiring.

### Base class: `ChatJsonView` (res://scripts/chat_json_view.gd)
- Exposes contact identity + pre-step NPC lines only. Steps are handled by `DialogueEngine` from the same `chat` array.
- API unchanged for consuming UI components; internal parsing simplified.

Scene/node contracts expected by subclasses are documented below.

### Contact card: `contact_card.gd` (res://scripts/contact_card.gd)
- Extends: `ChatJsonView`
- Scene: `res://scenes/contact_card.tscn`
- Signals:
	- `contact_selected(chat_path: String)` — Emitted on left click; `chat_path` equals `chat_json_path`.
- Methods:
	- `set_selected(selected: bool)` — Visually marks the card as focused (selected) or default (unselected).
	- `unread_message()` — Shows the notification badge on the card.
	- `clear_notifications()` (or `clear_notifcations()` typo variant) — Hides the notification badge.
	- `refresh_last_message(text_override: String)` — Updates the last message preview text.
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

### Notification system: `notification.gd` (res://scripts/notification.gd)
- Scene: `res://scenes/notification.tscn`
- Purpose: Toast-style popup that appears when messages arrive from contacts not currently open.
- Script: Attached to a `Control` node in `main_window.tscn` (named `notification`).
- Signals:
	- `notification_clicked(chat_path: String)` — Emitted when user clicks the notification; chat_handler uses this to open the contact.
- Methods:
	- `notification_in(profile_path: String, contact_name: String, message_preview: String, chat_path: String)` — Shows toast with contact info and message preview.
	- `notification_out()` — Dismisses the toast with animation.
	- `get_target_chat_path() -> String` — Returns the chat path associated with current notification.
- Behavior:
	- Plays audio (`AudioStreamPlayer`) when notification appears.
	- Auto-dismisses after `Timer` timeout.
	- Clicking notification opens the associated contact and clears unread badge.
- Integration: `chat_handler.gd` connects to `contact_incoming` signal from `DialogueEngine` and calls `notification_in()` when messages arrive for inactive contacts.

### Error/tutorial popup system
- Scene: `res://scenes/error_notification.tscn`
- Purpose: One-time tutorial popup that appears when player first tries to use unknown words.
- Node: `error_notification` (`Popup`) in `main_window.tscn`.
- Behavior:
	- `chat_handler.gd` shows this popup via `_maybe_show_tutorial_popup()` on first rejection.
	- Dismissed via button press; never shown again (`_tutorial_popup_shown` flag).
	- Explains the core mechanic: "You can only use words you've seen."

### Audio system
- `chat_handler.gd` includes two audio players:
	- `send_audio`: Plays when player sends a message (`assets/ui/audio/send.mp3`).
	- `recieve_audio`: Plays when NPC messages appear (`assets/ui/audio/recieve.mp3`).
- `notification.gd` includes `AudioStreamPlayer` for notification sound (`assets/ui/audio/notification.mp3`).

### Scene wiring assumptions
- `main_window.tscn` contains:
	- Left panel: `PanelContainer/ScrollContainer/Chatlist` (with `contact_handler.gd` attached to `Chatlist`).
	- Right panel: `ChatView` (with `chat_handler.gd` attached), which finds and connects to the `Chatlist` at runtime.
	- Toast notification: `notification` (`Control` with `notification.gd`).
	- Tutorial popup: `error_notification` (`Popup`).
- `contact_card.tscn` root node is a `PanelContainer` with an `HBoxContainer` child holding the notification badge, icon, and text.

---

### Vocabulary Autoload: `Vocabulary.gd` (res://scripts/autoloads/Vocabulary.gd)
- Purpose: Global singleton that tracks all words the player has seen and can use.
- Autoload name: `Vocabulary` (accessible via `/root/Vocabulary`)
- API:
	- `tokenize(text: String) -> PackedStringArray` — Breaks text into lowercase alphanumeric tokens (allows apostrophes).
	- `add_words(words: Array) -> void` — Adds new words/phrases to vocabulary (automatically tokenizes).
	- `contains(word: String) -> bool` — Checks if a single word is in vocabulary.
	- `has_all(tokens: Array) -> bool` — Checks if all tokens in array are known.
	- `all_words() -> PackedStringArray` — Returns sorted list of all known words.
	- `clear_all() -> void` — Resets vocabulary (useful for new game).
- Signals:
	- `words_unlocked(new_words: PackedStringArray)` — Emitted when new words are added.
- Integration: DialogueEngine automatically calls `add_words()` for displayed NPC messages and accepted player inputs.

### Dialogue Engine Autoload: `DialogueEngine.gd` (res://scripts/autoloads/DialogueEngine.gd)
- Purpose: Manages conversation state, step progression, vocabulary validation, and contact locking for all contacts.
- Autoload name: `DialogueEngine` (accessible via `/root/DialogueEngine`)
- Constants:
	- `ADD_FAILED_PLAYER_TOKENS := false` — If true, adds tokens from rejected player inputs to vocabulary.
	- `ADD_FAIL_LINE_TOKENS := true` — If true, adds tokens from step `fail` messages to vocabulary.
- Key methods:
	- `load_conversation(contact_id: String, data: Dictionary, force: bool)` — Loads/reloads a contact's chat data.
	- `process_input(contact_id: String, player_text: String) -> Dictionary` — Validates player input against current step.
	- `get_history(contact_id: String) -> Array` — Returns full message history for a contact.
	- `get_unread_count(contact_id: String) -> int` — Returns unread message count.
	- `clear_unread(contact_id: String) -> void` — Clears unread count for a contact.
	- `is_locked(contact_id: String) -> bool` — Returns whether a contact is currently locked.
- Signals:
	- `contact_incoming(contact_id: String, messages: PackedStringArray, source_contact_id: String)` — Fired when a contact sends messages via `notify` trigger.
	- `unread_count_changed(contact_id: String, unread_count: int)` — Fired when unread count changes.
	- `lock_state_changed(contact_id: String, is_locked: bool)` — Fired when a contact's lock state changes.
- Return format for `process_input()`:
	- `status`: `"rejected"` (unknown words), `"wrong"` (known words but incorrect), `"locked"` (contact is locked), or `"success"`
	- `unknown_words`: Array of tokens player used that aren't in vocabulary
	- `npc_messages`: Array of NPC response lines
	- `step_index`: Current step index after processing
	- `triggered`: Array of notification triggers that fired

### Linear Steps (Integrated into `chat`)
Each dictionary entry inside `chat` is a step defining the acceptable player response. Vocabulary accrues automatically from every displayed NPC line and accepted player input. No explicit unlock arrays.

Authoring tips:
- Keep pre-step NPC lines tight so players discover words in a controlled order.
- Phrase success lines to introduce only the next required vocabulary.
- Use `match: "contains"` when allowing polite extras (e.g., "door code please").
- Fail messages can introduce new vocabulary if `DialogueEngine.ADD_FAIL_LINE_TOKENS` is true (default).


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
	- Check `icon` resolves to a `Texture2D` and the resource exists.
- No chats appear:
	- Ensure your JSON files are in `res://scripts/chats/` and end with `.json`.
	- Filenames starting with `.` are ignored.
