@tool
extends Control
## Editor dock panel for the GitHub Classroom addon.
##
## Provides a simple UI so students can pull and push their Godot projects
## to a GitHub Classroom repository without ever touching the command line.

const CONFIG_PATH := "user://github_classroom_config.cfg"

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
var _load_repos_button: Button
var _repo_list: ItemList
var _commit_msg_input: TextEdit
var _pull_button: Button
var _push_button: Button
var _status_label: RichTextLabel
var _progress_bar: ProgressBar

# --- API node ---
var _api: Node

# --- State ---
var _github_username: String = ""
var _is_pushing: bool = false
var _loaded_repos: Array = []


# ===========================================================================
# Lifecycle
# ===========================================================================

func _ready() -> void:
	_build_ui()
	_setup_api()
	_load_settings()


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

	_add_label(vbox, "Role:")
	_role_option = OptionButton.new()
	_role_option.add_item("Student", 0)
	_role_option.add_item("Teacher", 1)
	_role_option.tooltip_text = "Select your role. Teachers can view all student repositories in the organization."
	_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_role_option)

	_add_label(vbox, "Organization:")
	_org_input = _add_line_edit(vbox, "github-classroom-org")
	_org_input.tooltip_text = "Your GitHub Classroom organization name. Used with Load Repos to browse assignments."

	_add_label(vbox, "Repository URL:")
	_repo_url_input = _add_line_edit(vbox, "https://github.com/owner/repo")
	_repo_url_input.tooltip_text = "Paste the repository link from GitHub Classroom here, or select one from the Classroom section below."

	_add_label(vbox, "GitHub Token:")
	_token_input = _add_line_edit(vbox, "ghp_xxxxxxxxxxxx")
	_token_input.secret = true
	_token_input.tooltip_text = "Your GitHub Personal Access Token (starts with ghp_ or github_pat_)."

	_add_label(vbox, "Branch:")
	_branch_input = _add_line_edit(vbox, "main")
	_branch_input.text = "main"
	_branch_input.tooltip_text = "Usually 'main'. Only change this if your teacher tells you to."

	_add_label(vbox, "Auto-Push:")
	_auto_push_option = OptionButton.new()
	_auto_push_option.add_item("Manual Only", AUTO_PUSH_MANUAL)
	_auto_push_option.add_item("Auto-Push on Save", AUTO_PUSH_ON_SAVE)
	_auto_push_option.add_item("Auto-Push on Close", AUTO_PUSH_ON_CLOSE)
	_auto_push_option.tooltip_text = "Automatically push changes when saving the project or closing the editor."
	_auto_push_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_auto_push_option)

	_save_button = Button.new()
	_save_button.text = "Save Settings"
	_save_button.pressed.connect(_on_save_pressed)
	vbox.add_child(_save_button)

	vbox.add_child(HSeparator.new())

	# ---- Classroom section ----
	_add_section_header(vbox, "Classroom")

	_load_repos_button = Button.new()
	_load_repos_button.text = "Load Repos"
	_load_repos_button.tooltip_text = "Load repositories from your GitHub Classroom organization. Requires token and organization name."
	_load_repos_button.pressed.connect(_on_load_repos_pressed)
	vbox.add_child(_load_repos_button)

	_repo_list = ItemList.new()
	_repo_list.custom_minimum_size = Vector2(0, 100)
	_repo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repo_list.item_selected.connect(_on_repo_selected)
	_repo_list.tooltip_text = "Select a repository to auto-fill the Repository URL above."
	vbox.add_child(_repo_list)

	vbox.add_child(HSeparator.new())

	# ---- Sync section ----
	_add_section_header(vbox, "Sync")

	_add_label(vbox, "Commit Message (optional):")
	_commit_msg_input = TextEdit.new()
	_commit_msg_input.placeholder_text = "Optional – auto-generates if left blank."
	_commit_msg_input.tooltip_text = "Write a short description of your changes, or leave blank for a default message with the current date and time."
	_commit_msg_input.custom_minimum_size = Vector2(0, 60)
	_commit_msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_commit_msg_input)

	var btn_row := HBoxContainer.new()
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(btn_row)

	_pull_button = Button.new()
	_pull_button.text = "Pull"
	_pull_button.tooltip_text = "Download the latest version of your project from GitHub."
	_pull_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pull_button.pressed.connect(_on_pull_pressed)
	btn_row.add_child(_pull_button)

	_push_button = Button.new()
	_push_button.text = "Push"
	_push_button.tooltip_text = "Upload your changes to GitHub."
	_push_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_push_button.pressed.connect(_on_push_pressed)
	btn_row.add_child(_push_button)

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


