import AppKit

// Entry Point
if let replayIdx = CommandLine.arguments.firstIndex(of: "--replay"), replayIdx + 1 < CommandLine.arguments.count {
    let replayPath = CommandLine.arguments[replayIdx + 1]
    var tuningOption: String? = nil
    if let tuningIdx = CommandLine.arguments.firstIndex(of: "--tuning"), tuningIdx + 1 < CommandLine.arguments.count {
        tuningOption = CommandLine.arguments[tuningIdx + 1]
    }
    var outPath: String? = nil
    if let outIdx = CommandLine.arguments.firstIndex(of: "--out"), outIdx + 1 < CommandLine.arguments.count {
        outPath = CommandLine.arguments[outIdx + 1]
    }
    var modeOption: String? = nil
    if let modeIdx = CommandLine.arguments.firstIndex(of: "--mode"), modeIdx + 1 < CommandLine.arguments.count {
        modeOption = CommandLine.arguments[modeIdx + 1]
    }

    let runner = ReplayRunner(
        replayFilePath: replayPath,
        tuningOption: tuningOption,
        outputFilePath: outPath,
        modeOption: modeOption
    )
    let exitCode = runner.run()
    exit(exitCode)
}

if CommandLine.arguments.contains("--test-gates") {
    runGateVerification()
    exit(0)
}

if let calIdx = CommandLine.arguments.firstIndex(of: "--calibrate-replay"), calIdx + 1 < CommandLine.arguments.count {
    let calPath = CommandLine.arguments[calIdx + 1]
    let exitCode = CalibrationReplayRunner.run(filePath: calPath)
    exit(exitCode)
}

if let dumpIdx = CommandLine.arguments.firstIndex(of: "--dump-features"), dumpIdx + 1 < CommandLine.arguments.count {
    let inPath = CommandLine.arguments[dumpIdx + 1]
    var outPath = "features.csv"
    if let outIdx = CommandLine.arguments.firstIndex(of: "--out"), outIdx + 1 < CommandLine.arguments.count {
        outPath = CommandLine.arguments[outIdx + 1]
    }
    let useRaw = CommandLine.arguments.contains("--raw")
    let exitCode = FeatureDumper.dumpFeatures(inputFile: inPath, outputFile: outPath, useRawPoints: useRaw)
    exit(exitCode)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
