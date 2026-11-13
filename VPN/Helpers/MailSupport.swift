import UIKit

@MainActor
enum MailSupport {
    static func open(completion: @escaping (AppAlertModel?) -> Void) {
        let email = AppConstants.Foundation.email
        guard !email.isEmpty, let url = URL(string: "mailto:\(email)") else {
            completion(unavailableAlert(email: email))
            return
        }
        UIApplication.shared.open(url) { success in
            DispatchQueue.main.async {
                completion(success ? nil : unavailableAlert(email: email))
            }
        }
    }

    static func unavailableAlert(email: String) -> AppAlertModel {
        let message: LocalizedStringResource
        if email.isEmpty {
            message = "No mail app installed. Install a mail app to contact us."
        } else {
            message = "No mail app installed. Install a mail app or contact us by email: [\(email)](mailto:\(email))"
        }
        return AppAlertModel(
            title: "Can't open Mail",
            message: message,
            kind: .info
        )
    }
}
