import AppKit

let argv = CommandLine.arguments

func argValue(_ flag: String) -> String? {
    guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}

if argv.contains("--help") {
    print("""
    Usage: virtualdisplay [options]

    Creates a virtual display at a custom refresh rate and mirrors the main
    screen to it.

    Options:
      --hz <rate>       Refresh rate for the virtual display (default: 240)
      --width <px>      Custom width (stretched resolution)
      --height <px>     Custom height (stretched resolution)
      --display <id>    Display ID to mirror (use --list-displays to see IDs)
      --list-displays   Print connected displays as JSON and exit
      --no-menu         Run without a menu bar icon (stop with SIGTERM or Ctrl-C)
      --help            Print this message and exit
    """)
    exit(0)
}

if argv.contains("--list-displays") {
    var count: CGDisplayCount = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)

    var displays: [[String: Any]] = []
    for id in ids {
        let mode = CGDisplayCopyDisplayMode(id)
        let w = mode?.pixelWidth ?? CGDisplayPixelsWide(id)
        let h = mode?.pixelHeight ?? CGDisplayPixelsHigh(id)
        let builtin = CGDisplayIsBuiltin(id) != 0
        let screen = NSScreen.screens.first(where: {
            $0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID == id
        })
        let name = screen?.localizedName ?? (builtin ? "Built-in Display" : "External Display")
        displays.append([
            "id": id,
            "name": name,
            "width": w,
            "height": h,
            "builtin": builtin,
        ])
    }

    if let data = try? JSONSerialization.data(withJSONObject: displays, options: .prettyPrinted),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    }
    exit(0)
}

let customWidth  = argValue("--width").flatMap(Int.init)
let customHeight = argValue("--height").flatMap(Int.init)
let refreshRate  = argValue("--hz").flatMap(Double.init) ?? 240.0
let displayID    = argValue("--display").flatMap(UInt32.init)

if refreshRate < 1 || refreshRate > 600 {
    fputs("Error: --hz must be between 1 and 600\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate(
    showMenu: !argv.contains("--no-menu"),
    width: customWidth,
    height: customHeight,
    hz: refreshRate,
    displayID: displayID
)
app.delegate = delegate
app.run()
