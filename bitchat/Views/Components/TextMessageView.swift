//
// TextMessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import BitFoundation

struct TextMessageView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.appTheme) private var theme
    @ThemedPalette private var palette
    @EnvironmentObject private var conversationUIModel: ConversationUIModel

    let message: BitchatMessage
    /// Value snapshot of the message's mutable delivery status, captured at
    /// construction. `BitchatMessage` is a reference type mutated in place by
    /// `ConversationStore`, and SwiftUI compares reference-typed view fields
    /// by identity — so a status-only change (e.g. delivered → read) on the
    /// SAME instance would otherwise compare "unchanged" and this row's body
    /// would be skipped even though the parent list re-rendered. Snapshotting
    /// the enum makes the change visible to SwiftUI's structural diff.
    private let deliveryStatus: DeliveryStatus
    private let showsBubbleTail: Bool
    @State private var expandedMessageIDs: Set<String> = []
    @State private var showDeliveryDetail = false

    init(message: BitchatMessage, showsBubbleTail: Bool = true) {
        self.message = message
        self.deliveryStatus = message.deliveryStatus
        self.showsBubbleTail = showsBubbleTail
    }

    @ViewBuilder
    var body: some View {
        if theme.usesGlassChrome {
            liquidGlassBody
                // Keep the detail caption in sync with the mutable delivery
                // state in the same way as the legacy renderer.
                .onChange(of: deliveryStatus) { _ in
                    if showDeliveryDetail {
                        showDeliveryDetail = false
                    }
                }
        } else {
            matrixBody
        }
    }

    private var matrixBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Precompute heavy token scans once per row
            let cashuLinks = message.content.extractCashuLinks()
            let lightningLinks = message.content.extractLightningLinks()
            // Baseline alignment keeps the lock and delivery glyphs on the
            // first text line; a fixed top padding left the lock's solid body
            // hanging below the line's visual center.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                let isLong = message.content.isLongForDisplay()
                let isExpanded = expandedMessageIDs.contains(message.id)
                if message.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.bitchatSystem(size: 8))
                        .foregroundColor(Color.orange.opacity(0.75))
                        .padding(.trailing, 4)
                        .accessibilityHidden(true)
                }
                if conversationUIModel.showsVerifiedSeal(for: message) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.bitchatSystem(size: 8))
                        .foregroundColor(Color.green.opacity(0.85))
                        .padding(.trailing, 4)
                        .accessibilityLabel(
                            String(localized: "content.accessibility.verified_sender", defaultValue: "Verified sender", comment: "Accessibility label for the seal next to a verified peer's name on a private message")
                        )
                }
                if message.isBridged {
                    Image(systemName: "network")
                        .font(.bitchatSystem(size: 8))
                        .foregroundColor(Color.cyan.opacity(0.75))
                        .padding(.trailing, 4)
                        .accessibilityLabel(
                            String(localized: "content.accessibility.bridged_message", defaultValue: "Arrived across a mesh bridge", comment: "Accessibility label for the glyph marking a message that arrived across a mesh bridge")
                        )
                }
                Text(conversationUIModel.formatMessage(message, colorScheme: colorScheme, theme: theme))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(isLong && !isExpanded ? TransportConfig.uiLongMessageLineLimit : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Delivery status indicator for private messages. Tappable:
                // .help() tooltips only exist on macOS, so iOS users get the
                // explanation as a caption under the row instead.
                if message.isPrivate && conversationUIModel.isSentByCurrentUser(message),
                   deliveryStatus != .notSentYet {
                    Button {
                        showDeliveryDetail.toggle()
                    } label: {
                        DeliveryStatusView(status: deliveryStatus)
                            .padding(.leading, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        String(localized: "content.accessibility.delivery_detail_hint", comment: "Accessibility hint for the delivery status glyph explaining a tap reveals details")
                    )
                }
            }

            // Failure reasons stay visible without a tap; other statuses
            // reveal on demand.
            if message.isPrivate && conversationUIModel.isSentByCurrentUser(message),
               deliveryStatus != .notSentYet {
                if case .failed = deliveryStatus {
                    Text(verbatim: deliveryStatus.bitchatDescription)
                        .bitchatFont(size: 11)
                        .foregroundColor(Color.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                } else if showDeliveryDetail {
                    Text(verbatim: deliveryStatus.bitchatDescription)
                        .bitchatFont(size: 11)
                        .foregroundColor(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            
            // Expand/Collapse for very long messages
            if message.content.isLongForDisplay() {
                let isExpanded = expandedMessageIDs.contains(message.id)
                let labelKey = isExpanded ? LocalizedStringKey("content.message.show_less") : LocalizedStringKey("content.message.show_more")
                Button(labelKey) {
                    if isExpanded { expandedMessageIDs.remove(message.id) }
                    else { expandedMessageIDs.insert(message.id) }
                }
                .bitchatFont(size: 11, weight: .medium)
                .foregroundColor(palette.accentBlue)
                .padding(.top, 4)
            }

            // Render payment chips (Lightning / Cashu) with rounded background
            if !lightningLinks.isEmpty || !cashuLinks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(lightningLinks, id: \.self) { link in
                        PaymentChipView(paymentType: .lightning(link))
                    }
                    ForEach(cashuLinks, id: \.self) { link in
                        PaymentChipView(paymentType: .cashu(link))
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 2)
            }
        }
        // Collapse the revealed caption when the status advances (e.g.
        // sending → sent → delivered) so a detail opened for one state
        // doesn't linger and silently morph into another. Guarded write:
        // under a message storm many rows change status within one frame,
        // and an unconditional state write per change trips SwiftUI's
        // "tried to update multiple times per frame" re-entrancy warning.
        .onChange(of: deliveryStatus) { _ in
            if showDeliveryDetail {
                showDeliveryDetail = false
            }
        }
    }

    @ViewBuilder
    private var liquidGlassBody: some View {
        let isFromMe = conversationUIModel.isSentByCurrentUser(message)
        let isLong = message.content.isLongForDisplay()
        let isExpanded = expandedMessageIDs.contains(message.id)
        let cashuLinks = message.content.extractCashuLinks()
        let lightningLinks = message.content.extractLightningLinks()

        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 3) {
            // Public mesh messages keep a quiet sender line. Private chats
            // read like iMessage: the conversation already identifies the
            // other person, so repeating their name wastes vertical space.
            if !isFromMe && !message.isPrivate {
                Text(message.sender)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 0) {
                if isFromMe {
                    Spacer(minLength: 42)
                }

                VStack(alignment: isFromMe ? .trailing : .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if message.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isFromMe ? Color.white.opacity(0.82) : Color.orange)
                                .accessibilityHidden(true)
                        }
                        if conversationUIModel.showsVerifiedSeal(for: message) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isFromMe ? Color.white.opacity(0.88) : Color.green)
                                .accessibilityLabel(
                                    String(localized: "content.accessibility.verified_sender", defaultValue: "Verified sender", comment: "Accessibility label for the seal next to a verified peer's name on a private message")
                                )
                        }
                        if message.isBridged {
                            Image(systemName: "network")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isFromMe ? Color.white.opacity(0.82) : Color.cyan)
                                .accessibilityLabel(
                                    String(localized: "content.accessibility.bridged_message", defaultValue: "Arrived across a mesh bridge", comment: "Accessibility label for the glyph marking a message that arrived across a mesh bridge")
                                )
                        }

                        Text(message.content)
                            .font(.body)
                            .foregroundStyle(isFromMe ? Color.white : palette.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(isLong && !isExpanded ? TransportConfig.uiLongMessageLineLimit : nil)
                            .textSelection(.enabled)
                    }

                    if isLong {
                        Button(isExpanded ? "content.message.show_less" : "content.message.show_more") {
                            if isExpanded {
                                expandedMessageIDs.remove(message.id)
                            } else {
                                expandedMessageIDs.insert(message.id)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFromMe ? Color.white.opacity(0.9) : palette.accentBlue)
                        .buttonStyle(.plain)
                    }

                    if !lightningLinks.isEmpty || !cashuLinks.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(lightningLinks, id: \.self) { link in
                                PaymentChipView(paymentType: .lightning(link))
                            }
                            ForEach(cashuLinks, id: \.self) { link in
                                PaymentChipView(paymentType: .cashu(link))
                            }
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    BTChatBubbleShape(isOutgoing: isFromMe, showsTail: showsBubbleTail)
                        .fill(isFromMe ? palette.accent : incomingBubbleColor)
                )
                .overlay(
                    BTChatBubbleShape(isOutgoing: isFromMe, showsTail: showsBubbleTail)
                        .stroke(isFromMe ? Color.white.opacity(0.14) : palette.divider.opacity(0.75), lineWidth: 0.6)
                )

                if !isFromMe {
                    Spacer(minLength: 42)
                }
            }

            if message.isPrivate && isFromMe && deliveryStatus != .notSentYet && showsBubbleTail {
                HStack(spacing: 4) {
                    if case .read(_, let readAt) = deliveryStatus {
                        Text(
                            String(
                                format: String(
                                    localized: "content.delivery.read_at",
                                    defaultValue: "Read %@",
                                    comment: "iMessage-style read receipt below the last outgoing message"
                                ),
                                locale: .current,
                                readAt.formatted(date: .omitted, time: .shortened)
                            )
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                    } else {
                        Button {
                            showDeliveryDetail.toggle()
                        } label: {
                            DeliveryStatusView(status: deliveryStatus)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            String(localized: "content.accessibility.delivery_detail_hint", comment: "Accessibility hint for the delivery status glyph explaining a tap reveals details")
                        )
                    }
                }
                .padding(.trailing, 4)
            }

            if message.isPrivate && isFromMe && deliveryStatus != .notSentYet && showsBubbleTail {
                if case .failed = deliveryStatus {
                    Text(verbatim: deliveryStatus.bitchatDescription)
                        .font(.caption)
                        .foregroundStyle(palette.alertRed)
                        .multilineTextAlignment(.trailing)
                } else if showDeliveryDetail {
                    Text(verbatim: deliveryStatus.bitchatDescription)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: String(localized: "content.accessibility.message", defaultValue: "%@ says %@", comment: "Accessibility label for a chat message, naming the sender and message content"),
                locale: .current,
                message.sender,
                message.content
            )
        )
    }

    private var incomingBubbleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.075)
    }
}

