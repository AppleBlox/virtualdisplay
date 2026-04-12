import Cocoa

struct DisplayMetrics {
    let pixelWidth: Int
    let pixelHeight: Int
    let scaleFactor: Double
    let physicalSizeMM: CGSize
}

struct ResolvedDisplay {
    let width: Int
    let height: Int
    let maxPixelsWide: Int
    let maxPixelsHigh: Int
    let hiDPI: Bool
}

func resolveDisplay(
    metrics: DisplayMetrics,
    customWidth: Int?,
    customHeight: Int?
) -> ResolvedDisplay {
    let isCustom = customWidth != nil || customHeight != nil

    if isCustom {
        let w = customWidth  ?? metrics.pixelWidth
        let h = customHeight ?? metrics.pixelHeight
        return ResolvedDisplay(
            width: w,
            height: h,
            maxPixelsWide: w,
            maxPixelsHigh: h,
            hiDPI: false
        )
    }

    let isRetina = metrics.scaleFactor > 1
    let w = isRetina ? Int((Double(metrics.pixelWidth) / metrics.scaleFactor).rounded()) : metrics.pixelWidth
    let h = isRetina ? Int((Double(metrics.pixelHeight) / metrics.scaleFactor).rounded()) : metrics.pixelHeight

    return ResolvedDisplay(
        width: w,
        height: h,
        maxPixelsWide: metrics.pixelWidth,
        maxPixelsHigh: metrics.pixelHeight,
        hiDPI: isRetina
    )
}

func metricsFromScreen(_ screen: NSScreen, displayID: CGDirectDisplayID) -> DisplayMetrics {
    let mode = CGDisplayCopyDisplayMode(displayID)
    return DisplayMetrics(
        pixelWidth:  mode?.pixelWidth  ?? CGDisplayPixelsWide(displayID),
        pixelHeight: mode?.pixelHeight ?? CGDisplayPixelsHigh(displayID),
        scaleFactor: Double(screen.backingScaleFactor),
        physicalSizeMM: screen.physicalSizeInMillimeters
    )
}
