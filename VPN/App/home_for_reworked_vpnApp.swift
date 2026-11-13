import SwiftUI
import ApphudSDK

@main
struct home_for_reworked_vpnApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var premium = SubscriptionService.shared

    init() {
        premium.start()
        Task { @MainActor in
            await VPNService.shared.prepare()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch premium.appState {
                case .onboarding:
                    OnboardingView()
                        .transition(.opacity)
                case .home:
                    MainTabView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: premium.appState)
            .preferredColorScheme(.dark)
            .environment(premium)
            .statusBarHidden()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppsFlyerService.shared.configure()
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Apphud.submitPushNotificationsToken(token: deviceToken, callback: nil)
        AppsFlyerService.shared.registerForUninstall(deviceToken)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo["paywall_id"] as? String,
              let paywallId = PaywallId(rawValue: raw)
        else { return }
        await MainActor.run {
            SubscriptionService.shared.showPaywall(paywallId)
        }
    }
}
