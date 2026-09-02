//
// IMessageFrontEnd.swift
// bitchat
//
// The visual shell in this file is a direct SwiftUI adaptation of the
// user's LiquidGlassMessenger front end. BitChat supplies the live peers,
// conversation state, transport status, and actions; this layer owns only
// presentation and navigation chrome.
//

import BitFoundation
import SwiftUI

struct IMessageContactListView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateInboxModel: PrivateInboxModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    @Binding var showSidebar: Bool
    @Binding var showVerifySheet: Bool
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                if filteredEntries.isEmpty {
                    IMessageContactEmptyState(
                        hasSearchText: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onSearch: beginSearch
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredEntries) { entry in
                        Button {
                            open(entry)
                        } label: {
                            IMessageContactRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.visible, edges: .bottom)
                        .listRowSeparatorTint(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(IMessageContactListBackground())
        .navigationTitle(
            String(
                localized: "content.tab.contacts",
                defaultValue: "联系人",
                comment: "Title of the contacts tab"
            )
        )
        .navigationBarTitleDisplayMode(.large)
        .modifier(
            IMessageContactSearchModifier(
                searchText: $searchText,
                isSearchPresented: $isSearchPresented
            )
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showVerifySheet = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel(
                    String(
                        localized: "content.accessibility.verification",
                        comment: "Accessibility label for the verification QR button"
                    )
                )
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    appChromeModel.presentAppInfo()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(
                    String(
                        localized: "content.accessibility.settings",
                        defaultValue: "设置",
                        comment: "Accessibility label for the contacts settings button"
                    )
                )

                Button {
                    beginSearch()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(
                    String(
                        localized: "content.accessibility.new_message",
                        defaultValue: "搜索联系人",
                        comment: "Accessibility label for starting a new private chat search"
                    )
                )
            }
        }
        .sheet(isPresented: $showVerifySheet) {
            VerificationSheetView(isPresented: $showVerifySheet)
                .environmentObject(verificationModel)
        }
        .onChange(of: privateConversationModel.selectedPeerID) { newValue in
            if newValue != nil {
                showSidebar = true
            }
        }
    }

    private var filteredEntries: [IMessageContactEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contactEntries }
        return contactEntries.filter { entry in
            entry.displayName.localizedCaseInsensitiveContains(query)
                || entry.preview.localizedCaseInsensitiveContains(query)
                || entry.status.localizedCaseInsensitiveContains(query)
        }
    }

    private var contactEntries: [IMessageContactEntry] {
        var entries: [IMessageContactEntry] = []
        var seenIDs = Set<String>()

        for peer in peerListModel.meshRows where !peer.isMe && !peer.isBlocked {
            let messages = privateInboxModel.messages(for: peer.peerID)
            let entry = IMessageContactEntry(
                id: peer.id,
                route: .peer(peer.peerID),
                displayName: peer.displayName,
                preview: messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? messages.last!.content
                    : String(
                        localized: "content.contacts.start_chat",
                        defaultValue: "点击开始私聊",
                        comment: "Preview shown for a contact without private messages"
                    ),
                timestamp: messages.last?.timestamp,
                unreadCount: peer.hasUnread ? 1 : 0,
                status: statusText(for: peer),
                statusColor: peer.isConnected ? .green : (peer.isReachable ? .blue : .secondary),
                tint: peerListModel.colorForMeshPeer(id: peer.peerID, isDark: colorScheme == .dark),
                isFavorite: peer.isFavorite,
                isGroup: false
            )
            entries.append(entry)
            seenIDs.insert(entry.id)
        }

        for group in peerListModel.groupRows {
            guard !seenIDs.contains(group.id) else { continue }
            let messages = privateInboxModel.messages(for: group.peerID)
            let entry = IMessageContactEntry(
                id: group.id,
                route: .peer(group.peerID),
                displayName: "#\(group.name)",
                preview: messages.last?.content ?? String(
                    format: String(
                        localized: "content.contacts.member_count",
                        defaultValue: "%@ 位成员",
                        comment: "Preview for a private group in the contacts list"
                    ),
                    locale: .current,
                    "\(group.memberCount)"
                ),
                timestamp: messages.last?.timestamp,
                unreadCount: group.hasUnread ? 1 : 0,
                status: String(
                    localized: "content.contacts.group",
                    defaultValue: "群聊",
                    comment: "Status label for a private group"
                ),
                statusColor: .blue,
                tint: .purple,
                isFavorite: false,
                isGroup: true
            )
            entries.append(entry)
            seenIDs.insert(entry.id)
        }

        for chat in peerListModel.recentChatRows where !seenIDs.contains(chat.id) {
            let messages = privateInboxModel.messages(for: chat.peerID)
            entries.append(
                IMessageContactEntry(
                    id: chat.id,
                    route: .peer(chat.peerID),
                    displayName: chat.displayName,
                    preview: messages.last?.content ?? String(
                        localized: "content.contacts.recent_chat",
                        defaultValue: "最近聊天",
                        comment: "Fallback preview for a recent private chat"
                    ),
                    timestamp: messages.last?.timestamp ?? chat.lastActivity,
                    unreadCount: chat.hasUnread ? 1 : 0,
                    status: String(
                        localized: "content.contacts.recent",
                        defaultValue: "最近联系",
                        comment: "Status label for a recent private chat"
                    ),
                    statusColor: .secondary,
                    tint: .blue,
                    isFavorite: false,
                    isGroup: false
                )
            )
        }

        // Geohash identities are still reachable from the same contact-first
        // screen. They use their existing Nostr route; no transport changes.
        for person in peerListModel.geohashPeople where !person.isMe && !person.isBlocked {
            let id = "geo:\(person.id)"
            guard !seenIDs.contains(id) else { continue }
            entries.append(
                IMessageContactEntry(
                    id: id,
                    route: .geohash(person.id),
                    displayName: person.displayName,
                    preview: String(
                        localized: "content.contacts.location_contact",
                        defaultValue: "位置联系人",
                        comment: "Preview for a contact discovered in a geohash channel"
                    ),
                    timestamp: nil,
                    unreadCount: 0,
                    status: person.isTeleported
                        ? String(
                            localized: "content.contacts.relayed",
                            defaultValue: "通过中继可达",
                            comment: "Status for a geohash contact reachable through a relay"
                        )
                        : String(
                            localized: "content.contacts.location",
                            defaultValue: "附近联系人",
                            comment: "Status for a contact discovered near the current location channel"
                        ),
                    statusColor: person.isTeleported ? .purple : .green,
                    tint: peerListModel.colorForGeohashPerson(id: person.id, isDark: colorScheme == .dark),
                    isFavorite: false,
                    isGroup: false
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            if lhs.unreadCount != rhs.unreadCount { return lhs.unreadCount > rhs.unreadCount }
            if let leftDate = lhs.timestamp, let rightDate = rhs.timestamp, leftDate != rightDate {
                return leftDate > rightDate
            }
            if lhs.timestamp != nil { return true }
            if rhs.timestamp != nil { return false }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func statusText(for peer: MeshPeerRow) -> String {
        if peer.isConnected {
            return String(
                localized: "content.contacts.bluetooth_nearby",
                defaultValue: "蓝牙附近",
                comment: "Status for a contact currently connected over Bluetooth mesh"
            )
        }
        if peer.isReachable {
            return String(
                localized: "content.contacts.mesh_reachable",
                defaultValue: "Mesh 可达",
                comment: "Status for a contact reachable through the mesh"
            )
        }
        if peer.isMutualFavorite {
            return String(
                localized: "content.contacts.relay_available",
                defaultValue: "中继可达",
                comment: "Status for a contact available through the relay"
            )
        }
        return String(
            localized: "content.contacts.offline",
            defaultValue: "不在线",
            comment: "Status for a contact that is not currently reachable"
        )
    }

    private func open(_ entry: IMessageContactEntry) {
        switch entry.route {
        case .peer(let peerID):
            peerListModel.startConversation(with: peerID)
        case .geohash(let publicKey):
            peerListModel.openGeohashDirectMessage(with: publicKey)
        }
        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
            showSidebar = true
        }
    }

    private func beginSearch() {
        searchText = ""
        if #available(iOS 17.0, *) {
            isSearchPresented = true
        }
    }
}

private struct IMessageContactSearchModifier: ViewModifier {
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: searchPrompt
            )
        } else {
            content.searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: searchPrompt
            )
        }
    }

    private var searchPrompt: Text {
        Text(
            String(
                localized: "content.contacts.search",
                defaultValue: "搜索联系人或聊天",
                comment: "Search prompt for the iMessage-style contacts list"
            )
        )
    }
}

