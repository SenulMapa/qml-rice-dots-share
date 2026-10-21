package app

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/SenulMapa/qml-rice-dots/tui/internal/gitutil"
	"github.com/SenulMapa/qml-rice-dots/tui/internal/manifest"
)

// UpdatePlan is what `qml-rice update` would do, computed before touching
// anything so the TUI (or --yes) can show it first.
type UpdatePlan struct {
	RemoteRef  string
	Changelog  []string
	Conflicts  []manifest.Diff // deployed files modified locally that the update would otherwise overwrite
	NothingNew bool
}

// PlanUpdate fetches and reports what an update would change, without
// changing anything.
func PlanUpdate(p Paths) (UpdatePlan, error) {
	var plan UpdatePlan
	repo := gitutil.New(p.InstallDir)
	if !repo.IsRepo() {
		return plan, fmt.Errorf("%s is not a git repository", p.InstallDir)
	}
	if err := repo.Fetch(); err != nil {
		return plan, fmt.Errorf("git fetch: %w", err)
	}
	ref, err := repo.RemoteRef()
	if err != nil {
		return plan, fmt.Errorf("resolve remote ref: %w", err)
	}
	plan.RemoteRef = ref
	log, err := repo.Changelog(ref)
	if err != nil {
		return plan, fmt.Errorf("changelog: %w", err)
	}
	plan.Changelog = log
	plan.NothingNew = len(log) == 0

	if m, err := manifest.Load(p.ManifestFile); err == nil {
		if diffs, err := m.Compare(p.HyprCfg); err == nil {
			plan.Conflicts = manifest.ModifiedOrConflicting(diffs)
		}
	}
	return plan, nil
}

// ApplyUpdate performs the update: backs up the deployed hypr config, pulls
// the InstallDir clone to the latest remote ref, re-deploys hypr/ (skipping
// files the manifest says the user modified, unless overwrite is true),
// rebuilds the manifest, re-syncs packages for anything new in
// packages/*.txt, restarts the shell + reloads Hyprland, and if tui/ files
// changed, rebuilds the qml-rice binary to ~/.local/bin.
//
// log receives progress lines; pass a no-op func if you don't want them.
func ApplyUpdate(p Paths, mods Modules, overwriteConflicts bool, syncPackages bool, log func(string)) error {
	if log == nil {
		log = func(string) {}
	}
	repo := gitutil.New(p.InstallDir)
	if !repo.IsRepo() {
		return fmt.Errorf("%s is not a git repository", p.InstallDir)
	}

	// Record HEAD before pulling so we can detect changes later
	oldHead, err := repo.HeadCommit()
	if err != nil {
		return fmt.Errorf("get HEAD commit: %w", err)
	}

	stamp := time.Now().Format("20060102-150405")
	backup, err := BackupHyprConfig(p, stamp)
	if err != nil {
		return fmt.Errorf("backup: %w", err)
	}
	if backup != "" {
		log("backed up " + p.HyprCfg + " -> " + backup)
	}

	log("git pull " + p.InstallDir)
	if err := repo.Pull(); err != nil {
		return fmt.Errorf("git pull: %w", err)
	}

	// Check if tui/ files changed and rebuild the binary if so
	newHead, err := repo.HeadCommit()
	if err == nil && oldHead != newHead {
		if changed, err := repo.ChangedPaths(oldHead, newHead); err == nil {
			if shouldRebuildTUI(changed) {
				if err := rebuildTUIBinary(p, log); err != nil {
					log("rebuild qml-rice binary failed: " + err.Error())
				}
			}
		}
	}

	if mods.Hypr {
		if err := deployHypr(p, overwriteConflicts, log); err != nil {
			return fmt.Errorf("deploy hypr config: %w", err)
		}
	}

	if mods.Shell {
		log("shell module enabled; shell/ deploy handled by install.sh conventions (binary already in place)")
	}

	if mods.Fonts {
		if err := deployFonts(p, log); err != nil {
			log("deploy fonts failed: " + err.Error())
		}
	}

	for name, enabled := range mods.dotsModules() {
		if !enabled {
			continue
		}
		if err := deployDotsModule(p, name, log); err != nil {
			log("deploy " + name + " failed: " + err.Error())
		}
	}

	if syncPackages {
		if err := syncPackageFile(filepath.Join(p.InstallDir, "packages", "arch.txt"), "pacman", []string{"-S", "--needed", "--noconfirm"}, log); err != nil {
			log("package sync (arch.txt) failed: " + err.Error())
		}
		if helper := aurHelper(); helper != "" {
			if err := syncPackageFile(filepath.Join(p.InstallDir, "packages", "aur.txt"), helper, []string{"-S", "--needed", "--noconfirm"}, log); err != nil {
				log("package sync (aur.txt) failed: " + err.Error())
			}
		}
	}

	if err := RestartShell(p); err != nil {
		log("restart shell failed: " + err.Error())
	} else {
		log("restarted shell")
	}
	if err := ReloadHyprland(); err != nil {
		log("hyprctl reload failed: " + err.Error())
	} else {
		log("hyprctl reload")
	}

	return nil
}

