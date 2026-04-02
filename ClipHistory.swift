#!/usr/bin/env swift

import AppKit
import Carbon
import Foundation
import ApplicationServices

private let maxDays = 7
private let maxItems = 1000
private let pollInterval: TimeInterval = 0.7

private struct HistoryEntry: Codable {
    let text: String
    let ts: Date
}

private final class ClipboardStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/cliphistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")

        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let entries = try? decoder.decode([HistoryEntry].self, from: data) else { return [] }
        return prune(entries)
    }

    func save(_ entries: [HistoryEntry]) {
        let pruned = prune(entries)
        guard let data = try? encoder.encode(pruned) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func prune(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxDays, to: Date()) ?? Date.distantPast
        return entries.filter { $0.ts >= cutoff }.prefix(maxItems).map { $0 }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private final class EnterTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return / Numpad Enter
            onEnter?()
        case 53: // Escape
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class SearchField: NSSearchField {
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return / Numpad Enter
            onEnter?()
        case 53: // Escape
            onEscape?()
        case 125: // Down
            onDown?()
        case 126: // Up
            onUp?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ClipboardPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private let entries: [HistoryEntry]
    private var filteredIndices: [Int]
    private var selectedIndex: Int?
    private var window: NSWindow?
    private var tableView: EnterTableView?
    private var searchField: SearchField?
    private var modalStopped = false

    init(entries: [HistoryEntry]) {
        self.entries = entries
        self.filteredIndices = Array(entries.indices)
    }

    func present() -> Int? {
        guard !entries.isEmpty else { return nil }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let w = floor(visible.width * 0.5)
        let h = floor(visible.height * 0.5)
        let x = visible.minX + (visible.width - w) / 2
        let y = visible.minY + (visible.height - h) / 2

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ClipHistory"
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self

        let content = NSView(frame: win.contentRect(forFrameRect: win.frame))
        content.autoresizingMask = [.width, .height]
        win.contentView = content

        let topPadding: CGFloat = 12
        let sidePadding: CGFloat = 12
        let searchHeight: CGFloat = 32

        let search = SearchField(frame: NSRect(
            x: sidePadding,
            y: content.bounds.height - topPadding - searchHeight,
            width: content.bounds.width - (sidePadding * 2),
            height: searchHeight
        ))
        search.autoresizingMask = [.width, .minYMargin]
        search.placeholderString = "Search history"
        search.delegate = self
        search.onEnter = { [weak self] in self?.acceptSelection() }
        search.onEscape = { [weak self] in self?.cancelSelection() }
        search.onDown = { [weak self] in self?.moveSelectionFromSearch(delta: 1) }
        search.onUp = { [weak self] in self?.moveSelectionFromSearch(delta: -1) }
        content.addSubview(search)

        let scroll = NSScrollView(frame: NSRect(
            x: 0,
            y: 0,
            width: content.bounds.width,
            height: content.bounds.height - searchHeight - (topPadding * 2)
        ))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let table = EnterTableView(frame: scroll.bounds)
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 26
        table.allowsMultipleSelection = false
        table.focusRingType = .none
        table.delegate = self
        table.dataSource = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        col.width = w - 24
        table.addTableColumn(col)

        table.onEnter = { [weak self] in self?.acceptSelection() }
        table.onEscape = { [weak self] in self?.cancelSelection() }
        table.doubleAction = #selector(onDoubleClick)
        table.target = self

        scroll.documentView = table
        content.addSubview(scroll)

        table.reloadData()
        table.deselectAll(nil)

        self.window = win
        self.tableView = table
        self.searchField = search

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(search)

        NSApp.runModal(for: win)

        self.window = nil
        self.tableView = nil
        self.searchField = nil

        return selectedIndex
    }

    private func acceptSelection() {
        guard let tv = tableView else {
            cancelSelection()
            return
        }
        let row = tv.selectedRow
        if row >= 0 && row < filteredIndices.count {
            selectedIndex = filteredIndices[row]
        }
        closeWindow()
    }

    private func moveSelection(delta: Int) {
        guard let tv = tableView, !filteredIndices.isEmpty else { return }
        let cur = tv.selectedRow >= 0 ? tv.selectedRow : 0
        let next = max(0, min(filteredIndices.count - 1, cur + delta))
        tv.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tv.scrollRowToVisible(next)
    }

    private func moveSelectionFromSearch(delta: Int) {
        guard let tv = tableView, let w = window, !filteredIndices.isEmpty else { return }

        let target = (delta >= 0) ? 0 : (filteredIndices.count - 1)
        tv.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        tv.scrollRowToVisible(target)
        w.makeFirstResponder(tv)
    }

    private func displayText(for index: Int) -> String {
        var s = entries[index].text.replacingOccurrences(of: "\n", with: "↵")
        s = s.replacingOccurrences(of: "\t", with: "⇥")
        if s.count > 120 {
            s = String(s.prefix(120)) + "..."
        }
        return "\(index + 1). \(s)"
    }

    private func fuzzyMatch(_ query: String, in text: String) -> Bool {
        if text.contains(query) {
            return true
        }

        var q = query.startIndex
        var t = text.startIndex
        while q < query.endIndex && t < text.endIndex {
            if query[q] == text[t] {
                q = query.index(after: q)
            }
            t = text.index(after: t)
        }
        return q == query.endIndex
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = (searchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredIndices = Array(entries.indices)
        } else {
            filteredIndices = entries.indices.filter { idx in
                fuzzyMatch(query, in: entries[idx].text.lowercased())
            }
        }

        tableView?.reloadData()
        if !filteredIndices.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelectionFromSearch(delta: 1)
            return true
        }

        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelectionFromSearch(delta: -1)
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            acceptSelection()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelSelection()
            return true
        }

        return false
    }

    private func cancelSelection() {
        selectedIndex = nil
        closeWindow()
    }
    
    private func closeWindow() {
        guard !modalStopped else { return }
        modalStopped = true
        NSApp.stopModal(withCode: .OK)
        if let w = window {
            w.close()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredIndices.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let textField: NSTextField
        if let tf = cell.textField {
            textField = tf
        } else {
            textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let actualIndex = filteredIndices[row]
        textField.stringValue = displayText(for: actualIndex)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        if row >= 0 && row < filteredIndices.count {
            selectedIndex = filteredIndices[row]
        }
    }

    @objc private func onDoubleClick() {
        acceptSelection()
    }

    func windowWillClose(_ notification: Notification) {
        guard !modalStopped else { return }
        modalStopped = true
        NSApp.stopModal(withCode: .cancel)
    }
}

final class ClipHistoryApp {
    private let store = ClipboardStore()
    private var history: [HistoryEntry] = []
    private var timer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var statusItem: NSStatusItem?

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var isInjectingPaste = false

    func start() {
        requestAccessibilityPermissionPrompt()

        history = store.load()
        captureCurrentClipboard()

        startClipboardPolling()
        registerHotkey()
        setupMenuBar()

        print("ClipHistory native running. Press Cmd+Shift+V")
    }

    private func requestAccessibilityPermissionPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startClipboardPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.onTick()
        }
    }

    private func onTick() {
        guard !isInjectingPaste else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        addToHistory(text)
    }

    private func captureCurrentClipboard() {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        addToHistory(text)
        lastChangeCount = pb.changeCount
    }

    private func addToHistory(_ text: String) {
        history.removeAll { $0.text == text }
        history.insert(HistoryEntry(text: text, ts: Date()), at: 0)
        if history.count > maxItems { history = Array(history.prefix(maxItems)) }
        store.save(history)
    }

    private func setupMenuBar() {
        guard statusItem == nil else { return }  // Prevent duplicate items
        
        let statusBar = NSStatusBar.system
        let item = statusBar.statusItem(withLength: 30.0)
        
        item.button?.title = "📋"
        item.button?.font = NSFont.systemFont(ofSize: 14)
        
        let menu = NSMenu()

        let clearItem = NSMenuItem(title: "Clear All History", action: #selector(clearAllHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ClipHistory", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        
        self.statusItem = item
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func clearAllHistory() {
        history.removeAll()
        store.clearAll()
    }

    private func registerHotkey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: UInt32(1))
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 9 // kVK_ANSI_V

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let app = Unmanaged<ClipHistoryApp>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.id == 1 {
                    app.showPickerAndPaste()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )
    }

    private func showPickerAndPaste() {
        history = store.prune(history)
        captureCurrentClipboard()
        guard !history.isEmpty else { return }

        let previousApp = NSWorkspace.shared.frontmostApplication

        let visibleEntries = Array(history.prefix(80))
        let picker = ClipboardPicker(entries: visibleEntries)
        guard let selectedIndex = picker.present(), selectedIndex < visibleEntries.count else {
            return
        }

        let text = visibleEntries[selectedIndex].text
        addToHistory(text)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard let app = previousApp else { return }

        isInjectingPaste = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.sendCmdV()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.isInjectingPaste = false
                }
            }
        }
    }

    private func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        let tap = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: tap)
        vDown?.post(tap: tap)
        vUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }
}

// Single-instance guard via lock file
let lockFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/share/cliphistory/.lock")
let lockPath = lockFile.path

if FileManager.default.fileExists(atPath: lockPath),
   let pidStr = try? String(contentsOfFile: lockPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
   let existingPid = Int32(pidStr),
   existingPid != getpid(),
   kill(existingPid, 0) == 0 {
    print("ClipHistory is already running (PID \(existingPid)). Exiting.")
    exit(0)
}
try? String(getpid()).write(toFile: lockPath, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let manager = ClipHistoryApp()
manager.start()

app.run()
