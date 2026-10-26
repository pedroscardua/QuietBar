// Linked to the actual app source, without starting its UI event loop.
// The process is prohibited from activating; state writes use an isolated folder.
let testApp = NSApplication.shared
testApp.setActivationPolicy(.prohibited)
let tester = AppDelegate()
var custom = Mix()
custom.volume = 0.37
custom.levels = [0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,0.99]
custom.width = 0.5
custom.animation = true
custom.speed = 2
assert(custom.isValid)
var invalid = custom
invalid.levels = [0.5]
assert(!invalid.isValid)
invalid = custom; invalid.volume = .infinity; assert(!invalid.isValid)
invalid = custom; invalid.levels[0] = .nan; assert(!invalid.isValid)
invalid = custom; invalid.speed = -1; assert(!invalid.isValid)
tester.state.current = custom
tester.state.selected = "Preset de teste isolado"
tester.state.presets = [SavedMix(name: tester.state.selected, mix: custom)]
tester.persist(immediate: true)
let restored = AppDelegate()
restored.loadState()
assert(restored.state.current.levels == custom.levels)
assert(restored.state.current.volume == 0.37)
assert(restored.state.presets.count == 1 && restored.state.presets[0].mix.speed == 2)
assert(restored.state.selected == tester.state.selected)
let encoder = JSONEncoder()
let decoded = try JSONDecoder().decode(SavedMix.self, from: encoder.encode(restored.state.presets[0]))
assert(decoded.mix.levels == custom.levels && decoded.mix.isValid)

// Exercise the same random targets and 50-step interpolation as the app.
tester.state.current = Mix(); tester.state.current.animation = true
var moved = false
for _ in 0..<510 {
    tester.tickAnimation()
    for i in 0..<10 {
        assert(tester.animated[i] >= originalLevels[i]*0.5 - 1e-12)
        assert(tester.animated[i] <= min(originalLevels[i]*1.25,0.99) + 1e-12)
        if abs(tester.animated[i]-originalLevels[i])>0.001 { moved = true }
    }
}
assert(moved)

// Prepare the audio graph, but never start output: this test emits no sound.
tester.player = try AudioPlayer()
tester.player?.apply(tester.state.current)
tester.timerPicker = NSPopUpButton()
tester.timerPicker.addItems(withTitles: ["Sem timer", "15", "30", "60", "90"])
for (index,seconds) in [(1,900.0),(2,1800),(3,3600),(4,5400)] {
    tester.timerPicker.selectItem(at:index)
    tester.timerChanged()
    assert(abs(tester.sleepDeadline!.timeIntervalSinceNow-seconds)<1)
    assert(abs(tester.sleepTimer!.fireDate.timeIntervalSinceNow-seconds)<1)
}
tester.timerPicker.selectItem(at:0);tester.timerChanged()
assert(tester.sleepTimer == nil && tester.sleepDeadline == nil)
tester.timerPicker.selectItem(at:1);tester.timerChanged()
let volume = tester.state.current.volume
// Fire the real registered callback; do not wait fifteen minutes to test a system timer.
tester.sleepTimer!.fire()
assert(tester.fadeTimer != nil)
let start = Date()
while Date().timeIntervalSince(start)<3.6 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
assert(tester.fadeTimer == nil)
assert(tester.timerPicker.indexOfSelectedItem == 0)
assert(tester.sleepDeadline == nil)
assert(tester.state.current.volume == volume)
assert(tester.player?.isPlaying == false)
tester.sleepTimer?.invalidate()
tester.timerPicker.selectItem(at:1);tester.timerChanged();tester.beginFade()
assert(tester.fadeTimer != nil)
tester.cancelFade();assert(tester.fadeTimer == nil)
tester.sleepTimer?.invalidate()
let result: [String:Any] = ["preset_persistence_roundtrip":true,"invalid_values_rejected":true,"animation_steps_checked":510,"timer_options_seconds":[900,1800,3600,5400],"actual_timer_callback_and_fade_completed":true,"fade_cancellation":true,"audible_output_started":false,"windows_created":false]
let report = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
try report.write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
print(String(data:report,encoding:.utf8)!)
