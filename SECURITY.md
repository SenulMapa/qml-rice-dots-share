# Security & privacy gate

This repo (and the vendored `shell/` subtree from `qml-rice`) ships personal
dotfiles and an installer that runs on the owner's machine. Before any push
— private now, public later — nothing personal or secret should leave this
machine. That is enforced two ways:

> **Keep this repository PRIVATE.** Commits 79200ec..7ee88b6 (the greetd
> greeter, pushed from the laptop) carry the owner's username and home path in
> git history. The working tree is scrubbed, but history is not rewritten, so
> the repo must never be made public unless that history is rewritten first.

## 1. Local pre-push hook

Enable it once per clone:

```sh
git config core.hooksPath .githooks
```

From then on, `git push` runs `tools/privacy-audit.sh <repo> --history`
against the full history of the repo and blocks the push if it finds any
FAIL-level issue: secrets, personal identifiers, stray metadata/log/state
artefacts, or an embedded `.git` directory. WARN-level findings (installer
attack-surface hygiene, telemetry/network calls, non-default commit emails)
are printed but do not block.

To bypass in a genuine emergency: `git push --no-verify`. This is strongly
discouraged — it skips the gate entirely.

## 2. CI secret scan

`.github/workflows/secrets.yml` runs `gitleaks` (using `.gitleaks.toml`) on
every push and PR with full fetch depth, as a backstop for anyone who pushes
without the local hook enabled.

## 3. Manual / deeper audit

```sh
tools/privacy-audit.sh /path/to/repo             # working tree only
tools/privacy-audit.sh /path/to/repo --history   # + every blob in git history
```

The script combines `gitleaks` and `trufflehog` (if installed locally) with
built-in regexes for common secret formats, a personal-identifier scan, EXIF/
metadata checks on images, and installer/attack-surface warnings (curl|sh,
sudo, chmod 777, eval of downloaded content, unpinned downloads, outbound
network calls). It is fully offline — no network calls, and secrets found by
trufflehog are never sent to a verification endpoint (`--no-verification`).

### Personal-identifier denylist

`tools/privacy-audit.sh` also greps for the owner's personal identifiers
(usernames, home paths, hostnames, local/Tailscale IPs, MACs, Wi-Fi SSIDs,
etc.) via a local file: `tools/.personal-denylist`. That file is **not**
shipped in this repo — it is gitignored and must be created locally (see the
script header for the exact contents expected) before relying on that part
of the audit. Verify it's actually ignored with:

```sh
git check-ignore -v tools/.personal-denylist
```

## Known accepted risk

Commit author/committer email (`mapasenul@gmail.com`) is intentionally
public in commit metadata once pushed — these repos are used as public
code-portfolio proof. If that becomes undesirable later, GitHub's
`noreply` email rewrite (`git config user.email <id>+user@users.noreply.github.com`,
applied going forward — this does not rewrite existing history) is an
option; it has not been applied here.

## Scope

Installer/updater attack-surface findings (unsigned pulls, `curl | sh`
patterns, IPC/lock-fallback behavior, clipboard/notification access) are
reported as WARN, not FAIL — they need a human judgement call, not an
automatic block. Review them before making the repo public.
