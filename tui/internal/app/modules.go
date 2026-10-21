package app

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Modules records which parts of qml-rice-dots the user wants `qml-rice
// update` to touch. All default to enabled except SDDM (needs sudo, opt-in
// even in the installer).
type Modules struct {
	Shell      bool `json:"shell"`
	Hypr       bool `json:"hypr"`
	Fonts      bool `json:"fonts"`
	Kitty      bool `json:"kitty"`
	Zsh        bool `json:"zsh"`
	Fastfetch  bool `json:"fastfetch"`
	GTK        bool `json:"gtk"`
	QT         bool `json:"qt"`
	Matugen    bool `json:"matugen"`
	Thunar     bool `json:"thunar"`
	Wallpapers bool `json:"wallpapers"`
	SDDM       bool `json:"sddm"`
}

// DefaultModules returns every module enabled except SDDM.
func DefaultModules() Modules {
	return Modules{
		Shell:      true,
		Hypr:       true,
		Fonts:      true,
		Kitty:      true,
		Zsh:        true,
		Fastfetch:  true,
		GTK:        true,
		QT:         true,
		Matugen:    true,
		Thunar:     true,
		Wallpapers: true,
		SDDM:       false,
	}
}

// ModuleRow is one togglable entry in the TUI's Modules screen.
type ModuleRow struct {
	Name string
	Ptr  *bool
}

// Rows returns every module as a (label, *bool) pair, in display order, so
// the TUI can render and toggle them generically instead of hard-coding a
// row per field.
func (m *Modules) Rows() []ModuleRow {
	return []ModuleRow{
		{"shell (Quickshell)", &m.Shell},
		{"hypr (Hyprland Lua config)", &m.Hypr},
		{"fonts (vendored OFL faces + Nerd/Material Symbols)", &m.Fonts},
		{"kitty (terminal)", &m.Kitty},
		{"zsh (shell + starship prompt)", &m.Zsh},
		{"fastfetch (logo + system info)", &m.Fastfetch},
		{"gtk (theme/icons/cursor)", &m.GTK},
		{"qt (qt5ct/qt6ct/Kvantum)", &m.QT},
		{"matugen (wallpaper -> colours)", &m.Matugen},
		{"thunar (file manager)", &m.Thunar},
		{"wallpapers (fallback + seeding)", &m.Wallpapers},
		{"sddm (login theme, needs sudo)", &m.SDDM},
	}
}

// dotsModules maps a Modules field to the dots/<name> directory it deploys
// via deployDotsModule -- everything that's a plain file-tree mirror onto
// $HOME. Shell, Hypr and SDDM have their own deploy paths and aren't here.
func (m Modules) dotsModules() map[string]bool {
	return map[string]bool{
		"kitty":     m.Kitty,
		"fastfetch": m.Fastfetch,
		"gtk":       m.GTK,
		"qt":        m.QT,
		"matugen":   m.Matugen,
		"zsh":       m.Zsh,
	}
}

// LoadModules reads the modules file, returning defaults if it doesn't
// exist yet.
func LoadModules(path string) (Modules, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return DefaultModules(), nil
		}
		return Modules{}, err
	}
	var m Modules
	if err := json.Unmarshal(data, &m); err != nil {
		return Modules{}, err
	}
	return m, nil
}

// Save writes the modules file.
func (m Modules) Save(path string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
