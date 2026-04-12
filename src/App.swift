import Cocoa
import ColorSync

class AppDelegate: NSObject, NSApplicationDelegate {
    private let showMenu: Bool
    private let customWidth: Int?
    private let customHeight: Int?
    private let refreshRate: Double
    private let targetDisplayID: CGDirectDisplayID?
    private var virtualDisplay: CGVirtualDisplay?
    private var statusItem: NSStatusItem?
    private var nativeMode: CGDisplayMode?
    private var physicalDisplayID: CGDirectDisplayID = 0
    private var signalSources: [DispatchSourceSignal] = []
    private var isStopping = false
    private var pollTimer: Timer?
    private var pollCount = 0
    private var colorProfileTmpURL: URL?

    init(showMenu: Bool, width: Int? = nil, height: Int? = nil, hz: Double = 240.0, displayID: UInt32? = nil) {
        self.showMenu = showMenu
        self.customWidth = width
        self.customHeight = height
        self.refreshRate = hz
        self.targetDisplayID = displayID.map { CGDirectDisplayID($0) }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.stop() }
            src.resume()
            signalSources.append(src)
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        setupVirtualDisplay()
        if showMenu { setupStatusBar() }
    }

    @objc private func handleSleep() {
        teardownVirtualDisplay()
    }

    @objc private func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.setupVirtualDisplay()
        }
    }

    private func teardownVirtualDisplay() {
        pollTimer?.invalidate()
        pollTimer = nil
        disableMirroring()
        virtualDisplay = nil
    }

    private func setupVirtualDisplay() {
        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        if let target = targetDisplayID, ids.contains(target) {
            physicalDisplayID = target
        } else {
            if targetDisplayID != nil {
                fputs("Warning: display ID \(targetDisplayID!) not found, falling back to default\n", stderr)
            }
            physicalDisplayID = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
        }

        let warnings = runDiagnostics(physicalDisplayID: physicalDisplayID)
        for w in warnings {
            fputs("Warning [\(w.code)]: \(w.message)\n", stderr)
        }

        guard let screen = NSScreen.screens.first(where: { $0.displayID == physicalDisplayID }) ?? NSScreen.main else { return }

        let metrics = metricsFromScreen(screen, displayID: physicalDisplayID)
        let resolved = resolveDisplay(metrics: metrics, customWidth: customWidth, customHeight: customHeight)

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = "Virtual \(Int(refreshRate))Hz"
        descriptor.maxPixelsWide = UInt32(resolved.maxPixelsWide)
        descriptor.maxPixelsHigh = UInt32(resolved.maxPixelsHigh)
        descriptor.sizeInMillimeters = metrics.physicalSizeMM
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0002
        descriptor.terminationHandler = { [weak self] _, _ in self?.virtualDisplay = nil }

        let display = CGVirtualDisplay(descriptor: descriptor)
        if display.displayID == 0 {
            fputs("Error: failed to create virtual display (unsupported hardware?)\n", stderr)
            return
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = resolved.hiDPI ? 1 : 0
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(resolved.width), height: UInt(resolved.height), refreshRate: refreshRate),
            CGVirtualDisplayMode(width: UInt(resolved.width), height: UInt(resolved.height), refreshRate: 60),
        ]
        display.apply(settings)
        virtualDisplay = display

        pollCount = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollForMirroring()
        }
    }

    private func pollForMirroring() {
        guard let vd = virtualDisplay else { pollTimer?.invalidate(); return }
        pollCount += 1
        if pollCount > 20 {
            fputs("Error: virtual display did not appear after 10 seconds\n", stderr)
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        guard ids.contains(vd.displayID) else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        enableMirroring()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyColorProfile(to: vd.displayID)
        }
    }

    private func applyColorProfile(to virtualID: CGDirectDisplayID) {
        guard
            let screen = NSScreen.screens.first(where: { $0.displayID == physicalDisplayID }),
            let iccData = screen.colorSpace?.iccProfileData
        else { return }
        let uuid = CGDisplayCreateUUIDFromDisplayID(virtualID).takeRetainedValue()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virtualdisplay-\(virtualID).icc")
        guard (try? iccData.write(to: url)) != nil else { return }
        colorProfileTmpURL = url

        func apply() {
            ColorSyncDeviceSetCustomProfiles(
                "mntr" as CFString,
                uuid,
                ["DeviceDefaultProfile": url] as CFDictionary
            )
        }

        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { apply() }
    }

    private func enableMirroring() {
        guard let vd = virtualDisplay else { return }
        nativeMode = CGDisplayCopyDisplayMode(physicalDisplayID)

        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        var cfg: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&cfg)
        for id in ids {
            if CGDisplayIsInMirrorSet(id) != 0 {
                CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
            }
        }
        CGConfigureDisplayMirrorOfDisplay(cfg, physicalDisplayID, vd.displayID)
        CGCompleteDisplayConfiguration(cfg, CGConfigureOption(rawValue: 0))
    }

    private func disableMirroring() {
        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        var cfg: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&cfg)
        for id in ids {
            if CGDisplayIsInMirrorSet(id) != 0 {
                CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
            }
        }
        if let mode = nativeMode {
            CGConfigureDisplayWithDisplayMode(cfg, physicalDisplayID, mode, nil)
        }
        CGCompleteDisplayConfiguration(cfg, CGConfigureOption(rawValue: 0))
        nativeMode = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["Dock"]
            try? task.run()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Virtual \(Int(refreshRate))Hz Display", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Stop", action: #selector(stop), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc func stop() {
        guard !isStopping else { return }
        isStopping = true
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        teardownVirtualDisplay()
        if let url = colorProfileTmpURL {
            try? FileManager.default.removeItem(at: url)
        }
        NSApp.terminate(nil)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as! CGDirectDisplayID
    }

    var physicalSizeInMillimeters: CGSize {
        guard let dpi = deviceDescription[NSDeviceDescriptionKey("NSDeviceResolution")] as? NSValue else {
            return CGSize(width: 600, height: 340)
        }
        let d = dpi.sizeValue
        guard d.width > 0, d.height > 0 else { return CGSize(width: 600, height: 340) }
        return CGSize(width: frame.width / d.width * 25.4, height: frame.height / d.height * 25.4)
    }
}