// deployHypr copies InstallDir/hypr's managed files over ConfigHome/hypr,
// skipping any file the manifest+compare says the user modified locally
// unless overwriteConflicts is set, then rebuilds the manifest from what's
// now on disk. Managed files are hyprland.lua, hypridle.conf, and the contents
// of hyprland/ and hyprlock/ directories. User-owned files (monitors.lua,
// custom/) are never deployed by the updater.
func deployHypr(p Paths, overwriteConflicts bool, log func(string)) error {
	src := filepath.Join(p.InstallDir, "hypr")
	oldManifest, _ := manifest.Load(p.ManifestFile)
	diffs, _ := oldManifest.Compare(p.HyprCfg)

	skip := map[string]bool{}
	if !overwriteConflicts {
		for _, d := range manifest.ModifiedOrConflicting(diffs) {
			skip[d.Path] = true
			log("skipping locally-modified " + d.Path + " (pass overwrite to replace it)")
		}
	}

	// Deploy managed files (always refreshed from the repo)
	managed := []string{"hyprland.lua", "hypridle.conf", "hyprlock.conf"}
	for _, f := range managed {
		if skip[f] {
			continue
		}
		if err := copyFile(filepath.Join(src, f), filepath.Join(p.HyprCfg, f)); err != nil {
			return err
		}
	}

	// Deploy managed directories (hyprland/ and hyprlock/)
	for _, dir := range []string{"hyprland", "hyprlock"} {
		dirPath := filepath.Join(src, dir)
		if _, err := os.Stat(dirPath); err != nil {
			if os.IsNotExist(err) {
				continue // Directory doesn't exist in source; skip it
			}
			return err
		}

		err := filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return err
			}
			rel, _ := filepath.Rel(src, path)
			if skip[filepath.ToSlash(rel)] {
				return nil
			}
			return copyFile(path, filepath.Join(p.HyprCfg, rel))
		})
		if err != nil {
			return err
		}
	}

	// Build manifest for only the managed files/dirs, excluding user-owned
	// files like monitors.lua and custom/
	manifestPaths := []string{
		"hyprland.lua",
		"hypridle.conf",
		"hyprlock.conf",
		"hyprland",
		"hyprlock",
	}
	newManifest, err := manifest.BuildFromPaths(src, manifestPaths)
	if err != nil {
		return err
	}
	return newManifest.Save(p.ManifestFile)
}

// deployDotsModule mirrors InstallDir/dots/<name>/ onto $HOME, backing up
// (with a timestamp suffix) any existing file whose content differs from
// what's about to be installed. This is the Go-side equivalent of
// install.sh's deploy_dots_module and covers every module that's a plain
// file tree (kitty, fastfetch, gtk, qt, matugen, zsh) -- shell/hypr/sddm
// have their own deploy paths.
func deployDotsModule(p Paths, name string, log func(string)) error {
	src := filepath.Join(p.InstallDir, "dots", name)
	if _, err := os.Stat(src); err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	stamp := time.Now().Format("20060102-150405")
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		rel, relErr := filepath.Rel(src, path)
		if relErr != nil {
			return relErr
		}
		dst := filepath.Join(p.Home, rel)
		if existing, statErr := os.ReadFile(dst); statErr == nil {
			data, readErr := os.ReadFile(path)
			if readErr != nil {
				return readErr
			}
			if string(existing) != string(data) {
				backup := dst + ".bak-" + stamp
				if err := os.MkdirAll(filepath.Dir(backup), 0o755); err != nil {
					return err
				}
				if err := os.WriteFile(backup, existing, 0o644); err != nil {
					return err
				}
				log("backed up " + dst + " -> " + backup)
			}
		}
		return copyFile(path, dst)
	})
}

