import AppKit
import AVFoundation

let originalLevels: [Double] = [0.42, 0.55, 0.64, 0.75, 0.53, 0.58, 0.47, 0.35, 0.30, 0.26]
let originalName = "Foco · QuietBar"
let supportFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuietBar-OpenSource", isDirectory: true)

struct Mix: Codable {
    var levels: [Double] = originalLevels
    var volume: Double = 0.5
    var width: Double = 1
    var animation: Bool = false
    var speed: Double = 1
    var dynamics: Bool = true
    var isValid: Bool {
        levels.count == 10 && levels.allSatisfy { $0.isFinite && (0...0.99).contains($0) }
        && volume.isFinite && (0...1).contains(volume)
        && width.isFinite && (0...2).contains(width)
        && speed.isFinite && [0.25, 0.5, 1, 2, 4].contains(speed)
    }
}
struct SavedMix: Codable { var name: String; var mix: Mix }
struct Storage: Codable {
    var current = Mix()
    var presets: [SavedMix] = []
    var selected = originalName
    var isValid: Bool { current.isValid && presets.allSatisfy { !$0.name.isEmpty && $0.mix.isValid } }
}

final class AudioPlayer {
    let engine = AVAudioEngine()
    let core: OpaquePointer
    var source: AVAudioSourceNode!
    var isPlaying: Bool { engine.isRunning }

