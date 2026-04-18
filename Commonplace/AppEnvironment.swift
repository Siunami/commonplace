import Foundation

enum AppEnvironment {
    static let uiTestModeKey = "UI_TEST_MODE"

    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment[uiTestModeKey] == "1"
    }
}
