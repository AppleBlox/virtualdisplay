import AppKit

let args = Set(CommandLine.arguments.dropFirst())

if args.contains("--help") {
    print("""
    Usage: virtualdisplay [options]

    Creates a virtual 240Hz display and mirrors the main screen to it.

    Options:
      --no-menu    Run without a menu bar icon (stop with SIGTERM or Ctrl-C)
      --help       Print this message and exit
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(showMenu: !args.contains("--no-menu"))
app.delegate = delegate
app.run()
