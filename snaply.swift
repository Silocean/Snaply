import AppKit

// 像素、选区交互、屏幕录制权限都走系统 /usr/sbin/screencapture。

enum Shot: String {
    case region, window, screen, screens

    var interactive: Bool { self == .region || self == .window }
}

struct Options: Equatable {
    var shot: Shot
    var silent = false
    var cursor = false
    var delay = 0
    var output: String?
}

enum Command: Equatable {
    case menu
    case help
    case openFolder
    case check
    case shoot(Options)
}

private let usageText = """
用法:
  snaply                  打开菜单栏
  snaply region           截取选区
  snaply window           截取窗口
  snaply screen           截取主屏幕
  snaply screens          每个屏幕一张
  snaply open             打开保存目录
  snaply check            自检

选项:
  --silent                关闭快门声
  --cursor                全屏时包含光标
  --delay <秒>            延迟后再截
  -o <文件或目录>         保存时的默认位置（默认 ~/Pictures/Snaply）
"""

private var menuController: MenuController?

func captureArguments(_ options: Options) -> [String] {
    var args: [String] = []
    switch options.shot {
    case .region: args += ["-i", "-s"]
    case .window: args += ["-i", "-w", "-o"]
    case .screen: args += ["-m"]
    case .screens: break
    }
    if options.cursor, !options.shot.interactive { args.append("-C") }
    if options.silent { args.append("-x") }
    if options.delay > 0 { args += ["-T", String(options.delay)] }
    args += ["-t", "png"]
    return args
}

func numberedPaths(base: String, count: Int) -> [String] {
    if count <= 1 { return [base] }
    let url = URL(fileURLWithPath: base)
    let ext = url.pathExtension
    let stem = url.deletingPathExtension().lastPathComponent
    let dir = url.deletingLastPathComponent()
    return (1...count).map { index in
        let leaf: String
        if ext.isEmpty {
            leaf = index == 1 ? stem : "\(stem) (\(index))"
        } else {
            leaf = index == 1 ? "\(stem).\(ext)" : "\(stem) (\(index)).\(ext)"
        }
        return dir.appendingPathComponent(leaf).path
    }
}

func allocateBase(dir: URL, stem: String, ext: String) -> String {
    func path(_ suffix: String) -> String {
        dir.appendingPathComponent(suffix.isEmpty ? "\(stem).\(ext)" : "\(stem)\(suffix).\(ext)").path
    }
    if !FileManager.default.fileExists(atPath: path("")) { return path("") }
    for n in 2...999 {
        let candidate = path(" \(n)")
        if !FileManager.default.fileExists(atPath: candidate) { return candidate }
    }
    return path("")
}

func activeDisplayCount() -> Int {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success else { return 1 }
    return max(1, Int(count))
}

func picturesDirectory() -> URL {
    let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Snaply", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func timestampStem(_ now: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Snaply \(formatter.string(from: now))"
}

func destinationPaths(_ options: Options) -> [String] {
    let count = options.shot == .screens ? activeDisplayCount() : 1
    if let output = options.output {
        let expanded = (output as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir)
        if expanded.hasSuffix("/") || (exists && isDir.boolValue) {
            let dir = URL(fileURLWithPath: expanded, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return numberedPaths(base: allocateBase(dir: dir, stem: timestampStem(), ext: "png"), count: count)
        }
        let url = URL(fileURLWithPath: expanded)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return numberedPaths(base: url.path, count: count)
    }
    return numberedPaths(
        base: allocateBase(dir: picturesDirectory(), stem: timestampStem(), ext: "png"),
        count: count
    )
}

struct UsageError: Error, Equatable {
    var message: String
}

func parse(_ args: [String]) -> Result<Command, UsageError> {
    if args.isEmpty || args == ["menu"] { return .success(.menu) }
    if args == ["help"] || args == ["-h"] || args == ["--help"] { return .success(.help) }
    if args == ["open"] { return .success(.openFolder) }
    if args == ["check"] { return .success(.check) }
    guard let shot = Shot(rawValue: args[0]) else {
        return .failure(UsageError(message: "未知命令: \(args[0])\n\n\(usageText)"))
    }
    var options = Options(shot: shot)
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--silent": options.silent = true
        case "--cursor": options.cursor = true
        case "--delay":
            index += 1
            guard index < args.count, let seconds = Int(args[index]), (0..<3600).contains(seconds) else {
                return .failure(UsageError(message: "--delay 需要 0 到 3599 的整数秒"))
            }
            options.delay = seconds
        case "-o", "--output":
            index += 1
            guard index < args.count else { return .failure(UsageError(message: "-o 需要路径")) }
            options.output = args[index]
        default:
            return .failure(UsageError(message: "未知选项: \(arg)\n\n\(usageText)"))
        }
        index += 1
    }
    return .success(.shoot(options))
}

func screencapture(_ args: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = args
    do {
        try task.run()
    } catch {
        fputs("无法启动截屏: \(error.localizedDescription)\n", stderr)
        return 1
    }
    task.waitUntilExit()
    return task.terminationStatus
}

func loadShot(_ path: String) -> NSImage? {
    guard let source = NSImage(contentsOfFile: path),
          let tiff = source.tiffRepresentation,
          let image = NSImage(data: tiff) else { return nil }
    return image
}

