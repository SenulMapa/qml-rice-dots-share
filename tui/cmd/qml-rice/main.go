// Command qml-rice is the qml-rice-dots updater: an interactive Bubble Tea
// TUI by default, plus non-interactive subcommands for scripts/keybinds
// (status, doctor, update --yes, rollback), and two passthroughs used by the
// shipped Hyprland keybinds: `ipc` (forwards to the running shell's IPC) and
// `restart-shell`.
package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SenulMapa/qml-rice-dots/tui/internal/app"
	"github.com/SenulMapa/qml-rice-dots/tui/internal/tui"
)

func main() {
	paths := app.DefaultPaths()

	if len(os.Args) < 2 {
		runInteractive(paths)
		return
	}

	var err error
	switch os.Args[1] {
	case "ipc":
		err = runIPC(paths, os.Args[2:])
	case "restart-shell":
		err = app.RestartShell(paths)
	case "status":
		err = runStatus(paths)
	case "doctor":
		err = runDoctor(paths)
	case "update":
		err = runUpdate(paths, hasFlag(os.Args[2:], "--yes"))
	case "rollback":
		err = runRollback(paths, hasFlag(os.Args[2:], "--yes"))
	case "-h", "--help", "help":
		printUsage()
		return
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`qml-rice -- qml-rice-dots updater

Usage:
  qml-rice                 interactive TUI (status/update/rollback/modules/doctor)
  qml-rice status          print install status and exit
  qml-rice doctor          run environment checks and exit
  qml-rice update [--yes]  fetch, show changelog, update (prompts unless --yes)
  qml-rice rollback [--yes]restore the newest backup + previous commit
  qml-rice restart-shell   kill and restart the qml-rice Quickshell shell
  qml-rice ipc <args...>   forward to the running shell's IPC (qs ipc call)`)
}

func hasFlag(args []string, flag string) bool {
	for _, a := range args {
		if a == flag {
			return true
		}
	}
	return false
}

func runInteractive(paths app.Paths) {
	p := tea.NewProgram(tui.New(paths))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func runIPC(paths app.Paths, args []string) error {
	full := append([]string{"-p", "./shell.qml", "ipc", "call"}, args...)
	cmd := exec.Command("qs", full...)
	cmd.Dir = paths.ShellDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runStatus(paths app.Paths) error {
	r, err := app.Status(paths, true)
	if err != nil {
		return err
	}
	fmt.Printf("install dir : %s\n", r.InstallDir)
	fmt.Printf("installed   : %s (%s)\n", r.HeadDescribe, r.HeadCommit)
	if r.RemoteRef != "" {
		fmt.Printf("remote      : %s @ %s (%d behind)\n", r.RemoteRef, r.RemoteCommit, r.UpdatesBehind)
	}
	fmt.Printf("shell       : running=%v\n", r.ShellRunning)
	if len(r.DirtyFiles) > 0 {
		fmt.Printf("dirty files : %v\n", r.DirtyFiles)
	}
	if len(r.ConfigDiffs) > 0 {
		fmt.Println("changed deployed files:")
		for _, d := range r.ConfigDiffs {
			fmt.Printf("  %-9s %s\n", d.Status, d.Path)
		}
	}
	return nil
}

func runDoctor(paths app.Paths) error {
	checks := app.Doctor(paths)
	fail := 0
	for _, c := range checks {
		status := "ok  "
		if !c.OK {
			status = "FAIL"
			fail++
		}
		fmt.Printf("%s  %s", status, c.Name)
		if c.Info != "" {
			fmt.Printf("  (%s)", c.Info)
		}
		fmt.Println()
	}
	if fail > 0 {
		return fmt.Errorf("%d check(s) failed", fail)
	}
	return nil
}

func confirm(prompt string) bool {
	fmt.Printf("%s [y/N] ", prompt)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	return len(line) > 0 && (line[0] == 'y' || line[0] == 'Y')
}

func runUpdate(paths app.Paths, yes bool) error {
	plan, err := app.PlanUpdate(paths)
	if err != nil {
		return err
	}
	if plan.NothingNew {
		fmt.Println("already up to date with", plan.RemoteRef)
		return nil
	}
	fmt.Printf("%d new commit(s) on %s:\n", len(plan.Changelog), plan.RemoteRef)
	for _, l := range plan.Changelog {
		fmt.Println(" ", l)
	}
	if len(plan.Conflicts) > 0 {
		fmt.Printf("%d locally-modified file(s) will be kept as-is:\n", len(plan.Conflicts))
		for _, d := range plan.Conflicts {
			fmt.Println(" ", d.Path)
		}
	}
	if !yes && !confirm("Apply this update?") {
		fmt.Println("aborted")
		return nil
	}
	mods, err := app.LoadModules(paths.ModulesFile)
	if err != nil {
		mods = app.DefaultModules()
	}
	return app.ApplyUpdate(paths, mods, false, true, func(line string) {
		fmt.Println("*", line)
	})
}

func runRollback(paths app.Paths, yes bool) error {
	if !yes && !confirm("Roll back to the previous backup and commit?") {
		fmt.Println("aborted")
		return nil
	}
	return app.Rollback(paths, func(line string) {
		fmt.Println("*", line)
	})
}