private struct IMessageContactEntry: Identifiable {
    enum Route {
        case peer(PeerID)
        case geohash(String)
    }

    let id: String
    let route: Route
    let displayName: String
    let preview: String
    let timestamp: Date?
    let unreadCount: Int
    let status: String
    let statusColor: Color
    let tint: Color
    let isFavorite: Bool
    let isGroup: Bool
}

private struct IMessageContactRow: View {
    let entry: IMessageContactEntry

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            IMessageFrontEndAvatar(
                name: entry.displayName,
                tint: entry.tint,
                size: 48,
                statusColor: entry.statusColor
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if entry.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.preview)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let timestamp = entry.timestamp {
                    Text(Self.relativeFormatter.localizedString(for: timestamp, relativeTo: Date()))
                        .font(.system(size: 12))
                        .foregroundStyle(entry.unreadCount > 0 ? Color.blue : Color.secondary)
                        .lineLimit(1)
                } else {
                    Text(entry.status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if entry.unreadCount > 0 {
                    Text("\(entry.unreadCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.red, in: Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.displayName + ", " + entry.preview + (entry.unreadCount > 0 ? ", 未读" : "")
        )
        .accessibilityHint(
            String(
                localized: "content.contacts.open_hint",
                defaultValue: "打开私聊",
                comment: "Accessibility hint for opening a contact's private chat"
            )
        )
    }
}

private struct IMessageContactEmptyState: View {
    let hasSearchText: Bool
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 90)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text(
                hasSearchText
                    ? String(
                        localized: "content.contacts.no_results",
                        defaultValue: "没有找到联系人",
                        comment: "Empty state when contact search returns no result"
                    )
                    : String(
                        localized: "content.contacts.empty",
                        defaultValue: "暂时没有可用联系人",
                        comment: "Empty state when no live contact is available"
                    )
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)

            Button(action: onSearch) {
                Label(
                    String(
                        localized: "content.contacts.search_action",
                        defaultValue: "搜索联系人",
                        comment: "Action in the empty contacts state that returns to the native search entry"
                    ),
                    systemImage: "magnifyingglass"
                )
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}

private struct IMessageContactListBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            colorScheme == .dark ? Color.black : Color.white
            if colorScheme == .light {
                RadialGradient(
                    colors: [Color.blue.opacity(0.06), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct IMessageReferenceChatHeader: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var privateInboxModel: PrivateInboxModel
    @Environment(\.colorScheme) private var colorScheme

    let headerState: PrivateConversationHeaderState
    let onBack: () -> Void
    let unreadCountOverride: Int?

    init(
        headerState: PrivateConversationHeaderState,
        onBack: @escaping () -> Void,
        unreadCountOverride: Int? = nil
    ) {
        self.headerState = headerState
        self.onBack = onBack
        self.unreadCountOverride = unreadCountOverride
    }

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .bold))

                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 3.5)
                                .background(Color.white.opacity(0.92), in: Capsule())
                        }
                    }
                    .foregroundStyle(foreground)
                    .frame(minWidth: 46, minHeight: 44)
                    .padding(.leading, 9)
                    .padding(.trailing, 10)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.82),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12),
                                lineWidth: 0.8
                            )
                    )
                    .imessageLiquidGlassBackground(cornerRadius: 22, interactive: true)
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 14, y: 8)
                .accessibilityLabel(
                    String(
                        localized: "content.accessibility.back_to_contacts",
                        defaultValue: "返回联系人",
                        comment: "Accessibility label for returning to the contacts list"
                    )
                )

                Spacer()

                Menu {
                    if headerState.supportsFavoriteToggle {
                        Button {
                            privateConversationModel.toggleFavoriteForSelectedConversation()
                        } label: {
                            Label(
                                headerState.isFavorite ? "取消置顶" : "置顶联系人",
                                systemImage: headerState.isFavorite ? "pin.slash" : "pin"
                            )
                        }
                    }

                    if !headerState.isGroupConversation {
                        Button {
                            appChromeModel.showFingerprint(for: headerState.headerPeerID)
                        } label: {
                            Label("验证联系人", systemImage: "checkmark.seal")
                        }
                    }

                    Button {
                        appChromeModel.presentAppInfo()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(foreground.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(
                            colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.78),
                            in: Circle()
                        )
                        .overlay(
                            Circle().stroke(
                                colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1),
                                lineWidth: 0.8
                            )
                        )
                        .imessageLiquidGlassBackground(cornerRadius: 22, interactive: true)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(
                    String(
                        localized: "content.accessibility.chat_actions",
                        defaultValue: "聊天操作",
                        comment: "Accessibility label for the private chat actions menu"
                    )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 14, y: 8)
            }
            .padding(.horizontal, 16)

            VStack(spacing: -3) {
                IMessageFrontEndAvatar(
                    name: headerState.displayName,
                    tint: headerState.isGroupConversation ? .purple : .blue,
                    size: 44,
                    statusColor: statusColor
                )
                .overlay(
                    Circle().stroke(
                        colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.12),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 16, y: 8)

                Text(headerState.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 7)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.82),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.12),
                            lineWidth: 0.8
                        )
                    )
                    .imessageLiquidGlassBackground(cornerRadius: 17)
            }
            .frame(maxWidth: 210)
            .offset(y: 6)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 92, alignment: .top)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black.opacity(0.52), Color.black.opacity(0.18), .clear]
                    : [Color.white.opacity(0.88), Color.white.opacity(0.45), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var unreadCount: Int {
        unreadCountOverride
            ?? (privateInboxModel.unreadPeerIDs.contains(headerState.conversationPeerID) ? 1 : 0)
    }

    private var statusColor: Color {
        switch headerState.availability {
        case .offline:
            return .secondary
        case .nostrAvailable:
            return .purple
        default:
            return .green
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.30) : Color.black.opacity(0.72)
    }
}

