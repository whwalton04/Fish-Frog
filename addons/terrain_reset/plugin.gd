@tool
extends EditorPlugin
## Adds "Create Savepoint" and "Reset Terrain" buttons to the 3D editor
## toolbar. A savepoint writes the edited scene's Terrain3D data to disk and
## stages its data directory in the git index. Reset restores that directory
## from the index (the last savepoint, or the last commit if there is none),
## deleting any regions added since, and reloads the scene, discarding unsaved
## changes.

var _savepoint_button: Button
var _button: Button
var _confirm: ConfirmationDialog
var _message: AcceptDialog


func _enter_tree() -> void:
	_savepoint_button = Button.new()
	_savepoint_button.text = "Create Savepoint"
	_savepoint_button.tooltip_text = "Save the terrain and stage it in git, so Reset Terrain returns here."
	_savepoint_button.flat = true
	_savepoint_button.pressed.connect(_create_savepoint)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _savepoint_button)

	_button = Button.new()
	_button.text = "Reset Terrain"
	_button.tooltip_text = "Restore the terrain to the last savepoint (or git commit) and reload the scene."
	_button.flat = true
	_button.pressed.connect(_on_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Reset Terrain"
	_confirm.ok_button_text = "Reset"
	_confirm.confirmed.connect(_reset)
	EditorInterface.get_base_control().add_child(_confirm)

	_message = AcceptDialog.new()
	_message.title = "Terrain"
	EditorInterface.get_base_control().add_child(_message)


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _savepoint_button)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
	_savepoint_button.queue_free()
	_button.queue_free()
	_confirm.queue_free()
	_message.queue_free()


func _on_pressed() -> void:
	var terrain := _find_terrain()
	if not terrain:
		_show("The open scene has no Terrain3D with a data directory.")
		return
	_confirm.dialog_text = "Throw away all changes to %s since the last savepoint (or commit),\nand reload %s without saving?" \
			% [terrain.data_directory, EditorInterface.get_edited_scene_root().scene_file_path]
	_confirm.popup_centered()


func _reset() -> void:
	var terrain := _find_terrain()
	if not terrain:
		return
	var scene_path := EditorInterface.get_edited_scene_root().scene_file_path
	var dir := ProjectSettings.globalize_path(terrain.data_directory)
	if _git(["checkout", "--", dir]) and _git(["clean", "-fq", "--", dir]):
		EditorInterface.reload_scene_from_path(scene_path)


func _create_savepoint() -> void:
	var terrain := _find_terrain()
	if not terrain:
		_show("The open scene has no Terrain3D with a data directory.")
		return
	terrain.data.save_directory(terrain.data_directory)
	var dir := ProjectSettings.globalize_path(terrain.data_directory)
	if _git(["add", "-A", "--", dir]):
		_show("Savepoint created for %s.\nReset Terrain will now return to this state." % terrain.data_directory)


func _git(args: Array) -> bool:
	var output := []
	var repo := ProjectSettings.globalize_path("res://")
	if OS.execute("git", ["-C", repo] + args, output, true) != 0:
		_show("git %s failed:\n%s" % [args[0], "".join(output)])
		return false
	return true


func _find_terrain() -> Terrain3D:
	var root := EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path.is_empty():
		return null
	var found := root.find_children("*", "Terrain3D", true, false)
	if root is Terrain3D:
		found.push_front(root)
	for terrain: Terrain3D in found:
		if not terrain.data_directory.is_empty():
			return terrain
	return null


func _show(text: String) -> void:
	_message.dialog_text = text
	_message.popup_centered()
