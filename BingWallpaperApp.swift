import AppKit
import SwiftUI
import Foundation
import ServiceManagement

// MARK: - App Paths (no hardcoded home dir)

enum AppPaths {
    static var logsDir: String {
        fm.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/BingWallpaper").path
    }
    static var launchAgentPlist: String {
        fm.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("LaunchAgents/com.nnet.bing-wallpaper.plist").path
    }
    static var defaultWallpaperDir: String {
        fm.urls(for: .picturesDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("BingWallpaper").path
    }
    static var settingsFile: String {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("BingWallpaper/settings.json").path
    }
    static var scriptPath: String {
        Bundle.main.path(forResource: "bing-wallpaper", ofType: "sh")
            ?? (Bundle.main.resourcePath! + "/bing-wallpaper.sh")
    }
    private static let fm = FileManager.default
}

// MARK: - Settings

struct Settings: Codable {
    var scheduledHour: Int       = 6
    var scheduledMinute: Int     = 0
    var wallpaperDir: String     = AppPaths.defaultWallpaperDir
    var market: String           = "en-US"
    var resolution: String       = "UHD"
    var logRetentionDays: Int    = 7
    var enableWatermark: Bool    = true
    var watermarkSize: String    = "medium"   // small | medium | large | extra-large
    var lastInstalledBuild: String = ""
    var selectedWallpaperFile: String = ""    // filename (not path) of a manually chosen wallpaper; "" = follow today's

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: AppPaths.settingsFile)),
              let s    = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return s
    }

    func save() {
        let dir = (AppPaths.settingsFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: URL(fileURLWithPath: AppPaths.settingsFile))
        }
    }
}

struct WallpaperMetadata: Codable {
    let title: String
    let description: String
    let date: String
}

struct WallpaperEntry {
    let fileName: String
    let path: String
    let date: Date
    let title: String
    let description: String
}

struct BingArchiveResponse: Codable {
    struct ImageEntry: Codable {
        let startdate: String
        let title: String?
        let copyright: String?
    }

    let images: [ImageEntry]
}

// MARK: - Script Runner  (--run-script mode, no UI)

enum ScriptRunner {
    static func runAndExit() {
        let settings = Settings.load()

        // Ensure directories exist
        let fm = FileManager.default
        try? fm.createDirectory(atPath: AppPaths.logsDir,          withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: settings.wallpaperDir,      withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments     = [AppPaths.scriptPath]
        task.environment   = [
            "HOME":                          NSHomeDirectory(),
            "PATH":                          "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "BINGWALLPAPER_LOG_DIR":         AppPaths.logsDir,
            "BINGWALLPAPER_WALLPAPER_DIR":   settings.wallpaperDir,
            "BINGWALLPAPER_MARKET":          settings.market,
            "BINGWALLPAPER_RESOLUTION":      settings.resolution,
            "BINGWALLPAPER_WATERMARK":       settings.enableWatermark ? "1" : "0",
            "BINGWALLPAPER_WATERMARK_SIZE":  settings.watermarkSize,
            "BINGWALLPAPER_LOG_RETENTION":   String(settings.logRetentionDays),
        ]
        do    { try task.run() } catch { exit(1) }
        task.waitUntilExit()
        exit(task.terminationStatus)
    }
}

// MARK: - Settings Window

@MainActor
final class SettingsEditorModel: ObservableObject {
    @Published var runAtLogin: Bool
    @Published var dailyScheduleEnabled: Bool
    @Published var scheduledHour: Int
    @Published var scheduledMinute: Int
    @Published var market: String
    @Published var resolution: String
    @Published var enableWatermark: Bool
    @Published var watermarkSize: String
    @Published var logRetentionDays: Int
    @Published var wallpaperDir: String

    let logsPath: String

    let markets = ["en-US", "en-GB", "en-AU", "de-DE", "fr-FR", "ja-JP", "zh-CN", "pt-BR"]
    let resolutions = ["UHD", "1920x1080", "1366x768", "1280x720"]
    let watermarkSizes = ["small", "medium", "large", "extra-large"]

    private var settings: Settings
    private let applySettings: (Settings) -> Void
    private let runNow: () -> Void
    private let setRunAtLogin: (Bool) -> Bool
    private let setDailyScheduleEnabled: (Bool) -> Bool