    init() throws {
        guard let raw = qb_create() else { throw NSError(domain: "QuietBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível preparar a memória do áudio."]) }
        let root = Bundle.main.resourceURL!.appendingPathComponent("Audio")
        let a = ["0b", "1a", "2a", "3a", "4b", "5b", "6b", "7a", "8b", "9b"]
        let b = ["0a", "1b", "2b", "3b", "4a", "5a", "6a", "7b", "8a", "9a"]
        for i in 0..<10 {
            for side in 0..<2 {
                let path = root.appendingPathComponent((side == 0 ? a[i] : b[i]) + ".f32").path
                guard qb_load(raw, Int32(i), Int32(side), path) == 1 else {
                    qb_destroy(raw)
                    throw NSError(domain: "QuietBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Arquivo de áudio ausente ou inválido: \(path)"])
                }
            }
        }
        guard qb_prepare(raw) == 1 else { qb_destroy(raw); throw NSError(domain: "QuietBar", code: 3, userInfo: [NSLocalizedDescriptionKey: "Não foi possível preparar a reprodução."]) }
        core = raw
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        source = AVAudioSourceNode(format: format) { _, _, frameCount, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count == 2, let left = buffers[0].mData, let right = buffers[1].mData else { return -1 }
            qb_render(raw, left.assumingMemoryBound(to: Float.self), right.assumingMemoryBound(to: Float.self), frameCount)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }
    func apply(_ mix: Mix, animatedLevels: [Double]? = nil) {
        let levels = animatedLevels ?? mix.levels
        for i in 0..<10 { qb_level(core, Int32(i), levels[i]) }
        qb_master(core, mix.volume)
        qb_width(core, mix.width)
        qb_dynamics(core, mix.dynamics ? 1 : 0)
    }
    func play() throws { if !engine.isRunning { try engine.start() } }
    func pause() { engine.pause() }
    deinit { engine.stop(); qb_destroy(core) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var player: AudioPlayer?
    var state = Storage()
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var quickPopover: NSPopover!
    var quickPlayButton: NSButton!
    var quickSubtitle: NSTextField!
    var quickVolumeSlider: NSSlider!
    var quickVolumeLabel: NSTextField!
    var quickPresetPicker: NSPopUpButton!
    var quickMotionSwitch: NSSwitch!
    var quickTimerPicker: NSPopUpButton!
    var levelSliders: [NSSlider] = []
    var levelLabels: [NSTextField] = []
    var volumeSlider: NSSlider!
    var volumeLabel: NSTextField!
    var playButton: NSButton!
    var animationButton: NSButton!
    var dynamicsButton: NSButton!
    var presetPicker: NSPopUpButton!
    var speedPicker: NSPopUpButton!
    var widthPicker: NSPopUpButton!
    var timerPicker: NSPopUpButton!
    var subtitle: NSTextField!
    var animationTimer: Timer?
    var sleepTimer: Timer?
    var fadeTimer: Timer?
    var sleepDeadline: Date?
    var animationFrom = originalLevels
    var animationTo = originalLevels
    var animated = originalLevels
    var animationStep = 0
    var saveJob: DispatchWorkItem?
    var configObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadState()
        do { player = try AudioPlayer(); player?.apply(state.current) }
        catch { alert("Não foi possível abrir o áudio", error.localizedDescription) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "QuietBar — ruído pessoal")
        statusItem.button?.toolTip = "QuietBar · pausado"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        buildPanel()
        buildQuickPopover()
        syncUI()
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: player?.engine, queue: .main) { [weak self] _ in
            // A changed output device can stop the engine. Reflect its real state.
            self?.refreshTransport()
        }
        // Launch quietly in the menu bar. The full window opens on request.
    }

    func loadState() {
        let url = supportFolder.appendingPathComponent("state.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Storage.self, from: data), saved.isValid { state = saved }
    }
    func persist(immediate: Bool = false) {
        saveJob?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(self.state).write(to: supportFolder.appendingPathComponent("state.json"), options: .atomic)
            } catch { self.alert("Não foi possível salvar", error.localizedDescription) }
        }
        saveJob = job
        if immediate { job.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: job) }
    }
    func applicationWillTerminate(_ notification: Notification) { persist(immediate: true); player?.pause() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showQuickPopover(); return true }

    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, muted: Bool = false) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = muted ? .secondaryLabelColor : .labelColor
        view.lineBreakMode = .byTruncatingTail
        return view
    }
    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
    }
    func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = spacing; stack.alignment = .centerY; return stack
    }
    func flexible() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
    func section(_ text: String) -> NSTextField { label(text, size: 11, weight: .semibold, muted: true) }
    func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

    func symbol(_ name: String, size: CGFloat = 16) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        let v = NSImageView(image: image)
        v.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        v.contentTintColor = .secondaryLabelColor
        v.widthAnchor.constraint(equalToConstant: size + 4).isActive = true
        v.heightAnchor.constraint(equalToConstant: size + 4).isActive = true
        return v
    }

    func buildQuickPopover() {
        let size = NSSize(width: 340, height: 286)
        let root: NSView
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.bounds)
            glass.style = .regular
            glass.cornerRadius = 24
            glass.contentView = content
            root = glass
        } else {
            let material = NSVisualEffectView(frame: content.bounds)
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.addSubview(content)
            root = material
        }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let heading = NSStackView()
        heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 3
        heading.addArrangedSubview(label("QuietBar", size: 18, weight: .semibold))
        quickSubtitle = label("Pausado · áudio local", size: 11, muted: true)
        heading.addArrangedSubview(quickSubtitle)
        let wave = symbol("waveform", size: 25)
        wave.contentTintColor = .controlAccentColor
        add(row([wave, heading, flexible()], spacing: 12))

        quickPlayButton = button("Reproduzir", #selector(togglePlayback))
        quickPlayButton.imagePosition = .imageLeading
        quickPlayButton.controlSize = .large
        quickPlayButton.bezelColor = .controlAccentColor
        quickPlayButton.keyEquivalent = " "
        quickPlayButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        quickPlayButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 146).isActive = true
        quickMotionSwitch = NSSwitch()
        quickMotionSwitch.target = self
        quickMotionSwitch.action = #selector(quickMotionChanged)
        quickMotionSwitch.setAccessibilityLabel("Movimento suave")
        add(row([quickPlayButton, flexible(), label("Movimento", size: 11, muted: true), quickMotionSwitch]))

        quickVolumeSlider = NSSlider(value: state.current.volume, minValue: 0, maxValue: 1, target: self, action: #selector(quickVolumeChanged))
        quickVolumeSlider.isContinuous = true
        quickVolumeSlider.setAccessibilityLabel("Volume do painel suspenso")
        quickVolumeLabel = label("50%", size: 12, weight: .medium)
        quickVolumeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        quickVolumeLabel.alignment = .right
        quickVolumeLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        add(row([symbol("speaker.wave.2.fill", size: 14), quickVolumeSlider, quickVolumeLabel], spacing: 10))
        add(separator())

        let presets = NSStackView()
        presets.orientation = .vertical; presets.alignment = .leading; presets.spacing = 6
        let caption = section("PRESET")
        presets.addArrangedSubview(caption)
        quickPresetPicker = NSPopUpButton()
        quickPresetPicker.controlSize = .large
        quickPresetPicker.target = self; quickPresetPicker.action = #selector(quickPresetChanged)
        quickPresetPicker.setAccessibilityLabel("Preset do painel suspenso")
        presets.addArrangedSubview(quickPresetPicker)
        quickPresetPicker.widthAnchor.constraint(equalTo: presets.widthAnchor).isActive = true
        add(presets)

        quickTimerPicker = NSPopUpButton()
        quickTimerPicker.controlSize = .small
        quickTimerPicker.addItems(withTitles: ["Sem timer", "15 min", "30 min", "60 min", "90 min"])
        quickTimerPicker.target = self; quickTimerPicker.action = #selector(quickTimerChanged)
        quickTimerPicker.setAccessibilityLabel("Timer do painel suspenso")
        let open = button("Abrir controles", #selector(showPanel))
        open.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
        open.imagePosition = .imageTrailing
        open.setAccessibilityLabel("Abrir todos os controles")
        add(row([quickTimerPicker, flexible(), open]))

        let controller = NSViewController()
        controller.view = root
        quickPopover = NSPopover()
        quickPopover.contentViewController = controller
        quickPopover.contentSize = size
        quickPopover.behavior = .transient
        quickPopover.animates = true
    }

    func syncQuickUI() {
        guard quickVolumeSlider != nil else { return }
        quickVolumeSlider.doubleValue = state.current.volume
        quickVolumeLabel.stringValue = "\(Int((state.current.volume * 100).rounded()))%"
        quickMotionSwitch.state = state.current.animation ? .on : .off
        let titles = [originalName] + state.presets.map(\.name)
        if quickPresetPicker.itemTitles != titles {
            quickPresetPicker.removeAllItems()
            quickPresetPicker.addItems(withTitles: titles)
        }
        if titles.contains(state.selected) { quickPresetPicker.selectItem(withTitle: state.selected) }
        refreshQuickTransport()
    }

    func refreshQuickTransport() {
        guard quickPlayButton != nil else { return }
        let playing = player?.isPlaying == true
        quickPlayButton.title = playing ? "Pausar" : "Reproduzir"
        quickPlayButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        if let deadline = sleepDeadline {
            quickSubtitle.stringValue = "Pausa às " + DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short)
        } else {
            quickSubtitle.stringValue = playing ? "Tocando · áudio local" : "Pausado · áudio local"
        }
        if let timerPicker { quickTimerPicker.selectItem(at: timerPicker.indexOfSelectedItem) }
    }

    @objc func quickVolumeChanged() {
        state.current.volume = quickVolumeSlider.doubleValue
        volumeSlider.doubleValue = state.current.volume
        volumeLabel.stringValue = "\(Int((state.current.volume * 100).rounded()))%"
        changed()
    }
    @objc func quickMotionChanged() {
        state.current.animation = quickMotionSwitch.state == .on
        animationButton.state = quickMotionSwitch.state
        changed(resetAnimation: true)
    }
    @objc func quickPresetChanged() {
        if let name = quickPresetPicker.titleOfSelectedItem {
            presetPicker.selectItem(withTitle: name)
            presetChanged()
        }
    }
    @objc func quickTimerChanged() {
        timerPicker.selectItem(at: quickTimerPicker.indexOfSelectedItem)
        timerChanged()
    }

    @objc func showQuickPopover() {
        guard let button = statusItem?.button else { return }
        syncQuickUI()
        NSApp.activate(ignoringOtherApps: true)
        quickPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func buildPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 740), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "QuietBar"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.delegate = self
        let content = panel.contentView!
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)])
        func add(_ v: NSView) { stack.addArrangedSubview(v); v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        let title = label("Seu espaço de foco.", size: 23, weight: .semibold)
        add(title)
        subtitle = label("Áudio local · pronto para tocar", size: 12, muted: true); add(subtitle)
        playButton = button("▶  Reproduzir", #selector(togglePlayback)); playButton.keyEquivalent = " "
        let hide = button("Ocultar janela", #selector(hidePanel))
        add(row([playButton, flexible(), hide]))
        volumeSlider = NSSlider(value: state.current.volume, minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged))
        volumeSlider.setAccessibilityLabel("Volume geral")
        volumeLabel = label("50%", size: 12, weight: .medium); volumeLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let volumeTitle = label("Volume"); volumeTitle.widthAnchor.constraint(equalToConstant: 62).isActive = true
        add(row([volumeTitle, volumeSlider, volumeLabel]))
        add(separator())
        add(section("PRESET"))
        presetPicker = NSPopUpButton(); presetPicker.target = self; presetPicker.action = #selector(presetChanged)
        add(row([presetPicker, button("Salvar…", #selector(savePreset)), button("Remover", #selector(removePreset))]))
        add(section("DEZ CAMADAS · GRAVES → AGUDOS"))
        let names = ["Subgrave", "Grave baixo", "Grave", "Grave alto", "Médio baixo", "Médio", "Médio alto", "Agudo baixo", "Agudo", "Agudo alto"]
        let colors: [NSColor] = [.systemBrown, .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemCyan, .systemBlue, .systemIndigo, .systemPurple]
        for i in 0..<10 {
            let name = label(names[i], size: 12); name.widthAnchor.constraint(equalToConstant: 88).isActive = true
            let slider = NSSlider(value: state.current.levels[i], minValue: 0, maxValue: 0.99, target: self, action: #selector(levelChanged(_:)))
            slider.tag = i; slider.isContinuous = true; slider.trackFillColor = colors[i]
            slider.setAccessibilityLabel("Camada \(i + 1): \(names[i])")
            let value = label("", size: 12, weight: .medium); value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 30).isActive = true
            levelSliders.append(slider); levelLabels.append(value)
            let r = row([name, slider, value]); r.heightAnchor.constraint(equalToConstant: 22).isActive = true; add(r)
        }
        add(separator())
        animationButton = NSButton(checkboxWithTitle: "Movimento suave", target: self, action: #selector(animationChanged))
        speedPicker = NSPopUpButton(); speedPicker.addItems(withTitles: ["¼×", "½×", "1×", "2×", "4×"]); speedPicker.target = self; speedPicker.action = #selector(speedChanged)
        add(row([animationButton, flexible(), label("Velocidade", size: 12, muted: true), speedPicker]))
        widthPicker = NSPopUpButton(); widthPicker.addItems(withTitles: ["Mono", "Estreito", "Normal", "Amplo"]); widthPicker.target = self; widthPicker.action = #selector(widthChanged)
        dynamicsButton = NSButton(checkboxWithTitle: "Compressor", target: self, action: #selector(dynamicsChanged))
        add(row([label("Estéreo", size: 12), widthPicker, flexible(), dynamicsButton]))
        timerPicker = NSPopUpButton(); timerPicker.addItems(withTitles: ["Sem timer", "15 minutos", "30 minutos", "60 minutos", "90 minutos"]); timerPicker.target = self; timerPicker.action = #selector(timerChanged)
        add(row([label("Pausar em", size: 12), timerPicker, flexible(), button("Restaurar original", #selector(restoreOriginal))]))
        add(separator())
        add(row([button("Importar…", #selector(importPreset)), button("Exportar…", #selector(exportPreset)), flexible(), button("Sair", #selector(quit))]))
        add(label("Continua tocando com a janela fechada. Sem navegador.", size: 11, muted: true))
        stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18).isActive = true
        panel.center()
    }

    func syncUI() {
        guard panel != nil else { return }
        volumeSlider.doubleValue = state.current.volume; volumeLabel.stringValue = "\(Int((state.current.volume * 100).rounded()))%"
        for i in 0..<10 { levelSliders[i].doubleValue = state.current.levels[i]; levelLabels[i].stringValue = String(format: "%02d", Int((state.current.levels[i] * 100).rounded())) }
        animationButton.state = state.current.animation ? .on : .off
        dynamicsButton.state = state.current.dynamics ? .on : .off
        speedPicker.selectItem(at: [0.25,0.5,1,2,4].firstIndex(of: state.current.speed) ?? 2)
        widthPicker.selectItem(at: [0.0,0.5,1,2].firstIndex(of: state.current.width) ?? 2)
        presetPicker.removeAllItems(); presetPicker.addItem(withTitle: originalName)
        presetPicker.addItems(withTitles: state.presets.map(\.name))
        if presetPicker.itemTitles.contains(state.selected) { presetPicker.selectItem(withTitle: state.selected) }
        refreshTransport()
        syncQuickUI()
    }
    func refreshTransport() {
        let playing = player?.isPlaying == true
        playButton?.title = playing ? "Ⅱ  Pausar" : "▶  Reproduzir"
        let timerText = sleepDeadline.map { " · pausa às " + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
        subtitle?.stringValue = (playing ? "Tocando offline" : "Pausado · áudio local") + timerText
        statusItem?.button?.toolTip = playing ? "QuietBar · tocando" : "QuietBar · pausado"
        statusItem?.button?.image = NSImage(systemSymbolName: playing ? "waveform.circle.fill" : "waveform", accessibilityDescription: "QuietBar")
        if !playing { animationTimer?.invalidate(); animationTimer = nil }
        refreshQuickTransport()
    }
    func changed(resetAnimation: Bool = false) {
        cancelFade()
        if resetAnimation { restartAnimation() }
        if !state.current.animation { player?.apply(state.current) }
        else { player?.apply(state.current, animatedLevels: animated) }
        persist()
        syncQuickUI()
    }
    @objc func togglePlayback() {
        guard let player else { alert("Áudio indisponível", "Feche e abra o QuietBar para tentar novamente."); return }
        if player.isPlaying { player.pause(); animationTimer?.invalidate(); animationTimer = nil }
        else {
            do { player.apply(state.current); try player.play(); restartAnimation() }
            catch { alert("Não foi possível reproduzir", error.localizedDescription) }
        }
        refreshTransport()
    }
    @objc func levelChanged(_ sender: NSSlider) {
        state.current.levels[sender.tag] = (sender.doubleValue * 1000).rounded()/1000
        levelLabels[sender.tag].stringValue = String(format: "%02d", Int((sender.doubleValue * 100).rounded()))
        changed(resetAnimation: true)
    }
    @objc func volumeChanged() { state.current.volume = volumeSlider.doubleValue; volumeLabel.stringValue = "\(Int((state.current.volume*100).rounded()))%"; changed() }
    @objc func widthChanged() { state.current.width = [0,0.5,1,2][widthPicker.indexOfSelectedItem]; changed() }
    @objc func dynamicsChanged() { state.current.dynamics = dynamicsButton.state == .on; changed() }
    @objc func animationChanged() { state.current.animation = animationButton.state == .on; changed(resetAnimation: true) }
    @objc func speedChanged() { state.current.speed = [0.25,0.5,1,2,4][speedPicker.indexOfSelectedItem]; changed(resetAnimation: true) }

    func restartAnimation() {
        animationTimer?.invalidate(); animationTimer = nil
        animationStep = 0; animated = state.current.levels; animationFrom = animated
        guard state.current.animation, player?.isPlaying == true else { player?.apply(state.current); return }
        drawTarget()
        let timer = Timer(timeInterval: 0.64/state.current.speed, repeats: true) { [weak self] _ in self?.tickAnimation() }
        RunLoop.main.add(timer, forMode: .common); animationTimer = timer
    }
    func drawTarget() { animationTo = state.current.levels.map { Double.random(in: ($0*0.5)...min($0*1.25,0.99)) } }
    func tickAnimation() {
        if animationStep == 0 { animationFrom = animated; drawTarget() }
        for i in 0..<10 { animated[i] = animationFrom[i] + Double(animationStep)*(animationTo[i]-animationFrom[i])/50 }
        player?.apply(state.current, animatedLevels: animated)
        animationStep += 1; if animationStep == 51 { animationStep = 0 }
    }
    @objc func presetChanged() {
        guard let name = presetPicker.titleOfSelectedItem else { return }
        state.current = name == originalName ? Mix() : (state.presets.first { $0.name == name }?.mix ?? Mix())
        state.selected = name; changed(resetAnimation: true); syncUI()
    }
    @objc func restoreOriginal() { state.current = Mix(); state.selected = originalName; changed(resetAnimation: true); syncUI() }
    @objc func savePreset() {
        guard let enteredName = prompt("Salvar preset", "Dê um nome à mistura atual.", initial: state.selected == originalName ? "Meu foco" : state.selected) else { return }
        let name = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != originalName else { alert("Escolha outro nome", "O preset original é preservado para você poder restaurá-lo."); return }
        if let index = state.presets.firstIndex(where: { $0.name == name }) {
            guard confirm("Substituir “\(name)”?", "A mistura atual substituirá o preset salvo.") else { return }
            state.presets[index].mix = state.current
        } else { state.presets.append(SavedMix(name: name, mix: state.current)) }
        state.selected = name; persist(immediate: true); syncUI()
    }
    @objc func removePreset() {
        guard let name = presetPicker.titleOfSelectedItem, name != originalName else { return }
        guard confirm("Remover “\(name)”?", "A mistura em reprodução será mantida. O preset original continua disponível.") else { return }
        state.presets.removeAll { $0.name == name }; state.selected = originalName; persist(immediate: true); syncUI()
    }
    @objc func importPreset() {
        let chooser = NSAlert(); chooser.messageText = "Importar preset"; chooser.informativeText = "Carregue um preset QuietBar ou cole um link personalizado do myNoise."
        chooser.addButton(withTitle: "Arquivo JSON"); chooser.addButton(withTitle: "Link myNoise"); chooser.addButton(withTitle: "Cancelar")
        let result = chooser.runModal()
        do {
            if result == .alertFirstButtonReturn {
                let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let data = try Data(contentsOf: url)
                guard data.count < 1_000_000 else { throw failure("O arquivo é muito grande para um preset.") }
                let saved = try JSONDecoder().decode(SavedMix.self, from: data)
                guard saved.mix.isValid, !saved.name.isEmpty else { throw failure("O preset contém valores inválidos.") }
                applyImported(saved)
            } else if result.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 1 {
                guard let text = prompt("Importar link myNoise", "Importa apenas os ajustes de White Noise & Co. O áudio do QuietBar é próprio e soa diferente.", initial: "") else { return }
                guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["mynoise.net","www.mynoise.net"].contains(parts.host ?? ""), parts.path == "/NoiseMachines/whiteNoiseGenerator.php" else { throw failure("Use um link do gerador White Noise & Co.") }
                let query = parts.queryItems ?? []
                guard let code = query.first(where: { $0.name == "l" })?.value, code.count == 20, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw failure("O link precisa conter os dez níveis no parâmetro l.") }
                var mix = Mix(); let chars = Array(code)
                mix.levels = stride(from: 0, to: 20, by: 2).map { Double(String(chars[$0...($0+1)]))! / 100 }
                if let mode = query.first(where: { $0.name == "am" })?.value, mode != "s" { throw failure("Este app implementa o movimento Soft (am=s).") }
                let supported = Set(["l","a","am","astart","title","c"])
                // Old shared links sometimes contain an unescaped '&' in the title,
                // e.g. title=White%20Noise%20&%20Co. A valueless fragment is harmless.
                if query.contains(where: { !supported.contains($0.name) && $0.value != nil }) { throw failure("Este link tem ajustes adicionais que o importador não reproduz. Use níveis e modo Soft.") }
                if let a = query.first(where: { $0.name == "a" })?.value {
                    guard let speed = Double(a) else { throw failure("A velocidade do link é inválida.") }
                    mix.speed = speed
                }
                mix.animation = query.first(where: { $0.name == "astart" })?.value == "1"
                guard mix.isValid else { throw failure("Os níveis ou a velocidade do link não são suportados.") }
                applyImported(SavedMix(name: "Importado myNoise", mix: mix))
            }
        } catch { alert("Não foi possível importar", error.localizedDescription) }
    }
    func applyImported(_ saved: SavedMix) {
        // Import changes the current mix; it never overwrites a named preset implicitly.
        state.current = saved.mix; changed(resetAnimation: true); syncUI()
        subtitle.stringValue = "Preset importado · clique em Salvar para nomear"
    }
    @objc func exportPreset() {
        let dialog = NSSavePanel(); dialog.nameFieldStringValue = "QuietBar-preset.json"
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(SavedMix(name: state.selected, mix: state.current)).write(to: url, options: .atomic)
        } catch { alert("Não foi possível exportar", error.localizedDescription) }
    }
    @objc func timerChanged() {
        sleepTimer?.invalidate(); sleepTimer = nil; cancelFade(); sleepDeadline = nil
        let minutes = [0,15,30,60,90][timerPicker.indexOfSelectedItem]
        if minutes > 0 {
            sleepDeadline = Date().addingTimeInterval(Double(minutes*60))
            let timer = Timer(timeInterval: Double(minutes*60), repeats: false) { [weak self] _ in self?.beginFade() }
            RunLoop.main.add(timer, forMode: .common); sleepTimer = timer
        }
        refreshTransport()
    }
    func beginFade() {
        animationTimer?.invalidate(); animationTimer = nil; sleepDeadline = nil
        let initial = state.current.volume
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, let player = self.player else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 3)
            qb_master(player.core, initial * max(0, 1 - progress))
            if progress >= 1 { timer.invalidate(); self.fadeTimer = nil; player.pause(); player.apply(self.state.current); self.timerPicker.selectItem(at: 0); self.refreshTransport() }
        }
        RunLoop.main.add(timer, forMode: .common); fadeTimer = timer
    }
    func cancelFade() { if fadeTimer != nil { fadeTimer?.invalidate(); fadeTimer = nil; player?.apply(state.current) } }

    @objc func statusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (name,action) in [("Abrir QuietBar",#selector(showPanel)),(player?.isPlaying == true ? "Pausar" : "Reproduzir",#selector(togglePlayback)),("Sair",#selector(quit))] {
                let item = NSMenuItem(title: name, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else if quickPopover.isShown { quickPopover.performClose(nil) } else { showQuickPopover() }
    }
    @objc func showPanel() { quickPopover?.performClose(nil); NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
    @objc func hidePanel() { panel.orderOut(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    func alert(_ title: String, _ message: String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal() }
    func failure(_ text: String) -> NSError { NSError(domain: "QuietBar", code: 10, userInfo: [NSLocalizedDescriptionKey: text]) }
    func confirm(_ title: String, _ message: String) -> Bool { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.addButton(withTitle: "Confirmar"); a.addButton(withTitle: "Cancelar"); return a.runModal() == .alertFirstButtonReturn }
    func prompt(_ title: String, _ message: String, initial: String) -> String? {
        let a = NSAlert(); a.messageText = title; a.informativeText = message
        let input = NSTextField(string: initial); input.frame = NSRect(x: 0, y: 0, width: 350, height: 24); a.accessoryView = input
        a.addButton(withTitle: "Confirmar"); a.addButton(withTitle: "Cancelar"); a.window.initialFirstResponder = input
        return a.runModal() == .alertFirstButtonReturn ? input.stringValue : nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
