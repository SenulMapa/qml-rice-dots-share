package app

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/SenulMapa/qml-rice-dots/tui/internal/gitutil"
	"github.com/SenulMapa/qml-rice-dots/tui/internal/manifest"
)

// StatusReport is what the `status` screen/subcommand renders.
type StatusReport struct {
	InstallDir    string
	HeadCommit    string
	HeadDescribe  string
	RemoteCommit  string
	RemoteRef     string
	UpdatesBehind int
	DirtyFiles    []string        // uncommitted changes in the InstallDir clone
	ConfigDiffs   []manifest.Diff // deployed ~/.config/hypr vs manifest
	ShellRunning  bool
}

// Status gathers everything the status screen needs. It fetches from the
// remote first so "updates behind" is accurate; pass fetch=false to skip
// that (e.g. offline, or a quick local-only check).
func Status(p Paths, fetch bool) (StatusReport, error) {
	r := StatusReport{InstallDir: p.InstallDir}
	repo := gitutil.New(p.InstallDir)

	if !repo.IsRepo() {
		return r, fmt.Errorf("%s is not a git repository (run install.sh first)", p.InstallDir)
	}

	var err error
	if r.HeadCommit, err = repo.HeadCommit(); err != nil {
		return r, err
	}
	if r.HeadDescribe, err = repo.HeadDescribe(); err != nil {
		r.HeadDescribe = r.HeadCommit
	}
	if r.DirtyFiles, err = repo.DirtyFiles(); err != nil {
		return r, err
	}

	if fetch {
		_ = repo.Fetch() // best-effort; offline shouldn't fail Status entirely
	}
	if ref, err := repo.RemoteRef(); err == nil {
		r.RemoteRef = ref
		if rc, err := repo.RemoteCommit(ref); err == nil {
			r.RemoteCommit = rc
		}
		if log, err := repo.Changelog(ref); err == nil {
			r.UpdatesBehind = len(log)
		}
	}

	m, err := manifest.Load(p.ManifestFile)
	if err == nil {
		if diffs, err := m.Compare(p.HyprCfg); err == nil {
			r.ConfigDiffs = manifest.ModifiedOrConflicting(diffs)
		}
	}

	r.ShellRunning = processRunning("shell.qml")
	return r, nil
}

func processRunning(needle string) bool {
	out, err := exec.Command("pgrep", "-f", needle).Output()
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) != ""
}

// DoctorCheck is one pass/fail line in the doctor report.
type DoctorCheck struct {
	Name string
	OK   bool
	Info string
}

// Doctor runs a battery of environment checks: every binary named in
// packages/*.txt (best-effort -- AUR package names don't always match the
// binary name, so this is "did we find *a* binary that makes sense", not
// exhaustive), whether the shell process is running, and hyprctl
// configerrors.
func Doctor(p Paths) []DoctorCheck {
	var checks []DoctorCheck

	bins := []string{"hyprctl", "qs", "cava", "playerctl", "wpctl", "brightnessctl",
		"cliphist", "wl-copy", "grim", "slurp", "nmcli", "bluetoothctl", "matugen", "awww-daemon"}
	for _, b := range bins {
		_, err := exec.LookPath(b)
		checks = append(checks, DoctorCheck{Name: "binary: " + b, OK: err == nil})
	}

	checks = append(checks, DoctorCheck{
		Name: "qml-rice shell running",
		OK:   processRunning("shell.qml"),
	})

	if out, err := exec.Command("hyprctl", "configerrors").Output(); err == nil {
		text := strings.TrimSpace(string(out))
		ok := text == "" || strings.EqualFold(text, "no errors")
		checks = append(checks, DoctorCheck{Name: "hyprctl configerrors", OK: ok, Info: text})
	} else {
		checks = append(checks, DoctorCheck{Name: "hyprctl configerrors", OK: false, Info: "hyprctl not reachable"})
	}

	if info, err := os.Stat(p.InstallDir); err == nil && info.IsDir() {
		checks = append(checks, DoctorCheck{Name: "install dir: " + p.InstallDir, OK: true})
	} else {
		checks = append(checks, DoctorCheck{Name: "install dir: " + p.InstallDir, OK: false, Info: "not found"})
	}

	return checks
}