    init(settings: Settings,
         runAtLogin: Bool,
         dailyScheduleEnabled: Bool,
         logsPath: String,
         applySettings: @escaping (Settings) -> Void,
         runNow: @escaping () -> Void,
         setRunAtLogin: @escaping (Bool) -> Bool,
         setDailyScheduleEnabled: @escaping (Bool) -> Bool) {
        self.settings = settings
        self.runAtLogin = runAtLogin
        self.dailyScheduleEnabled = dailyScheduleEnabled
        self.scheduledHour = settings.scheduledHour
        self.scheduledMinute = settings.scheduledMinute
        self.market = settings.market
        self.resolution = settings.resolution
        self.enableWatermark = settings.enableWatermark
        self.watermarkSize = settings.watermarkSize
        self.logRetentionDays = settings.logRetentionDays
        self.wallpaperDir = settings.wallpaperDir
        self.logsPath = logsPath
        self.applySettings = applySettings
        self.runNow = runNow
        self.setRunAtLogin = setRunAtLogin
        self.setDailyScheduleEnabled = setDailyScheduleEnabled
    }

    func updateRunAtLogin() {
        runAtLogin = setRunAtLogin(runAtLogin)
    }

    func updateDailyScheduleEnabled() {
        dailyScheduleEnabled = setDailyScheduleEnabled(dailyScheduleEnabled)
    }

    func chooseWallpaperFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            wallpaperDir = url.path
            applyChanges(triggerRunNow: false)
        }
    }

    func applyChanges(triggerRunNow: Bool) {
        settings.scheduledHour = min(max(scheduledHour, 0), 23)
        settings.scheduledMinute = min(max(scheduledMinute, 0), 59)
        settings.market = markets.contains(market) ? market : "en-US"
        settings.resolution = resolutions.contains(resolution) ? resolution : "UHD"
        settings.enableWatermark = enableWatermark
        settings.watermarkSize = watermarkSizes.contains(watermarkSize) ? watermarkSize : "medium"
        settings.logRetentionDays = max(logRetentionDays, 1)
        settings.wallpaperDir = wallpaperDir.trimmingCharacters(in: .whitespacesAndNewlines)

        scheduledHour = settings.scheduledHour
        scheduledMinute = settings.scheduledMinute
        logRetentionDays = settings.logRetentionDays
        wallpaperDir = settings.wallpaperDir

        settings.save()
        applySettings(settings)
        if triggerRunNow { runNow() }
    }
}

struct SettingsWindowView: View {
    @ObservedObject var model: SettingsEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Text("Customize wallpaper updates, schedule, and storage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionCard(title: "Startup", icon: "power") {
                Toggle("Launch menu bar app at login", isOn: Binding(
                    get: { model.runAtLogin },
                    set: { newValue in
                        model.runAtLogin = newValue
                        model.updateRunAtLogin()
                    }
                ))
                .toggleStyle(.switch)
            }

