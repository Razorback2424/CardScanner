import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PerformanceSignpost.measureLaunch("Launch.backgroundTaskRegistration") {
            BackgroundPriceRefresh.register()
        }
        PerformanceSignpost.measureLaunch("Launch.backgroundTaskScheduling") {
            BackgroundPriceRefresh.schedule()
        }
        return true
    }
}