func runCapture(_ options: Options) -> Int32 {
    let count = options.shot == .screens ? activeDisplayCount() : 1
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("snaply-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        fputs("无法保存截图\n", stderr)
        return 1
    }
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = (0..<count).map { dir.appendingPathComponent("\($0).png").path }
    let code = screencapture(captureArguments(options) + paths)
    if code != 0 {
        if !options.shot.interactive { fputs("未截到\n", stderr) }
        return code
    }
    let images = paths.compactMap(loadShot)
    if images.isEmpty {
        if !options.shot.interactive { fputs("未截到\n", stderr) }
        return options.shot.interactive ? 0 : 1
    }
    showEditors(zip(images, destinationPaths(options)).map { ($0, URL(fileURLWithPath: $1)) })
    return 0
}

func selfCheck() -> Int32 {
    var failures = 0
    func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            fputs("fail: \(message)\n", stderr)
        }
    }

    let region = captureArguments(Options(shot: .region, silent: true, cursor: true))
    expect(region == ["-i", "-s", "-x", "-t", "png"], "region \(region)")
    let window = captureArguments(Options(shot: .window, delay: 2))
    expect(window == ["-i", "-w", "-o", "-T", "2", "-t", "png"], "window \(window)")
    let screen = captureArguments(Options(shot: .screen, cursor: true))
    expect(screen == ["-m", "-C", "-t", "png"], "screen \(screen)")
    let screens = captureArguments(Options(shot: .screens, silent: true))
    expect(screens == ["-x", "-t", "png"], "screens \(screens)")

    let numbered = numberedPaths(base: "/tmp/Snaply.png", count: 2)
    expect(numbered == ["/tmp/Snaply.png", "/tmp/Snaply (2).png"], "numbered \(numbered)")

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("snaply-check-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = allocateBase(dir: dir, stem: "Shot", ext: "png")
        expect(first == dir.appendingPathComponent("Shot.png").path, "allocate \(first)")
        FileManager.default.createFile(atPath: first, contents: Data("x".utf8))
        let second = allocateBase(dir: dir, stem: "Shot", ext: "png")
        expect(second == dir.appendingPathComponent("Shot 2.png").path, "allocate2 \(second)")
        try FileManager.default.removeItem(at: dir)
    } catch {
        expect(false, "tmpdir \(error)")
    }

    expect(parse([]) == .success(.menu), "parse menu")
    expect(parse(["region", "-o", "/tmp"]) == .success(.shoot(Options(shot: .region, output: "/tmp"))), "parse region")
    let mapped = imagePoint(view: CGPoint(x: 60, y: 40), imageRect: CGRect(x: 10, y: 20, width: 100, height: 50), imageSize: CGSize(width: 200, height: 100))
    expect(mapped.x == 100 && mapped.y == 40, "image point \(mapped)")
    if case .failure = parse(["nope"]) {} else { expect(false, "parse nope") }

    if failures == 0 {
        print("ok")
        return 0
    }
    return 1
}

func prepareCLI() {
    NSApplication.shared.setActivationPolicy(.prohibited)
}

func execute(_ command: Command) -> Int32 {
    switch command {
    case .menu:
        startMenu()
        return 0
    case .help:
        print(usageText)
        return 0
    case .openFolder:
        prepareCLI()
        NSWorkspace.shared.open(picturesDirectory())
        return 0
    case .check:
        return selfCheck()
    case .shoot(let options):
        return runCapture(options)
    }
}

func startMenu() {
    if isatty(STDOUT_FILENO) == 1 {
        print("Snaply 在菜单栏。用菜单退出，或按 Ctrl+C。")
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = MenuController()
    menuController = controller
    app.delegate = controller
    app.run()
}

final class MenuController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status.button?.image = appIcon()
        status.button?.imageScaling = .scaleProportionallyDown
        status.button?.toolTip = "Snaply"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        signalSource = source
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        status.button?.performClick(nil)
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addShot(menu, "截取选区", .region)
        addShot(menu, "截取窗口", .window)
        addShot(menu, "截取主屏幕", .screen)
        if activeDisplayCount() > 1 {
            addShot(menu, "截取全部屏幕", .screens)
        }
        menu.addItem(.separator())
        let open = menu.addItem(withTitle: "打开保存目录", action: #selector(openFolder(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
    }

    private func addShot(_ menu: NSMenu, _ title: String, _ shot: Shot) {
        let item = menu.addItem(withTitle: title, action: #selector(shoot(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = shot.rawValue
    }

    @objc func shoot(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let shot = Shot(rawValue: raw) else { return }
        let code = runCapture(Options(shot: shot))
        if code == 0 {
            flash("checkmark")
        } else if !shot.interactive {
            flash("xmark")
        }
    }

    @objc func openFolder(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(picturesDirectory())
    }

    @objc func quit(_ sender: NSMenuItem) {
        NSApp.terminate(sender)
    }

    private func flash(_ symbol: String) {
        status.button?.image = icon(symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.status.button?.image = self.appIcon()
        }
    }

    private func appIcon() -> NSImage? {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = rect.insetBy(dx: 1.6, dy: 2.6)
            let screen = NSBezierPath(roundedRect: body, xRadius: 2, yRadius: 2)
            screen.lineWidth = 1.15
            screen.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: body.maxX - 3.2, y: body.minY - 0.5, width: 3.5, height: 3.5))
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func icon(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Snaply")
        image?.isTemplate = true
        return image
    }
}

@main
struct SnaplyMain {
    static func main() {
        switch parse(Array(CommandLine.arguments.dropFirst())) {
        case .failure(let error):
            fputs(error.message + "\n", stderr)
            exit(2)
        case .success(let command):
            exit(execute(command))
        }
    }
}
