import Cocoa

struct DiagnosticWarning {
    let code: String
    let message: String
}

func runDiagnostics(physicalDisplayID: CGDirectDisplayID) -> [DiagnosticWarning] {
    var warnings: [DiagnosticWarning] = []

    var count: CGDisplayCount = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)

    let externalDisplays = ids.filter { CGDisplayIsBuiltin($0) == 0 }
    if !externalDisplays.isEmpty {
        warnings.append(DiagnosticWarning(
            code: "MULTI_MONITOR",
            message: "Detected \(externalDisplays.count) external monitor(s). " +
                     "The virtual display may cause artifacts or mirroring glitches " +
                     "with external monitors connected. If you experience issues, " +
                     "disconnect external monitors or disable mirroring in System Settings."
        ))
    }

    for id in ids where id != physicalDisplayID {
        if CGDisplayIsBuiltin(id) == 0 && CGDisplayIsInMirrorSet(id) != 0 {
            warnings.append(DiagnosticWarning(
                code: "EXISTING_MIRROR",
                message: "Display \(id) is already in a mirror set. " +
                         "Another app (BetterDisplay, SwitchResX) may be managing virtual displays. " +
                         "This can conflict with virtualdisplay. Consider closing that app first."
            ))
            break
        }
    }

    return warnings
}