struct IMessageReferenceChatBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.07, blue: 0.11),
                        Color(red: 0.03, green: 0.17, blue: 0.25),
                        Color(red: 0.01, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                IMessageReferenceWavePattern()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.1)
                    .blur(radius: 0.6)
                IMessageReferenceWavePattern(phase: 0.38, amplitude: 18)
                    .stroke(Color(red: 0.22, green: 0.70, blue: 0.86).opacity(0.18), lineWidth: 1.2)
                    .blur(radius: 1.4)
            } else {
                Color.white
                RadialGradient(
                    colors: [Color.blue.opacity(0.06), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 580
                )
            }

            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black.opacity(0.12), Color.black.opacity(0.06), Color.black.opacity(0.4)]
                    : [Color.clear, Color.clear, Color.black.opacity(0.025)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct IMessageLiquidGlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
            )
    }
}

extension View {
    func imessageLiquidGlassBackground(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(
            IMessageLiquidGlassBackgroundModifier(
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}

private struct IMessageReferenceWavePattern: Shape {
    var phase: CGFloat = 0
    var amplitude: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = stride(from: rect.minY - 40, through: rect.maxY + 80, by: 34)

        for (index, y) in rows.enumerated() {
            let rowPhase = phase * rect.width + CGFloat(index % 5) * 17
            path.move(to: CGPoint(x: rect.minX - 24, y: y))
            var x = rect.minX - 24
            while x <= rect.maxX + 24 {
                let relative = (x + rowPhase) / 34
                let offset = sin(relative) * amplitude + sin(relative * 0.43) * (amplitude * 0.54)
                path.addLine(to: CGPoint(x: x, y: y + offset))
                x += 9
            }
        }
        return path
    }
}

private struct IMessageFrontEndAvatar: View {
    let name: String
    let tint: Color
    let size: CGFloat
    let statusColor: Color?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.96), tint.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                )

            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: max(9, size * 0.22), height: max(9, size * 0.22))
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }

    private var initials: String {
        let cleaned = name
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        if parts.count > 1 {
            return String(parts.prefix(2).compactMap(\.first)).uppercased()
        }
        return String(cleaned.prefix(2)).uppercased()
    }
}

