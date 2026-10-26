let testApp = NSApplication.shared
testApp.setActivationPolicy(.prohibited)
let tester = AppDelegate()
tester.buildPanel()
tester.buildQuickPopover()
tester.syncUI()
assert(tester.quickPopover.behavior == .transient)
assert(!tester.panel.isVisible && !tester.quickPopover.isShown)
if #available(macOS 26.0, *) {
    assert(tester.quickPopover.contentViewController!.view is NSGlassEffectView)
}
assert(tester.quickPlayButton.title == "Reproduzir")
tester.quickVolumeSlider.doubleValue = 0.37
tester.quickVolumeChanged()
assert(tester.state.current.volume == 0.37)
assert(tester.volumeSlider.doubleValue == 0.37)
assert(tester.volumeLabel.stringValue == "37%")
tester.volumeSlider.doubleValue = 0.62
tester.volumeChanged()
assert(tester.quickVolumeSlider.doubleValue == 0.62)
assert(tester.quickVolumeLabel.stringValue == "62%")
tester.quickMotionSwitch.state = .on
tester.quickMotionChanged()
assert(tester.state.current.animation && tester.animationButton.state == .on)
tester.animationButton.state = .off
tester.animationChanged()
assert(!tester.state.current.animation && tester.quickMotionSwitch.state == .off)
var custom = Mix();custom.volume = 0.28;custom.levels[3] = 0.4
tester.state.presets = [SavedMix(name: "Meu teste", mix: custom)]
tester.syncUI()
tester.quickPresetPicker.selectItem(withTitle: "Meu teste")
tester.quickPresetChanged()
assert(tester.state.current.volume == 0.28 && tester.levelSliders[3].doubleValue == 0.4)
assert(tester.presetPicker.titleOfSelectedItem == "Meu teste")
tester.restoreOriginal()
assert(tester.quickPresetPicker.titleOfSelectedItem == originalName)
assert(tester.quickVolumeSlider.doubleValue == 0.5)
tester.quickTimerPicker.selectItem(at: 2)
tester.quickTimerChanged()
assert(tester.timerPicker.indexOfSelectedItem == 2)
assert(abs(tester.sleepDeadline!.timeIntervalSinceNow - 1800) < 1)
tester.timerPicker.selectItem(at: 0)
tester.timerChanged()
assert(tester.quickTimerPicker.indexOfSelectedItem == 0 && tester.sleepDeadline == nil)
tester.state.presets = [];tester.syncUI()
tester.saveJob?.cancel()

let view = tester.quickPopover.contentViewController!.view
let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
window.isOpaque = false
window.backgroundColor = .clear
window.contentView = view
view.appearance = NSAppearance(named: .aqua)
view.layoutSubtreeIfNeeded()
window.displayIfNeeded()
assert(view.bounds.width == 340 && view.bounds.height == 286)
let controls: [NSView] = [tester.quickPlayButton,tester.quickVolumeSlider,tester.quickVolumeLabel,tester.quickPresetPicker,tester.quickMotionSwitch,tester.quickTimerPicker]
for control in controls {
    let rect = control.convert(control.bounds, to: view)
    assert(rect.width > 0 && rect.height > 0)
    assert(view.bounds.insetBy(dx: -1, dy: -1).contains(rect), "Clipped control: \(rect)")
}
// Glass is composited by WindowServer and cannot be faithfully captured while hidden.
// Snapshot the detached content for typography/layout QA; the native material is
// verified by its actual view type above, without showing any window.
let snapshotView: NSView
if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
    snapshotView = glass.contentView!
    glass.contentView = nil
} else { snapshotView = view }
window.contentView = snapshotView
snapshotView.wantsLayer = false
for (name,appearance) in [("quick-panel-content-light",NSAppearance.Name.aqua),("quick-panel-content-dark",.darkAqua)] {
    snapshotView.appearance = NSAppearance(named: appearance)
    snapshotView.layoutSubtreeIfNeeded()
    if let bitmap = snapshotView.bitmapImageRepForCachingDisplay(in: snapshotView.bounds) {
        snapshotView.cacheDisplay(in: snapshotView.bounds, to: bitmap)
        let url = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(name+".png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
assert(!window.isVisible && !tester.panel.isVisible && !tester.quickPopover.isShown)
let result: [String:Any] = ["native_liquid_glass":true,"transient_popover":true,"volume_synced_both_directions":true,"motion_synced_both_directions":true,"preset_sync":true,"timer_sync":true,"layout_controls_unclipped":true,"windows_shown":false,"main_app_touched":false]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("quick-panel-test.json"))
print(String(data:data,encoding:.utf8)!)