            SectionCard(title: "Schedule", icon: "clock") {
                Toggle("Enable automatic daily wallpaper update", isOn: Binding(
                    get: { model.dailyScheduleEnabled },
                    set: { newValue in
                        model.dailyScheduleEnabled = newValue
                        model.updateDailyScheduleEnabled()
                    }
                ))
                .toggleStyle(.switch)

                HStack(spacing: 10) {
                    Text("Run time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Picker("Hour", selection: Binding(
                        get: { model.scheduledHour },
                        set: { model.scheduledHour = $0; model.applyChanges(triggerRunNow: false) }
                    )) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    Text(":")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Picker("Minute", selection: Binding(
                        get: { model.scheduledMinute },
                        set: { model.scheduledMinute = $0; model.applyChanges(triggerRunNow: false) }
                    )) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    Text("24-hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.dailyScheduleEnabled)
                .opacity(model.dailyScheduleEnabled ? 1 : 0.55)
            }

            SectionCard(title: "Image", icon: "photo") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Market / language")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Picker("Market", selection: Binding(
                            get: { model.market },
                            set: { model.market = $0; model.applyChanges(triggerRunNow: false) }
                        )) {
                            ForEach(model.markets, id: \.self) { m in Text(m).tag(m) }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }

                    GridRow {
                        Text("Resolution")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Picker("Resolution", selection: Binding(
                            get: { model.resolution },
                            set: { model.resolution = $0; model.applyChanges(triggerRunNow: false) }
                        )) {
                            ForEach(model.resolutions, id: \.self) { r in Text(r).tag(r) }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }
                }

                Divider().padding(.vertical, 2)

                Toggle("Stamp title & description on image", isOn: Binding(
                    get: { model.enableWatermark },
                    set: { model.enableWatermark = $0; model.applyChanges(triggerRunNow: true) }
                ))
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Overlay size")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Overlay size", selection: Binding(
                        get: { model.watermarkSize },
                        set: { model.watermarkSize = $0; model.applyChanges(triggerRunNow: true) }
                    )) {
                        Text("S").tag("small")
                        Text("M").tag("medium")
                        Text("L").tag("large")
                        Text("XL").tag("extra-large")
                    }
                    .pickerStyle(.segmented)
                    .disabled(!model.enableWatermark)
                    .opacity(model.enableWatermark ? 1 : 0.55)
                }
            }

            SectionCard(title: "Paths", icon: "folder") {
                Text("Wallpaper folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Wallpaper folder", text: Binding(
                        get: { model.wallpaperDir },
                        set: { model.wallpaperDir = $0 }
                    ), onCommit: {
                        model.applyChanges(triggerRunNow: false)
                    })
                    .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        model.chooseWallpaperFolder()
                    }
                    .controlSize(.regular)
                }
            }

            SectionCard(title: "Logs", icon: "doc.text") {
                HStack(spacing: 8) {
                    Text("Retention")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Stepper(value: Binding(
                        get: { model.logRetentionDays },
                        set: { model.logRetentionDays = $0; model.applyChanges(triggerRunNow: false) }
                    ), in: 1...365) {
                        Text("\(model.logRetentionDays) days")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Logs path: \(model.logsPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(18)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 620, minHeight: 640)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
            )
        }
    }
}

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static var shared: SettingsWindowController?

    private var settings: Settings
    private weak var appDelegate: AppDelegate?
    private var editorModel: SettingsEditorModel?

    init(settings: Settings, delegate: AppDelegate) {
        self.settings = settings
        self.appDelegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bing Wallpaper — Settings"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        guard let appDelegate else { return }

        let model = SettingsEditorModel(
            settings: settings,
            runAtLogin: SMAppService.mainApp.status == .enabled,
            dailyScheduleEnabled: appDelegate.isDailyScheduleEnabled(),
            logsPath: AppPaths.logsDir,
            applySettings: { [weak self] newSettings in
                self?.settings = newSettings
                appDelegate.applySettings(newSettings)
            },
            runNow: { [weak appDelegate] in
                appDelegate?.runNow()
            },
            setRunAtLogin: { [weak appDelegate] enabled in
                appDelegate?.setRunAtLogin(enabled)
                return SMAppService.mainApp.status == .enabled
            },
            setDailyScheduleEnabled: { [weak appDelegate] enabled in
                appDelegate?.setDailyScheduleEnabled(enabled)
                return appDelegate?.isDailyScheduleEnabled() ?? false
            }
        )
        self.editorModel = model

        let root = SettingsWindowView(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = cv.bounds
        hosting.autoresizingMask = [.width, .height]
        cv.addSubview(hosting)
    }

    func windowWillClose(_ notification: Notification) { SettingsWindowController.shared = nil }
}

// MARK: - About Window

class AboutWindowController: NSWindowController, NSWindowDelegate {

    static var shared: AboutWindowController?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Bing Wallpaper"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // App icon
        let iconView = NSImageView(frame: NSRect(x: 125, y: 168, width: 90, height: 90))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        cv.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Bing Wallpaper")
        nameLabel.frame = NSRect(x: 20, y: 138, width: 300, height: 26)
        nameLabel.font = .boldSystemFont(ofSize: 18)
        nameLabel.alignment = .center
        cv.addSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let verLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        verLabel.frame = NSRect(x: 20, y: 116, width: 300, height: 18)
        verLabel.font = .systemFont(ofSize: 12)
        verLabel.textColor = .secondaryLabelColor
        verLabel.alignment = .center
        cv.addSubview(verLabel)

        // Divider
        let divider = NSBox(frame: NSRect(x: 20, y: 108, width: 300, height: 1))
        divider.boxType = .separator
        cv.addSubview(divider)

        // Description
        let desc = NSTextField(wrappingLabelWithString:
            "Downloads the Bing daily wallpaper and sets it on all desktops.")
        desc.frame = NSRect(x: 28, y: 60, width: 284, height: 44)
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .labelColor
        desc.alignment = .center
        cv.addSubview(desc)

