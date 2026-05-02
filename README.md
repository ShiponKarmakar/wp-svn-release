<div align="center">

# 🚀 wp-svn-release

**Universal, interactive release tool for WordPress.org plugins.**

Auto-detects your plugin, validates versions, handles SVN — ship a release with one command.

[![Bash](https://img.shields.io/badge/bash-3.2%2B-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![Maintained](https://img.shields.io/badge/maintained-yes-brightgreen.svg)]()
[![Made by Shipon](https://img.shields.io/badge/made%20by-Shipon%20Karmakar-blue.svg)](https://github.com/ShiponKarmakar)

[Why](#-why) • [Install](#-install-2-minutes) • [Configure](#-configure-each-plugin-30-seconds) • [Release](#-release-a-new-version) • [How it works](#-how-it-works) • [Troubleshooting](#-troubleshooting)

</div>

---

## ✨ Why

Releasing a plugin to WordPress.org SVN is annoying:

- You have to remember the SVN command sequence (`svn update`, `rsync`, `svn add`, `svn cp trunk tags/X`, `svn ci`).
- You can accidentally release the wrong version if your `Version:` header and `Stable tag:` disagree.
- You can try to overwrite an already-released tag — WordPress.org tags are **immutable**, so this breaks things.
- Most teams end up with one ad-hoc shell script per plugin, all hardcoding paths and usernames.

**`wp-svn-release` fixes all of that.** Configure once per machine, configure each plugin once, then every release is one command:

```bash
wprel 1.2.3
```

The tool validates the version against three places (`Version:` header, `Stable tag:`, and your input), refuses to overwrite immutable tags, scrubs macOS junk, syncs source → trunk, creates the new tag, shows you a preview, and commits — only after you confirm.

---

## 📦 What's in this repo

| File | Purpose |
|---|---|
| **`wp-release-setup.sh`** | One-time setup wizard (machine-wide config + per-plugin config). |
| **`wp-release.sh`** | The daily release tool. The `wprel` alias points here. |
| **`README.md`** | This file. |
| **`.gitignore`** | Keeps personal aliases (`ALIASES.md`) and SVN passwords out of git. |

---

## 🛠 Requirements

All standard tools — nothing exotic to install:

| Tool | Why it's needed |
|---|---|
| `bash` 3.2+ | Ships with macOS. Pre-installed on most Linux distros. |
| `svn` | Talks to WordPress.org's SVN server. `brew install svn` on macOS, `apt install subversion` on Debian/Ubuntu. |
| `rsync`, `awk`, `grep`, `find` | Standard POSIX tools. Already on every Mac and Linux box. |

You also need a **WordPress.org account** with at least one plugin you've published, and your **SVN password** set at:

<https://profiles.wordpress.org/me/profile/edit/group/3/?screen=svn-password>

(Different from your WP.org login password. You set it once, ever. SVN remembers it via your OS keychain after the first commit.)

---

## 🚀 Install (2 minutes)

### Step 1 — Clone the repo

```bash
git clone https://github.com/ShiponKarmakar/wp-svn-release.git ~/wp-svn-release
cd ~/wp-svn-release
chmod +x wp-release.sh wp-release-setup.sh
```

### Step 2 — Run the setup wizard

```bash
./wp-release-setup.sh
```

You'll see:

```
═══════════════════════════════════════════════════════════════
  Phase 1 — Machine setup (one time per developer)
═══════════════════════════════════════════════════════════════

  These are MACHINE-WIDE settings that apply to every plugin you
  ever release. The wizard only asks for your username — the rest
  uses safe defaults you can edit by hand later if needed.

Your WordPress.org username: _
```

**Type your WP.org username and press Enter.** Then a summary appears:

```
─────────────────────────────────────────────────────────────
  About to install on this machine:
    WP.org username:    your-username
    SVN checkouts base: /Users/you/wp-svn
    Shell alias:        wprel
    Shell profile:      /Users/you/.zshrc
─────────────────────────────────────────────────────────────

Continue with these settings? [Y/n] _
```

**Press Enter.** Done. The wizard appends three lines to your shell profile and creates `~/wp-svn/` for future SVN checkouts.

### Step 3 — Reload your shell

```bash
source ~/.zshrc        # or ~/.bashrc if you use bash
type wprel             # confirm the alias is loaded
```

You should see:

```
wprel is an alias for /Users/you/wp-svn-release/wp-release.sh
```

✅ Machine setup is complete.

---

## 🔧 Configure each plugin (30 seconds)

Each plugin needs to be told once where its SVN checkout folder lives. Run the same wizard from inside the plugin's source folder:

```bash
cd /path/to/your/plugin/source            # the folder with your .php files and readme.txt
~/wp-svn-release/wp-release-setup.sh
```

The wizard auto-skips Phase 1 (already done) and runs only Phase 2:

```
═══════════════════════════════════════════════════════════════
  Phase 2 — Plugin setup (one time per plugin)
═══════════════════════════════════════════════════════════════

  Linking your plugin SOURCE folder to its SVN folder.

  Plugin source folder (where you develop)
    ↳ detected: /Users/you/path/to/your/plugin
    ↳ Press Enter to accept, or type a different path: _

  Plugin slug (the WP.org repo name)
    ↳ detected: my-plugin
    ↳ Press Enter to accept: _

  Main plugin PHP file
    ↳ detected: my-plugin.php
    ↳ Press Enter to accept: _

  SVN checkout folder
    ↳ detected: /Users/you/wp-svn/my-plugin
    ↳ Press Enter to accept: _
```

**Just press Enter at every prompt** — the auto-detected defaults are correct in 95% of cases.

If your SVN folder doesn't exist yet, the wizard offers to run `svn checkout` for you. Say **y** to that.

At the end, it offers to add a **per-plugin shortcut alias** so you can release without `cd`-ing first:

```
Add a shortcut alias for this plugin? [y/N] y
Alias name (lowercase letters/digits/hyphens only) [mp_rel]: mp
```

Now `mp 1.2.3` from anywhere on your machine releases this plugin.

✅ Plugin setup is complete. The wizard saved a `.svnrelease` config file in your plugin folder.

---

## 🎯 Release a new version

Three steps, every time.

### Step 1 — Bump the version in two files

Open your **main plugin PHP file** and change the `Version:` header:

```diff
  /*
   * Plugin Name: My Cool Plugin
-  * Version: 1.2.3
+  * Version: 1.2.4
   */
```

Open **readme.txt** and change the stable tag:

```diff
- Stable tag: 1.2.3
+ Stable tag: 1.2.4
```

Both numbers MUST match what you'll type next, or the tool refuses (this is a feature — it catches the most common release mistake).

### Step 2 — Preview the release (no SVN writes)

```bash
wprel --dry-run 1.2.4
```

You'll see exactly what would change, and any warnings, without anything being committed. Use this every time before a real release — it's free safety.

### Step 3 — Real release

```bash
wprel 1.2.4
```

Sample output of a real release:

```
─────────────────────────────────────────────────────────────
  Plugin slug:   my-plugin
  Source:        /Users/you/path/to/your/plugin
  Main file:     my-plugin.php
  SVN checkout:  /Users/you/wp-svn/my-plugin
  Releasing as:  v1.2.4
  Username:      your-username
─────────────────────────────────────────────────────────────

Use this config? [Y/n/edit] y
ℹ️  Updating SVN checkout…
🧹  Scrubbing macOS junk from source…
📦  Syncing source → trunk/…
📝  Reconciling SVN with the synced files…
🏷  Creating tags/1.2.4 (snapshot of trunk)…

==================== About to commit ====================
A  +    tags/1.2.4
M  +    tags/1.2.4/my-plugin.php
M  +    tags/1.2.4/readme.txt
M       trunk/my-plugin.php
M       trunk/readme.txt
…  (5 total changes)
=========================================================

Commit as v1.2.4? [y/N] y
🚀  Committing…
✅  v1.2.4 pushed to https://plugins.svn.wordpress.org/my-plugin
   Public page updates within ~15 min: https://wordpress.org/plugins/my-plugin/
```

That's it. Your release is live on WordPress.org within ~15 minutes.

---

## 📋 Command reference

| Command | What it does |
|---|---|
| `wprel <version>` | Release a new version. The main daily command. |
| `wprel --dry-run <version>` | Preview the release. No SVN writes. **Run this before every real release.** |
| `wprel --reconfigure <version>` | Re-run the per-plugin wizard before releasing. Use if you moved the SVN folder. |
| `wprel --help` | Show help. |
| `<short-alias> <version>` | Per-plugin alias (if you set one). Releases that specific plugin from anywhere. |

---

## 📁 Files written / managed

| File | Where | What it holds | Commit to git? |
|---|---|---|---|
| `~/.zshrc` (or `.bashrc`) | Your home folder | `WP_SVN_USER`, `WP_SVN_BASE`, `wprel` alias, per-plugin aliases | N/A — this is your shell profile |
| `<plugin-source>/.svnrelease` | Inside each plugin's source folder | `slug`, `main_file`, `svn_dir`, `assets_src` | ✅ Yes — safe, no secrets |
| `~/wp-svn/<plugin-slug>/` | SVN base folder | The SVN working copy (trunk/, tags/, assets/) | ❌ Not your concern — managed by SVN |
| `wp-svn-release/ALIASES.md` | This repo's folder on your machine | Auto-tracked list of every per-plugin alias | ❌ No — gitignored, per-machine |

### What `.svnrelease` looks like

```ini
# wp-release per-plugin config (managed by wp-release-setup.sh)
# Safe to commit — contains no secrets.
slug=my-plugin
main_file=my-plugin.php
svn_dir=/Users/you/wp-svn/my-plugin
assets_src=
```

> **Backward compatibility:** older versions named this file `.wprelease`. The release script reads either name. Re-run `wp-release-setup.sh` from the plugin folder to migrate to the new name.

---

## 🔧 How it works

```
┌──────────────────────────────┐                 ┌──────────────────────────────┐
│   wp-release-setup.sh        │  ── writes ──▶  │  ~/.zshrc                    │
│   (run once per machine,     │                 │    export WP_SVN_USER=…      │
│    once per plugin)          │                 │    export WP_SVN_BASE=…      │
│                              │                 │    alias wprel=…             │
└──────────────────────────────┘                 └──────────────────────────────┘
              │                                                  │
              │ writes per-plugin config                         │ alias →
              ▼                                                  ▼
┌──────────────────────────────┐                 ┌──────────────────────────────┐
│   <plugin-source>/.svnrelease│  ── read by ─▶  │  wp-release.sh               │
│     slug=my-plugin           │                 │  (run on every release)      │
│     main_file=…              │                 │                              │
│     svn_dir=…                │                 │  rsync, svn cp, svn ci, etc. │
└──────────────────────────────┘                 └──────────────────────────────┘
```

**Two scripts, two jobs.** Setup configures things once. The release script does the daily work. Each plugin gets a tiny `.svnrelease` config in its source folder so it remembers its SVN location forever.

### Step-by-step on every `wprel <version>`

1. **Reads `.svnrelease`** from the current folder to know the slug and SVN folder.
2. **Validates the version** against the `Version:` header in the main PHP file AND the `Stable tag:` in `readme.txt`. If any disagree → ❌ refuses.
3. **Checks `tags/<version>` doesn't already exist in SVN** (immutable). If it does → ❌ refuses.
4. **Scrubs** `.DS_Store` and `._*` from the source folder.
5. **`rsync`s** source → `trunk/`, excluding dev artifacts (`.git`, `node_modules`, etc., or your `.distignore` if present).
6. **Reconciles** SVN: `svn add` new files, `svn rm` deleted files.
7. **Creates `tags/<version>`** as a snapshot of `trunk/`.
8. **Shows you a preview** of every changed file.
9. **Asks for confirmation** — last chance to cancel.
10. **`svn ci`** with the message `Release v<version>`. Live on WordPress.org within ~15 minutes.

---

## 🔒 Safety guarantees

- **Never stores SVN passwords.** Your password is handled by SVN's own keychain integration after the first commit. `wp-svn-release` never sees it.
- **Never edits your shell profile silently.** The wizard always shows you the lines and asks for confirmation before appending.
- **Refuses to overwrite immutable tags.** WordPress.org tags can never be re-released. If you try `wprel 1.2.3` after 1.2.3 is already up, the tool stops you.
- **Triple-validates the version.** The version you type must match `Version:` AND `Stable tag:`. Catches the most common release mistake.
- **Preview before commit.** You always see the full changeset and confirm before any SVN write happens.

---

## 🛟 Troubleshooting

### `WP_SVN_USER is not set`
You haven't reloaded your shell since running the setup wizard. Run `source ~/.zshrc` (or open a new terminal).

### `Version mismatch in <file>`
Your `Version:` header (or `readme.txt` Stable tag) doesn't match the version you typed. Open the file, fix the number so all three agree, then re-run.

### `tags/X.Y.Z already exists in SVN. Tags are immutable; pick a new version.`
You can't re-release the same version on WordPress.org. Bump the number to the next one (e.g. 1.2.3 → 1.2.4).

### `No SVN checkout at: …`
First time releasing this plugin from this machine. Re-run the setup wizard for this plugin and say **y** when it offers `svn checkout`. Or do it manually:

```bash
mkdir -p ~/wp-svn
svn checkout https://plugins.svn.wordpress.org/<your-slug> ~/wp-svn/<your-slug>
```

### `command not found: wprel` (or your per-plugin alias)
The alias is in `~/.zshrc` but your current terminal hasn't loaded it. Run `source ~/.zshrc` or open a new terminal.

### A release errored out mid-way
Local SVN state may be inconsistent. Reset it:

```bash
cd ~/wp-svn/<your-slug>
svn revert -R .       # discard local changes
svn cleanup           # if "working copy locked"
# then re-run wprel
```

### I forgot what I named my per-plugin alias
Three ways to find it:

```bash
cat ~/wp-svn-release/ALIASES.md           # the auto-tracked list
grep '^alias' ~/.zshrc | grep -i wprel    # search shell profile
alias | grep -i wp                        # search loaded aliases
```

### Wrong values in `.svnrelease`
Two ways to fix:

1. Edit the file by hand — it's plain key=value text.
2. Re-run `wp-release-setup.sh` from the plugin source folder. It detects the existing `.svnrelease`, pre-fills your previous answers as defaults, and lets you change any field.

---

## 🌟 Pro tips

- **Always dry-run first:** `wprel --dry-run 1.2.4` before `wprel 1.2.4`. Free safety net.
- **Use `.distignore`** in your plugin source folder to control what gets shipped to WP.org. The release script honors it (matches WP.org's official tooling). If absent, a sensible default exclude list is used.
- **Per-plugin alias = power user move.** When you have 5+ plugins, typing `mp 1.2.4` from anywhere beats remembering paths.
- **Commit `.svnrelease`** to your plugin's git repo. Anyone on the team who clones it can immediately run `wprel <version>` after their own machine setup — no per-plugin config needed.

---

## 🤝 Contributing

PRs welcome. Especially valuable:

- **Bug reports** with the failing terminal output and your `~/.zshrc` snippet (sanitized).
- **OS coverage** — currently tested on macOS and Ubuntu. If you run into issues on FreeBSD, Alpine, etc., file an issue.
- **Feature ideas** that fit the "simple, portable, daily-use" philosophy. Avoid feature creep.

---

## 📄 License

[MIT](./LICENSE) — free to use, modify, and share.

---

## 👤 Author

**Shipon Karmakar** — WordPress plugin developer.

Built this so my team could publish releases without memorizing SVN commands. If it saves you time, share it with another plugin developer.

- GitHub: [@ShiponKarmakar](https://github.com/ShiponKarmakar)
- WordPress.org: <https://profiles.wordpress.org/shiponkarmakar/>

---

<div align="center">

⭐ **If this saved you time, star the repo.**

Made for the WordPress plugin community.

</div>
