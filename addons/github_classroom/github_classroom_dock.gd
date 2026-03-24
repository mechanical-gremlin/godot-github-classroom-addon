@tool
extends Control
## Editor dock panel for the GitHub Classroom addon.
##
## Provides a simple UI so students can pull and push their Godot projects
## to a GitHub Classroom repository without ever touching the command line.

# CONFIG_PATH is now per-OS-user; see _get_config_path() below.

# Directories to skip when scanning/downloading project files.
const EXCLUDED_DIRS := [".godot", ".git"]

# Individual file names to always skip.
const EXCLUDED_FILES := [".DS_Store", "Thumbs.db", "ehthumbs.db", "Desktop.ini"]

# Hint shown when a 403 permission error is detected during push.
const TOKEN_PERMISSION_HINT := "[color=yellow]A 403 error means your token does not have write permission. " \
	+ "If your repository is in an organization (e.g. GitHub Classroom), try using a " \
	+ "classic token with the 'repo' scope instead of a fine-grained token. " \
	+ "See the README for details.[/color]"

# Auto-push mode constants.
const AUTO_PUSH_MANUAL := 0
const AUTO_PUSH_ON_SAVE := 1
const AUTO_PUSH_ON_CLOSE := 2

# --- UI references ---
var _role_option: OptionButton
var _org_input: LineEdit
var _repo_url_input: LineEdit
var _token_input: LineEdit
var _branch_input: LineEdit
var _auto_push_option: OptionButton
var _save_button: Button
var _sign_out_button: Button
var _load_repos_button: Button
var _repo_tree: Tree
var _commit_msg_input: TextEdit
var _pull_button: Button
var _push_button: Button
var _status_label: RichTextLabel
var _progress_bar: ProgressBar
var _advanced_toggle: CheckButton
var _connected_label: Label
var _last_saved_label: Label
var _advanced_nodes: Array = []
var _pull_confirm_dialog: ConfirmationDialog
var _auto_push_mode_label: Label
var _clean_pull_button: Button
var _clean_pull_confirm_dialog: ConfirmationDialog

# --- API node ---
var _api: Node

# --- State ---
var _github_username: String = ""
var _is_pushing: bool = false
var _loaded_repos: Array = []
var _config_load_error: bool = false


# ===========================================================================
# Lifecycle
# ===========================================================================

func _ready() -> void:
	_build_ui()
	_setup_api()
	_load_settings()
	# Connect token-change signal after loading so it does not fire during init.
	_token_input.text_changed.connect(_on_token_changed)
	# Show a context-appropriate status message on startup.
	if _config_load_error:
		_set_status("⚠️ [color=yellow]Settings file could not be read and has been reset. Please re-enter your settings and click Save Settings.[/color]")
	elif _token_input.text.strip_edges().is_empty():
		_set_status("ℹ️ Welcome! Enter your GitHub Token and Organization above, then click Save Settings and Load My Assignments.")


# ===========================================================================
# UI Construction
# ===========================================================================