        // Copyright
        let copy = NSTextField(labelWithString: "© 2026 Mitchell St Amant")
        copy.frame = NSRect(x: 20, y: 38, width: 300, height: 16)
        copy.font = .systemFont(ofSize: 11)
        copy.textColor = .tertiaryLabelColor
        copy.alignment = .center
        cv.addSubview(copy)

        // Close button
        let closeBtn = NSButton(frame: NSRect(x: 130, y: 12, width: 80, height: 24))
        closeBtn.title = "Close"
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.target = self
        closeBtn.action = #selector(closeWindow)
        cv.addSubview(closeBtn)
    }

    @objc private func closeWindow() { window?.close() }

    func windowWillClose(_ notification: Notification) { AboutWindowController.shared = nil }
}

// MARK: - Wallpaper Switcher Window

class WallpaperSwitcherWindowController: NSWindowController, NSWindowDelegate {

    static var shared: WallpaperSwitcherWindowController?

    private weak var appDelegate: AppDelegate?
    private var wallpapers: [WallpaperEntry] = []
    private var activeFileName: String?

    private var summaryLabel: NSTextField!
    private var scrollView: NSScrollView!
    private var listContainerView: NSView!

    private let rowHeight: CGFloat = 78
    private let rowGap: CGFloat = 8
    private let edgePadding: CGFloat = 10

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }()

    init(delegate: AppDelegate) {
        self.appDelegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Switch Wallpaper"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        let inset: CGFloat = 20
        let summaryHeight: CGFloat = 18
        let summaryTopInset: CGFloat = 14
        let summaryToListGap: CGFloat = 8

        summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.frame = NSRect(
            x: inset,
            y: cv.bounds.height - summaryTopInset - summaryHeight,
            width: cv.bounds.width - (inset * 2),
            height: summaryHeight
        )
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(summaryLabel)

        let scrollHeight = cv.bounds.height - inset - summaryToListGap - summaryTopInset - summaryHeight
        scrollView = NSScrollView(frame: NSRect(
            x: inset,
            y: inset,
            width: cv.bounds.width - (inset * 2),
            height: scrollHeight
        ))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        listContainerView = NSView(frame: NSRect(x: 0, y: 0, width: scrollView.contentView.bounds.width, height: scrollHeight))
        scrollView.documentView = listContainerView
        cv.addSubview(scrollView)
    }

    func refresh(wallpapers: [WallpaperEntry], activeFileName: String?) {
        self.wallpapers = wallpapers
        self.activeFileName = activeFileName
        rebuildRows()
    }

    private func rebuildRows() {
        listContainerView.subviews.forEach { $0.removeFromSuperview() }

        summaryLabel.stringValue = wallpapers.isEmpty
            ? "No wallpapers available yet"
            : "Showing \(wallpapers.count) wallpaper\(wallpapers.count == 1 ? "" : "s")"

        guard !wallpapers.isEmpty else {
            let empty = NSTextField(labelWithString: "Run the wallpaper fetch once, then come back here.")
            empty.frame = NSRect(x: edgePadding, y: edgePadding, width: 500, height: 18)
            empty.textColor = .secondaryLabelColor
            listContainerView.addSubview(empty)
            updateListFrame(contentHeight: 60)
            return
        }

        let rowCount = CGFloat(wallpapers.count)
        let contentHeight = edgePadding + (rowCount * rowHeight) + ((rowCount - 1) * rowGap) + edgePadding
        updateListFrame(contentHeight: contentHeight)

        let rowWidth = max(scrollView.contentView.bounds.width - (edgePadding * 2), 620)

        for (idx, wallpaper) in wallpapers.enumerated() {
            let yFromTop = edgePadding + CGFloat(idx) * (rowHeight + rowGap)
            let rowY = contentHeight - yFromTop - rowHeight
            let row = buildRow(wallpaper: wallpaper, rowWidth: rowWidth, rowY: rowY)
            listContainerView.addSubview(row)
        }
    }

    private func buildRow(wallpaper: WallpaperEntry, rowWidth: CGFloat, rowY: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: edgePadding, y: rowY, width: rowWidth, height: rowHeight))

        let thumb = NSImageView(frame: NSRect(x: 0, y: 10, width: 112, height: 58))
        thumb.imageScaling = .scaleAxesIndependently
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        thumb.image = NSImage(contentsOfFile: wallpaper.path)
        row.addSubview(thumb)

        let buttonWidth: CGFloat = 90
        let buttonX = rowWidth - buttonWidth
        let textX: CGFloat = 124
        let textWidth = max(buttonX - textX - 12, 220)

        let title = NSTextField(labelWithString: wallpaper.title)
        title.frame = NSRect(x: textX, y: 48, width: textWidth, height: 20)
        title.font = .boldSystemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        row.addSubview(title)

        let isToday = Calendar.current.isDateInToday(wallpaper.date)
        let dateText = isToday ? "Today" : Self.dateFormatter.string(from: wallpaper.date)
        let date = NSTextField(labelWithString: dateText)
        date.frame = NSRect(x: textX, y: 30, width: textWidth, height: 16)
        date.font = .systemFont(ofSize: 11)
        date.textColor = .secondaryLabelColor
        row.addSubview(date)

        let descText = wallpaper.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = NSTextField(labelWithString: descText.isEmpty ? "No description" : descText)
        desc.frame = NSRect(x: textX, y: 10, width: textWidth, height: 18)
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .tertiaryLabelColor
        desc.lineBreakMode = .byTruncatingTail
        row.addSubview(desc)

        let button = NSButton(frame: NSRect(x: buttonX, y: 24, width: buttonWidth, height: 30))
        let isActive = wallpaper.fileName == activeFileName
        button.title = isActive ? "Using" : "Use"
        button.bezelStyle = .rounded
        button.isEnabled = !isActive
        button.identifier = NSUserInterfaceItemIdentifier(wallpaper.fileName)
        button.target = self
        button.action = #selector(useWallpaper(_:))
        row.addSubview(button)

        return row
    }

    private func updateListFrame(contentHeight: CGFloat) {
        let visibleWidth = max(scrollView.contentView.bounds.width, 300)
        let visibleHeight = scrollView.contentView.bounds.height
        let finalHeight = max(contentHeight, visibleHeight)
        listContainerView.frame = NSRect(x: 0, y: 0, width: visibleWidth, height: finalHeight)
    }

    func windowDidResize(_ notification: Notification) {
        rebuildRows()
    }

    @objc private func useWallpaper(_ sender: NSButton) {
        guard let fileName = sender.identifier?.rawValue else { return }
        appDelegate?.switchToWallpaper(named: fileName)
    }

    func windowWillClose(_ notification: Notification) { WallpaperSwitcherWindowController.shared = nil }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var isRunning = false
    private var settings  = Settings.load()
    private var screenChangeWorkItem: DispatchWorkItem?

    private let launchAgentLabel = "com.nnet.bing-wallpaper"

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureDirectories()
        setupStatusItem()
        DispatchQueue.global(qos: .utility).async { self.installOrUpdateLaunchAgent() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(running: false)
        rebuildMenu()
    }

    private func setIcon(running: Bool) {
        let name = running ? "arrow.clockwise" : "photo.on.rectangle.angled"
        let img  = NSImage(systemSymbolName: name, accessibilityDescription: "Bing Wallpaper")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    // MARK: Menu

    func rebuildMenu() {
        let menu = NSMenu()

        let infoItem = NSMenuItem(title: lastRunInfo(), action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())

        menu.addItem(mi(isRunning ? "Running…" : "Run Now",
                        sel: isRunning ? nil : #selector(runNow), key: "r"))
        menu.addItem(.separator())

        menu.addItem(mi("Open Wallpaper Folder", sel: #selector(openWallpaperFolder)))
        menu.addItem(mi("View Latest Log",        sel: #selector(viewLatestLog)))
        menu.addItem(.separator())

        menu.addItem(mi("Switch Wallpaper…", sel: #selector(openWallpaperSwitcher)))
        menu.addItem(.separator())

        menu.addItem(mi("Settings…", sel: #selector(openSettings), key: ","))
        menu.addItem(mi("About Bing Wallpaper", sel: #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(mi("Quit", sel: #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func mi(_ title: String, sel: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Last Run Info

    private func lastRunInfo() -> String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: AppPaths.logsDir) else { return "Never run" }
        let sorted = files
            .filter { $0.hasPrefix("BingWallpaper_") && $0.hasSuffix(".log") }
            .compactMap { name -> (String, Date)? in
                let p = AppPaths.logsDir + "/" + name
                let d = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date
                return d.map { (p, $0) }
            }
            .sorted { $0.1 > $1.1 }
        guard let (path, date) = sorted.first else { return "Never run" }
        let ok   = (try? String(contentsOfFile: path, encoding: .utf8))?.contains("Completed") == true
        let df   = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        return "\(ok ? "✓" : "✗") Last run: \(df.string(from: date))"
    }

    // MARK: Wallpaper Switching

    private static let wallpaperDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let wallpaperFallbackTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }()

    private func metadataPath(forImageFileName fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return (settings.wallpaperDir as NSString).appendingPathComponent("\(base).json")
    }

    private func loadMetadata(forImageFileName fileName: String) -> WallpaperMetadata? {
        let path = metadataPath(forImageFileName: fileName)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(WallpaperMetadata.self, from: data)
    }

    private func saveMetadata(_ metadata: WallpaperMetadata, forImageFileName fileName: String) {
        let path = metadataPath(forImageFileName: fileName)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func backfillMissingMetadata(for wallpapers: [WallpaperEntry]) {
        let missing = wallpapers.filter { loadMetadata(forImageFileName: $0.fileName) == nil }
        guard !missing.isEmpty else { return }

        guard let encodedMarket = settings.market.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=\(encodedMarket)") else { return }

        guard let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(BingArchiveResponse.self, from: data) else { return }

        var byDate: [String: WallpaperMetadata] = [:]
        for image in archive.images {
            guard image.startdate.count >= 8 else { continue }
            let date = image.startdate.prefix(8)
            let yyyy = date.prefix(4)
            let mm = date.dropFirst(4).prefix(2)
            let dd = date.dropFirst(6).prefix(2)
            let normalized = "\(yyyy)-\(mm)-\(dd)"
            byDate[normalized] = WallpaperMetadata(
                title: (image.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? image.title!
                    : "Bing Daily Wallpaper",
                description: image.copyright ?? "",
                date: normalized
            )
        }

        for wallpaper in missing {
            let key = Self.wallpaperDateFormatter.string(from: wallpaper.date)
            if let metadata = byDate[key] {
                saveMetadata(metadata, forImageFileName: wallpaper.fileName)
            }
        }
    }

    /// Wallpaper files present on disk (newest first). The script keeps at most 3.
    private func availableWallpapers() -> [WallpaperEntry] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: settings.wallpaperDir) else { return [] }
        return files
            .filter { $0.hasPrefix("bing-") && $0.hasSuffix(".jpg") }
            .compactMap { fileName -> WallpaperEntry? in
                let dateString = fileName.dropFirst("bing-".count).dropLast(".jpg".count)
                guard let date = Self.wallpaperDateFormatter.date(from: String(dateString)) else { return nil }
                let path = (settings.wallpaperDir as NSString).appendingPathComponent(fileName)
                let metadata = loadMetadata(forImageFileName: fileName)
                let fallbackTitle = "Bing Wallpaper — \(Self.wallpaperFallbackTitleFormatter.string(from: date))"
                let title = metadata?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? metadata!.title
                    : fallbackTitle
                let description = metadata?.description ?? ""
                return WallpaperEntry(
                    fileName: fileName,
                    path: path,
                    date: date,
                    title: title,
                    description: description
                )
            }
            .sorted { $0.date > $1.date }
    }

    private func resolveActiveWallpaperFileName(from wallpapers: [WallpaperEntry]) -> String? {
        if !settings.selectedWallpaperFile.isEmpty,
           wallpapers.contains(where: { $0.fileName == settings.selectedWallpaperFile }) {
            return settings.selectedWallpaperFile
        }

        let today = Self.wallpaperDateFormatter.string(from: Date())
        let todayFile = "bing-\(today).jpg"
        if wallpapers.contains(where: { $0.fileName == todayFile }) {
            return todayFile
        }

        return wallpapers.first?.fileName
    }

    @objc private func openWallpaperSwitcher() {
        if WallpaperSwitcherWindowController.shared == nil {
            WallpaperSwitcherWindowController.shared = WallpaperSwitcherWindowController(delegate: self)
        }

        refreshWallpaperSwitcher()
        NSApp.activate(ignoringOtherApps: true)
        WallpaperSwitcherWindowController.shared?.window?.makeKeyAndOrderFront(nil)

        DispatchQueue.global(qos: .utility).async {
            let current = self.availableWallpapers()
            self.backfillMissingMetadata(for: current)
            DispatchQueue.main.async {
                self.refreshWallpaperSwitcher()
            }
        }
    }

    func switchToWallpaper(named fileName: String) {
        let path = (settings.wallpaperDir as NSString).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard applyWallpaperFile(path) else { return }
        settings.selectedWallpaperFile = fileName
        settings.save()
        rebuildMenu()
        refreshWallpaperSwitcher()
    }

    private func refreshWallpaperSwitcher() {
        let wallpapers = availableWallpapers()
        let activeFileName = resolveActiveWallpaperFileName(from: wallpapers)
        WallpaperSwitcherWindowController.shared?.refresh(wallpapers: wallpapers, activeFileName: activeFileName)
    }

    /// Re-applies an already-downloaded wallpaper file to every desktop without re-running the download script.
    @discardableResult
    private func applyWallpaperFile(_ path: String) -> Bool {
        bash("osascript -e 'tell application \"System Events\" to set picture of every desktop to \"\(path)\"'").exitCode == 0
    }

    // MARK: Actions

    @objc func runNow() {
        guard !isRunning else { return }
        isRunning = true
        setIcon(running: true)
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            ScriptRunner.runInProcess(settings: self.settings, force: true)
            DispatchQueue.main.async {
                self.isRunning = false
                self.setIcon(running: false)
                self.settings.selectedWallpaperFile = ""
                self.settings.save()
                self.rebuildMenu()
                self.refreshWallpaperSwitcher()
            }
        }
    }

    @objc private func systemDidWake() {
        guard !isRunning else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        let wallpaperFile = (settings.wallpaperDir as NSString).appendingPathComponent("bing-\(today).jpg")
        guard !FileManager.default.fileExists(atPath: wallpaperFile) else { return }
        isRunning = true
        setIcon(running: true)
        rebuildMenu()
        DispatchQueue.global(qos: .utility).async {
            ScriptRunner.runInProcess(settings: self.settings, force: false)
            DispatchQueue.main.async {
                self.isRunning = false
                self.setIcon(running: false)
                self.settings.selectedWallpaperFile = ""
                self.settings.save()
                self.rebuildMenu()
                self.refreshWallpaperSwitcher()
            }
        }
    }

    // Fires when a display is connected/disconnected or its arrangement/resolution
    // changes. Newly connected displays don't inherit the desktop picture that was
    // already set on the others, so re-apply today's wallpaper to every screen.
    // Screen reconfiguration can post this notification several times in quick
    // succession, so debounce before reapplying.
    @objc private func screenParametersDidChange() {
        screenChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reapplyWallpaperForCurrentScreens()
        }
        screenChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func reapplyWallpaperForCurrentScreens() {
        guard !isRunning else { return }
        let wallpapers = availableWallpapers()
        guard let activeFileName = resolveActiveWallpaperFileName(from: wallpapers) else { return }
        let wallpaperFile = (settings.wallpaperDir as NSString).appendingPathComponent(activeFileName)
        guard FileManager.default.fileExists(atPath: wallpaperFile) else { return }
        DispatchQueue.global(qos: .utility).async {
            self.applyWallpaperFile(wallpaperFile)
        }
    }

    @objc func openWallpaperFolder() {
        let url = URL(fileURLWithPath: settings.wallpaperDir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc func viewLatestLog() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: AppPaths.logsDir) else { return }
        let sorted = files
            .filter { $0.hasPrefix("BingWallpaper_") && $0.hasSuffix(".log") }
            .compactMap { name -> (String, Date)? in
                let p = AppPaths.logsDir + "/" + name
                let d = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date
                return d.map { (p, $0) }
            }
            .sorted { $0.1 > $1.1 }
        if let (path, _) = sorted.first {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    func isDailyScheduleEnabled() -> Bool {
        launchAgentIsLoaded()
    }

    func setDailyScheduleEnabled(_ enable: Bool) {
        let loaded = launchAgentIsLoaded()
        if enable == loaded { return }
        if enable {
            bash("launchctl load '\(AppPaths.launchAgentPlist)'")
        } else {
            bash("launchctl unload '\(AppPaths.launchAgentPlist)'")
        }
        rebuildMenu()
    }

    @objc func toggleSchedule() {
        setDailyScheduleEnabled(!launchAgentIsLoaded())
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func openAbout() {
        if AboutWindowController.shared == nil {
            AboutWindowController.shared = AboutWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        AboutWindowController.shared?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings() {
        if SettingsWindowController.shared == nil {
            SettingsWindowController.shared = SettingsWindowController(settings: settings, delegate: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared?.window?.makeKeyAndOrderFront(nil)
    }

    func applySettings(_ newSettings: Settings) {
        settings = newSettings
        rewriteLaunchAgentSchedule()
        rebuildMenu()
        refreshWallpaperSwitcher()
    }

    func setRunAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Checkbox corrects itself by re-reading SMAppService.mainApp.status
        }
    }

    // MARK: Directories

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: AppPaths.logsDir,       withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: settings.wallpaperDir,  withIntermediateDirectories: true)
    }

    // MARK: LaunchAgent

    private func launchAgentIsLoaded() -> Bool {
        bash("launchctl list '\(launchAgentLabel)' 2>/dev/null").exitCode == 0
    }

    /// Install the LaunchAgent on first launch, or rewrite it when the app moves or the build changes.
    /// Runs on a background thread — never call from the main thread.
    private func installOrUpdateLaunchAgent() {
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let currentExec  = Bundle.main.executablePath ?? ""
        let plistExists  = FileManager.default.fileExists(atPath: AppPaths.launchAgentPlist)

        let buildChanged = settings.lastInstalledBuild != currentBuild
        let pathChanged  = plistInstalledExecPath() != currentExec

        guard !plistExists || buildChanged || pathChanged else { return }

        let wasLoaded = plistExists && launchAgentIsLoaded()
        if wasLoaded { bash("launchctl unload '\(AppPaths.launchAgentPlist)'") }
        writeLaunchAgentPlist()
        bash("launchctl load '\(AppPaths.launchAgentPlist)'")

        settings.lastInstalledBuild = currentBuild
        settings.save()
    }

    /// Returns the ProgramArguments[0] path stored in the installed plist, or "" if unreadable.
    private func plistInstalledExecPath() -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: AppPaths.launchAgentPlist)),
              let obj  = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any],
              let args = dict["ProgramArguments"] as? [String],
              let first = args.first else { return "" }
        return first
    }

    private func rewriteLaunchAgentSchedule() {
        let wasLoaded = launchAgentIsLoaded()
        if wasLoaded { bash("launchctl unload '\(AppPaths.launchAgentPlist)'") }
        writeLaunchAgentPlist()
        if wasLoaded { bash("launchctl load '\(AppPaths.launchAgentPlist)'") }
    }

    private func writeLaunchAgentPlist() {
        guard let execPath = Bundle.main.executablePath else { return }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
                <string>--run-script</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>\(settings.scheduledHour)</integer>
                <key>Minute</key>
                <integer>\(settings.scheduledMinute)</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>/dev/null</string>
            <key>StandardErrorPath</key>
            <string>/dev/null</string>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
        let dir = (AppPaths.launchAgentPlist as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? plist.write(toFile: AppPaths.launchAgentPlist, atomically: true, encoding: .utf8)
    }

    // MARK: Shell

    @discardableResult
    private func bash(_ cmd: String) -> (output: String, exitCode: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments     = ["-c", cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = pipe
        do { try task.run() } catch { return ("", -1) }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", task.terminationStatus)
    }
}

// MARK: - ScriptRunner (in-process variant for Run Now)

extension ScriptRunner {
    static func runInProcess(settings: Settings, force: Bool = true) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments     = [AppPaths.scriptPath]
        task.environment   = [
            "HOME":                          NSHomeDirectory(),
            "PATH":                          "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "BINGWALLPAPER_LOG_DIR":         AppPaths.logsDir,
            "BINGWALLPAPER_WALLPAPER_DIR":   settings.wallpaperDir,
            "BINGWALLPAPER_MARKET":          settings.market,
            "BINGWALLPAPER_RESOLUTION":      settings.resolution,
            "BINGWALLPAPER_WATERMARK":       settings.enableWatermark ? "1" : "0",
            "BINGWALLPAPER_WATERMARK_SIZE":  settings.watermarkSize,
            "BINGWALLPAPER_LOG_RETENTION":   String(settings.logRetentionDays),
            "BINGWALLPAPER_FORCE":           force ? "1" : "0",
        ]
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Entry Point

// LaunchAgent mode: run the script silently and exit (no UI)
if CommandLine.arguments.contains("--run-script") {
    ScriptRunner.runAndExit()
}

// Normal mode: menu bar app
let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
