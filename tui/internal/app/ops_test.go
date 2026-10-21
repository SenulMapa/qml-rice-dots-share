package app

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestShellCommandWithoutAppScope(t *testing.T) {
	home := t.TempDir()
	if got := appScopePath(home); got != "" {
		t.Fatalf("appScopePath with no helper = %q, want empty", got)
	}
	if got := appScopePath(""); got != "" {
		t.Fatalf("appScopePath with no home = %q, want empty", got)
	}
	want := []string{"qs", "-p", "./shell.qml"}
	if got := shellCommand(appScopePath(home)); !reflect.DeepEqual(got, want) {
		t.Fatalf("shellCommand = %v, want %v", got, want)
	}
}

func TestShellCommandNonExecutableAppScopeIgnored(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, ".local", "bin", "app-scope")
	writeTestFile(t, path, "#!/bin/sh\n")
	if got := appScopePath(home); got != "" {
		t.Fatalf("appScopePath with non-executable helper = %q, want empty", got)
	}
}

func TestShellCommandWithAppScope(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, ".local", "bin", "app-scope")
	writeTestFile(t, path, "#!/bin/sh\n")
	if err := os.Chmod(path, 0o755); err != nil {
		t.Fatal(err)
	}
	if got := appScopePath(home); got != path {
		t.Fatalf("appScopePath = %q, want %q", got, path)
	}
	want := []string{path, "--unit", "qml-rice-shell", "shell", "--", "qs", "-p", "./shell.qml"}
	if got := shellCommand(appScopePath(home)); !reflect.DeepEqual(got, want) {
		t.Fatalf("shellCommand = %v, want %v", got, want)
	}
}
