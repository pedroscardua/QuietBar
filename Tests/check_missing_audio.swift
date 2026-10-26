let testApp = NSApplication.shared
testApp.setActivationPolicy(.prohibited)
for _ in 0..<5 {
    do { _ = try AudioPlayer(); fatalError("Expected missing audio error") }
    catch { assert((error as NSError).code == 2) }
}
print("Missing audio initialization fails cleanly.")
