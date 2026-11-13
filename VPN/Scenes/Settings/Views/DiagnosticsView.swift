import SwiftUI
import UIKit

/// Технический отчёт о состоянии приложения. Нужен для удалённого тестирования
/// через TestFlight: тестер копирует текст одной кнопкой и присылает —
/// причина сбоя видна без повторной сборки.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: String = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView(showsIndicators: false) {
                Text(report)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            copyButton
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "0B1424").ignoresSafeArea())
        .task { await refresh() }
    }

    private var navBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(hex: "5B9BFF"))

            Spacer()

            Text("Diagnostics")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "5B9BFF"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func refresh() async {
        let enabled = await LocationAuthorizer.servicesEnabled()
        report = DiagnosticsReport.makeText(servicesEnabled: enabled)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = report
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { copied = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied" : "Copy report")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(copied ? Color(hex: "34D27A") : Color(hex: "2F63D8"))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiagnosticsView()
}
