package manifest

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestChecksumFileDeterministic(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "a.txt")
	writeFile(t, p, "hello")

	sum1, err := ChecksumFile(p)
	if err != nil {
		t.Fatal(err)
	}
	sum2, err := ChecksumFile(p)
	if err != nil {
		t.Fatal(err)
	}
	if sum1 != sum2 {
		t.Fatalf("checksum not deterministic: %s != %s", sum1, sum2)
	}
	if sum1 == "" {
		t.Fatal("empty checksum")
	}
}

func TestBuildWalksTree(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "hyprland.lua"), "content-a")
	writeFile(t, filepath.Join(dir, "hyprland", "rules.lua"), "content-b")

	m, err := Build(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(m.Files) != 2 {
		t.Fatalf("expected 2 files, got %d: %+v", len(m.Files), m.Files)
	}
	if _, ok := m.Files["hyprland.lua"]; !ok {
		t.Error("missing hyprland.lua in manifest")
	}
	if _, ok := m.Files["hyprland/rules.lua"]; !ok {
		t.Error("missing hyprland/rules.lua in manifest")
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	writeFile(t, filepath.Join(src, "a.lua"), "aaa")

	m, err := Build(src)
	if err != nil {
		t.Fatal(err)
	}

	manifestPath := filepath.Join(dir, "manifest.json")
	if err := m.Save(manifestPath); err != nil {
		t.Fatal(err)
	}

	loaded, err := Load(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Files["a.lua"] != m.Files["a.lua"] {
		t.Fatalf("round trip mismatch: %v != %v", loaded.Files, m.Files)
	}
}

func TestLoadMissingFileReturnsEmpty(t *testing.T) {
	m, err := Load(filepath.Join(t.TempDir(), "does-not-exist.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(m.Files) != 0 {
		t.Fatalf("expected empty manifest, got %+v", m.Files)
	}
}

func TestCompareUnchanged(t *testing.T) {
	dir := t.TempDir()
	deployed := filepath.Join(dir, "deployed")
	writeFile(t, filepath.Join(deployed, "a.lua"), "same")

	m, err := Build(deployed)
	if err != nil {
		t.Fatal(err)
	}

	diffs, err := m.Compare(deployed)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 || diffs[0].Status != Unchanged {
		t.Fatalf("expected 1 unchanged diff, got %+v", diffs)
	}
}

func TestCompareModifiedByUser(t *testing.T) {
	dir := t.TempDir()
	deployed := filepath.Join(dir, "deployed")
	writeFile(t, filepath.Join(deployed, "a.lua"), "original")

	m, err := Build(deployed)
	if err != nil {
		t.Fatal(err)
	}

	// The user edits the file after deploy.
	writeFile(t, filepath.Join(deployed, "a.lua"), "user edited this")

	diffs, err := m.Compare(deployed)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 || diffs[0].Status != ModifiedByUser {
		t.Fatalf("expected 1 modified diff, got %+v", diffs)
	}
}

func TestCompareMissingLocally(t *testing.T) {
	dir := t.TempDir()
	deployed := filepath.Join(dir, "deployed")
	writeFile(t, filepath.Join(deployed, "a.lua"), "original")

	m, err := Build(deployed)
	if err != nil {
		t.Fatal(err)
	}

	if err := os.Remove(filepath.Join(deployed, "a.lua")); err != nil {
		t.Fatal(err)
	}

	diffs, err := m.Compare(deployed)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 || diffs[0].Status != MissingLocally {
		t.Fatalf("expected 1 missing diff, got %+v", diffs)
	}
}

func TestDiffAgainstSourceClassifiesNewAndChanged(t *testing.T) {
	old := New()
	old.Files["a.lua"] = "sumA"
	old.Files["b.lua"] = "sumB"

	next := New()
	next.Files["a.lua"] = "sumA"  // unchanged upstream
	next.Files["b.lua"] = "sumB2" // upstream changed it
	next.Files["c.lua"] = "sumC"  // brand new file

	diffs := DiffAgainstSource(old, next)
	got := map[string]Status{}
	for _, d := range diffs {
		got[d.Path] = d.Status
	}

	if _, present := got["a.lua"]; present {
		t.Errorf("a.lua should not appear (unchanged upstream), got %+v", got)
	}
	if got["b.lua"] != ModifiedByUser {
		t.Errorf("b.lua should be reported as changed, got %v", got["b.lua"])
	}
	if got["c.lua"] != NewFromSource {
		t.Errorf("c.lua should be reported as new, got %v", got["c.lua"])
	}
}

func TestModifiedOrConflictingFiltersUnchanged(t *testing.T) {
	diffs := []Diff{
		{Path: "a", Status: Unchanged},
		{Path: "b", Status: ModifiedByUser},
		{Path: "c", Status: MissingLocally},
	}
	out := ModifiedOrConflicting(diffs)
	if len(out) != 2 {
		t.Fatalf("expected 2 entries, got %+v", out)
	}
	for _, d := range out {
		if d.Status == Unchanged {
			t.Errorf("unchanged entry leaked through: %+v", d)
		}
	}
}

func TestCompareDeterministicOrder(t *testing.T) {
	dir := t.TempDir()
	deployed := filepath.Join(dir, "deployed")
	writeFile(t, filepath.Join(deployed, "z.lua"), "z")
	writeFile(t, filepath.Join(deployed, "a.lua"), "a")
	writeFile(t, filepath.Join(deployed, "m.lua"), "m")

	m, err := Build(deployed)
	if err != nil {
		t.Fatal(err)
	}
	diffs, err := m.Compare(deployed)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 3 {
		t.Fatalf("expected 3 diffs, got %d", len(diffs))
	}
	if diffs[0].Path != "a.lua" || diffs[1].Path != "m.lua" || diffs[2].Path != "z.lua" {
		t.Fatalf("expected sorted order, got %v, %v, %v", diffs[0].Path, diffs[1].Path, diffs[2].Path)
	}
}

func TestBuildFromPathsIncludesOnlySpecified(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	writeFile(t, filepath.Join(src, "hyprland.lua"), "h")
	writeFile(t, filepath.Join(src, "hypridle.conf"), "hi")
	writeFile(t, filepath.Join(src, "monitors.lua"), "m")
	writeFile(t, filepath.Join(src, "hyprland", "rules.lua"), "r")
	writeFile(t, filepath.Join(src, "custom", "override.lua"), "c")

	// Only build manifest for hyprland.lua, hypridle.conf, and hyprland/ directory
	m, err := BuildFromPaths(src, []string{"hyprland.lua", "hypridle.conf", "hyprland"})
	if err != nil {
		t.Fatal(err)
	}

	if len(m.Files) != 3 {
		t.Fatalf("expected 3 files in manifest, got %d: %+v", len(m.Files), m.Files)
	}
	if _, ok := m.Files["hyprland.lua"]; !ok {
		t.Error("missing hyprland.lua")
	}
	if _, ok := m.Files["hypridle.conf"]; !ok {
		t.Error("missing hypridle.conf")
	}
	if _, ok := m.Files["hyprland/rules.lua"]; !ok {
		t.Error("missing hyprland/rules.lua")
	}
	if _, ok := m.Files["monitors.lua"]; ok {
		t.Error("monitors.lua should not be in manifest")
	}
	if _, ok := m.Files["custom/override.lua"]; ok {
		t.Error("custom/override.lua should not be in manifest")
	}
}

func TestBuildFromPathsHandlesMissingPaths(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	writeFile(t, filepath.Join(src, "a.lua"), "a")

	// Include both an existing and non-existing path
	m, err := BuildFromPaths(src, []string{"a.lua", "nonexistent.lua", "missing_dir"})
	if err != nil {
		t.Fatal(err)
	}

	// Should only have the existing file
	if len(m.Files) != 1 {
		t.Fatalf("expected 1 file in manifest, got %d: %+v", len(m.Files), m.Files)
	}
	if _, ok := m.Files["a.lua"]; !ok {
		t.Error("missing a.lua")
	}
}

func TestBuildFromPathsWithDirectory(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	writeFile(t, filepath.Join(src, "hyprlock", "colors.conf"), "colors")
	writeFile(t, filepath.Join(src, "hyprlock", "nested", "file.conf"), "nested")

	m, err := BuildFromPaths(src, []string{"hyprlock"})
	if err != nil {
		t.Fatal(err)
	}

	if len(m.Files) != 2 {
		t.Fatalf("expected 2 files in manifest, got %d: %+v", len(m.Files), m.Files)
	}
	if _, ok := m.Files["hyprlock/colors.conf"]; !ok {
		t.Error("missing hyprlock/colors.conf")
	}
	if _, ok := m.Files["hyprlock/nested/file.conf"]; !ok {
		t.Error("missing hyprlock/nested/file.conf")
	}
}
