// Package tui implements the interactive Bubble Tea front-end for qml-rice:
// status / update / rollback / modules / doctor screens, all driven by
// internal/app so the same logic backs the non-interactive subcommands.
package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/SenulMapa/qml-rice-dots/tui/internal/app"
)

type screen int

const (
	screenStatus screen = iota
	screenUpdate
	screenRollback
	screenModules
	screenDoctor
)

var screenNames = []string{"Status", "Update", "Rollback", "Modules", "Doctor"}

var (
	titleStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	tabActive     = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("0")).Background(lipgloss.Color("212")).Padding(0, 1)
	tabInactive   = lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Padding(0, 1)
	okStyle       = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
	warnStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	errStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	dimStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	helpStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("240")).MarginTop(1)
	logLineStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("250"))
	confirmPrompt = lipgloss.NewStyle().Foreground(lipgloss.Color("214")).Bold(true)
)

// Model is the root Bubble Tea model.
type Model struct {
	paths   app.Paths
	cur     screen
	width   int
	spinner spinner.Model
	busy    bool
	err     error

	status StatusState
	update UpdateState
	roll   RollbackState
	mods   ModulesState
	doc    DoctorState
}

// StatusState holds the status screen's data.
type StatusState struct {
	loaded bool
	report app.StatusReport
	err    error
}

// UpdateState holds the update screen's data + confirmation flow.
type UpdateState struct {
	planLoaded bool
	plan       app.UpdatePlan
	err        error
	confirming bool
	applying   bool
	overwrite  bool
	logs       []string
	done       bool
}

// RollbackState holds the rollback screen's confirmation flow.
type RollbackState struct {
	confirming bool
	applying   bool
	logs       []string
	done       bool
	err        error
}

// ModulesState holds the modules screen's toggle state.
type ModulesState struct {
	loaded bool
	mods   app.Modules
	cursor int
	err    error
	saved  bool
}

// DoctorState holds the doctor screen's checks.
type DoctorState struct {
	loaded bool
	checks []app.DoctorCheck
}

// New builds the initial model.
func New(p app.Paths) Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	return Model{paths: p, spinner: s}
}

func (m Model) Init() tea.Cmd {
	return loadStatusCmd(m.paths)
}

// --- messages ---------------------------------------------------------

type statusLoadedMsg struct {
	report app.StatusReport
	err    error
}
type planLoadedMsg struct {
	plan app.UpdatePlan
	err  error
}
type updateProgressMsg string
type updateDoneMsg struct{ err error }
type rollbackProgressMsg string
type rollbackDoneMsg struct{ err error }
type modulesLoadedMsg struct {
	mods app.Modules
	err  error
}
type doctorLoadedMsg struct{ checks []app.DoctorCheck }

func loadStatusCmd(p app.Paths) tea.Cmd {
	return func() tea.Msg {
		r, err := app.Status(p, true)
		return statusLoadedMsg{report: r, err: err}
	}
}

func loadPlanCmd(p app.Paths) tea.Cmd {
	return func() tea.Msg {
		plan, err := app.PlanUpdate(p)
		return planLoadedMsg{plan: plan, err: err}
	}
}

func loadModulesCmd(p app.Paths) tea.Cmd {
	return func() tea.Msg {
		mods, err := app.LoadModules(p.ModulesFile)
		return modulesLoadedMsg{mods: mods, err: err}
	}
}

func loadDoctorCmd(p app.Paths) tea.Cmd {
	return func() tea.Msg {
		return doctorLoadedMsg{checks: app.Doctor(p)}
	}
}

func applyUpdateCmd(p app.Paths, mods app.Modules, overwrite bool) tea.Cmd {
	return func() tea.Msg {
		err := app.ApplyUpdate(p, mods, overwrite, true, func(string) {})
		return updateDoneMsg{err: err}
	}
}

func applyRollbackCmd(p app.Paths) tea.Cmd {
	return func() tea.Msg {
		err := app.Rollback(p, func(string) {})
		return rollbackDoneMsg{err: err}
	}
}