#if DEBUG && os(iOS)
/// Screenshot-only showcase for a simulator without a real mesh peer. It is
/// deliberately behind a launch argument and never touches ConversationStore,
/// BLE, Noise, or the live private-chat models.
struct IMessageFrontEndPreviewChatView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var privateInboxModel: PrivateInboxModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private let previewPeerID = PeerID(str: "0011223344556677")

    private var previewHeader: PrivateConversationHeaderState {
        PrivateConversationHeaderState(
            conversationPeerID: previewPeerID,
            headerPeerID: previewPeerID,
            displayName: "CX",
            availability: .bluetoothConnected,
            isFavorite: false,
            encryptionStatus: nil
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            IMessageReferenceChatBackdrop()

            ScrollView {
                VStack(alignment: .trailing, spacing: 7) {
                    Text("今天 3:59 PM")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.48) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 6)

                    IMessagePreviewBubble(isOutgoing: false, text: "他这个验证逻辑")
                    IMessagePreviewBubble(isOutgoing: true, text: "我之前的内购退号不影响")
                    IMessagePreviewBubble(isOutgoing: true, text: "消息会保持端到端加密。")

                    Text("已读 10:59 AM")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.62) : .secondary)
                        .padding(.trailing, 8)
                        .padding(.top, -2)
                }
                .padding(.horizontal, 10)
                .padding(.top, 92)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            IMessageReferenceChatHeader(
                headerState: previewHeader,
                onBack: { dismiss() },
                unreadCountOverride: 1
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IMessagePreviewComposer(draft: $draft)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(colorScheme)
    }
}

