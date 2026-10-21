// Package gitutil wraps the handful of `git` invocations the qml-rice
// updater needs: reading the current/remote commit, listing local changes,
// and producing a one-line-per-commit changelog between two refs.
package gitutil

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

// Repo is a thin handle around a git working tree path.
type Repo struct {
	Dir string
}

func New(dir string) *Repo { return &Repo{Dir: dir} }

func (r *Repo) run(args ...string) (string, error) {
	out, err := r.runRaw(args...)
	return strings.TrimSpace(out), err
}

// runRaw is like run but only strips the trailing newline, preserving any
// leading whitespace on the first line -- needed for commands like
// `git status --porcelain` whose fixed-width status columns start with a
// space that strings.TrimSpace would otherwise eat.
func (r *Repo) runRaw(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = r.Dir
	var out, errBuf bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errBuf
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(errBuf.String()))
	}
	return strings.TrimRight(out.String(), "\n"), nil
}

// IsRepo reports whether Dir is (inside) a git working tree.
func (r *Repo) IsRepo() bool {
	_, err := r.run("rev-parse", "--is-inside-work-tree")
	return err == nil
}

// HeadCommit returns the current HEAD commit hash (short form).
func (r *Repo) HeadCommit() (string, error) {
	return r.run("rev-parse", "--short", "HEAD")
}

// HeadDescribe returns `git describe --tags --always`, i.e. the nearest tag
// if any, else the short commit hash.
func (r *Repo) HeadDescribe() (string, error) {
	return r.run("describe", "--tags", "--always")
}

// Fetch runs `git fetch` against the configured remote.
func (r *Repo) Fetch() error {
	_, err := r.run("fetch", "--quiet")
	return err
}

// RemoteRef returns the ref to compare local HEAD against after a fetch,
// e.g. "origin/main". It uses the upstream of the current branch if one is
// configured, falling back to origin/HEAD.
func (r *Repo) RemoteRef() (string, error) {
	if ref, err := r.run("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"); err == nil && ref != "" {
		return ref, nil
	}
	return r.run("rev-parse", "--abbrev-ref", "origin/HEAD")
}

// RemoteCommit returns the short commit hash the remote ref points at.
func (r *Repo) RemoteCommit(remoteRef string) (string, error) {
	return r.run("rev-parse", "--short", remoteRef)
}

// Changelog returns one line per commit reachable from remoteRef but not
// from HEAD, oldest last (git's default `log` order), in `<hash> <subject>`
// form. Empty slice (not an error) if there is nothing new.
func (r *Repo) Changelog(remoteRef string) ([]string, error) {
	out, err := r.run("log", "--oneline", "HEAD.."+remoteRef)
	if err != nil {
		return nil, err
	}
	if out == "" {
		return nil, nil
	}
	return strings.Split(out, "\n"), nil
}

// DirtyFiles returns the list of paths `git status --porcelain` reports as
// changed (staged, unstaged, or untracked) in the working tree.
func (r *Repo) DirtyFiles() ([]string, error) {
	out, err := r.runRaw("status", "--porcelain")
	if err != nil {
		return nil, err
	}
	if out == "" {
		return nil, nil
	}
	lines := strings.Split(out, "\n")
	files := make([]string, 0, len(lines))
	for _, l := range lines {
		if len(l) > 3 {
			files = append(files, strings.TrimSpace(l[3:]))
		}
	}
	return files, nil
}

// Pull fast-forwards the working tree to the remote ref.
func (r *Repo) Pull() error {
	_, err := r.run("pull", "--ff-only", "--quiet")
	return err
}

// PreviousCommit returns the commit hash before the given one (HEAD~1 style),
// used as the rollback target when no explicit backup exists.
func (r *Repo) PreviousCommit() (string, error) {
	return r.run("rev-parse", "--short", "HEAD~1")
}

// CheckoutCommit hard-resets the working tree to the given commit. Callers
// are expected to have already taken a config backup before calling this.
func (r *Repo) CheckoutCommit(commit string) error {
	_, err := r.run("checkout", commit)
	return err
}

// ChangedPaths returns the list of paths that changed between two commits,
// one per line in the order git diff reports them.
func (r *Repo) ChangedPaths(fromCommit, toCommit string) ([]string, error) {
	out, err := r.run("diff", "--name-only", fromCommit, toCommit)
	if err != nil {
		return nil, err
	}
	if out == "" {
		return nil, nil
	}
	return strings.Split(out, "\n"), nil
}