// deployFonts mirrors InstallDir/fonts/<Family>/*.ttf (the vendored OFL
// faces -- see the README's Fonts section) onto FontDir, then refreshes the
// fontconfig cache for that directory. This is the Go-side equivalent of
// install.sh's fonts module; it does not install packages (Nerd Fonts,
// Material Symbols, Gamja Flower/Geist/Geist Mono from
// packages/modules/fonts.{arch,aur}.txt) -- that only happens via
// syncPackages/install.sh.
func deployFonts(p Paths, log func(string)) error {
	src := filepath.Join(p.InstallDir, "fonts")
	if _, err := os.Stat(src); err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if err := os.MkdirAll(p.FontDir, 0o755); err != nil {
		return err
	}
	copied := 0
	err := filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ext != ".ttf" && ext != ".otf" {
			return nil
		}
		if err := copyFile(path, filepath.Join(p.FontDir, info.Name())); err != nil {
			return err
		}
		copied++
		return nil
	})
	if err != nil {
		return err
	}
	log(fmt.Sprintf("copied %d font file(s) -> %s", copied, p.FontDir))
	if fc, lookErr := exec.LookPath("fc-cache"); lookErr == nil {
		c := exec.Command(fc, "-f", p.FontDir)
		if runErr := c.Run(); runErr != nil {
			log("fc-cache failed: " + runErr.Error())
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0o644)
}

func aurHelper() string {
	for _, h := range []string{"paru", "yay"} {
		if _, err := exec.LookPath(h); err == nil {
			return h
		}
	}
	return ""
}

func syncPackageFile(path, cmd string, baseArgs []string, log func(string)) error {
	pkgs, err := readPackageList(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if len(pkgs) == 0 {
		return nil
	}
	log(fmt.Sprintf("syncing %d package(s) from %s via %s", len(pkgs), path, cmd))
	args := append(append([]string{}, baseArgs...), pkgs...)
	c := exec.Command(cmd, args...)
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return c.Run()
}

func readPackageList(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var pkgs []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		pkgs = append(pkgs, line)
	}
	return pkgs, scanner.Err()
}

// shouldRebuildTUI checks whether any of the changed paths are under tui/,
// which would require rebuilding the qml-rice binary.
func shouldRebuildTUI(changedPaths []string) bool {
	for _, p := range changedPaths {
		if strings.HasPrefix(p, "tui/") {
			return true
		}
	}
	return false
}

// rebuildTUIBinary rebuilds the qml-rice binary at BinDir/qml-rice by running
// `go build` in the tui/ directory. If go is not on PATH, this is a no-op
// (the binary is already deployed). The rebuild is atomic: built to a temp
// file, then os.Rename over the target.
func rebuildTUIBinary(p Paths, log func(string)) error {
	go_bin, err := exec.LookPath("go")
	if err != nil {
		// go not found; binary won't be rebuilt, but update continues
		return nil
	}

	tuiDir := filepath.Join(p.InstallDir, "tui")
	binPath := filepath.Join(p.BinDir, "qml-rice")
	binDir := filepath.Dir(binPath)

	// Build to a temporary file in the same directory as the target
	tmpBin := binPath + ".tmp-" + time.Now().Format("20060102150405")

	cmd := exec.Command(go_bin, "build", "-o", tmpBin, "./cmd/qml-rice")
	cmd.Dir = tuiDir
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("go build failed: %w", err)
	}

	// Ensure target directory exists
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		os.Remove(tmpBin)
		return fmt.Errorf("mkdir %s: %w", binDir, err)
	}

	// Atomically replace the old binary with the new one
	if err := os.Rename(tmpBin, binPath); err != nil {
		os.Remove(tmpBin)
		return fmt.Errorf("replace binary: %w", err)
	}

	log("rebuilt qml-rice (takes effect next run)")
	return nil
}

// Rollback restores the newest hypr config backup (if one exists) and
// checks the InstallDir clone out to the commit before HEAD.
func Rollback(p Paths, log func(string)) error {
	if log == nil {
		log = func(string) {}
	}
	backup, err := LatestBackup(p)
	if err != nil {
		return err
	}
	if backup == "" {
		log("no config backup found; only rolling back the git clone")
	} else {
		if err := os.RemoveAll(p.HyprCfg); err != nil {
			return err
		}
		if err := copyDir(backup, p.HyprCfg); err != nil {
			return err
		}
		log("restored config from " + backup)
	}

	repo := gitutil.New(p.InstallDir)
	if repo.IsRepo() {
		prev, err := repo.PreviousCommit()
		if err == nil {
			if err := repo.CheckoutCommit(prev); err != nil {
				return err
			}
			log("checked out " + prev + " in " + p.InstallDir)
		}
	}

	if err := RestartShell(p); err != nil {
		log("restart shell failed: " + err.Error())
	}
	if err := ReloadHyprland(); err != nil {
		log("hyprctl reload failed: " + err.Error())
	}
	return nil
}
