import SwiftUI

struct SupportView: View {
    @State private var expanded: Set<UUID> = []
    @State private var supportAlert: AppAlertModel?

    private let sections: [FAQSection] = [
        FAQSection(
            title: "GETTING STARTED",
            items: [
                FAQItem(
                    question: "How do I add my own server?",
                    answer: "Open «Own server» from the side menu and tap «+ Add new server». Pick Import File to load a plain-text or share-link file, Scan QR to capture a code, or Manual Entry to type host, port and credentials by hand. Bulk imports create a folder — every server inside it lives there together."
                ),
                FAQItem(
                    question: "Which protocols does the app support?",
                    answer: "VLESS, VMess, Trojan and Shadowsocks. Standard share-links from your provider work as-is — the tunnel is powered by Xray-core (LibXray) under the hood."
                )
            ]
        ),
        FAQSection(
            title: "PRIVACY & SECURITY",
            items: [
                FAQItem(
                    question: "What do the coloured bars next to each server mean?",
                    answer: "They show real latency in ms, measured by a TCP probe to the server's host and port. Green — under 200 ms, yellow — under 400 ms, red — over 400 ms or timeout. Bars refresh automatically when you expand a folder, or on demand via «Test Ping» in the folder menu."
                ),
                FAQItem(
                    question: "What is Kill Switch and when should I turn it on?",
                    answer: "Kill Switch tells iOS to block every network request the moment the tunnel drops. Turn it on when you don't want any app to leak your real IP during a reconnect — for example while streaming, torrenting or working on public Wi-Fi. Toggle it in Privacy Center or Settings."
                ),
                FAQItem(
                    question: "What is Encrypted DNS (DoH) and do I need it if the connection is on?",
                    answer: "DoH encrypts every domain lookup your device makes. When you pick a provider in Privacy Center → DNS Protection, iOS applies it system-wide — even for apps that don't use the tunnel connection, and even when the tunnel is off. Cloudflare Block-Malware and AdGuard variants additionally filter known malicious and ad domains."
                ),
                FAQItem(
                    question: "What does the Privacy Score number mean?",
                    answer: "It's a 0-100 breakdown of five checks: tunnel connection connected (+30), active subscription (+20), Kill Switch on (+20), custom DNS enabled (+20) and secure Wi-Fi (+10). Turn each on to reach the maximum."
                )
            ]
        ),
        FAQSection(
            title: "CONNECTION & TROUBLESHOOTING",
            items: [
                FAQItem(
                    question: "The tunnel won't connect or drops right after — what should I check?",
                    answer: "First, verify the config isn't expired on the provider side. Then try another server from the folder — public Wi-Fi in hotels, offices and airports frequently blocks tunnel protocols. Switching to cellular or a different server usually helps. If the profile itself looks broken, re-import it."
                ),
                FAQItem(
                    question: "Speed Test says «DNS leak detected». What should I do?",
                    answer: "The test compares the country of your exit-IP with the country of the DNS resolver that answers your queries. Different countries usually mean your device still uses the ISP's DNS. Enable Custom DNS in Privacy Center (Cloudflare is a good default) and re-run the test."
                ),
                FAQItem(
                    question: "Auto-Connect is on but the tunnel doesn't start.",
                    answer: "Auto-Connect uses iOS on-demand rules, which need a saved connection profile in the system. Connect manually at least once so the profile is created — from that point Auto-Connect will bring the tunnel up automatically whenever the device gets network access."
                ),
                FAQItem(
                    question: "What data do you collect about me?",
                    answer: "Nothing about your traffic, DNS lookups or connection metadata. The only data we hold is what's required for the subscription (via Apple + Apphud) and anonymous install attribution (via AppsFlyer). Full list — see Privacy Policy in Settings."
                )
            ]
        )
    ]

    var body: some View {
        contentView
            .background(
                Image("subScreenBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
            .overlay(alignment: .center) {
                if let alert = supportAlert {
                    AppAlertView(
                        model: alert,
                        onClose: { supportAlert = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: supportAlert)
    }

    // MARK: - Content
    private var contentView: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        sectionBlock(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 25)
                .padding(.bottom, 20)
            }

            contactSupportButton
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Nav bar
    private var navBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Text("FAQ")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(height: 50)
    }

    // MARK: - Section
    private func sectionBlock(_ section: FAQSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "A1A1A6"))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { pair in
                    faqRow(pair.element)
                    if pair.offset < section.items.count - 1 {
                        divider
                    }
                }
            }
        }
    }

    // MARK: - FAQ row
    private func faqRow(_ item: FAQItem) -> some View {
        let isOpen = expanded.contains(item.id)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(item.question)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "EDEDEF"))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "A1A1A6"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(item.answer)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(Color(hex: "A1A1A6"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
    }

    // MARK: - Contact support button
    private var contactSupportButton: some View {
        Button {
            MailSupport.open { alert in
                supportAlert = alert
            }
        } label: {
            Text("Contact support")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            stops: [
                                .init(color: Color(hex: "5295FF"), location: 0.0),
                                .init(color: Color(hex: "2F6BFF"), location: 0.55),
                                .init(color: Color(hex: "2459E8"), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FAQ models (local — only used here)
private struct FAQSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [FAQItem]
}

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

#Preview {
    SupportView()
}
