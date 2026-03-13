@tool
extends EditorPlugin

var dock: Control


func _enter_tree() -> void:
	var DockScript = preload("res://addons/github_classroom/github_classroom_dock.gd")
	dock = DockScript.new()
	dock.name = "GitHubClassroom"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	# Attempt auto-push on close if the user configured it.
	if dock and dock.has_method("_on_editor_close"):
		dock._on_editor_close()
	remove_control_from_docks(dock)
	if dock:
		dock.queue_free()
		dock = null


func _save_external_data() -> void:
	# Trigger auto-push on save if the user configured it.
	if dock and dock.has_method("_on_editor_save"):
		dock._on_editor_save()
