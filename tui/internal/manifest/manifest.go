// Package manifest tracks the checksums of files qml-rice deploys onto the
// user's system (currently the Hyprland config under ~/.config/hypr), so the
// updater can tell "we deployed this and it hasn't changed" apart from
// "the user edited this since we deployed it" before ever overwriting
// anything.
package manifest

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"sort"
)

// Manifest maps a path, relative to the deploy root, to the sha256 hex
// digest it had when qml-rice deployed it.
type Manifest struct {
	// Version is a schema version, bumped if the on-disk format changes.
	Version int `json:"version"`
	// Files maps relative path -> sha256 hex digest at deploy time.
	Files map[string]string `json:"files"`
}

// New returns an empty manifest.
func New() *Manifest {
	return &Manifest{Version: 1, Files: map[string]string{}}
}

// ChecksumFile returns the sha256 hex digest of a file's contents.
func ChecksumFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// Build walks srcRoot and records the checksum of every regular file under
// it, keyed by its path relative to srcRoot (using forward slashes). This is
// what install.sh/qml-rice run against the *source* tree right after
// deploying it, to produce the manifest that later diffs are checked
// against.
func Build(srcRoot string) (*Manifest, error) {
	m := New()
	err := filepath.Walk(srcRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(srcRoot, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		sum, err := ChecksumFile(path)
		if err != nil {
			return err
		}
		m.Files[rel] = sum
		return nil
	})
	if err != nil {
		return nil, err
	}
	return m, nil
}

// BuildFromPaths walks srcRoot but only includes regular files under the
// specified paths (which can be either files or directories). This is used
// to build a manifest that covers only the managed files, excluding user-owned
// files like monitors.lua or custom/ overrides.
func BuildFromPaths(srcRoot string, includePaths []string) (*Manifest, error) {
	m := New()
	for _, p := range includePaths {
		fullPath := filepath.Join(srcRoot, p)
		info, err := os.Stat(fullPath)
		if err != nil {
			if os.IsNotExist(err) {
				continue // Path doesn't exist in the source tree; skip it
			}
			return nil, err
		}

		if !info.IsDir() {
			// It's a regular file; add it to the manifest
			rel := filepath.ToSlash(p)
			sum, err := ChecksumFile(fullPath)
			if err != nil {
				return nil, err
			}
			m.Files[rel] = sum
			continue
		}

		// It's a directory; walk it and add all regular files
		err = filepath.Walk(fullPath, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() {
				return nil
			}
			rel, err := filepath.Rel(srcRoot, path)
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)
			sum, err := ChecksumFile(path)
			if err != nil {
				return err
			}
			m.Files[rel] = sum
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return m, nil
}

// Load reads a manifest from disk. A missing file returns an empty manifest,
// not an error, since "no manifest yet" is a normal first-run state.
func Load(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return New(), nil
		}
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	if m.Files == nil {
		m.Files = map[string]string{}
	}
	return &m, nil
}

// Save writes the manifest to disk as indented JSON.
func (m *Manifest) Save(path string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

// Status describes how a deployed file compares to the manifest and the
// live filesystem.
type Status int

const (
	// Unchanged: still on disk, checksum matches the manifest (safe to
	// overwrite silently).
	Unchanged Status = iota
	// ModifiedByUser: still on disk, but its checksum no longer matches the
	// manifest -- the user (or something else) edited it since deploy.
	ModifiedByUser
	// MissingLocally: recorded in the manifest but no longer present on disk.
	MissingLocally
	// NewFromSource: exists in the new source tree but was not in the old
	// manifest (a file the update would add).
	NewFromSource
)

func (s Status) String() string {
	switch s {
	case Unchanged:
		return "unchanged"
	case ModifiedByUser:
		return "modified"
	case MissingLocally:
		return "missing"
	case NewFromSource:
		return "new"
	default:
		return "unknown"
	}
}

// Diff is one file's comparison result.
type Diff struct {
	Path   string
	Status Status
}

// Compare walks deployRoot against the manifest and reports, for every file
// the manifest knows about, whether it's unchanged, user-modified, or gone.
// Deterministic order (sorted by path) so callers/tests don't need to sort.
func (m *Manifest) Compare(deployRoot string) ([]Diff, error) {
	var out []Diff
	for rel, wantSum := range m.Files {
		full := filepath.Join(deployRoot, filepath.FromSlash(rel))
		info, err := os.Stat(full)
		if err != nil {
			if os.IsNotExist(err) {
				out = append(out, Diff{Path: rel, Status: MissingLocally})
				continue
			}
			return nil, err
		}
		if info.IsDir() {
			continue
		}
		gotSum, err := ChecksumFile(full)
		if err != nil {
			return nil, err
		}
		if gotSum == wantSum {
			out = append(out, Diff{Path: rel, Status: Unchanged})
		} else {
			out = append(out, Diff{Path: rel, Status: ModifiedByUser})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out, nil
}

// DiffAgainstSource compares a new source manifest against the old deployed
// manifest to classify every file the update would touch: new files (not
// previously deployed), files whose source content changed, and files whose
// source content is identical (skip -- nothing to do regardless of local
// edits).
func DiffAgainstSource(old, next *Manifest) []Diff {
	var out []Diff
	for rel, nextSum := range next.Files {
		oldSum, existed := old.Files[rel]
		switch {
		case !existed:
			out = append(out, Diff{Path: rel, Status: NewFromSource})
		case oldSum != nextSum:
			out = append(out, Diff{Path: rel, Status: ModifiedByUser}) // source changed
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out
}

// ModifiedOrConflicting returns the subset of Compare() results that require
// a decision from the user before being overwritten (i.e. everything except
// Unchanged).
func ModifiedOrConflicting(diffs []Diff) []Diff {
	var out []Diff
	for _, d := range diffs {
		if d.Status != Unchanged {
			out = append(out, d)
		}
	}
	return out
}