func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 0)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# ---- Settings section ----
	_add_section_header(vbox, "Settings")

	_advanced_toggle = CheckButton.new()
	_advanced_toggle.text = "Show Advanced Options"
	_advanced_toggle.tooltip_text = "Show extra settings like Role, Branch, and Repository URL."
	_advanced_toggle.toggled.connect(_on_advanced_toggle_changed)
	vbox.add_child(_advanced_toggle)

	var role_label := _add_label(vbox, "Role:")
	_role_option = OptionButton.new()
	_role_option.add_item("Student", 0)
	_role_option.add_item("Teacher", 1)
	_role_option.tooltip_text = "Select your role. Teachers can view all student repositories in the organization."
	_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_role_option)
	_advanced_nodes.append_array([role_label, _role_option])

	_add_label(vbox, "Organization:")
	_org_input = _add_line_edit(vbox, "github-classroom-org")
	_org_input.tooltip_text = "Your GitHub Classroom organization name. Used with Load My Assignments to browse assignments."

	var repo_url_label := _add_label(vbox, "Repository URL:")
	_repo_url_input = _add_line_edit(vbox, "https://github.com/owner/repo")
	_repo_url_input.tooltip_text = "Paste the repository link from GitHub Classroom here, or select one from the Classroom section below."
	_advanced_nodes.append_array([repo_url_label, _repo_url_input])

	_add_label(vbox, "GitHub Token:")
	_token_input = _add_line_edit(vbox, "ghp_xxxxxxxxxxxx")
	_token_input.secret = true
	_token_input.tooltip_text = "Your GitHub Personal Access Token (starts with ghp_ or github_pat_)."

	var branch_label := _add_label(vbox, "Branch:")
	_branch_input = _add_line_edit(vbox, "main")
	_branch_input.text = "main"
	_branch_input.tooltip_text = "Usually 'main'. Only change this if your teacher tells you to."
	_advanced_nodes.append_array([branch_label, _branch_input])

	var auto_push_label := _add_label(vbox, "Auto-Push:")
	_auto_push_option = OptionButton.new()
	_auto_push_option.add_item("Auto-Push on Save", AUTO_PUSH_ON_SAVE)
	_auto_push_option.add_item("Manual Only", AUTO_PUSH_MANUAL)
	_auto_push_option.add_item("Auto-Push on Close", AUTO_PUSH_ON_CLOSE)
	_auto_push_option.tooltip_text = "Automatically push changes when saving the project or closing the editor."
	_auto_push_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_auto_push_option)
	_auto_push_option.item_selected.connect(_on_auto_push_option_changed)
	_advanced_nodes.append_array([auto_push_label, _auto_push_option])

	_save_button = Button.new()
	_save_button.text = "Save Settings"
	_save_button.pressed.connect(_on_save_pressed)
	vbox.add_child(_save_button)

	_sign_out_button = Button.new()
	_sign_out_button.text = "🔒 Sign Out / Clear Credentials"
	_sign_out_button.tooltip_text = "Clear your token and repository URL before logging out of this computer."
	_sign_out_button.pressed.connect(_on_sign_out_pressed)
	vbox.add_child(_sign_out_button)

	vbox.add_child(HSeparator.new())

	# ---- Classroom section ----
	_add_section_header(vbox, "Classroom")

	_load_repos_button = Button.new()
	_load_repos_button.text = "Load My Assignments"
	_load_repos_button.tooltip_text = "Load repositories from your GitHub Classroom organization. Requires token and organization name."
	_load_repos_button.pressed.connect(_on_load_repos_pressed)
	vbox.add_child(_load_repos_button)

	_repo_tree = Tree.new()
	_repo_tree.custom_minimum_size = Vector2(0, 100)
	_repo_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repo_tree.hide_root = true
	_repo_tree.item_selected.connect(_on_repo_tree_selected)
	_repo_tree.tooltip_text = "Select a repository to auto-fill the Repository URL above."
	vbox.add_child(_repo_tree)

	vbox.add_child(HSeparator.new())

	# ---- Sync section ----
	_add_section_header(vbox, "Sync")

	var commit_msg_label := _add_label(vbox, "Commit Message (optional):")
	_commit_msg_input = TextEdit.new()
	_commit_msg_input.placeholder_text = "Optional – auto-generates if left blank."
	_commit_msg_input.tooltip_text = "Write a short description of your changes, or leave blank for a default message with the current date and time."
	_commit_msg_input.custom_minimum_size = Vector2(0, 60)
	_commit_msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_commit_msg_input)
	_advanced_nodes.append_array([commit_msg_label, _commit_msg_input])

	_connected_label = Label.new()
	_connected_label.text = "Not connected — load your assignments above."
	_connected_label.add_theme_color_override("font_color", Color.GRAY)
	_connected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_connected_label)

	var btn_row := HBoxContainer.new()
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(btn_row)

	_pull_button = Button.new()
	_pull_button.text = "⬇ Download Latest (Pull)"
	_pull_button.tooltip_text = "Download the latest version of your project from GitHub. (Git: Pull)"
	_pull_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pull_button.pressed.connect(_on_pull_pressed)
	btn_row.add_child(_pull_button)

	_push_button = Button.new()
	_push_button.text = "⬆ Save to GitHub (Push)"
	_push_button.tooltip_text = "Save your work to GitHub. (Git: Push)"
	_push_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_push_button.pressed.connect(_on_push_pressed)
	btn_row.add_child(_push_button)

	_last_saved_label = Label.new()
	_last_saved_label.text = ""
	_last_saved_label.add_theme_color_override("font_color", Color.GRAY)
	_last_saved_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_last_saved_label)

	_auto_push_mode_label = Label.new()
	_auto_push_mode_label.text = ""
	_auto_push_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_auto_push_mode_label)

	_clean_pull_button = Button.new()
	_clean_pull_button.text = "🗑️ Clean Pull (Replace All Files)"
	_clean_pull_button.tooltip_text = "Delete all local project files (keeping the addons folder) and download a fresh copy from GitHub. Use this when grading or switching student projects."
	_clean_pull_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clean_pull_button.pressed.connect(_on_clean_pull_pressed)
	vbox.add_child(_clean_pull_button)
	_advanced_nodes.append(_clean_pull_button)

	vbox.add_child(HSeparator.new())

	# ---- Progress / Status section ----
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 20)
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)

	_add_section_header(vbox, "Status")

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.custom_minimum_size = Vector2(0, 80)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_label.scroll_following = true
	vbox.add_child(_status_label)

	_set_status("[color=gray]Ready. Configure your settings above to get started.[/color]")

	# Pull confirmation dialog.
	_pull_confirm_dialog = ConfirmationDialog.new()
	_pull_confirm_dialog.title = "Download Latest Version?"
	_pull_confirm_dialog.dialog_text = "Downloading will replace your local project files with the latest version from GitHub.\n\nYour pushed work on GitHub is always safe.\n\nContinue?"
	_pull_confirm_dialog.ok_button_text = "Yes, Download"
	_pull_confirm_dialog.confirmed.connect(_on_pull_confirmed)
	add_child(_pull_confirm_dialog)

	# Clean pull confirmation dialog (destructive – stronger warning).
	_clean_pull_confirm_dialog = ConfirmationDialog.new()
	_clean_pull_confirm_dialog.title = "Replace All Project Files?"
	_clean_pull_confirm_dialog.dialog_text = "This will DELETE all local project files (except the addons folder) and replace them with the latest version from GitHub.\n\nFiles that have NOT been pushed to GitHub will be permanently lost.\n\nThis cannot be undone. Continue?"
	_clean_pull_confirm_dialog.ok_button_text = "Yes, Replace All Files"
	_clean_pull_confirm_dialog.confirmed.connect(_on_clean_pull_confirmed)
	add_child(_clean_pull_confirm_dialog)

	# Initially hide all advanced nodes (simple mode by default).
	for node in _advanced_nodes:
		node.visible = false


# Small helpers to reduce repetition when building the UI.

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	parent.add_child(HSeparator.new())