/// A compact iMessage-inspired bubble with a small directional tail. The
/// shape is intentionally kept local to BT Chat so the existing matrix
/// renderer and message semantics remain unchanged.
private struct BTChatBubbleShape: Shape {
    let isOutgoing: Bool
    let showsTail: Bool

    init(isOutgoing: Bool, showsTail: Bool = true) {
        self.isOutgoing = isOutgoing
        self.showsTail = showsTail
    }

    func path(in rect: CGRect) -> Path {
        let tailWidth: CGFloat = showsTail ? 8 : 0
        let tailHeight: CGFloat = showsTail ? 6 : 0
        let bodyRect = CGRect(
            x: isOutgoing || !showsTail ? rect.minX : rect.minX + tailWidth,
            y: rect.minY,
            width: max(0, rect.width - tailWidth),
            height: max(0, rect.height - tailHeight)
        )
        let cornerRadius: CGFloat = 18
        var path = Path(roundedRect: bodyRect, cornerRadius: cornerRadius, style: .continuous)

        if showsTail && isOutgoing {
            path.move(to: CGPoint(x: bodyRect.maxX - 18, y: bodyRect.maxY - 2))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: bodyRect.maxX - 2, y: bodyRect.maxY + 2)
            )
            path.addQuadCurve(
                to: CGPoint(x: bodyRect.maxX - 8, y: bodyRect.maxY - 10),
                control: CGPoint(x: bodyRect.maxX - 4, y: bodyRect.maxY - 3)
            )
        } else if showsTail {
            path.move(to: CGPoint(x: bodyRect.minX + 18, y: bodyRect.maxY - 2))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: bodyRect.minX + 2, y: bodyRect.maxY + 2)
            )
            path.addQuadCurve(
                to: CGPoint(x: bodyRect.minX + 8, y: bodyRect.maxY - 10),
                control: CGPoint(x: bodyRect.minX + 4, y: bodyRect.maxY - 3)
            )
        }

        return path
    }
}

// Wrapped in #if DEBUG because the preview depends on _PreviewHelpers
// (PreviewKeychainManager, BitchatMessage.preview), a development asset
// excluded from archive builds.
#if DEBUG
#Preview {
    let keychain = PreviewKeychainManager()
    let viewModel = ChatViewModel(
        keychain: keychain,
        idBridge: NostrIdentityBridge(),
        identityManager: SecureIdentityStateManager(keychain)
    )
    let privateConversationModel = PrivateConversationModel(
        chatViewModel: viewModel,
        conversations: viewModel.conversations
    )
    let conversationUIModel = ConversationUIModel(
        chatViewModel: viewModel,
        privateConversationModel: privateConversationModel,
        conversations: viewModel.conversations
    )
    
    Group {
        List {
            TextMessageView(message: .preview)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
        }
        .environment(\.colorScheme, .light)
        
        List {
            TextMessageView(message: .preview)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
        }
        .environment(\.colorScheme, .dark)
    }
    .environmentObject(conversationUIModel)
}
#endif
