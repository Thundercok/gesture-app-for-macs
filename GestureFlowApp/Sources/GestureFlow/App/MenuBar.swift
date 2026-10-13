import AppKit

extension AppDelegate {
    func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "GestureFlow")
        }

        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "GestureFlow (Minimal Switcher)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Bật / Tắt Debug Camera HUD", action: #selector(toggleHUD), keyEquivalent: "d")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let compactItem = NSMenuItem(title: "Thu nhỏ / Phóng to Debug HUD", action: #selector(toggleCompact), keyEquivalent: "m")
        compactItem.target = self
        menu.addItem(compactItem)

        let recordItem = NSMenuItem(title: "Bắt đầu / Dừng ghi Dataset (Record)", action: #selector(toggleRecordingDataset), keyEquivalent: "r")
        recordItem.target = self
        menu.addItem(recordItem)

        let markMisfireItem = NSMenuItem(title: "Đánh dấu vừa bắn sai (⌃⌥⌘M)", action: #selector(markMisfireIncident), keyEquivalent: "")
        markMisfireItem.target = self
        menu.addItem(markMisfireItem)

        let markMissedItem = NSMenuItem(title: "Đánh dấu vừa bỏ lỡ cử chỉ (⌃⌥⌘N)", action: #selector(markMissedIncident), keyEquivalent: "")
        markMissedItem.target = self
        menu.addItem(markMissedItem)

        let passiveItem = NSMenuItem(title: "Ghi sự cố thụ động (Flight Recorder)", action: #selector(togglePassiveIncidents), keyEquivalent: "")
        passiveItem.target = self
        passiveItem.state = IncidentRecorder.shared.isEnabled ? .on : .off
        passiveItem.toolTip = "Chỉ lưu toạ độ landmark và trạng thái engine khi xảy ra sự cố, tuyệt đối không lưu hình ảnh camera."
        menu.addItem(passiveItem)

        let undoMisfireItem = NSMenuItem(title: "Hoàn tác khi đánh dấu bắn sai", action: #selector(toggleUndoOnMisfire), keyEquivalent: "")
        undoMisfireItem.target = self
        undoMisfireItem.state = appState.undoOnMisfire ? .on : .off
        undoMisfireItem.toolTip = "Khi bấm ⌃⌥⌘M trong vòng 3 giây sau khi cử chỉ tự kích hoạt, tự động thực hiện hành động ngược lại."
        menu.addItem(undoMisfireItem)

        let sensitivityMenu = NSMenu()
        let safeItem = NSMenuItem(title: "An toàn (Safe - Ít bắn nhầm nhất)", action: #selector(setTuningSafe), keyEquivalent: "")
        safeItem.target = self
        safeItem.state = (GestureTuning.current.preset == .safe) ? .on : .off
        sensitivityMenu.addItem(safeItem)

        let balancedItem = NSMenuItem(title: "Cân bằng (Balanced - Mặc định)", action: #selector(setTuningBalanced), keyEquivalent: "")
        balancedItem.target = self
        balancedItem.state = (GestureTuning.current.preset == .balanced) ? .on : .off
        sensitivityMenu.addItem(balancedItem)

        let sensitiveItem = NSMenuItem(title: "Nhạy (Sensitive - Nhẹ tay)", action: #selector(setTuningSensitive), keyEquivalent: "")
        sensitiveItem.target = self
        sensitiveItem.state = (GestureTuning.current.preset == .sensitive) ? .on : .off
        sensitivityMenu.addItem(sensitiveItem)

        let sensitivityParentItem = NSMenuItem(title: "Độ nhạy cử chỉ (Sensitivity)", action: nil, keyEquivalent: "")
        sensitivityParentItem.submenu = sensitivityMenu
        menu.addItem(sensitivityParentItem)

        let calibrateItem = NSMenuItem(title: "Hiệu chuẩn (60s Calibration)...", action: #selector(toggleCalibrationWizard), keyEquivalent: "")
        calibrateItem.target = self
        calibrateItem.toolTip = "Đo kích thước bàn tay và tốc độ vuốt tự nhiên (5 lần) trong 60 giây để tự động điều chỉnh ngưỡng cử chỉ."
        menu.addItem(calibrateItem)

        let modeMenu = NSMenu()
        let minimalItem = NSMenuItem(title: "Tối giản (Vector)", action: #selector(setModeMinimal), keyEquivalent: "")
        minimalItem.target = self
        modeMenu.addItem(minimalItem)

        let monoItem = NSMenuItem(title: "Đơn sắc (Monochrome)", action: #selector(setModeMonochrome), keyEquivalent: "")
        monoItem.target = self
        modeMenu.addItem(monoItem)

        let feedItem = NSMenuItem(title: "Hình ảnh Camera", action: #selector(setModeCameraFeed), keyEquivalent: "")
        feedItem.target = self
        modeMenu.addItem(feedItem)

        let modeParentItem = NSMenuItem(title: "Chế độ hiển thị Canvas", action: nil, keyEquivalent: "")
        modeParentItem.submenu = modeMenu
        menu.addItem(modeParentItem)

        let systemModeMenu = NSMenu()
        let scrollItem = NSMenuItem(title: "1. Air Scroll (Lướt như điện thoại)", action: #selector(setModeAirScroll), keyEquivalent: "1")
        scrollItem.target = self
        systemModeMenu.addItem(scrollItem)

        let navItem = NSMenuItem(title: "2. Mac Navigation (Vuốt chuyển App, Mission Control)", action: #selector(setModeMacNavigation), keyEquivalent: "2")
        navItem.target = self
        systemModeMenu.addItem(navItem)

        let zoomItem = NSMenuItem(title: "3. Spatial Zoom (Thu phóng 2 tay tự nhiên)", action: #selector(setModeSpatialZoom), keyEquivalent: "3")
        zoomItem.target = self
        systemModeMenu.addItem(zoomItem)

        let systemModeParent = NSMenuItem(title: "Chế độ hoạt động (System Mode)", action: nil, keyEquivalent: "")
        systemModeParent.submenu = systemModeMenu
        menu.addItem(systemModeParent)

        let permItem = NSMenuItem(title: "Cài đặt quyền Trợ năng (Accessibility)...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Thoát GestureFlow", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    @objc func toggleRecordingDataset() {
        if DatasetRecorder.shared.isRecording {
            DatasetRecorder.shared.stopRecording()
            appState.isRecordingDataset = false
            appState.setAction("Đã dừng ghi dữ liệu")
        } else {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd_HHmmss"
            let defaultName = "gestures_\(df.string(from: Date())).jsonl"
            let defaultDir = ("~/Library/Application Support/GestureFlow/recordings" as NSString).expandingTildeInPath
            let path = "\(defaultDir)/\(defaultName)"
            if DatasetRecorder.shared.startRecording(toPath: path) {
                appState.isRecordingDataset = true
                appState.datasetLabel = DatasetRecorder.shared.currentLabel
                appState.setAction("Đang ghi: \(defaultName)")
            }
        }
    }

    @objc func markMisfireIncident() {
        IncidentRecorder.shared.markUser(.misfire)
        if appState.undoOnMisfire,
           let recentAction = IntentArbiter.shared.recentCommittedAction(within: 3.0),
           let undoDesc = ActionDispatcher.performUndo(forAction: recentAction) {
            appState.setAction(undoDesc)
        } else {
            appState.setAction("Đã đánh dấu bắn sai")
        }
        NSSound(named: "Basso")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc func markMissedIncident() {
        IncidentRecorder.shared.markUser(.missed)
        appState.setAction("Đã đánh dấu bỏ lỡ cử chỉ")
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc func togglePassiveIncidents(_ sender: NSMenuItem) {
        IncidentRecorder.shared.isEnabled.toggle()
        sender.state = IncidentRecorder.shared.isEnabled ? .on : .off
        let status = IncidentRecorder.shared.isEnabled ? "BẬT" : "TẮT"
        appState.setAction("Ghi sự cố thụ động: \(status)")
    }

    @objc func toggleUndoOnMisfire(_ sender: NSMenuItem) {
        appState.undoOnMisfire.toggle()
        sender.state = appState.undoOnMisfire ? .on : .off
        let status = appState.undoOnMisfire ? "BẬT" : "TẮT"
        appState.setAction("Hoàn tác khi bắn sai: \(status)")
    }

    @objc func toggleCalibrationWizard() {
        let wizard = CalibrationWizard.shared
        if wizard.isRunning {
            wizard.cancel()
        } else {
            wizard.onStatus = { [weak self] status in
                self?.appState.setAction(status)
            }
            wizard.onFinish = { [weak self] _ in
                self?.updateTuningMenuState()
            }
            wizard.start()
        }
    }

    @objc func setTuningSafe(_ sender: NSMenuItem) {
        GestureTuning.current = .safe
        updateTuningMenuState()
        appState.setAction("Độ nhạy: An toàn (Safe)")
    }

    @objc func setTuningBalanced(_ sender: NSMenuItem) {
        GestureTuning.current = .balanced
        updateTuningMenuState()
        appState.setAction("Độ nhạy: Cân bằng (Balanced)")
    }

    @objc func setTuningSensitive(_ sender: NSMenuItem) {
        GestureTuning.current = .sensitive
        updateTuningMenuState()
        appState.setAction("Độ nhạy: Nhạy (Sensitive)")
    }

    func updateTuningMenuState() {
        guard let item = statusItem?.menu?.item(withTitle: "Độ nhạy cử chỉ (Sensitivity)"),
              let sub = item.submenu else { return }
        let currentPreset = GestureTuning.current.preset
        for menuItem in sub.items {
            if menuItem.action == #selector(setTuningSafe) {
                menuItem.state = (currentPreset == .safe) ? .on : .off
            } else if menuItem.action == #selector(setTuningBalanced) {
                menuItem.state = (currentPreset == .balanced) ? .on : .off
            } else if menuItem.action == #selector(setTuningSensitive) {
                menuItem.state = (currentPreset == .sensitive) ? .on : .off
            }
        }
    }

    @objc func setModeAirScroll() {
        IntentArbiter.shared.forceReset()
        appState.setMode(.airScroll)
        engine.forceDischarge()
    }

    @objc func setModeMacNavigation() {
        IntentArbiter.shared.forceReset()
        appState.setMode(.macNavigation)
        scrollEngine.forceDischarge()
    }

    @objc func setModeSpatialZoom() {
        IntentArbiter.shared.forceReset()
        appState.setMode(.spatialZoom)
        engine.forceDischarge()
        scrollEngine.forceDischarge()
    }

    @objc func setModeMinimal() {
        appState.displayMode = .minimal
    }

    @objc func setModeMonochrome() {
        appState.displayMode = .monochrome
    }

    @objc func setModeCameraFeed() {
        appState.displayMode = .cameraFeed
    }
}