# Small helpers to reduce repetition when building the UI.

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	parent.add_child(HSeparator.new())


func _add_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


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
# Settings persistence
# ===========================================================================

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("github", "repo_url", _repo_url_input.text)
	config.set_value("github", "token", _token_input.text)
	config.set_value("github", "branch", _branch_input.text)
	config.set_value("github", "role", _role_option.selected)
	config.set_value("github", "organization", _org_input.text)
	config.set_value("github", "auto_push", _auto_push_option.selected)
	config.save(CONFIG_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		_repo_url_input.text = config.get_value("github", "repo_url", "")
		_token_input.text = config.get_value("github", "token", "")
		_branch_input.text = config.get_value("github", "branch", "main")
		_role_option.selected = config.get_value("github", "role", 0)
		_org_input.text = config.get_value("github", "organization", "")
		_auto_push_option.selected = config.get_value("github", "auto_push", 0)


# ===========================================================================
# Validation helpers
# ===========================================================================

## Parse a GitHub URL into {"owner": ..., "repo": ...}. Returns {} on failure.
func _parse_repo_url(url: String) -> Dictionary:
	url = url.strip_edges().trim_suffix(".git").trim_suffix("/")
	if url.begins_with("https://"):
		url = url.substr(8)
	elif url.begins_with("http://"):
		url = url.substr(7)
	if url.begins_with("github.com/"):
		url = url.substr(11)
	var parts := url.split("/")
	if parts.size() >= 2 and not parts[0].is_empty() and not parts[1].is_empty():
		return {"owner": parts[0], "repo": parts[1]}
	return {}


## Validate inputs and configure the API node. Returns true on success.
func _configure_api() -> bool:
	var info := _parse_repo_url(_repo_url_input.text)
	if info.is_empty():
		_set_status("[color=red]Invalid repository URL. Use the format: https://github.com/owner/repo[/color]")
		return false
	if _token_input.text.strip_edges().is_empty():
		_set_status("[color=red]Please enter your GitHub token.[/color]")
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
	_load_repos_button.disabled = not enabled


# ===========================================================================
# Button callbacks
# ===========================================================================

func _on_save_pressed() -> void:
	_save_settings()
	_set_status("[color=green]Settings saved![/color]")


func _on_pull_pressed() -> void:
	if not _configure_api():
		return
	_save_settings()
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
		_set_status("[color=red]Please enter your GitHub token.[/color]")
		return
	var org := _org_input.text.strip_edges()
	if org.is_empty():
		_set_status("[color=red]Please enter your GitHub Classroom organization name.[/color]")
		return
	# Set token for API calls (owner/repo not needed for org/user endpoints).
	_api.setup(token, "", "", "")
	_set_buttons_enabled(false)
	await _do_load_repos(org)
	_set_buttons_enabled(true)


func _on_repo_selected(index: int) -> void:
	if index >= 0 and index < _loaded_repos.size():
		var repo: Dictionary = _loaded_repos[index]
		_repo_url_input.text = "https://github.com/" + repo.owner + "/" + repo.name
		_set_status("[color=green]Selected: " + str(repo.name) + "[/color]")


# ===========================================================================
# Pull logic
# ===========================================================================

func _do_pull() -> void:
	_set_status("[color=yellow]Pulling from GitHub...[/color]")
	_progress_bar.visible = true
	_progress_bar.value = 0

	# 1 – Get branch info (latest commit + tree SHA).
	_append_status("Getting latest version...")
	var branch_result: Dictionary = await _api.get_branch()
	if branch_result.has("error"):
		_append_status("[color=red]Error: " + str(branch_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	var tree_sha: String = branch_result.data.commit.commit.tree.sha

	# 2 – Get full recursive tree.
	_append_status("Getting file list...")
	var tree_result: Dictionary = await _api.get_git_tree(tree_sha)
	if tree_result.has("error"):
		_append_status("[color=red]Error: " + str(tree_result.error) + "[/color]")
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
		_append_status("[color=yellow]The repository has no downloadable files.[/color]")
		_progress_bar.visible = false
		return

	_append_status("Downloading " + str(files.size()) + " files...")

	# 3 – Download each blob and write to disk.
	var project_path: String = ProjectSettings.globalize_path("res://")
	var downloaded: int = 0
	var errors: int = 0

	for i in range(files.size()):
		var file_info: Dictionary = files[i]
		_progress_bar.value = float(i + 1) / float(files.size()) * 100.0

		var blob_result: Dictionary = await _api.get_blob(file_info.sha)
		if blob_result.has("error"):
			_append_status("[color=red]  Failed: " + file_info.path + " – " + str(blob_result.error) + "[/color]")
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
			_append_status("[color=red]  Could not write: " + file_info.path + "[/color]")
			errors += 1

	_progress_bar.visible = false
	if errors == 0:
		_append_status("[color=green]Pull complete! Downloaded " + str(downloaded) + " files.[/color]")
	else:
		_append_status("[color=yellow]Pull finished with " + str(errors) + " error(s). Downloaded " + str(downloaded) + " files.[/color]")

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

	_set_status("[color=yellow]Pushing to GitHub...[/color]")
	_progress_bar.visible = true
	_progress_bar.value = 0

	# 1 – Get branch HEAD. A 404 means the repo/branch has no commits yet.
	_append_status("Getting current version...")
	var branch_result: Dictionary = await _api.get_branch()
	var is_first_commit := false
	var head_sha := ""
	var base_tree_sha := ""

	if branch_result.has("error"):
		if "404" in str(branch_result.error):
			is_first_commit = true
			_append_status("No existing commits found – this will be the first commit.")
		else:
			_append_status("[color=red]Error: " + str(branch_result.error) + "[/color]")
			_progress_bar.visible = false
			return
	else:
		head_sha = branch_result.data.commit.sha
		base_tree_sha = branch_result.data.commit.commit.tree.sha

	# 2 – Build a map of remote file SHAs for comparison.
	var remote_files: Dictionary = {}
	if not base_tree_sha.is_empty():
		_append_status("Comparing files...")
		var remote_tree_result: Dictionary = await _api.get_git_tree(base_tree_sha)
		if not remote_tree_result.has("error"):
			for item in remote_tree_result.data.tree:
				if item.type == "blob":
					remote_files[item.path] = item.sha

	# 3 – Scan local project files.
	var project_path: String = ProjectSettings.globalize_path("res://")
	var local_files: Array = _scan_project_files(project_path, "")

	if local_files.is_empty():
		_append_status("[color=yellow]No files found to push.[/color]")
		_progress_bar.visible = false
		return

	# 4 – Compare each local file, upload blobs only for changed/new files.
	_append_status("Checking " + str(local_files.size()) + " files for changes...")
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
			_append_status("[color=red]  Could not read: " + rel_path + "[/color]")
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
				_append_status("[color=red]  Upload failed: " + rel_path + " – " + err_msg + "[/color]")
				if "403" in err_msg:
					had_permission_error = true
				upload_errors += 1
				continue
			tree_entries.append({"path": rel_path, "mode": "100644", "type": "blob", "sha": blob_result.data.sha})
			changed_count += 1

	if upload_errors > 0:
		_append_status("[color=red]Push failed: " + str(upload_errors) + " file(s) could not be uploaded.[/color]")
		if had_permission_error:
			_append_status(TOKEN_PERMISSION_HINT)
		_progress_bar.visible = false
		return

	if changed_count == 0 and not is_first_commit:
		_append_status("[color=green]No changes to push. Everything is up to date![/color]")
		_progress_bar.visible = false
		return

	_append_status("Creating commit with " + str(changed_count) + " changed file(s)...")
	_progress_bar.value = 70.0

	# 5 – Create a brand-new tree (no base_tree so deletions are captured).
	var tree_result: Dictionary = await _api.create_tree(tree_entries)
	if tree_result.has("error"):
		_append_status("[color=red]Error creating file tree: " + str(tree_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	_progress_bar.value = 85.0

	# 6 – Create the commit.
	_append_status("Saving commit...")
	var commit_result: Dictionary = await _api.create_commit(tree_result.data.sha, head_sha, message)
	if commit_result.has("error"):
		_append_status("[color=red]Error creating commit: " + str(commit_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	_progress_bar.value = 95.0

	# 7 – Point the branch at the new commit.
	_append_status("Updating branch...")
	var ref_result: Dictionary
	if is_first_commit:
		ref_result = await _api.create_ref(commit_result.data.sha)
	else:
		ref_result = await _api.update_ref(commit_result.data.sha)

	if ref_result.has("error"):
		_append_status("[color=red]Error updating branch: " + str(ref_result.error) + "[/color]")
		_progress_bar.visible = false
		return

	_progress_bar.value = 100.0
	_progress_bar.visible = false

	_append_status("[color=green]Push complete! " + str(changed_count) + " file(s) updated.[/color]")
	_commit_msg_input.text = ""


# ===========================================================================
# Classroom repo loading
# ===========================================================================

func _do_load_repos(org: String) -> void:
	_set_status("[color=yellow]Loading repositories...[/color]")
	_repo_list.clear()
	_loaded_repos.clear()

	# 1 – Verify token and get username.
	var user_result: Dictionary = await _api.get_authenticated_user()
	if user_result.has("error"):
		_set_status("[color=red]Authentication failed: " + str(user_result.error) + "[/color]")
		return
	_github_username = str(user_result.data.login)
	_append_status("Signed in as @" + _github_username)

	var is_teacher := (_role_option.selected == 1)

	if is_teacher:
		# 2a – Verify the user is an org admin (teacher).
		var membership_result: Dictionary = await _api.get_org_membership(org, _github_username)
		if membership_result.has("error"):
			_set_status("[color=red]Could not verify organization membership: " + str(membership_result.error) + "[/color]")
			_append_status("[color=yellow]Teacher access requires organization admin/owner privileges.[/color]")
			return
		var role_str: String = str(membership_result.data.get("role", ""))
		if role_str != "admin":
			_set_status("[color=red]Teacher access requires organization admin/owner privileges. Your role is '" + role_str + "'.[/color]")
			return
		_append_status("Verified as organization admin.")

		# 3a – Load all org repos (paginated).
		var page := 1
		while true:
			var repos_result: Dictionary = await _api.get_org_repos(org, page)
			if repos_result.has("error"):
				_append_status("[color=red]Error loading repos: " + str(repos_result.error) + "[/color]")
				break
			if not (repos_result.data is Array) or repos_result.data.is_empty():
				break
			for repo in repos_result.data:
				_loaded_repos.append({
					"name": str(repo.name),
					"owner": str(repo.owner.login),
				})
				_repo_list.add_item(str(repo.name))
			if repos_result.data.size() < 100:
				break
			page += 1
	else:
		# 2b/3b – Student: load user repos filtered by org and username.
		var page := 1
		var org_lower := org.to_lower()
		var username_lower := _github_username.to_lower()
		while true:
			var repos_result: Dictionary = await _api.get_user_repos(page)
			if repos_result.has("error"):
				_append_status("[color=red]Error loading repos: " + str(repos_result.error) + "[/color]")
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
					_repo_list.add_item(repo_name)
			if repos_result.data.size() < 100:
				break
			page += 1

	if _loaded_repos.is_empty():
		_append_status("[color=yellow]No repositories found.[/color]")
	else:
		_append_status("[color=green]Found " + str(_loaded_repos.size()) + " repositories.[/color]")


# ===========================================================================
# Auto-push hooks (called from plugin.gd)
# ===========================================================================

## Called by the plugin when the editor saves external data (project save).
func _on_editor_save() -> void:
	if _auto_push_option.selected == AUTO_PUSH_ON_SAVE and not _is_pushing:
		_trigger_auto_push()


## Called by the plugin when the editor is about to close.
func _on_editor_close() -> void:
	if _auto_push_option.selected == AUTO_PUSH_ON_CLOSE and not _is_pushing:
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
