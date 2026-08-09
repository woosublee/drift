import AppKit

@main
enum DriftApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = DriftApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