// --- update -------------------------------------------------------------

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)

	case statusLoadedMsg:
		m.status.loaded = true
		m.status.report = msg.report
		m.status.err = msg.err
		return m, nil

	case planLoadedMsg:
		m.update.planLoaded = true
		m.update.plan = msg.plan
		m.update.err = msg.err
		return m, nil

	case updateDoneMsg:
		m.update.applying = false
		m.update.done = true
		m.update.err = msg.err
		return m, loadStatusCmd(m.paths)

	case rollbackDoneMsg:
		m.roll.applying = false
		m.roll.done = true
		m.roll.err = msg.err
		return m, loadStatusCmd(m.paths)

	case modulesLoadedMsg:
		m.mods.loaded = true
		m.mods.mods = msg.mods
		m.mods.err = msg.err
		return m, nil

	case doctorLoadedMsg:
		m.doc.loaded = true
		m.doc.checks = msg.checks
		return m, nil

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Screen-local key handling for anything mid-confirmation takes
	// priority over global nav so 'q'/'y'/'n' don't leak through.
	switch m.cur {
	case screenUpdate:
		if m.update.confirming {
			switch msg.String() {
			case "y":
				m.update.confirming = false
				m.update.applying = true
				return m, tea.Batch(applyUpdateCmd(m.paths, currentMods(m), m.update.overwrite), m.spinner.Tick)
			case "n", "esc":
				m.update.confirming = false
				return m, nil
			}
			return m, nil
		}
	case screenRollback:
		if m.roll.confirming {
			switch msg.String() {
			case "y":
				m.roll.confirming = false
				m.roll.applying = true
				return m, tea.Batch(applyRollbackCmd(m.paths), m.spinner.Tick)
			case "n", "esc":
				m.roll.confirming = false
				return m, nil
			}
			return m, nil
		}
	}

	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	case "tab", "right", "l":
		m.cur = (m.cur + 1) % screen(len(screenNames))
		return m, m.enterScreen()
	case "shift+tab", "left", "h":
		m.cur = (m.cur - 1 + screen(len(screenNames))) % screen(len(screenNames))
		return m, m.enterScreen()
	case "1", "2", "3", "4", "5":
		m.cur = screen(msg.String()[0] - '1')
		return m, m.enterScreen()
	case "r":
		if m.cur == screenStatus {
			m.status.loaded = false
			return m, loadStatusCmd(m.paths)
		}
	case "enter":
		switch m.cur {
		case screenUpdate:
			if !m.update.applying {
				m.update.confirming = true
			}
		case screenRollback:
			if !m.roll.applying {
				m.roll.confirming = true
			}
		}
	case "o":
		if m.cur == screenUpdate {
			m.update.overwrite = !m.update.overwrite
		}
	case "up", "k":
		if m.cur == screenModules && m.mods.cursor > 0 {
			m.mods.cursor--
		}
	case "down", "j":
		if m.cur == screenModules && m.mods.loaded && m.mods.cursor < len(m.mods.mods.Rows())-1 {
			m.mods.cursor++
		}
	case " ":
		if m.cur == screenModules && m.mods.loaded {
			rows := m.mods.mods.Rows()
			if m.mods.cursor < len(rows) {
				*rows[m.mods.cursor].Ptr = !*rows[m.mods.cursor].Ptr
			}
			_ = m.mods.mods.Save(m.paths.ModulesFile)
			m.mods.saved = true
		}
	}
	return m, nil
}

func currentMods(m Model) app.Modules {
	if m.mods.loaded {
		return m.mods.mods
	}
	return app.DefaultModules()
}

func (m Model) enterScreen() tea.Cmd {
	switch m.cur {
	case screenUpdate:
		if !m.update.planLoaded {
			return loadPlanCmd(m.paths)
		}
	case screenModules:
		if !m.mods.loaded {
			return loadModulesCmd(m.paths)
		}
	case screenDoctor:
		if !m.doc.loaded {
			return loadDoctorCmd(m.paths)
		}
	}
	return nil
}

// --- view -----------------------------------------------------------------

func (m Model) View() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("qml-rice"))
	b.WriteString("  ")
	for i, name := range screenNames {
		if screen(i) == m.cur {
			b.WriteString(tabActive.Render(name))
		} else {
			b.WriteString(tabInactive.Render(name))
		}
	}
	b.WriteString("\n\n")

	switch m.cur {
	case screenStatus:
		b.WriteString(m.viewStatus())
	case screenUpdate:
		b.WriteString(m.viewUpdate())
	case screenRollback:
		b.WriteString(m.viewRollback())
	case screenModules:
		b.WriteString(m.viewModules())
	case screenDoctor:
		b.WriteString(m.viewDoctor())
	}

	b.WriteString(helpStyle.Render("tab/1-5 switch screen  ·  enter act  ·  r refresh  ·  q quit"))
	return b.String()
}

func (m Model) viewStatus() string {
	if !m.status.loaded {
		return m.spinner.View() + " loading status...\n"
	}
	if m.status.err != nil {
		return errStyle.Render("error: "+m.status.err.Error()) + "\n"
	}
	r := m.status.report
	var b strings.Builder
	fmt.Fprintf(&b, "Install dir : %s\n", r.InstallDir)
	fmt.Fprintf(&b, "Installed   : %s (%s)\n", r.HeadDescribe, r.HeadCommit)
	if r.RemoteRef != "" {
		fmt.Fprintf(&b, "Remote      : %s @ %s\n", r.RemoteRef, r.RemoteCommit)
		if r.UpdatesBehind > 0 {
			b.WriteString(warnStyle.Render(fmt.Sprintf("%d commit(s) behind\n", r.UpdatesBehind)))
		} else {
			b.WriteString(okStyle.Render("up to date\n"))
		}
	} else {
		b.WriteString(dimStyle.Render("no remote configured\n"))
	}
	if r.ShellRunning {
		b.WriteString(okStyle.Render("shell: running\n"))
	} else {
		b.WriteString(warnStyle.Render("shell: not running\n"))
	}
	if len(r.DirtyFiles) > 0 {
		b.WriteString(warnStyle.Render(fmt.Sprintf("\n%d uncommitted change(s) in install dir:\n", len(r.DirtyFiles))))
		for _, f := range r.DirtyFiles {
			fmt.Fprintf(&b, "  %s\n", f)
		}
	}
	if len(r.ConfigDiffs) > 0 {
		b.WriteString(warnStyle.Render(fmt.Sprintf("\n%d deployed config file(s) changed since install:\n", len(r.ConfigDiffs))))
		for _, d := range r.ConfigDiffs {
			fmt.Fprintf(&b, "  %-9s %s\n", d.Status, d.Path)
		}
	}
	return b.String()
}

