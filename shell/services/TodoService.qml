pragma Singleton
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * TodoService -- minimal persisted task list backing widgets/TodoWidget.qml,
 * ported from end4-ii's services/Todo.qml (list of {text, done} objects,
 * one JSON file). Simplified from ii's version: no tabs/keyboard-shortcut
 * plumbing (that lived in its sidebar chrome, not the data model) and no
 * per-item originalIndex bookkeeping -- items are addressed by id here so
 * reordering/filtering in the widget never has to renumber anything.
 *
 * Persistence path mirrors WidgetStore.qml exactly (XDG_STATE_HOME-first,
 * qml-rice/todo.json) rather than ii's Directories.todoPath, since this
 * shell has no equivalent "Directories" singleton and WidgetStore's
 * resolution is already the shell's established convention.
 */
QtObject {
    id: root

    property var items: []
    property bool loaded: false

    function nextId(): string {
        return "todo-" + Date.now() + "-" + Math.floor(Math.random() * 10000)
    }

    function addTask(text: string): void {
        const trimmed = text.trim()
        if (trimmed.length === 0)
            return
        root.items = root.items.concat([{ id: root.nextId(), text: trimmed, done: false }])
        root.save()
    }

    function toggleDone(id: string): void {
        root.items = root.items.map(item => item.id === id
            ? Object.assign({}, item, { done: !item.done }) : item)
        root.save()
    }

    function removeTask(id: string): void {
        root.items = root.items.filter(item => item.id !== id)
        root.save()
    }

    function resolveStateRoot(): string {
        const explicit = Quickshell.env("XDG_STATE_HOME") || ""
        if (explicit.length > 0)
            return explicit
        return (Quickshell.env("HOME") || "") + "/.local/state"
    }

    readonly property string statePath: resolveStateRoot() + "/qml-rice/todo.json"

    function save(): void {
        if (!root.loaded)
            return
        todoFile.setText(JSON.stringify({ version: 1, items: root.items }, null, 2))
    }

    function deserialize(raw: string): var {
        try {
            const parsed = JSON.parse(raw)
            return Array.isArray(parsed?.items) ? parsed.items : []
        } catch (error) {
            return []
        }
    }

    property FileView todoFile: FileView {
        path: root.statePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.items = root.deserialize(text())
            root.loaded = true
        }
        onLoadFailed: error => {
            root.loaded = true
            if (error !== FileViewError.FileNotFound)
                console.warn("qml-rice TodoService:", FileViewError.toString(error))
        }
        onSaveFailed: error => console.warn("qml-rice TodoService:",
            FileViewError.toString(error))
    }
}