// MissingPackages reads a packages/*.txt-style file (comments with '#',
// blank lines ignored) and returns the subset not resolvable via
// exec.LookPath. This is only meaningful for arch.txt entries whose package
// name matches a binary name; it's a best-effort heuristic used by `doctor`,
// not a substitute for pacman -Qi.
func MissingPackages(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var missing []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if _, err := exec.LookPath(line); err != nil {
			missing = append(missing, line)
		}
	}
	return missing, scanner.Err()
}

// BackupHyprConfig copies ConfigHome/hypr to a timestamped sibling
// directory, returning the backup path. No-op (returns "", nil) if the
// config doesn't exist yet.
func BackupHyprConfig(p Paths, stamp string) (string, error) {
	info, err := os.Stat(p.HyprCfg)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	if !info.IsDir() {
		return "", nil
	}
	dest := filepath.Join(p.ConfigHome, "hypr.backup-"+stamp)
	if err := copyDir(p.HyprCfg, dest); err != nil {
		return "", err
	}
	return dest, nil
}

// LatestBackup returns the most recent hypr.backup-* directory under
// ConfigHome, or "" if none exists.
func LatestBackup(p Paths) (string, error) {
	entries, err := os.ReadDir(p.ConfigHome)
	if err != nil {
		return "", err
	}
	var names []string
	for _, e := range entries {
		if e.IsDir() && strings.HasPrefix(e.Name(), "hypr.backup-") {
			names = append(names, e.Name())
		}
	}
	if len(names) == 0 {
		return "", nil
	}
	sort.Strings(names)
	return filepath.Join(p.ConfigHome, names[len(names)-1]), nil
}

func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, data, info.Mode())
	})
}

// shellUnit is the fixed systemd scope the shell runs in when launched via
// app-scope, so per-scope energy accounting can attribute it by name.
const shellUnit = "qml-rice-shell"

// appScopePath returns ~/.local/bin/app-scope (home resolved at runtime) when
// that helper exists and is executable on this machine, else "".
func appScopePath(home string) string {
	if home == "" {
		return ""
	}
	path := filepath.Join(home, ".local", "bin", "app-scope")
	info, err := os.Stat(path)
	if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
		return ""
	}
	return path
}

// shellCommand is the argv RestartShell starts from ShellDir: through
// app-scope in its own fixed scope when the helper is present, otherwise
// the plain `qs -p ./shell.qml` as before.
func shellCommand(appScope string) []string {
	if appScope == "" {
		return []string{"qs", "-p", "./shell.qml"}
	}
	return []string{appScope, "--unit", shellUnit, "shell", "--", "qs", "-p", "./shell.qml"}
}

// waitScopeGone gives the previous shell's fixed scope up to ~2s to be
// collected after pkill; app-scope refuses a unit name that is still
// loaded (and would then fall back to an unscoped launch).
func waitScopeGone(unit string) {
	for i := 0; i < 20; i++ {
		out, err := exec.Command("systemctl", "--user", "show", "-p", "LoadState",
			"--value", unit+".scope").Output()
		if err != nil || strings.TrimSpace(string(out)) == "not-found" {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// RestartShell kills any running qml-rice shell process and starts it again
// from ShellDir, in its own systemd scope when ~/.local/bin/app-scope exists.
func RestartShell(p Paths) error {
	_ = exec.Command("pkill", "-f", "shell.qml").Run()
	home, _ := os.UserHomeDir()
	appScope := appScopePath(home)
	argv := shellCommand(appScope)
	cmd := exec.Command(argv[0], argv[1:]...)
	if appScope != "" {
		waitScopeGone(shellUnit)
		// app-scope stays the shell's parent for a fixed unit; detach it
		// from this terminal's session so closing the terminal can't HUP it.
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	}
	cmd.Dir = p.ShellDir
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}

// ReloadHyprland runs `hyprctl reload`.
func ReloadHyprland() error {
	return exec.Command("hyprctl", "reload").Run()
}
