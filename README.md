# GitHub Classroom for Godot

A simple Godot 4.5+ editor addon that lets students **pull** and **push** their projects to GitHub Classroom repositories — no command line or GitHub Desktop needed.

Everything happens through a small panel inside the Godot editor, making it ideal for introductory game-design courses where students are new to version control.

---

## Features

| Feature | Description |
|---------|-------------|
| **⬇ Download Latest (Pull)** | Download the latest version of the project from GitHub with one click. |
| **⬆ Save to GitHub (Push)** | Upload changes to GitHub with a short commit message. |
| **Auto-Push on Save (default)** | Automatically pushes every time you save the project — no manual push needed. |
| **Default Commit Message** | Commit message is optional — a timestamped default is generated when left blank. |
| **Simple / Advanced View** | A toggle hides advanced options by default so beginners only see what they need. |
| **Teacher / Student Roles** | Teachers can browse all student repos in an organization; students see only their own. Teacher access requires verified organization admin/owner status. |
| **Classroom Repo Browser** | Load and select repositories from a GitHub Classroom organization. Click **Load My Assignments** to browse. |
| **No Git required** | Uses the GitHub REST API directly — Git does not need to be installed. |
| **Simple UI** | One panel with only the controls students need. |
| **🔒 Sign Out button** | Clears your token and settings with one click — use it before logging out of a shared computer. |
| **Per-user settings** | Settings are stored separately for each OS desktop account, so Student B's Godot session never loads Student A's token. |
| **Token obfuscation** | The GitHub token is stored with XOR obfuscation (defense-in-depth, not encryption) — not plain text. |

---

## Installation

### For Teachers — Setting Up the Template

1. Copy the `addons/github_classroom/` folder into your Godot project's `addons/` directory.
2. Open the project in Godot, go to **Project → Project Settings → Plugins** and enable **GitHub Classroom**.
3. Commit the project (including the addon) to your GitHub Classroom template repository.

### For Students — First-Time Setup

1. Accept the GitHub Classroom assignment. This creates your own repository.
2. Open the Godot project your teacher provided.
3. Look for the **GitHubClassroom** panel on the right side of the editor.
4. Enter two things:
   - **Organization** — the name of your GitHub Classroom organization (your teacher will give you this).
   - **GitHub Token** — a Personal Access Token you create on GitHub (see below).
5. Click **Save Settings**.
6. Click **Load My Assignments** to see your assignment repository.
7. Click your repository in the list, then click **⬇ Download Latest (Pull)** to download the starter code.

> **Tip:** The addon defaults to **Auto-Push on Save** — your work is automatically saved to GitHub every time you save your Godot project. You don't need to click Push manually!

> **Shared computers:** When you are done, click the **🔒 Sign Out / Clear Credentials** button in the panel before logging out of the desktop. This ensures the next person who opens the project cannot access your GitHub account.

---

## Creating a GitHub Personal Access Token

Students need a token so the addon can talk to GitHub on their behalf.

### Option A — Classic Token (Recommended for GitHub Classroom)

Classic tokens work reliably with organization-owned repositories such as those created by GitHub Classroom.

1. Go to <https://github.com/settings/tokens> (classic tokens page).
2. Click **Generate new token** → **Generate new token (classic)**.
3. Give it a name, for example `Godot Classroom`.
4. Set the **Expiration** to match your course length.
5. Under **Select scopes**, check **`repo`** (this grants full read/write access to your repositories).
6. Click **Generate token** and **copy** the token immediately (you will not see it again).
7. Paste the token into the **GitHub Token** field in Godot.

### Option B — Fine-Grained Token

Fine-grained tokens offer narrower permissions but may require extra setup for organization repositories.

1. Go to <https://github.com/settings/tokens?type=beta> (Fine-grained tokens).
2. Click **Generate new token**.
3. Give it a name, for example `Godot Classroom`.
4. Set the **Expiration** to match your course length (or choose *Custom*).
5. Under **Resource owner**, select the **organization** that owns the classroom repository (not your personal account). If the organization is not listed, the org admin must first allow fine-grained tokens — see the note below.
6. Under **Repository access**, select **Only select repositories** and pick your classroom repository.
7. Under **Permissions → Repository permissions**, set **Contents** to **Read and write**.
8. Click **Generate token** and **copy** the token immediately (you will not see it again).
9. Paste the token into the **GitHub Token** field in Godot.

