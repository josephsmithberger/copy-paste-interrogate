# Dialogue Import System

## How It Works

The dialogue import system allows players to create and import custom dialogues from your web editor at josephsmithberger.com/dialogue_editor.

### For Web Builds (itch.io)

When running on the web:
- Uses JavaScript file input (HTML5 file picker) instead of Godot's FileDialog
- Files are stored in the browser's `user://chats/` directory (persistent browser storage)
- The game automatically detects if custom dialogues exist and uses them instead of default dialogues

### For Native Builds (Desktop)

When running natively:
- Uses Godot's native FileDialog
- Files are stored in `res://scripts/chats/`
- Standard file system operations

## How Players Use It

1. Visit josephsmithberger.com/dialogue_editor
2. Create custom dialogue using the editor
3. Export as JSON file(s)
4. In the game, access the import screen (you need to add this to your menu)
5. Click "Select JSON Files" and choose their exported files
6. Click "Import Dialogues"
7. The game deletes all existing dialogues and imports the new ones
8. The game automatically reloads with the new dialogues

## Implementation Details

### Files Modified

- `scenes/dialogue_import.tscn` - UI for the import screen
- `scripts/dialogue_import.gd` - Handles file selection and import logic
- `scripts/contact_handler.gd` - Checks for custom dialogues in web builds

### Key Features

- **Cross-platform**: Works on both web (itch.io) and native builds
- **JSON validation**: Checks that imported files are valid JSON
- **Clean slate**: Deletes all existing dialogues before importing
- **Vocabulary reset**: Clears player vocabulary when new dialogues are loaded
- **User feedback**: Shows status messages throughout the process

## TODO: Add Import to Main Menu

You'll need to add a button to your main window or create a menu system that allows players to access the `dialogue_import.tscn` scene. For example:

```gdscript
# In your main menu or settings
func _on_import_dialogues_pressed():
    get_tree().change_scene_to_file("res://scenes/dialogue_import.tscn")
```
