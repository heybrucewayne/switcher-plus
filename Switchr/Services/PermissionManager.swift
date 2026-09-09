import ApplicationServices
import CoreGraphics

enum PermissionManager {
    static var accessibilityGranted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func promptForAccessibility() {
        // The documented raw key avoids Swift 6's imported mutable-global diagnostic.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