> **Important for teachers / org admins:** GitHub organizations must explicitly opt in to allow fine-grained personal access tokens. Go to **Organization Settings → Personal access tokens → Settings** and enable *Allow access via fine-grained personal access tokens*. If this is not enabled, students will get **HTTP 403** errors when pushing. Using a **classic token** (Option A) avoids this requirement.

> **Tip for teachers:** Walk students through the token creation process once at the beginning of the course. The token only needs to be created once per repository.

---

## Daily Workflow

1. **Start of class** — Click **⬇ Download Latest (Pull)** to make sure you have the latest version.  
   > A confirmation dialog will appear — click **Yes, Download** to proceed.
2. **Work on your project** — Add scenes, write scripts, create art, etc.
3. **Save as you go** — Because **Auto-Push on Save** is the default, your project is automatically saved to GitHub each time you press Ctrl+S (or use File → Save). You'll see a "Last saved to GitHub: Today at ..." message appear below the buttons.
4. **End of class** — Click **🔒 Sign Out / Clear Credentials** before logging out of the shared desktop computer. This removes your token from the panel so the next student cannot access your work.

> **Optional:** If you want to add a meaningful commit message, type it in the **Commit Message** box (visible in Advanced Options) and click **⬆ Save to GitHub (Push)** manually.

---

## Simple vs. Advanced View

By default the panel shows only the essentials:

- Organization name
- GitHub Token
- **🔒 Sign Out / Clear Credentials** button
- **Load My Assignments** button + repository list
- **⬇ Download Latest (Pull)** and **⬆ Save to GitHub (Push)** buttons

Click **Show Advanced Options** to reveal additional settings:

- **Role** — Student or Teacher
- **Repository URL** — paste a URL directly if you prefer
- **Branch** — usually `main`
- **Auto-Push** — choose between Auto-Push on Save (default), Manual Only, or Auto-Push on Close
- **Commit Message** — write a custom message for your push

The toggle state is saved automatically so advanced options stay visible after a restart if you have enabled them.

---

## Auto-Push

The addon defaults to **Auto-Push on Save**, which automatically pushes your work to GitHub every time you save the Godot project. No manual clicking needed.

To change the behaviour, enable **Show Advanced Options** and find the **Auto-Push** dropdown:

1. **Auto-Push on Save** (default) — push every time you save the project. Also triggers when the editor closes.
2. **Manual Only** — push only when you click **⬆ Save to GitHub (Push)**.
3. **Auto-Push on Close** — attempts to push when the editor is closed. Note: due to technical limitations, this push may not always complete if the editor shuts down before the upload finishes. For the most reliable automatic pushes, use **Auto-Push on Save**.

Click **Save Settings** after changing this option.

> **Tip:** When auto-push is enabled and no commit message is entered, a default message with the current date and time is used automatically.

