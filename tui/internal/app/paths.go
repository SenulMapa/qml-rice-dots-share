// Package app holds the shared paths, config, and the non-interactive
// operations (status, doctor, update, rollback) that both the Bubble Tea TUI
// and the `qml-rice <subcommand>` CLI drive.
package app

import (
	"os"
	"path/filepath"
)

// Paths bundles every filesystem location qml-rice cares about, all
// resolvable from environment variables so tests can point them at a temp
// dir instead of the real $HOME.
type Paths struct {
	Home         string
	ConfigHome   string // $XDG_CONFIG_HOME, default ~/.config
	DataHome     string // $XDG_DATA_HOME, default ~/.local/share
	InstallDir   string // DataHome/qml-rice -- the git clone
	ShellDir     string // InstallDir/shell
	FontDir      string // DataHome/fonts/qml-rice -- vendored + shell-bundled fonts
	HyprCfg      string // ConfigHome/hypr -- deployed Hyprland config
	StateDir     string // ConfigHome/qml-rice -- our own state (manifest, modules)
	BinDir       string // $HOME/.local/bin -- where the qml-rice binary lives
	ManifestFile string
	ModulesFile  string
}

// DefaultPaths resolves Paths from the environment, matching install.sh's
// own resolution rules exactly (XDG_CONFIG_HOME / XDG_DATA_HOME with the
// usual fallbacks under $HOME).
func DefaultPaths() Paths {
	home := os.Getenv("HOME")
	cfg := os.Getenv("XDG_CONFIG_HOME")
	if cfg == "" {
		cfg = filepath.Join(home, ".config")
	}
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		data = filepath.Join(home, ".local", "share")
	}
	install := filepath.Join(data, "qml-rice")
	state := filepath.Join(cfg, "qml-rice")
	binDir := filepath.Join(home, ".local", "bin")
	return Paths{
		Home:         home,
		ConfigHome:   cfg,
		DataHome:     data,
		InstallDir:   install,
		ShellDir:     filepath.Join(install, "shell"),
		FontDir:      filepath.Join(data, "fonts", "qml-rice"),
		HyprCfg:      filepath.Join(cfg, "hypr"),
		StateDir:     state,
		BinDir:       binDir,
		ManifestFile: filepath.Join(state, "manifest.json"),
		ModulesFile:  filepath.Join(state, "modules.json"),
	}
}
