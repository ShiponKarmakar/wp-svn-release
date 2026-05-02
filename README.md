# wp-release

> Universal release tool for WordPress.org plugins. By **Shipon Karmakar**.

A friendly release tool for WordPress.org plugins. Works for any plugin, any developer, any Mac or Linux.

You run a setup wizard once per machine and once per plugin. After that, releasing a new version is one command:

```bash
wprel 1.2.3
```

The tool handles SVN updates, version validation, the rsync to `trunk/`, the immutable `tags/X.Y.Z` snapshot, the preview, and the commit. You only see prompts that actually need your input.

---

## Contents

- [What you get](#what-you-get)
- [Files in this folder](#files-in-this-folder)
- [Requirements](#requirements)
- [Install (one-time per developer)](#install-one-time-per-developer)
- [Configure each plugin](#configure-each-plugin)
- [Releasing a version](#releasing-a-version)
- [The `.svnrelease` file](#the-wprelease-file)
- [Aliases & env vars reference](#aliases--env-vars-reference)
- [Common gotchas](#common-gotchas)
- [Troubleshooting](#troubleshooting)

---

## What you get

- **One alias for every plugin you own.** No need for a separate alias per plugin — just `wprel`. (Per-plugin shortcut aliases are still supported as an opt-in convenience.)
- **Auto-detection.** Plugin slug, main PHP file, version → all read from your folder.
- **Triple version validation.** The version you type must match the `Version:` header AND `readme.txt` Stable tag. No silent mismatches.
- **Refuses to overwrite immutable tags.** WordPress.org tags can never be re-released — the tool stops you before you make a mistake.
- **Preview before commit.** You always see what's about to be pushed, with a single Y/N confirmation.
- **Safe by default.** No destructive action runs without your confirmation. Your shell profile is never edited silently.

---

## Files in this folder

| File | Run when | What it does |
|---|---|---|
| `wp-release-setup.sh` | Once per machine + once per plugin | Configures your shell profile and writes `.svnrelease` for the current plugin. |
| `wp-release.sh` | Every release (`wprel 1.2.3`) | Does the actual rsync, `svn cp`, `svn ci`. The alias points here. |
| `README.md` | — | This file. |

You always run `wp-release-setup.sh` first. After that, you only ever type `wprel <version>`.

---

## Requirements

All standard tools — nothing exotic to install:

- `bash` (3.2+ — ships with macOS)
- `svn`, `rsync`, `awk`, `grep`, `find` — POSIX

Tested on macOS and Linux.

---

## Install (one-time per developer)

```bash
# 1. Clone or download this folder somewhere stable
git clone <your-repo> ~/shell-scripts

# 2. Run the setup wizard
cd ~/shell-scripts/WP-SVN-Release
chmod +x wp-release.sh wp-release-setup.sh
./wp-release-setup.sh
```

The wizard splits into two phases. **You don't have to do them at the same time.**

### Phase 1 — Machine setup (one time, then auto-skipped)

The wizard asks 4 things:

| Question | Default | Notes |
|---|---|---|
| Your WordPress.org username | — | Required. Used by `svn ci --username`. |
| Default folder for SVN checkouts | `~/wp-svn` | Where each plugin's SVN working copy lives by default. |
| Shell alias | `wprel` | Short command you'll type to release. |
| Shell profile to update | auto-detected (`.zshrc` / `.bashrc`) | The file that gets the snippet. |

It then **shows you** the exact lines it will append to your shell profile, asks `[Y/n]`, and only writes after you confirm. Nothing is modified silently.

After Phase 1, reload your shell:

```bash
source ~/.zshrc       # or ~/.bashrc — whatever profile you picked
type wprel            # confirm the alias is wired up
```

You also need to set your **SVN password** (different from your wordpress.org login password) — once, ever — at:
<https://profiles.wordpress.org/me/profile/edit/group/3/?screen=svn-password>

The first time you do an `svn ci`, SVN will ask for that password and cache it in your OS keychain. After that you'll never type it again.

---

## Configure each plugin

For each plugin you own, run the same wizard from inside the plugin's source folder:

```bash
cd /path/to/your/plugin/source
~/shell-scripts/WP-SVN-Release/wp-release-setup.sh
```

The wizard auto-skips Phase 1 (you already did it) and runs only Phase 2.

### Phase 2 — Plugin setup

The wizard asks 5 things, with auto-detected defaults you can hit Enter on:

| Question | Default | Notes |
|---|---|---|
| Plugin source folder | current folder | The folder you `cd`'d into. |
| Plugin slug | basename of folder | The exact name on WordPress.org. |
| Main PHP file | auto-detected (`Plugin Name:` header) | The file with the `Version:` header. |
| SVN checkout folder | `~/wp-svn/<slug>` | Where `trunk/`, `tags/`, `assets/` live. |
| Marketing assets folder | empty (skipped) | Optional. PNGs for your WP.org listing page. |

The wizard then:

1. **Validates the SVN folder.** Shows a checklist:
   ```
   [✓] .svn/ working copy
   [✓] trunk/
   [✓] tags/  (3 existing release tags)
   [✓] assets/
   ```
2. **Offers to run `svn checkout`** if the SVN folder doesn't exist yet.
3. **Prints a summary** with the WP.org page URL, SVN repository URL, detected version, detected stable tag, and both folders side-by-side.
4. **Shows the `.svnrelease` content** it's about to write, asks `[Y/n]`, then writes it.

That's it for setup. The plugin is now linked.

---

## Releasing a version

After setup, releasing is one line:

```bash
cd /path/to/your/plugin/source
wprel 1.2.3
```

Sample output:

```
🧹  Scrubbing macOS junk from source…
📥  Updating local SVN checkout…
🚫  Refusing to overwrite an existing tag (tags are immutable).
📦  Syncing source → trunk/…
📝  Reconciling SVN with the synced files…
🏷  Creating tags/1.2.3 (snapshot of trunk)…

==================== About to commit ====================
A  +    tags/1.2.3
M  +    tags/1.2.3/my-plugin.php
M       trunk/my-plugin.php
…  (19 total changes)
=========================================================

Commit as v1.2.3? [y/N] y
🚀  Committing…
✅  v1.2.3 pushed to https://plugins.svn.wordpress.org/my-plugin
   Public page updates within ~15 min: https://wordpress.org/plugins/my-plugin/
```

If anything's wrong, you see a red ❌ with the exact reason — version mismatch, missing SVN folder, tag already exists, etc. — before any destructive action runs.

### Flags

| Flag | What it does |
|---|---|
| `wprel <version>` | Release. |
| `wprel --dry-run <version>` | Show what *would* change. Don't touch SVN. Doesn't commit. Safe for testing. |
| `wprel --reconfigure <version>` | Re-run the in-script wizard before releasing. Updates `.svnrelease`. |
| `wprel --help` | Print full usage. |

---

## The `.svnrelease` file

Written by the setup wizard into the plugin source folder. Plain `key=value` text — safe to commit to git, no secrets:

```ini
# wp-release per-plugin config (managed by wp-release-setup.sh)
slug=my-plugin
main_file=my-plugin.php
svn_dir=/Users/you/wp-svn/my-plugin
assets_src=
```

> **Backward compatibility:** if you have an older `.wprelease` file from a previous version, the release script reads it automatically. Re-run `wp-release-setup.sh` from the plugin folder to migrate to the new `.svnrelease` name.

| Key | Meaning |
|---|---|
| `slug` | The plugin slug as it appears on WordPress.org. |
| `main_file` | Main plugin PHP file (filename only, no path). |
| `svn_dir` | Absolute path to the SVN working copy. |
| `assets_src` | Optional. Local folder with marketing PNGs. Empty = skip. |

Edit by hand if anything ever changes. Or re-run the setup wizard from inside the plugin folder — it pre-fills your previous answers.

---

## Aliases & env vars reference

Everything the setup script adds to your shell profile.

| Name | Type | Default | Purpose |
|---|---|---|---|
| `WP_SVN_USER` | env var (required) | — | Your WordPress.org username. Used by `svn ci`. |
| `WP_SVN_BASE` | env var | `~/wp-svn` | Base folder where each plugin's checkout lives, as `<base>/<slug>`. |
| `wprel` | alias | — | Points to `wp-release.sh`. Run from any plugin source folder. |

To inspect what's set in your current shell:

```bash
echo "$WP_SVN_USER"
echo "$WP_SVN_BASE"
type wprel
```

---

## Common gotchas

- **Username is case-sensitive.** Use it exactly as you registered on WordPress.org.
- **`Stable tag:` in `readme.txt` MUST match the latest tag folder.** The script catches mismatches before commit. If you ever release manually, a mismatch means users can't download anything.
- **Tags are immutable.** Never edit files inside `tags/X.Y.Z/` after committing. To fix a release: bump the version, edit `trunk/`, create a new tag.
- **Plugin assets — two different `assets/` folders.** Your plugin's source folder may have an `assets/` directory with CSS/JS — that's plugin code and gets rsynced into `trunk/assets/`. The WP.org `assets/` (sibling of `trunk/`) is for marketing PNGs only — banners, icons, screenshots — and is *not* shipped with the plugin.

---

## Troubleshooting

### "WP_SVN_USER is not set"
You haven't reloaded your shell since running the setup wizard. Run `source ~/.zshrc` (or open a new terminal).

### "Version mismatch in `<file>`"
The version in your `Version:` header (or `readme.txt` Stable tag) doesn't match the version you typed. Fix one so they agree, then re-run.

### "tags/X.Y.Z already exists in SVN"
WordPress.org tags are immutable. You can't re-release the same version — bump the number.

### "No SVN checkout at: …"
First time releasing this plugin from this machine. Re-run the setup wizard and say **yes** when it offers to run `svn checkout`. Or do it manually:

```bash
mkdir -p ~/wp-svn
svn checkout https://plugins.svn.wordpress.org/<your-slug> ~/wp-svn/<your-slug>
```

### A release errored out mid-way
Local SVN state may be inconsistent. Reset it:

```bash
cd "$WP_SVN_BASE/<slug>"
svn revert -R .       # discard local changes
svn cleanup           # if "working copy locked"
# then re-run wprel
```

### Wrong values in `.svnrelease`
Two ways to fix:

1. Edit the file by hand.
2. Re-run `wp-release-setup.sh` from the plugin source folder. It detects the existing `.svnrelease`, pre-fills your previous answers as defaults, and lets you change any field.

### `xargs -r` errors on macOS
Shouldn't happen — the script avoids `xargs -r` for BSD compatibility. If you see it, you're running an older copy of `wp-release.sh`. Pull the latest.

---

## Notes for maintainers

- Two scripts, one job each:
  - `wp-release-setup.sh` is an installer/configurator (runs once per developer + once per plugin).
  - `wp-release.sh` is the daily tool (runs every release; the `wprel` alias points here).
- `set -euo pipefail` is on in both. Errors abort.
- Portability quirks worth knowing:
  - macOS BSD `xargs` has no `-r`; the script uses a `while read` loop.
  - macOS bash is 3.2 — no associative arrays, no `${var,,}`.
  - All `find` invocations use POSIX flags only.
- The `.svnrelease` file is `key=value` text and is parsed line-by-line, not `source`-d. Adding unknown keys is safe — they're ignored. The release script reads `slug`, `main_file`, `svn_dir`. The setup script writes those plus `assets_src` (reserved for future use).

---

## Credits

Built and maintained by **Shipon Karmakar**.

Tested on macOS and Linux. POSIX-friendly bash so it runs anywhere. No external dependencies beyond `svn`, `rsync`, `awk`, `grep`, `find`.

If this tool saves you time, share it with another plugin developer.