> **Verifying your push:** You can always check whether your latest changes made it to GitHub by visiting your repository on [github.com](https://github.com) and looking at the most recent commit. If an auto-push on close was interrupted, simply reopen the project and push manually.

---

## Teacher / Student Roles and Classroom Repo Browser

The addon supports **Teacher** and **Student** roles for browsing repositories within a GitHub Classroom organization.

### For Teachers

1. Enable **Show Advanced Options** and select **Teacher** from the **Role** dropdown.
2. Enter the **Organization** name (the GitHub org used by your classroom).
3. Enter your **GitHub Token** and click **Save Settings**.
4. Click **Load My Assignments** in the **Classroom** section.
5. The addon verifies you are an **admin/owner** of the organization. If verified, all student repositories are loaded and organized into collapsible **assignment folders**.
   - Repositories that follow the GitHub Classroom naming convention (`{assignment}-{username}`) are automatically grouped by assignment name.
   - Expand a folder to see the individual student submissions for that assignment.
   - Repositories that don't match any shared assignment prefix appear at the top level.
6. Click a student repository in the tree to auto-fill the **Repository URL**, then use **⬇ Download Latest (Pull)** to download the student's project for review.

### For Students

1. Enter the **Organization** name.
2. Enter your **GitHub Token** and click **Save Settings**.
3. Click **Load My Assignments** — only repositories containing your GitHub username are shown (matching the `{assignment}-{username}` naming convention used by GitHub Classroom).
4. Click your repository in the list to auto-fill the Repository URL, then use **⬇ Download Latest (Pull)** / **⬆ Save to GitHub (Push)** as usual.

> **Note:** You can still enter the Repository URL manually by enabling **Show Advanced Options** — the Classroom section is optional.

---

## How It Works

The addon uses the [GitHub REST API](https://docs.github.com/en/rest) (specifically the Git Data API) to transfer files between the local Godot project and the remote GitHub repository.

- **⬇ Download Latest (Pull)** downloads every file from the repository and writes it into the project folder.
- **⬆ Save to GitHub (Push)** computes a local SHA-1 hash for each project file, compares it with the remote, uploads only the files that changed, and creates a new commit.

No local Git installation is needed at all.

### What Gets Synced

| Included | Excluded |
|----------|----------|
| All project files (scenes, scripts, assets, `project.godot`, etc.) | `.godot/` (editor cache) |
| `.gitignore`, `.gitattributes`, etc. | `.git/` (if present) |
| The addon itself (if included in the template) | OS junk files (`.DS_Store`, `Thumbs.db`) |

---

## Security — Shared Lab Computers

The addon is designed to be safe on shared desktop machines (computer labs) where multiple students log in to the same OS account or where different OS accounts share a common Godot installation.

| Protection | How it works |
|------------|--------------|
| **Per-OS-user config file** | Settings are stored in a file whose name includes the OS desktop username (e.g. `github_classroom_jsmith.cfg`). Student B's Godot session will never load Student A's token. |
| **Token obfuscation** | The GitHub Personal Access Token is not written to disk as plain text. A per-user XOR key is applied before saving. This is defense-in-depth (not cryptographic encryption) — it prevents casual snooping but is not a substitute for proper filesystem permissions on the machine. |
| **Sign Out button** | The **🔒 Sign Out / Clear Credentials** button (always visible) wipes the token, organization, and repository URL from both the panel and the config file in one click. **Always click Sign Out before logging out of the shared computer.** |
| **Teacher role verification** | Selecting the Teacher role always triggers a live GitHub API check. If your account is not an organization admin/owner, the addon immediately resets you to the Student role and saves that state — so you cannot be left in an unverified Teacher role. |
| **Repo list cleared on token change** | If you clear or change the token field, the repository list and repository URL are immediately cleared so a previous student's repo names are no longer visible. |
| **HTTPS only** | The addon rejects any `http://` repository URL with a clear error. All traffic goes over HTTPS. |

---

## Troubleshooting

| Message | What to Do |
|---------|------------|
| **Invalid repository URL** | Make sure the URL looks like `https://github.com/owner/repo`. |
| **HTTP 401: Bad credentials** | Your token is invalid or expired. Generate a new one. |
| **HTTP 403: Resource not accessible by personal access token** | Your token does not have write permission. This is common with **fine-grained tokens** and organization (GitHub Classroom) repositories. **Fix:** Create a **classic token** with the `repo` scope instead (see *Creating a GitHub Personal Access Token — Option A* above). If you prefer fine-grained tokens, make sure the organization allows them and that the **Resource owner** is the organization, not your personal account. |
| **HTTP 403: …** (other messages) | Your token does not have the required permissions. Make sure **Contents → Read and write** is enabled (fine-grained) or the **repo** scope is checked (classic). |
| **HTTP 404: Not Found** | Double-check the repository URL and make sure your token has access to that repository. |
| **Connection failed** | Check your internet connection and try again. |
| **No changes to push** | Your local files already match what is on GitHub. |
| **Push failed: X file(s) could not be uploaded** | One or more files failed to upload. Check the error messages above for details. A 403 error usually means a token permissions problem (see above). |
| **Teacher access requires organization admin/owner privileges** | Only organization owners/admins can use the Teacher role. The addon automatically resets you to the Student role. Ask your organization admin to grant you the owner role, or use the Student role. |
| **No repositories found** (Load My Assignments) | Make sure the organization name is correct and your token has access. Students: your GitHub username must appear in the repository name. |
| **Authentication failed** (Load My Assignments) | Your token could not be verified. Check that it is correct and not expired. |

---

## Project Structure

```
addons/
└── github_classroom/
    ├── plugin.cfg                  # Plugin metadata
    ├── plugin.gd                   # EditorPlugin entry point
    ├── github_api.gd               # GitHub REST API wrapper
    └── github_classroom_dock.gd    # Dock panel UI + pull/push logic
```

---

## Requirements

- **Godot 4.5** or later (tested with 4.5 and 4.6).
- A GitHub account with a Personal Access Token.
- An internet connection.

---

## License

This project is provided as-is for educational use. Feel free to modify and redistribute it for your classroom.