func _add_label(parent: VBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _add_line_edit(parent: VBoxContainer, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit


# ===========================================================================
# API setup
# ===========================================================================

func _setup_api() -> void:
	var APIScript = preload("res://addons/github_classroom/github_api.gd")
	_api = APIScript.new()
	_api.name = "GitHubAPI"
	add_child(_api)


# ===========================================================================
# Per-OS-user config path helpers
# ===========================================================================

## Return the raw OS-level desktop username (empty string if unavailable).
func _get_os_username() -> String:
	var os_user := OS.get_environment("USERNAME")  # Windows
	if os_user.is_empty():
		os_user = OS.get_environment("USER")       # macOS / Linux
	return os_user


## Return a config-file path unique to the current OS-level desktop user.
## This prevents Student A's token from loading when Student B logs in.
func _get_config_path() -> String:
	var os_user := _get_os_username()
	if os_user.is_empty():
		os_user = "default"
	# Sanitize: keep only alphanumeric and underscore characters.
	var safe_user := ""
	for ch in os_user:
		if (ch >= "0" and ch <= "9") or \
		   (ch >= "A" and ch <= "Z") or \
		   (ch >= "a" and ch <= "z") or \
		   ch == "_":
			safe_user += ch
		else:
			safe_user += "_"
	if safe_user.is_empty():
		safe_user = "default"
	return "user://github_classroom_" + safe_user + ".cfg"


# ===========================================================================
# Token obfuscation helpers (XOR keyed to the OS username)
# ===========================================================================

## XOR-obfuscate a token string so it is not stored as visible plaintext.
## This is defense-in-depth, not true encryption.
## Each byte is XOR'd with the key, and the result is encoded as lowercase hex pairs.
func _obfuscate_token(token: String) -> String:
	var key := _get_os_username()
	if key.is_empty():
		key = "godot_classroom_key"
	var result := ""
	for i in range(token.length()):
		var t_byte := token.unicode_at(i)
		var k_byte := key.unicode_at(i % key.length())
		result += "%02x" % (t_byte ^ k_byte)
	return result


## Reverse _obfuscate_token(). Expects lowercase hex pairs produced by _obfuscate_token().
func _deobfuscate_token(obfuscated: String) -> String:
	var key := _get_os_username()
	if key.is_empty():
		key = "godot_classroom_key"
	var result := ""
	for i in range(0, obfuscated.length(), 2):
		var hex_pair := obfuscated.substr(i, 2)
		var t_byte := hex_pair.hex_to_int()
		var key_idx := (i / 2) % key.length()
		var k_byte := key.unicode_at(key_idx)
		result += char(t_byte ^ k_byte)
	return result


# ===========================================================================
# Settings persistence
# ===========================================================================

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("github", "repo_url", _repo_url_input.text)
	config.set_value("github", "token_v2", _obfuscate_token(_token_input.text))
	config.set_value("github", "branch", _branch_input.text)
	config.set_value("github", "role", _role_option.selected)
	config.set_value("github", "organization", _org_input.text)
	config.set_value("github", "auto_push", _auto_push_option.get_selected_id())
	config.set_value("github", "advanced_mode", _advanced_toggle.button_pressed)
	config.save(_get_config_path())


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_get_config_path()) == OK:
		_repo_url_input.text = config.get_value("github", "repo_url", "")
		# Load token: prefer obfuscated token_v2; migrate plaintext token if present.
		if config.has_section_key("github", "token_v2"):
			_token_input.text = _deobfuscate_token(config.get_value("github", "token_v2", ""))
		elif config.has_section_key("github", "token"):
			# Migrate old plaintext token to obfuscated format.
			var plain := config.get_value("github", "token", "")
			_token_input.text = plain
			config.set_value("github", "token_v2", _obfuscate_token(plain))
			config.erase_section_key("github", "token")
			config.save(_get_config_path())
		_branch_input.text = config.get_value("github", "branch", "main")
		_role_option.selected = config.get_value("github", "role", 0)
		_org_input.text = config.get_value("github", "organization", "")
		# Load auto_push by ID so reordered items work correctly.
		# The saved integer values (0=Manual, 1=OnSave, 2=OnClose) match the
		# AUTO_PUSH_* constants exactly, so this is also backward-compatible
		# with config files written before the dropdown was reordered.
		var auto_push_id: int = config.get_value("github", "auto_push", AUTO_PUSH_ON_SAVE)
		for i in range(_auto_push_option.item_count):
			if _auto_push_option.get_item_id(i) == auto_push_id:
				_auto_push_option.selected = i
				break
		var advanced_mode: bool = config.get_value("github", "advanced_mode", false)
		_advanced_toggle.button_pressed = advanced_mode
		_apply_advanced_mode(advanced_mode)
		_update_connected_label()
		_update_auto_push_mode_label()
	elif FileAccess.file_exists(_get_config_path()):
		# Config file exists but could not be parsed (possibly corrupt).
		_config_load_error = true


# ===========================================================================
# Validation helpers
# ===========================================================================

## Parse a GitHub URL into {"owner": ..., "repo": ...}. Returns {} on failure.
## This is a pure parsing function — it does not update the status label.
func _parse_repo_url(url: String) -> Dictionary:
	url = url.strip_edges().trim_suffix(".git").trim_suffix("/")
	if url.begins_with("https://"):
		url = url.substr(8)
	elif url.begins_with("http://"):
		return {}
	if url.begins_with("github.com/"):
		url = url.substr(11)
	var parts := url.split("/")
	if parts.size() >= 2 and not parts[0].is_empty() and not parts[1].is_empty():
		return {"owner": parts[0], "repo": parts[1]}
	return {}


## Validate inputs and configure the API node. Returns true on success.
func _configure_api() -> bool:
	var raw_url := _repo_url_input.text.strip_edges()
	# Reject insecure http:// URLs with a clear message before any parsing.
	if raw_url.begins_with("http://"):
		_set_status("❌ [color=red]Insecure URL (http://) is not allowed. Use https://github.com/owner/repo.[/color]")
		return false
	var info := _parse_repo_url(raw_url)
	if info.is_empty():
		_set_status("❌ [color=red]Invalid repository URL. Use the format: https://github.com/owner/repo[/color]")
		return false
	if _token_input.text.strip_edges().is_empty():
		_set_status("❌ [color=red]Please enter your GitHub token.[/color]")
		return false
	var branch := _branch_input.text.strip_edges()
	if branch.is_empty():
		branch = "main"
	_api.setup(_token_input.text.strip_edges(), info.owner, info.repo, branch)
	return true


# ===========================================================================
# Status display
# ===========================================================================

func _set_status(bbcode: String) -> void:
	_status_label.clear()
	_status_label.append_text(bbcode)


func _append_status(bbcode: String) -> void:
	_status_label.append_text("\n" + bbcode)


func _set_buttons_enabled(enabled: bool) -> void:
	_pull_button.disabled = not enabled
	_push_button.disabled = not enabled
	_save_button.disabled = not enabled
	_sign_out_button.disabled = not enabled
	_load_repos_button.disabled = not enabled


# ===========================================================================
# Button callbacks
# ===========================================================================

func _on_save_pressed() -> void:
	_save_settings()
	_set_status("✅ [color=green]Settings saved![/color]")
	_update_connected_label()
	_update_auto_push_mode_label()


func _on_pull_pressed() -> void:
	if not _configure_api():
		return
	_pull_confirm_dialog.popup_centered()


func _on_pull_confirmed() -> void:
	_set_buttons_enabled(false)
	await _do_pull()
	_set_buttons_enabled(true)


func _on_push_pressed() -> void:
	if not _configure_api():
		return
	_save_settings()
	_is_pushing = true
	_set_buttons_enabled(false)
	await _do_push()
	_set_buttons_enabled(true)
	_is_pushing = false


func _on_load_repos_pressed() -> void:
	var token := _token_input.text.strip_edges()
	if token.is_empty():
		_set_status("❌ [color=red]Please enter your GitHub token.[/color]")
		return
	var org := _org_input.text.strip_edges()
	if org.is_empty():
		_set_status("❌ [color=red]Please enter your GitHub Classroom organization name.[/color]")
		return
	# Set token for API calls (owner/repo not needed for org/user endpoints).
	_api.setup(token, "", "", "")
	_set_buttons_enabled(false)
	await _do_load_repos(org)
	_set_buttons_enabled(true)


func _on_repo_tree_selected() -> void:
	var selected := _repo_tree.get_selected()
	if selected == null:
		return
	var meta = selected.get_metadata(0)
	if meta is int and meta >= 0 and meta < _loaded_repos.size():
		var repo: Dictionary = _loaded_repos[meta]
		_repo_url_input.text = "https://github.com/" + repo.owner + "/" + repo.name
		_set_status("✅ [color=green]Selected: " + str(repo.name) + "[/color]")
		_update_connected_label()


## Clear repo list, repo URL, and username whenever the token is manually edited.
## This prevents a previous student's data from remaining visible after a logout.
## The _new_text parameter is intentionally unused — we act on the change event
## itself, not the value (callers can inspect _token_input.text directly).
func _on_token_changed(_new_text: String) -> void:
	_loaded_repos.clear()
	_repo_tree.clear()
	_repo_url_input.text = ""
	_github_username = ""
	_update_connected_label()


## Sign out: wipe all credentials from the UI and persist the cleared state.
func _on_sign_out_pressed() -> void:
	_token_input.text = ""
	_org_input.text = ""
	_repo_url_input.text = ""
	_role_option.selected = 0
	_loaded_repos.clear()
	_repo_tree.clear()
	_github_username = ""
	_save_settings()
	_set_status("🔒 Signed out. Enter your GitHub Token to get started.")
	_update_connected_label()


func _on_clean_pull_pressed() -> void:
	if not _configure_api():
		return
	_clean_pull_confirm_dialog.popup_centered()


func _on_clean_pull_confirmed() -> void:
	_set_buttons_enabled(false)
	await _do_clean_pull()
	_set_buttons_enabled(true)


## Called when the Auto-Push dropdown selection changes.
func _on_auto_push_option_changed(_index: int) -> void:
	_update_auto_push_mode_label()


# ===========================================================================
# Pull logic
# ===========================================================================

func _do_pull() -> void:
	_set_status("⏳ [color=yellow]Downloading from GitHub...[/color]")
	_progress_bar.visible = true
	_progress_bar.value = 0

	# 1 – Get branch info (latest commit + tree SHA).
	_append_status("⏳ Getting latest version...")
	var branch_result: Dictionary = await _api.get_branch()
	if branch_result.has("error"):
		_append_status("❌ [color=red]Error: " + str(branch_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	var tree_sha: String = branch_result.data.commit.commit.tree.sha

	# 2 – Get full recursive tree.
	_append_status("⏳ Getting file list...")
	var tree_result: Dictionary = await _api.get_git_tree(tree_sha)
	if tree_result.has("error"):
		_append_status("❌ [color=red]Error: " + str(tree_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	# Filter to blobs only, skip excluded directories.
	var files: Array = []
	for item in tree_result.data.tree:
		if item.type != "blob":
			continue
		if _is_path_excluded(item.path):
			continue
		files.append(item)

	if files.is_empty():
		_append_status("⚠️ [color=yellow]The repository has no downloadable files.[/color]")
		_progress_bar.visible = false
		return

	_append_status("⏳ Downloading " + str(files.size()) + " files...")

	# 3 – Download each blob and write to disk.
	var project_path: String = ProjectSettings.globalize_path("res://")
	var downloaded: int = 0
	var errors: int = 0

	for i in range(files.size()):
		var file_info: Dictionary = files[i]
		_progress_bar.value = float(i + 1) / float(files.size()) * 100.0

		var blob_result: Dictionary = await _api.get_blob(file_info.sha)
		if blob_result.has("error"):
			_append_status("❌ [color=red]  Failed: " + file_info.path + " – " + str(blob_result.error) + "[/color]")
			errors += 1
			continue

		var file_path: String = project_path.path_join(file_info.path)
		var dir_path: String = file_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)

		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_buffer(blob_result.content)
			file.close()
			downloaded += 1
		else:
			_append_status("❌ [color=red]  Could not write: " + file_info.path + "[/color]")
			errors += 1

	_progress_bar.visible = false
	if errors == 0:
		_append_status("✅ [color=green]Download complete! Downloaded " + str(downloaded) + " files.[/color]")
	else:
		_append_status("⚠️ [color=yellow]Download finished with " + str(errors) + " error(s). Downloaded " + str(downloaded) + " files.[/color]")

	# Refresh the Godot editor so it sees the new/changed files.
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


# ===========================================================================
# Push logic
# ===========================================================================

func _do_push() -> void:
	var message := _commit_msg_input.text.strip_edges()
	if message.is_empty():
		var dt := Time.get_datetime_dict_from_system()
		message = "Update project files – %04d-%02d-%02d %02d:%02d:%02d" % [
			dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
		]

	_set_status("⏳ [color=yellow]Saving to GitHub...[/color]")
	_progress_bar.visible = true
	_progress_bar.value = 0

	# 1 – Get branch HEAD. A 404 means the repo/branch has no commits yet.
	_append_status("⏳ Getting current version...")
	var branch_result: Dictionary = await _api.get_branch()
	var is_first_commit := false
	var head_sha := ""
	var base_tree_sha := ""

	if branch_result.has("error"):
		if "404" in str(branch_result.error):
			is_first_commit = true
			_append_status("ℹ️ No existing commits found – this will be the first commit.")
		else:
			_append_status("❌ [color=red]Error: " + str(branch_result.error) + "[/color]")
			_progress_bar.visible = false
			return
	else:
		head_sha = branch_result.data.commit.sha
		base_tree_sha = branch_result.data.commit.commit.tree.sha

	# 2 – Build a map of remote file SHAs for comparison.
	var remote_files: Dictionary = {}
	if not base_tree_sha.is_empty():
		_append_status("⏳ Comparing files...")
		var remote_tree_result: Dictionary = await _api.get_git_tree(base_tree_sha)
		if not remote_tree_result.has("error"):
			for item in remote_tree_result.data.tree:
				if item.type == "blob":
					remote_files[item.path] = item.sha

	# 3 – Scan local project files.
	var project_path: String = ProjectSettings.globalize_path("res://")
	var local_files: Array = _scan_project_files(project_path, "")

	if local_files.is_empty():
		_append_status("⚠️ [color=yellow]No files found to push.[/color]")
		_progress_bar.visible = false
		return

	# 4 – Compare each local file, upload blobs only for changed/new files.
	_append_status("⏳ Checking " + str(local_files.size()) + " files for changes...")
	var tree_entries: Array = []
	var changed_count: int = 0
	var upload_errors: int = 0
	var had_permission_error := false

	for i in range(local_files.size()):
		var rel_path: String = local_files[i]
		_progress_bar.value = float(i + 1) / float(local_files.size()) * 50.0

		var full_path: String = project_path.path_join(rel_path)
		var content: PackedByteArray = FileAccess.get_file_as_bytes(full_path)
		if content.is_empty() and FileAccess.get_open_error() != OK:
			_append_status("❌ [color=red]  Could not read: " + rel_path + "[/color]")
			continue

		var local_sha: String = _compute_git_blob_sha(content)

		if remote_files.has(rel_path) and remote_files[rel_path] == local_sha:
			# Unchanged – reuse the existing SHA (no upload needed).
			tree_entries.append({"path": rel_path, "mode": "100644", "type": "blob", "sha": local_sha})
		else:
			# New or modified – upload the blob.
			var blob_result: Dictionary = await _api.create_blob(content)
			if blob_result.has("error"):
				var err_msg: String = str(blob_result.error)
				_append_status("❌ [color=red]  Upload failed: " + rel_path + " – " + err_msg + "[/color]")
				if "403" in err_msg:
					had_permission_error = true
				upload_errors += 1
				continue
			tree_entries.append({"path": rel_path, "mode": "100644", "type": "blob", "sha": blob_result.data.sha})
			changed_count += 1

	if upload_errors > 0:
		_append_status("❌ [color=red]Push failed: " + str(upload_errors) + " file(s) could not be uploaded.[/color]")
		if had_permission_error:
			_append_status(TOKEN_PERMISSION_HINT)
		_progress_bar.visible = false
		return

	if changed_count == 0 and not is_first_commit:
		_append_status("✅ [color=green]No changes to push. Everything is up to date![/color]")
		_progress_bar.visible = false
		return

	_append_status("⏳ Creating commit with " + str(changed_count) + " changed file(s)...")
	_progress_bar.value = 70.0

	# 5 – Create a brand-new tree (no base_tree so deletions are captured).
	var tree_result: Dictionary = await _api.create_tree(tree_entries)
	if tree_result.has("error"):
		_append_status("❌ [color=red]Error creating file tree: " + str(tree_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	_progress_bar.value = 85.0

	# 6 – Create the commit.
	_append_status("⏳ Saving commit...")
	var commit_result: Dictionary = await _api.create_commit(tree_result.data.sha, head_sha, message)
	if commit_result.has("error"):
		_append_status("❌ [color=red]Error creating commit: " + str(commit_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	_progress_bar.value = 95.0

	# 7 – Point the branch at the new commit.
	_append_status("⏳ Updating branch...")
	var ref_result: Dictionary
	if is_first_commit:
		ref_result = await _api.create_ref(commit_result.data.sha)
	else:
		ref_result = await _api.update_ref(commit_result.data.sha)

	if ref_result.has("error"):
		_append_status("❌ [color=red]Error updating branch: " + str(ref_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	_progress_bar.value = 100.0
	_progress_bar.visible = false

	_append_status("✅ [color=green]Saved to GitHub! " + str(changed_count) + " file(s) updated.[/color]")
	_commit_msg_input.text = ""
	_update_last_saved_label()


# ===========================================================================
# Classroom repo loading
# ===========================================================================

func _do_load_repos(org: String) -> void:
	_set_status("⏳ [color=yellow]Loading assignments...[/color]")
	_repo_tree.clear()
	_loaded_repos.clear()

	# 1 – Verify token and get username.
	var user_result: Dictionary = await _api.get_authenticated_user()
	if user_result.has("error"):
		_set_status("❌ [color=red]Authentication failed: " + str(user_result.error) + "[/color]")
		return
	_github_username = str(user_result.data.login)
	_append_status("ℹ️ Signed in as @" + _github_username)

	var is_teacher := (_role_option.selected == 1)

	if is_teacher:
		# 2a – Verify the user is an org admin/owner (teacher).
		var membership_result: Dictionary = await _api.get_org_membership(org, _github_username)
		if membership_result.has("error"):
			_set_status("❌ [color=red]Could not verify organization membership: " + str(membership_result.error) + "[/color]")
			_append_status("⚠️ [color=yellow]Teacher access requires organization admin/owner privileges.[/color]")
			_append_status("ℹ️ Switching you back to the Student role.")
			# Reset to Student role and persist so state is never left in an
			# unverified Teacher role.
			_role_option.selected = 0
			_save_settings()
			return
		var role_str: String = str(membership_result.data.get("role", ""))
		# GitHub's org membership API returns "admin" for both owners and admins;
		# there is no separate "owner" string in this response.
		if role_str != "admin":
			_set_status("❌ [color=red]Teacher access requires organization admin/owner privileges. Your role is '" + role_str + "'.[/color]")
			_append_status("ℹ️ Switching you back to the Student role.")
			# Reset to Student role and persist.
			_role_option.selected = 0
			_save_settings()
			return
		_append_status("✅ Verified as organization admin/owner.")

		# Ensure auto-push is set to Manual for teachers to prevent
		# accidentally overwriting student work.
		if _auto_push_option.get_selected_id() != AUTO_PUSH_MANUAL:
			for i in range(_auto_push_option.item_count):
				if _auto_push_option.get_item_id(i) == AUTO_PUSH_MANUAL:
					_auto_push_option.selected = i
					break
			_save_settings()
			_update_auto_push_mode_label()
			_append_status("⚠️ [color=yellow]Auto-push set to Manual to protect student work.[/color]")

		# 3a – Load all org repos (paginated).
		var page := 1
		while true:
			var repos_result: Dictionary = await _api.get_org_repos(org, page)
			if repos_result.has("error"):
				_append_status("❌ [color=red]Error loading repos: " + str(repos_result.error) + "[/color]")
				break
			if not (repos_result.data is Array) or repos_result.data.is_empty():
				break
			for repo in repos_result.data:
				_loaded_repos.append({
					"name": str(repo.name),
					"owner": str(repo.owner.login),
				})
			if repos_result.data.size() < 100:
				break
			page += 1

		# Build the grouped tree view for teachers.
		_populate_teacher_tree()
	else:
		# 2b/3b – Student: load user repos filtered by org and username.
		var page := 1
		var org_lower := org.to_lower()
		var username_lower := _github_username.to_lower()
		while true:
			var repos_result: Dictionary = await _api.get_user_repos(page)
			if repos_result.has("error"):
				_append_status("❌ [color=red]Error loading repos: " + str(repos_result.error) + "[/color]")
				break
			if not (repos_result.data is Array) or repos_result.data.is_empty():
				break
			for repo in repos_result.data:
				var owner_name: String = str(repo.owner.login)
				var repo_name: String = str(repo.name)
				if owner_name.to_lower() == org_lower and username_lower in repo_name.to_lower():
					_loaded_repos.append({
						"name": repo_name,
						"owner": owner_name,
					})
			if repos_result.data.size() < 100:
				break
			page += 1

		# Build a flat tree view for students.
		_populate_student_tree()

	if _loaded_repos.is_empty():
		_append_status("⚠️ [color=yellow]No repositories found.[/color]")
	else:
		_append_status("✅ [color=green]Found " + str(_loaded_repos.size()) + " repositories.[/color]")


## Build a grouped tree view for teachers.  Repos following the GitHub
## Classroom naming convention ({assignment}-{username}) are grouped
## under collapsible assignment folders.
func _populate_teacher_tree() -> void:
	var root := _repo_tree.create_item()

	# 1 – Determine the assignment prefix for each repo.
	#     Count how many repos share each possible hyphen-delimited prefix.
	var prefix_counts := {}
	for repo in _loaded_repos:
		var parts: PackedStringArray = str(repo.name).split("-")
		for i in range(1, parts.size()):
			var prefix := "-".join(parts.slice(0, i))
			prefix_counts[prefix] = prefix_counts.get(prefix, 0) + 1

	# 2 – For each repo, find the longest prefix shared with at least one
	#     other repo.  That prefix is the assignment name.
	var assignment_for_repo: Array = []  # parallel to _loaded_repos
	for repo in _loaded_repos:
		var parts: PackedStringArray = str(repo.name).split("-")
		var best_prefix := ""
		for i in range(parts.size() - 1, 0, -1):
			var prefix := "-".join(parts.slice(0, i))
			if prefix_counts.get(prefix, 0) >= 2:
				best_prefix = prefix
				break
		assignment_for_repo.append(best_prefix)

	# 3 – Build ordered list of unique assignment names (preserving first-seen order).
	var seen_assignments := {}
	var assignment_order: Array = []
	for idx in range(assignment_for_repo.size()):
		var a: String = assignment_for_repo[idx]
		if a != "" and not seen_assignments.has(a):
			seen_assignments[a] = true
			assignment_order.append(a)

	# 4 – Create assignment folder items.
	var folder_items := {}  # assignment_name -> TreeItem
	for assignment_name in assignment_order:
		var folder := _repo_tree.create_item(root)
		folder.set_text(0, assignment_name + " (" + str(prefix_counts[assignment_name]) + ")")
		folder.set_selectable(0, false)
		folder.collapsed = true
		folder_items[assignment_name] = folder

	# Template repo name patterns (suffix-based detection).
	const TEMPLATE_SUFFIXES := ["-template", "-starter", "-base", "-solution", "-demo"]
	# Lazily-created folders for template and other (non-assignment) repos.
	var template_folder: TreeItem = null
	var extra_folder: TreeItem = null

	for idx in range(_loaded_repos.size()):
		var repo_name: String = str(_loaded_repos[idx].name)
		var assignment: String = assignment_for_repo[idx]
		if assignment != "":
			var student_label: String = repo_name.substr(assignment.length() + 1)  # +1 skips the "-" separator
			var child := _repo_tree.create_item(folder_items[assignment])
			child.set_text(0, student_label)
			child.set_tooltip_text(0, repo_name)
			child.set_metadata(0, idx)
		else:
			# Determine whether this ungrouped repo is a template or an extra.
			# A repo is treated as a template if its name exactly matches a known
			# assignment prefix (e.g. the source repo named "project-1" alongside
			# student repos "project-1-alice", "project-1-bob") or if it uses a
			# common template-naming suffix.
			var is_template := seen_assignments.has(repo_name)
			if not is_template:
				for suffix in TEMPLATE_SUFFIXES:
					if repo_name.ends_with(suffix):
						is_template = true
						break
			if is_template:
				if template_folder == null:
					template_folder = _repo_tree.create_item(root)
					template_folder.set_text(0, "📋 Templates")
					template_folder.set_selectable(0, false)
					template_folder.collapsed = true
				var child := _repo_tree.create_item(template_folder)
				child.set_text(0, repo_name)
				child.set_tooltip_text(0, repo_name)
				child.set_metadata(0, idx)
			else:
				if extra_folder == null:
					extra_folder = _repo_tree.create_item(root)
					extra_folder.set_text(0, "📦 Other Repos")
					extra_folder.set_selectable(0, false)
					extra_folder.collapsed = true
				var child := _repo_tree.create_item(extra_folder)
				child.set_text(0, repo_name)
				child.set_tooltip_text(0, repo_name)
				child.set_metadata(0, idx)


## Build a flat tree view for students (no grouping).
func _populate_student_tree() -> void:
	var root := _repo_tree.create_item()
	for idx in range(_loaded_repos.size()):
		var child := _repo_tree.create_item(root)
		child.set_text(0, str(_loaded_repos[idx].name))
		child.set_metadata(0, idx)


# ===========================================================================
# Auto-push hooks (called from plugin.gd)
# ===========================================================================

## Called by the plugin when the editor saves external data (project save).
func _on_editor_save() -> void:
	if _auto_push_option.get_selected_id() == AUTO_PUSH_ON_SAVE and not _is_pushing:
		_trigger_auto_push()


## Called by the plugin when the editor is about to close.
func _on_editor_close() -> void:
	if _auto_push_option.get_selected_id() == AUTO_PUSH_ON_CLOSE and not _is_pushing:
		_trigger_auto_push()


func _trigger_auto_push() -> void:
	if not _configure_api():
		return
	_is_pushing = true
	_set_buttons_enabled(false)
	await _do_push()
	_set_buttons_enabled(true)
	_is_pushing = false


# ===========================================================================
# Clean pull logic
# ===========================================================================

## Delete all local project files except the addons/ directory, then
## perform a normal pull.  Used by teachers when switching between student
## projects to guarantee no stale files remain.
func _do_clean_pull() -> void:
	_set_status("⏳ [color=yellow]Preparing clean pull – removing local files...[/color]")
	var project_path: String = ProjectSettings.globalize_path("res://")
	_delete_files_except_addons(project_path, "")
	_append_status("⏳ Downloading fresh copy from GitHub...")
	await _do_pull()


## Recursively delete all files and non-excluded directories under
## base_path/relative_path, skipping the top-level "addons" directory
## so the addon itself remains functional.
func _delete_files_except_addons(base_path: String, relative_path: String) -> void:
	var full_dir: String = base_path.path_join(relative_path) if not relative_path.is_empty() else base_path
	var dir := DirAccess.open(full_dir)
	if dir == null:
		return

	var subdirs: Array = []
	var files_to_delete: Array = []

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var rel: String = (relative_path + "/" + entry) if not relative_path.is_empty() else entry
		if dir.current_is_dir():
			# Preserve the addons/ directory at the project root so the
			# addon itself (and any other plugins) keep working.
			var is_root_addons := (relative_path.is_empty() and entry == "addons")
			if not is_root_addons and not entry in EXCLUDED_DIRS:
				subdirs.append(rel)
		else:
			if not entry in EXCLUDED_FILES:
				files_to_delete.append(rel)
		entry = dir.get_next()
	dir.list_dir_end()

	# Recurse depth-first so directories are empty before we try to remove them.
	for subdir in subdirs:
		_delete_files_except_addons(base_path, subdir)
		DirAccess.remove_absolute(base_path.path_join(subdir))

	for file_rel in files_to_delete:
		DirAccess.remove_absolute(base_path.path_join(file_rel))


# ===========================================================================
# File scanning helpers
# ===========================================================================

## Recursively scan the project directory and return an Array of relative
## file paths (using forward slashes) suitable for the GitHub API.
func _scan_project_files(base_path: String, relative_path: String) -> Array:
	var results: Array = []
	var full_dir: String = base_path.path_join(relative_path) if not relative_path.is_empty() else base_path
	var dir := DirAccess.open(full_dir)
	if dir == null:
		return results

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var rel: String
		if relative_path.is_empty():
			rel = entry
		else:
			rel = relative_path + "/" + entry

		if dir.current_is_dir():
			if not entry in EXCLUDED_DIRS:
				results.append_array(_scan_project_files(base_path, rel))
		else:
			if not entry in EXCLUDED_FILES:
				results.append(rel)

		entry = dir.get_next()
	dir.list_dir_end()
	return results


## Return true when a file path (from the remote tree) should be skipped.
func _is_path_excluded(file_path: String) -> bool:
	for excluded in EXCLUDED_DIRS:
		if file_path == excluded or file_path.begins_with(excluded + "/"):
			return true
	for excluded in EXCLUDED_FILES:
		if file_path.get_file() == excluded:
			return true
	return false


## Compute the SHA-1 hash that Git would assign to a blob with the given content.
## The hash covers the header ``blob <size>\0`` followed by the raw bytes.
func _compute_git_blob_sha(content: PackedByteArray) -> String:
	var header: PackedByteArray = ("blob " + str(content.size())).to_utf8_buffer()
	header.append(0) # null byte separator
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(header)
	ctx.update(content)
	return ctx.finish().hex_encode()


# ===========================================================================
# Advanced mode toggle
# ===========================================================================

func _on_advanced_toggle_changed(pressed: bool) -> void:
	_apply_advanced_mode(pressed)
	# Persist the toggle state immediately so it survives a restart.
	var config := ConfigFile.new()
	config.load(_get_config_path())
	config.set_value("github", "advanced_mode", pressed)
	config.save(_get_config_path())


func _apply_advanced_mode(advanced: bool) -> void:
	for node in _advanced_nodes:
		node.visible = advanced


# ===========================================================================
# Connected label + last-saved label helpers
# ===========================================================================

## Update the persistent "Connected" label based on the current URL + branch.
func _update_connected_label() -> void:
	var url := _repo_url_input.text.strip_edges()
	if url.is_empty():
		_connected_label.text = "Not connected — load your assignments above."
		_connected_label.add_theme_color_override("font_color", Color.GRAY)
		return
	var info := _parse_repo_url(url)
	if info.is_empty():
		_connected_label.text = "Not connected — load your assignments above."
		_connected_label.add_theme_color_override("font_color", Color.GRAY)
	else:
		var branch := _branch_input.text.strip_edges()
		if branch.is_empty():
			branch = "main"
		_connected_label.text = "🟢 Connected: " + str(info.repo) + " on " + branch
		_connected_label.remove_theme_color_override("font_color")


## Update the "Last saved to GitHub" label with the current time.
func _update_last_saved_label() -> void:
	var dt := Time.get_datetime_dict_from_system()
	var hour: int = dt.hour
	var minute: int = dt.minute
	var am_pm := "AM"
	if hour >= 12:
		am_pm = "PM"
	if hour > 12:
		hour -= 12
	elif hour == 0:
		hour = 12
	_last_saved_label.text = "Last saved to GitHub: Today at %d:%02d %s" % [hour, minute, am_pm]


## Update the auto-push mode indicator label to reflect the current setting.
## This label is always visible so both Simple and Advanced users can see
## whether changes are uploaded automatically.
func _update_auto_push_mode_label() -> void:
	var mode_id := _auto_push_option.get_selected_id()
	match mode_id:
		AUTO_PUSH_MANUAL:
			_auto_push_mode_label.text = "Upload mode: Manual only (use ⬆ Save to GitHub)"
			_auto_push_mode_label.add_theme_color_override("font_color", Color.GRAY)
		AUTO_PUSH_ON_SAVE:
			_auto_push_mode_label.text = "Upload mode: Auto-push on every save ✓"
			_auto_push_mode_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		AUTO_PUSH_ON_CLOSE:
			_auto_push_mode_label.text = "Upload mode: Auto-push when editor closes ✓"
			_auto_push_mode_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		_:
			_auto_push_mode_label.text = ""
