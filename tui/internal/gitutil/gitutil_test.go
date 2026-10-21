package gitutil

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func requireGit(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed, skipping")
	}
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(),
		"GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@test",
		"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@test",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func initRepoWithCommit(t *testing.T, dir, filename, content string) {
	t.Helper()
	runGit(t, dir, "init", "--quiet", "--initial-branch=main")
	if err := os.WriteFile(filepath.Join(dir, filename), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, dir, "add", ".")
	runGit(t, dir, "commit", "--quiet", "-m", "commit: "+filename)
}

func TestIsRepo(t *testing.T) {
	requireGit(t)
	dir := t.TempDir()
	initRepoWithCommit(t, dir, "a.txt", "a")

	r := New(dir)
	if !r.IsRepo() {
		t.Fatal("expected IsRepo() true for a git-initialized dir")
	}

	notRepo := New(t.TempDir())
	if notRepo.IsRepo() {
		t.Fatal("expected IsRepo() false for a plain dir")
	}
}

func TestHeadCommitAndDirtyFiles(t *testing.T) {
	requireGit(t)
	dir := t.TempDir()
	initRepoWithCommit(t, dir, "a.txt", "a")

	r := New(dir)
	head, err := r.HeadCommit()
	if err != nil {
		t.Fatal(err)
	}
	if head == "" {
		t.Fatal("empty HEAD commit")
	}

	dirty, err := r.DirtyFiles()
	if err != nil {
		t.Fatal(err)
	}
	if len(dirty) != 0 {
		t.Fatalf("expected clean tree, got %v", dirty)
	}

	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("edited"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirty, err = r.DirtyFiles()
	if err != nil {
		t.Fatal(err)
	}
	if len(dirty) != 1 || dirty[0] != "a.txt" {
		t.Fatalf("expected [a.txt] dirty, got %v", dirty)
	}
}

func TestChangelogAndPull(t *testing.T) {
	requireGit(t)
	upstream := t.TempDir()
	initRepoWithCommit(t, upstream, "a.txt", "a")

	clone := t.TempDir()
	runGit(t, clone, "clone", "--quiet", upstream, ".")

	// Advance upstream with a second commit.
	if err := os.WriteFile(filepath.Join(upstream, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, upstream, "add", ".")
	runGit(t, upstream, "commit", "--quiet", "-m", "second commit")

	r := New(clone)
	if err := r.Fetch(); err != nil {
		t.Fatal(err)
	}

	log, err := r.Changelog("origin/main")
	if err != nil {
		t.Fatal(err)
	}
	if len(log) != 1 {
		t.Fatalf("expected 1 new commit in changelog, got %v", log)
	}

	if err := r.Pull(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(clone, "b.txt")); err != nil {
		t.Fatalf("expected b.txt to exist after pull: %v", err)
	}

	log, err = r.Changelog("origin/main")
	if err != nil {
		t.Fatal(err)
	}
	if len(log) != 0 {
		t.Fatalf("expected empty changelog after pull, got %v", log)
	}
}

func TestPreviousCommitAndCheckout(t *testing.T) {
	requireGit(t)
	dir := t.TempDir()
	initRepoWithCommit(t, dir, "a.txt", "a")

	r := New(dir)
	first, err := r.HeadCommit()
	if err != nil {
		t.Fatal(err)
	}

	if err := os.WriteFile(filepath.Join(dir, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, dir, "add", ".")
	runGit(t, dir, "commit", "--quiet", "-m", "second")

	prev, err := r.PreviousCommit()
	if err != nil {
		t.Fatal(err)
	}
	if prev != first {
		t.Fatalf("expected previous commit %s, got %s", first, prev)
	}

	if err := r.CheckoutCommit(prev); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "b.txt")); !os.IsNotExist(err) {
		t.Fatalf("expected b.txt to be gone after checkout to previous commit")
	}
}

func TestChangedPaths(t *testing.T) {
	requireGit(t)
	dir := t.TempDir()
	initRepoWithCommit(t, dir, "a.txt", "a")

	r := New(dir)
	first, err := r.HeadCommit()
	if err != nil {
		t.Fatal(err)
	}

	// Add new file and modify existing one
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("modified"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "b.txt"), []byte("b"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, dir, "add", ".")
	runGit(t, dir, "commit", "--quiet", "-m", "changes")

	second, err := r.HeadCommit()
	if err != nil {
		t.Fatal(err)
	}

	changed, err := r.ChangedPaths(first, second)
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 2 {
		t.Fatalf("expected 2 changed paths, got %d: %v", len(changed), changed)
	}
	// Check that both files are reported (order may vary)
	found := make(map[string]bool)
	for _, path := range changed {
		found[path] = true
	}
	if !found["a.txt"] || !found["b.txt"] {
		t.Fatalf("expected a.txt and b.txt in changes, got %v", changed)
	}
}

func TestChangedPathsNoChanges(t *testing.T) {
	requireGit(t)
	dir := t.TempDir()
	initRepoWithCommit(t, dir, "a.txt", "a")

	r := New(dir)
	head, err := r.HeadCommit()
	if err != nil {
		t.Fatal(err)
	}

	// Compare HEAD to itself
	changed, err := r.ChangedPaths(head, head)
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 0 {
		t.Fatalf("expected no changes when comparing commit to itself, got %v", changed)
	}
}
