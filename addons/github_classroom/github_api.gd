@tool
extends Node
## GitHub REST API wrapper for the GitHub Classroom addon.
##
## Uses the GitHub REST API v3 to perform git operations (pull/push) without
## requiring git to be installed on the machine. All file transfers go through
## the Git Data API (blobs, trees, commits, refs).

const BASE_URL := "https://api.github.com"
const _CERT_PATH := "res://addons/github_classroom/certs/github-ca.crt"

var _token: String = ""
var _owner: String = ""
var _repo: String = ""
var _branch: String = "main"
var _tls_options: TLSOptions = null


func _ready() -> void:
	_setup_tls()


func _setup_tls() -> void:
	var cert := X509Certificate.new()
	var err := cert.load(_CERT_PATH)
	if err == OK:
		_tls_options = TLSOptions.client(cert)
	else:
		push_warning("GodotGitHubClassroom: Could not load bundled CA cert from %s (error %d). TLS validation may fail." % [_CERT_PATH, err])
		_tls_options = null


func setup(token: String, owner: String, repo: String, branch: String = "main") -> void:
	_token = token
	_owner = owner
	_repo = repo
	_branch = branch


# ---------------------------------------------------------------------------
# Internal HTTP helper
# ---------------------------------------------------------------------------

func _make_request(method: HTTPClient.Method, endpoint: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	if _tls_options != null:
		http.set_tls_options(_tls_options)

	var url := BASE_URL + endpoint
	var headers := PackedStringArray([
		"Authorization: Bearer " + _token,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: GodotGitHubClassroom/1.0",
	])

	var error: int
	if body != null:
		headers.append("Content-Type: application/json")
		error = http.request(url, headers, method, JSON.stringify(body))
	else:
		error = http.request(url, headers, method)

	if error != OK:
		http.queue_free()
		return {"error": "Failed to start request (error %d)" % error}

	var response: Array = await http.request_completed
	http.queue_free()

	var result: int = response[0]
	var response_code: int = response[1]
	# response[2] = headers (unused)
	var response_body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed (result %d). Check your internet connection." % result}

	if response_code >= 400:
		var error_text := response_body.get_string_from_utf8()
		var error_json = JSON.parse_string(error_text)
		var msg := "HTTP %d" % response_code
		if error_json is Dictionary and error_json.has("message"):
			msg += ": " + str(error_json.message)
		return {"error": msg}

	var json_text := response_body.get_string_from_utf8()
	if json_text.strip_edges().is_empty():
		return {"data": null, "code": response_code}

	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		return {"error": "Failed to parse server response"}

	return {"data": parsed, "code": response_code}


# ---------------------------------------------------------------------------
# Public API methods
# ---------------------------------------------------------------------------

## Get information about the configured branch (latest commit SHA, tree SHA).
func get_branch() -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_GET,
		"/repos/%s/%s/branches/%s" % [_owner, _repo, _branch],
	)


## Get the full file tree for a given tree SHA (recursive).
func get_git_tree(tree_sha: String) -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_GET,
		"/repos/%s/%s/git/trees/%s?recursive=1" % [_owner, _repo, tree_sha],
	)


## Download a blob's content. Returns {"content": PackedByteArray} on success.
func get_blob(blob_sha: String) -> Dictionary:
	var result := await _make_request(
		HTTPClient.METHOD_GET,
		"/repos/%s/%s/git/blobs/%s" % [_owner, _repo, blob_sha],
	)
	if result.has("error"):
		return result

	var content_b64: String = result.data.content
	content_b64 = content_b64.replace("\n", "")
	var decoded := Marshalls.base64_to_raw(content_b64)
	return {"content": decoded}


## Upload file content as a blob. Returns {"sha": String} on success.
func create_blob(content: PackedByteArray) -> Dictionary:
	var base64_content := Marshalls.raw_to_base64(content)
	return await _make_request(
		HTTPClient.METHOD_POST,
		"/repos/%s/%s/git/blobs" % [_owner, _repo],
		{"content": base64_content, "encoding": "base64"},
	)


## Create a new tree from an array of tree entry dictionaries.
## Each entry: {"path": "file.gd", "mode": "100644", "type": "blob", "sha": "..."}
## If [param base_tree_sha] is provided, entries are merged on top of the base.
func create_tree(tree_entries: Array, base_tree_sha: String = "") -> Dictionary:
	var body: Dictionary = {"tree": tree_entries}
	if not base_tree_sha.is_empty():
		body["base_tree"] = base_tree_sha
	return await _make_request(
		HTTPClient.METHOD_POST,
		"/repos/%s/%s/git/trees" % [_owner, _repo],
		body,
	)


## Create a commit. Pass an empty [param parent_sha] for the initial commit.
func create_commit(tree_sha: String, parent_sha: String, message: String) -> Dictionary:
	var parents: Array = [parent_sha] if not parent_sha.is_empty() else []
	return await _make_request(
		HTTPClient.METHOD_POST,
		"/repos/%s/%s/git/commits" % [_owner, _repo],
		{"message": message, "tree": tree_sha, "parents": parents},
	)


## Update an existing branch reference to point to a new commit.
func update_ref(commit_sha: String) -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_PATCH,
		"/repos/%s/%s/git/refs/heads/%s" % [_owner, _repo, _branch],
		{"sha": commit_sha, "force": false},
	)


## Create a new branch reference (used for the first commit to an empty repo).
func create_ref(commit_sha: String) -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_POST,
		"/repos/%s/%s/git/refs" % [_owner, _repo],
		{"ref": "refs/heads/" + _branch, "sha": commit_sha},
	)


# ---------------------------------------------------------------------------
# Organization / user endpoints (for classroom role features)
# ---------------------------------------------------------------------------

## Get the authenticated user's information. Useful for verifying the token
## and retrieving the GitHub username.
func get_authenticated_user() -> Dictionary:
	return await _make_request(HTTPClient.METHOD_GET, "/user")


## Get the authenticated user's membership in an organization.
## The response includes a "role" field ("admin" or "member").
func get_org_membership(org: String, username: String) -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_GET,
		"/orgs/%s/memberships/%s" % [org, username],
	)


## Get repositories belonging to an organization (paginated, 100 per page).
func get_org_repos(org: String, page: int = 1) -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_GET,
		"/orgs/%s/repos?per_page=100&page=%d&sort=updated&direction=desc" % [org, page],
	)


## Get the authenticated user's repositories (paginated, 100 per page).
func get_user_repos(page: int = 1) -> Dictionary:
	return await _make_request(
		HTTPClient.METHOD_GET,
		"/user/repos?per_page=100&page=%d&affiliation=collaborator,organization_member&sort=updated&direction=desc" % [page],
	)
