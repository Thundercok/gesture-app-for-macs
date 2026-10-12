import AppKit

extension AppDelegate {
    func setupKeyboardMonitoring() {
        // Global monitor
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            // Check for misfire / missed gesture markers (Ctrl + Opt + Cmd + M / N)
            let flags = event.modifierFlags
            let hasModifiers = flags.contains([.control, .option, .command])
            if hasModifiers, let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "m" {
                    IncidentRecorder.shared.markUser(.misfire)
                    DispatchQueue.main.async {
                        self.appState.setAction("Đã đánh dấu bắn sai")
                        NSSound(named: "Basso")?.play()
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                    return
                } else if chars == "n" {
                    IncidentRecorder.shared.markUser(.missed)
                    DispatchQueue.main.async {
                        self.appState.setAction("Đã đánh dấu bỏ lỡ cử chỉ")
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                    return
                }
            }

            // Labeling gestures during recording (keys '0'...'8')
            guard DatasetRecorder.shared.isRecording else { return }
            guard let characters = event.characters, let firstChar = characters.first else { return }
            if DatasetRecorder.shared.setLabelFromKey(firstChar) {
                DispatchQueue.main.async {
                    self.appState.datasetLabel = DatasetRecorder.shared.currentLabel
                    self.appState.setAction("Nhãn: [\(DatasetRecorder.shared.currentLabel)]")
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        }

        // Local monitor when window/panel has focus
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check for misfire / missed gesture markers (Ctrl + Opt + Cmd + M / N)
            let flags = event.modifierFlags
            let hasModifiers = flags.contains([.control, .option, .command])
            if hasModifiers, let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "m" {
                    IncidentRecorder.shared.markUser(.misfire)
                    DispatchQueue.main.async {
                        self.appState.setAction("Đã đánh dấu bắn sai")
                        NSSound(named: "Basso")?.play()
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                    return nil
                } else if chars == "n" {
                    IncidentRecorder.shared.markUser(.missed)
                    DispatchQueue.main.async {
                        self.appState.setAction("Đã đánh dấu bỏ lỡ cử chỉ")
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
                    return nil
                }
            }

            guard DatasetRecorder.shared.isRecording else { return event }
            guard let characters = event.characters, let firstChar = characters.first else { return event }
            if DatasetRecorder.shared.setLabelFromKey(firstChar) {
                DispatchQueue.main.async {
                    self.appState.datasetLabel = DatasetRecorder.shared.currentLabel
                    self.appState.setAction("Nhãn: [\(DatasetRecorder.shared.currentLabel)]")
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                return nil
            }
            return event
        }
    }
}
