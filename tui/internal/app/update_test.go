package app

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/SenulMapa/qml-rice-dots/tui/internal/manifest"
)

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestShouldRebuildTUI(t *testing.T) {
	tests := []struct {
		name    string
		changed []string
		want    bool
	}{
		{
			name:    "no changes",
			changed: []string{},
			want:    false,
		},
		{
			name:    "tui changes",
			changed: []string{"tui/cmd/qml-rice/main.go"},
			want:    true,
		},
		{
			name:    "tui internal changes",
			changed: []string{"tui/internal/app/update.go"},
			want:    true,
		},
		{
			name:    "non-tui changes",
			changed: []string{"hypr/hyprland.lua", "shell/bar.qml"},
			want:    false,
		},
		{
			name:    "mixed changes with tui",
			changed: []string{"hypr/hyprland.lua", "tui/go.mod", "shell/bar.qml"},
			want:    true,
		},
		{
			name:    "tui-like name but not tui path",
			changed: []string{"tuition.txt"},
			want:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := shouldRebuildTUI(tt.changed)
			if got != tt.want {
				t.Errorf("shouldRebuildTUI(%v) = %v, want %v", tt.changed, got, tt.want)
			}
		})
	}
}

func TestDeployHyprWithHyprlock(t *testing.T) {
	// Set up a temporary repo structure
	dir := t.TempDir()
	repo := filepath.Join(dir, "repo")
	config := filepath.Join(dir, "config")
	state := filepath.Join(dir, "state")

	if err := os.MkdirAll(config, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(state, 0o755); err != nil {
		t.Fatal(err)
	}

	// Set up source (repo) structure
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprland.lua"), "hyprland content")
	writeTestFile(t, filepath.Join(repo, "hypr", "hypridle.conf"), "hypridle content")
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprlock.conf"), "hyprlock content")
	writeTestFile(t, filepath.Join(repo, "hypr", "monitors.lua"), "monitors content")
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprland", "rules.lua"), "rules content")
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprlock", "colors.conf"), "colors content")
	writeTestFile(t, filepath.Join(repo, "hypr", "custom", "override.lua"), "custom content")

	// Create paths
	hyprCfg := filepath.Join(config, "hypr")
	manifestFile := filepath.Join(state, "manifest.json")

	p := Paths{
		InstallDir:   repo,
		HyprCfg:      hyprCfg,
		ManifestFile: manifestFile,
	}

	// Deploy
	noop := func(string) {}
	err := deployHypr(p, false, noop)
	if err != nil {
		t.Fatalf("deployHypr failed: %v", err)
	}

	// Verify managed files were deployed
	for _, f := range []string{
		"hyprland.lua",
		"hypridle.conf",
		"hyprlock.conf",
		"hyprland/rules.lua",
		"hyprlock/colors.conf",
	} {
		path := filepath.Join(hyprCfg, f)
		if _, err := os.Stat(path); err != nil {
			t.Errorf("managed file not deployed: %s", f)
		}
	}

	// Verify user-owned files were NOT deployed
	if _, err := os.Stat(filepath.Join(hyprCfg, "monitors.lua")); err == nil {
		t.Error("monitors.lua should not be deployed by updater")
	}
	if _, err := os.Stat(filepath.Join(hyprCfg, "custom", "override.lua")); err == nil {
		t.Error("custom/override.lua should not be deployed by updater")
	}

	// Verify manifest was built correctly
	m, err := manifest.Load(manifestFile)
	if err != nil {
		t.Fatalf("failed to load manifest: %v", err)
	}

	// Manifest should include managed files
	managedPaths := []string{
		"hyprland.lua",
		"hypridle.conf",
		"hyprlock.conf",
		"hyprland/rules.lua",
		"hyprlock/colors.conf",
	}
	for _, p := range managedPaths {
		if _, ok := m.Files[p]; !ok {
			t.Errorf("manifest missing managed file: %s", p)
		}
	}

	// Manifest should NOT include user-owned files
	if _, ok := m.Files["monitors.lua"]; ok {
		t.Error("manifest should not include monitors.lua")
	}
	if _, ok := m.Files["custom/override.lua"]; ok {
		t.Error("manifest should not include custom/override.lua")
	}

	// Total files should be exactly the managed ones
	if len(m.Files) != len(managedPaths) {
		t.Errorf("expected %d files in manifest, got %d: %+v",
			len(managedPaths), len(m.Files), m.Files)
	}
}

func TestDeployHyprSkipsLocallyModifiedFiles(t *testing.T) {
	dir := t.TempDir()
	repo := filepath.Join(dir, "repo")
	config := filepath.Join(dir, "config")
	state := filepath.Join(dir, "state")

	if err := os.MkdirAll(config, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(state, 0o755); err != nil {
		t.Fatal(err)
	}

	// Set up source
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprland.lua"), "original")
	writeTestFile(t, filepath.Join(repo, "hypr", "hypridle.conf"), "original")
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprlock.conf"), "original")

	hyprCfg := filepath.Join(config, "hypr")
	manifestFile := filepath.Join(state, "manifest.json")

	p := Paths{
		InstallDir:   repo,
		HyprCfg:      hyprCfg,
		ManifestFile: manifestFile,
	}

	// First deploy
	noop := func(string) {}
	err := deployHypr(p, false, noop)
	if err != nil {
		t.Fatalf("first deployHypr failed: %v", err)
	}

	// User modifies a deployed file
	userModified := filepath.Join(hyprCfg, "hyprland.lua")
	if err := os.WriteFile(userModified, []byte("user modified"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Update source
	writeTestFile(t, filepath.Join(repo, "hypr", "hyprland.lua"), "updated by maintainer")

	// Second deploy without overwrite
	err = deployHypr(p, false, noop)
	if err != nil {
		t.Fatalf("second deployHypr failed: %v", err)
	}

	// User's modification should still be there (not overwritten)
	content, err := os.ReadFile(userModified)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "user modified" {
		t.Errorf("user modification was overwritten: got %q", string(content))
	}

	// But other files should be updated
	otherFile := filepath.Join(hyprCfg, "hypridle.conf")
	content, err = os.ReadFile(otherFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "original" {
		t.Errorf("unmodified file should still have original content")
	}
}
