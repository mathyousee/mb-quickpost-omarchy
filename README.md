# Micro.blog quick post for Omarchy

A keyboard-driven Micro.blog composer for Omarchy/Hyprland.

Press **SUPER+CTRL+M** to open the Quickshell composer with wrapping and a
live character count. The ~500-character target is advisory, not a hard limit.
**Enter** inserts a newline; **Ctrl+Enter** or **Post** publishes; **Escape**
or **Cancel** discards. Empty or whitespace-only notes are not posted.

The multiline composer is the only posting interface; the former single-line
prompt has been removed.

## Composer

Unstashed drafts stay in memory, with no draft, backup, history, or temporary input file.
The composer sends the text through a pipe to `microblog-post --stdin`;
the script passes it to curl through another pipe, not command-line arguments.
The existing posting code still uses private temporary response/error files,
which are deleted when it exits. As with other desktop apps, this does not
protect memory from same-user malware, system swap, or crash dumps.

The composer closes after successful posting. On failure it keeps your draft
open; check the notification and your blog before retrying. While a request
is in flight, editing and cancellation are disabled to avoid an ambiguous
partial send. No automatic retries occur.

### Stash and resume

Click **Stash** or press **Ctrl+S** to save the current note and clear the
editor. Click **Drafts (count)** or press **Ctrl+O** to review saved notes,
shown newest first with their save date and first line. Choose **Resume** to
continue one, or **Delete** to remove it. In the list, arrow keys select a
draft, **Enter** resumes it, and **Delete** removes it. Replacing unfinished text requires confirmation.
**Escape** goes back from the list or confirmation before closing the composer.

Resuming does not remove the saved copy. Stashing a resumed note updates that
copy instead of creating a duplicate. Successful posting removes the resumed
stash; a failed post leaves it saved and keeps the edited text in the composer.
Closing or cancelling a resumed note also leaves its saved copy intact.
If post-success stash cleanup fails, the composer warns that the post was
published and disables further posting to avoid duplicates.

Stashes are plaintext in `~/.local/state/microblog/drafts.json` (or under
`$XDG_STATE_HOME/microblog` when set), separate from the token and this project.
The directory has permissions `700`; the JSON and lock files have permissions
`600`. Writes are atomic and locked. Stashes survive reboot and may be included
in your backups. They are not encrypted or synced by this tool; deleting one is
not a secure erase of filesystem snapshots or backups.

Storage uses `~/.local/bin/microblog-drafts`, a Python 3 standard-library helper.
No third-party Python packages are required.

The launcher is `~/.local/bin/microblog-compose`; its UI is installed at
`~/.config/quickshell/microblog-compose/shell.qml`. It uses the Micro.blog app
token configured during setup below. The Hyprland binding is:

```lua
o.bind("SUPER + CTRL + M", "Micro.blog multiline post", os.getenv("HOME") .. "/.local/bin/microblog-compose")
```

## Setup

Requires a current Omarchy installation, Quickshell with Qt Quick Controls,
Bash, Python 3, curl, notify-send, jq, and standard Unix utilities.
The example Hyprland binding above uses Omarchy's Lua configuration.

From the cloned repository, install the scripts and composer:

```sh
mkdir -p ~/.local/bin ~/.config/microblog
chmod 700 ~/.config/microblog
install -m 755 microblog-post ~/.local/bin/microblog-post
install -m 755 microblog-compose ~/.local/bin/microblog-compose
install -m 755 microblog-drafts ~/.local/bin/microblog-drafts
install -Dm 644 shell.qml ~/.config/quickshell/microblog-compose/shell.qml
(umask 077; touch ~/.config/microblog/token)
chmod 600 ~/.config/microblog/token
```

Ensure `~/.local/bin` is on your PATH. Add the Lua binding example in this
README to `~/.config/hypr/bindings.lua`, checking for conflicts first and
choosing a different shortcut if necessary. When upgrading from the original
two-prompt version, remove the old `SUPER+ALT+M` binding to `microblog-post`.

1. Open `~/.config/microblog/token` locally in your editor. Paste a Micro.blog
   app token on its own line, below any comment, then save. Do not add quotes or
   `Bearer`. Keep the token file outside this project
   and never commit or share it.
2. Run `hyprctl reload`, then `hyprctl configerrors` to check the config.
   Hyprland may also automatically load saved configuration changes.
3. Press **SUPER+CTRL+M** and publish a note when ready.

`microblog-compose` opens the editor. `microblog-post --stdin` is its internal
posting helper, not a separate prompt. The helper sends a single POST to
`https://micro.blog/micropub` with form
fields `h=entry` and `content`, using the token as a Bearer authorization header.
The token is passed to curl through standard input, not command-line arguments.
Notifications show the returned `Location` header or JSON `url`, when supplied,
otherwise a simple confirmation. Failures show the HTTP status and a bounded
error excerpt. Requests time out after 30 seconds and are never automatically
retried, to avoid duplicate posts. A timeout can still mean the server published
the note: check your blog before trying again.

## Updating

To update an existing installation after editing the project files:

```sh
install -m 755 microblog-post ~/.local/bin/microblog-post
install -m 755 microblog-compose ~/.local/bin/microblog-compose
install -m 755 microblog-drafts ~/.local/bin/microblog-drafts
install -Dm 644 shell.qml ~/.config/quickshell/microblog-compose/shell.qml
```

The token and saved drafts live outside this repository. To remove the
hotkey, remove its binding and reload Hyprland.

Local, non-network storage and posting checks:

```sh
python3 -m unittest discover -s tests -p 'test_drafts.py'
bash tests/test-post.sh
```
