package app

import (
	"path/filepath"
	"testing"
)

func TestLoadModulesMissingReturnsDefaults(t *testing.T) {
	m, err := LoadModules(filepath.Join(t.TempDir(), "nope.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !m.Shell || !m.Hypr {
		t.Fatalf("expected both modules enabled by default, got %+v", m)
	}
}

func TestModulesSaveLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "modules.json")

	m := Modules{Shell: false, Hypr: true}
	if err := m.Save(path); err != nil {
		t.Fatal(err)
	}

	loaded, err := LoadModules(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded != m {
		t.Fatalf("round trip mismatch: %+v != %+v", loaded, m)
	}
}
