import AppKit
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

class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    static var shared: SettingsWindowController?

    private var settings: Settings
    private weak var appDelegate: AppDelegate?

    private var runAtLoginCheck:     NSButton!
    private var hourField:          NSTextField!
    private var minuteField:        NSTextField!
    private var marketPopup:        NSPopUpButton!
    private var resolutionPopup:    NSPopUpButton!
    private var retentionField:     NSTextField!
    private var wallpaperDirField:  NSTextField!
    private var watermarkCheck:     NSButton!
    private var watermarkSizePopup: NSPopUpButton!

    init(settings: Settings, delegate: AppDelegate) {
        self.settings    = settings
        self.appDelegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 414),
            styleMask: [.titled, .closable],
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

        var y: CGFloat        = 374
        let labelW: CGFloat   = 160
        let fieldX: CGFloat   = 175
        let fieldW: CGFloat   = 260
        let rowH:   CGFloat   = 28

        func label(_ text: String, y: CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.frame     = NSRect(x: 20, y: y + 2, width: labelW, height: 20)
            l.alignment = .right
            l.font      = .systemFont(ofSize: 13)
            cv.addSubview(l)
        }
        func section(_ text: String, y: CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.frame     = NSRect(x: 20, y: y, width: 420, height: 18)
            l.font      = .boldSystemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            cv.addSubview(l)
        }

        // ── Startup ─────────────────────────────────────
        section("STARTUP", y: y); y -= rowH

        label("Open at Login:", y: y)
        runAtLoginCheck = NSButton(checkboxWithTitle: "Launch menu bar app at login",
                                   target: self, action: #selector(runAtLoginChanged))
        runAtLoginCheck.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 24)
        runAtLoginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        cv.addSubview(runAtLoginCheck)
        y -= rowH

        // ── Schedule ────────────────────────────────────
        section("SCHEDULE", y: y); y -= rowH

        label("Run Daily At:", y: y)
        let timeStack = NSView(frame: NSRect(x: fieldX, y: y, width: 200, height: 24))
        hourField = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 24))
        hourField.stringValue  = String(settings.scheduledHour)
        hourField.formatter    = intFormatter(0, 23)
        hourField.delegate     = self
        minuteField = NSTextField(frame: NSRect(x: 70, y: 0, width: 50, height: 24))
        minuteField.stringValue = String(format: "%02d", settings.scheduledMinute)
        minuteField.formatter   = intFormatter(0, 59)
        minuteField.delegate    = self
        let colon = NSTextField(labelWithString: ":")
        colon.frame = NSRect(x: 54, y: 2, width: 12, height: 20)
        let hint = NSTextField(labelWithString: "(HH : MM)")
        hint.frame     = NSRect(x: 128, y: 2, width: 80, height: 20)
        hint.font      = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        for v in [hourField!, colon, minuteField!, hint] { timeStack.addSubview(v) }
        cv.addSubview(timeStack)
        y -= rowH

        // ── Image ───────────────────────────────────────
        section("IMAGE", y: y); y -= rowH

        label("Market / Language:", y: y)
        let markets = ["en-US","en-GB","en-AU","de-DE","fr-FR","ja-JP","zh-CN","pt-BR"]
        marketPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 24))
        marketPopup.addItems(withTitles: markets)
        if let i = markets.firstIndex(of: settings.market) { marketPopup.selectItem(at: i) }
        marketPopup.target = self
        marketPopup.action = #selector(popupChanged)
        cv.addSubview(marketPopup)
        y -= rowH

        label("Resolution:", y: y)
        let resolutions = ["UHD","1920x1080","1366x768","1280x720"]
        resolutionPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 24))
        resolutionPopup.addItems(withTitles: resolutions)
        if let i = resolutions.firstIndex(of: settings.resolution) { resolutionPopup.selectItem(at: i) }
        resolutionPopup.target = self
        resolutionPopup.action = #selector(popupChanged)
        cv.addSubview(resolutionPopup)
        y -= rowH

        label("Watermark:", y: y)
        watermarkCheck = NSButton(checkboxWithTitle: "Stamp title & description on image",
                                   target: self, action: #selector(overlayChanged))
        watermarkCheck.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 24)
        watermarkCheck.state = settings.enableWatermark ? .on : .off
        cv.addSubview(watermarkCheck)
        y -= rowH

        label("Overlay Size:", y: y)
        let sizes = ["small", "medium", "large", "extra-large"]
        watermarkSizePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 160, height: 24))
        watermarkSizePopup.addItems(withTitles: sizes)
        if let i = sizes.firstIndex(of: settings.watermarkSize) { watermarkSizePopup.selectItem(at: i) }
        watermarkSizePopup.target = self
        watermarkSizePopup.action = #selector(overlayChanged)
        cv.addSubview(watermarkSizePopup)
        y -= rowH

        // ── Paths ───────────────────────────────────────
        section("PATHS", y: y); y -= rowH

        label("Wallpaper Folder:", y: y)
        wallpaperDirField = NSTextField(frame: NSRect(x: fieldX, y: y, width: fieldW - 34, height: 24))
        wallpaperDirField.stringValue = settings.wallpaperDir
        wallpaperDirField.delegate    = self
        cv.addSubview(wallpaperDirField)
        let browseBtn = NSButton(frame: NSRect(x: fieldX + fieldW - 30, y: y, width: 30, height: 24))
        browseBtn.title      = "…"
        browseBtn.bezelStyle = .rounded
        browseBtn.target     = self
        browseBtn.action     = #selector(browseWallpaperDir)
        cv.addSubview(browseBtn)
        y -= rowH

        // ── Logs ────────────────────────────────────────
        section("LOGS", y: y); y -= rowH

        label("Keep Logs For:", y: y)
        let logStack = NSView(frame: NSRect(x: fieldX, y: y, width: 160, height: 24))
        retentionField = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 24))
        retentionField.stringValue = String(settings.logRetentionDays)
        retentionField.formatter   = intFormatter(1, 365)
        retentionField.delegate    = self
        let daysLbl = NSTextField(labelWithString: "days")
        daysLbl.frame = NSRect(x: 56, y: 2, width: 50, height: 20)
        logStack.addSubview(retentionField)
        logStack.addSubview(daysLbl)
        cv.addSubview(logStack)

        let logsPathLbl = NSTextField(labelWithString: "→ \(AppPaths.logsDir)")
        logsPathLbl.frame     = NSRect(x: fieldX, y: y - 18, width: fieldW, height: 16)
        logsPathLbl.font      = .systemFont(ofSize: 10)
        logsPathLbl.textColor = .tertiaryLabelColor
        cv.addSubview(logsPathLbl)
    }

    private func intFormatter(_ min: Int, _ max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum      = NSNumber(value: min)
        f.maximum      = NSNumber(value: max)
        f.allowsFloats = false
        return f
    }

    // MARK: Actions

    @objc private func runAtLoginChanged() {
        appDelegate?.setRunAtLogin(runAtLoginCheck.state == .on)
        runAtLoginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func browseWallpaperDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.canCreateDirectories  = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            wallpaperDirField.stringValue = url.path
            commit()
        }
    }

    /// Market / resolution popup changes — save and update schedule only.
    @objc private func popupChanged() { commit() }

    /// Watermark on/off or overlay size changes — save, update, and re-stamp wallpaper immediately.
    @objc private func overlayChanged() {
        commit()
        appDelegate?.runNow()
    }

    // MARK: NSTextFieldDelegate — fires on Return or focus loss

    func controlTextDidEndEditing(_ obj: Notification) { commit() }

    // MARK: Helpers

    private func collectValues() {
        settings.scheduledHour    = hourField.integerValue
        settings.scheduledMinute  = minuteField.integerValue
        settings.market           = marketPopup.selectedItem?.title ?? "en-US"
        settings.resolution       = resolutionPopup.selectedItem?.title ?? "UHD"
        settings.enableWatermark  = watermarkCheck.state == .on
        settings.watermarkSize    = watermarkSizePopup.selectedItem?.title ?? "medium"
        settings.logRetentionDays = retentionField.integerValue
        settings.wallpaperDir     = wallpaperDirField.stringValue
    }

    private func commit() {
        collectValues()
        settings.save()
        appDelegate?.applySettings(settings)
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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var isRunning = false
    private var settings  = Settings.load()

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

        let loaded       = launchAgentIsLoaded()
        let scheduleItem = mi(loaded ? "Disable Daily Schedule" : "Enable Daily Schedule",
                               sel: #selector(toggleSchedule))
        if loaded { scheduleItem.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) }
        menu.addItem(scheduleItem)
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
                self.rebuildMenu()
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
                self.rebuildMenu()
            }
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

    @objc func toggleSchedule() {
        if launchAgentIsLoaded() {
            bash("launchctl unload '\(AppPaths.launchAgentPlist)'")
        } else {
            bash("launchctl load '\(AppPaths.launchAgentPlist)'")
        }
        rebuildMenu()
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