func (m Model) viewUpdate() string {
	var b strings.Builder
	if m.update.applying {
		b.WriteString(m.spinner.View() + " applying update...\n")
		return b.String()
	}
	if m.update.done {
		if m.update.err != nil {
			b.WriteString(errStyle.Render("update failed: "+m.update.err.Error()) + "\n")
		} else {
			b.WriteString(okStyle.Render("update applied\n"))
		}
		return b.String()
	}
	if !m.update.planLoaded {
		return m.spinner.View() + " checking for updates...\n"
	}
	if m.update.err != nil {
		return errStyle.Render("error: "+m.update.err.Error()) + "\n"
	}
	p := m.update.plan
	if p.NothingNew {
		b.WriteString(okStyle.Render("already up to date with " + p.RemoteRef + "\n"))
		return b.String()
	}
	fmt.Fprintf(&b, "%d new commit(s) on %s:\n", len(p.Changelog), p.RemoteRef)
	for _, l := range p.Changelog {
		fmt.Fprintf(&b, "  %s\n", l)
	}
	if len(p.Conflicts) > 0 {
		b.WriteString(warnStyle.Render(fmt.Sprintf("\n%d locally-modified file(s) will be KEPT (not overwritten):\n", len(p.Conflicts))))
		for _, d := range p.Conflicts {
			fmt.Fprintf(&b, "  %s\n", d.Path)
		}
		overwriteLabel := "off"
		if m.update.overwrite {
			overwriteLabel = "on"
		}
		fmt.Fprintf(&b, "\npress 'o' to toggle overwriting them (currently %s)\n", overwriteLabel)
	}
	if m.update.confirming {
		b.WriteString("\n" + confirmPrompt.Render("Apply this update? [y/n]") + "\n")
	} else {
		b.WriteString("\npress enter to update\n")
	}
	return b.String()
}

func (m Model) viewRollback() string {
	var b strings.Builder
	if m.roll.applying {
		return m.spinner.View() + " rolling back...\n"
	}
	if m.roll.done {
		if m.roll.err != nil {
			return errStyle.Render("rollback failed: "+m.roll.err.Error()) + "\n"
		}
		return okStyle.Render("rolled back\n")
	}
	b.WriteString("Restores the newest ~/.config/hypr.backup-* directory (if any) and\n")
	b.WriteString("checks the install directory out to the commit before HEAD.\n")
	if m.roll.confirming {
		b.WriteString("\n" + confirmPrompt.Render("Roll back now? [y/n]") + "\n")
	} else {
		b.WriteString("\npress enter to roll back\n")
	}
	return b.String()
}

func (m Model) viewModules() string {
	if !m.mods.loaded {
		return m.spinner.View() + " loading modules...\n"
	}
	if m.mods.err != nil {
		return errStyle.Render("error: "+m.mods.err.Error()) + "\n"
	}
	var b strings.Builder
	rows := m.mods.mods.Rows()
	for i, row := range rows {
		cursor := "  "
		if m.mods.cursor == i {
			cursor = "> "
		}
		mark := "[ ]"
		style := dimStyle
		if *row.Ptr {
			mark = "[x]"
			style = okStyle
		}
		fmt.Fprintf(&b, "%s%s\n", cursor, style.Render(mark+" "+row.Name))
	}
	b.WriteString("\nspace to toggle · disabling a module skips it during `qml-rice update`\n")
	return b.String()
}

func (m Model) viewDoctor() string {
	if !m.doc.loaded {
		return m.spinner.View() + " running checks...\n"
	}
	var b strings.Builder
	failCount := 0
	for _, c := range m.doc.checks {
		mark := okStyle.Render("ok  ")
		if !c.OK {
			mark = errStyle.Render("FAIL")
			failCount++
		}
		fmt.Fprintf(&b, "%s  %s", mark, c.Name)
		if c.Info != "" {
			fmt.Fprintf(&b, "  %s", logLineStyle.Render(c.Info))
		}
		b.WriteString("\n")
	}
	if failCount == 0 {
		b.WriteString(okStyle.Render("\nall checks passed\n"))
	} else {
		b.WriteString(warnStyle.Render(fmt.Sprintf("\n%d check(s) failed\n", failCount)))
	}
	return b.String()
}