private struct IMessagePreviewComposer: View {
    @Binding var draft: String
    @Environment(\.colorScheme) private var colorScheme

    private let tools: [(String, String?)] = [
        ("快捷回复", nil),
        ("WeChat液态Glass.ai", nil),
        ("拍摄", "camera.fill"),
        ("文件", "folder.fill"),
        ("添加", "plus")
    ]

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                    HStack(spacing: 5) {
                        if let symbol = tool.1 {
                            Image(systemName: symbol)
                                .font(.system(size: index == tools.count - 1 ? 19 : 17, weight: .semibold))
                        }
                        Text(tool.0)
                            .font(.system(size: index == 1 ? 13.5 : 15.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.72))
                    .padding(.horizontal, index < 2 ? 8 : 9)
                    .frame(minHeight: 28)
                    .overlay(
                        Capsule().stroke(
                            colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.12),
                            lineWidth: 0.7
                        )
                    )
                    .imessageLiquidGlassBackground(cornerRadius: 14, interactive: true)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: 9) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.84))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle().stroke(
                                colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.12),
                                lineWidth: 0.8
                            )
                        )
                        .imessageLiquidGlassBackground(cornerRadius: 24, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加附件")

                HStack(spacing: 10) {
                    TextField(
                        "Text Message · SMS",
                        text: $draft,
                        axis: .vertical
                    )
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.86))
                    .tint(colorScheme == .dark ? .white : .blue)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(true)
                    .padding(.leading, 17)
                    .onSubmit { draft = "" }

                    Button {
                        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft = ""
                        }
                    } label: {
                        Image(systemName: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "face.smiling" : "arrow.up.circle.fill")
                            .font(.system(size: draft.isEmpty ? 25 : 29, weight: .medium))
                            .foregroundStyle(
                                draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? (colorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.72))
                                    : (colorScheme == .dark ? .white.opacity(0.88) : .blue)
                            )
                            .frame(width: 43, height: 43)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(draft.isEmpty ? "表情" : "发送")
                }
                .frame(height: 48)
                .padding(.trailing, 6)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.12),
                            lineWidth: 0.8
                        )
                )
                .imessageLiquidGlassBackground(cornerRadius: 24, interactive: true)

                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.72))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle().stroke(
                            colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.12),
                            lineWidth: 0.9
                        )
                    )
                    .imessageLiquidGlassBackground(cornerRadius: 24, interactive: true)
            }
            .frame(minHeight: 54)
        }
        .padding(.horizontal, 17)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            if colorScheme == .dark {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle().fill(Color.white.opacity(0.74))
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08))
                .frame(height: 0.6)
        }
    }
}

private struct IMessagePreviewBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    let isOutgoing: Bool
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16.5))
            .lineSpacing(1.5)
            .foregroundStyle(isOutgoing ? Color.black.opacity(0.86) : (colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.86)))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                IMessagePreviewBubbleShape(isOutgoing: isOutgoing)
                    .fill(isOutgoing ? Color(red: 0.06, green: 0.78, blue: 0.36) : (colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.76) : Color(red: 0.91, green: 0.91, blue: 0.93)))
            )
            .frame(maxWidth: 298, alignment: isOutgoing ? .trailing : .leading)
    }
}

private struct IMessagePreviewBubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 19
        var path = Path()
        let bubbleRect = rect.inset(by: UIEdgeInsets(top: 0, left: isOutgoing ? 0 : 6, bottom: 0, right: isOutgoing ? 6 : 0))
        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)

        if isOutgoing {
            path.move(to: CGPoint(x: rect.maxX - 13, y: rect.maxY - 7))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 1), control: CGPoint(x: rect.maxX - 3, y: rect.maxY - 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 9, y: rect.maxY - 15), control: CGPoint(x: rect.maxX - 3, y: rect.maxY - 13))
        } else {
            path.move(to: CGPoint(x: rect.minX + 13, y: rect.maxY - 7))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 1), control: CGPoint(x: rect.minX + 3, y: rect.maxY - 2))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 9, y: rect.maxY - 15), control: CGPoint(x: rect.minX + 3, y: rect.maxY - 13))
        }
        return path
    }
}
#endif
