import BitFoundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentPeopleSheetModalPresentationState {
    var isImagePreviewPresented = false
    var isVerificationSheetPresented = false
    var legacyPrivateMediaConsentRequest: LegacyPrivateMediaConsentRequest? = nil
    var isVoiceAlertPresented = false
    var isMediaPickerPresented = false

    var hasPresentation: Bool {
        isImagePreviewPresented
            || isVerificationSheetPresented
            || legacyPrivateMediaConsentRequest != nil
            || isVoiceAlertPresented
            || isMediaPickerPresented
    }
}

struct ContentPeopleSheetView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @Environment(\.scenePhase) private var scenePhase

    @Binding var showSidebar: Bool
    @Binding var messageText: String
    @Binding var selectedMessageSender: String?
    @Binding var selectedMessageSenderID: PeerID?
    @Binding var imagePreviewURL: URL?
    @Binding var windowCountPublic: Int
    @Binding var windowCountPrivate: [PeerID: Int]
    @Binding var isAtBottomPrivate: Bool
    var isTextFieldFocused: FocusState<Bool>.Binding
    @ObservedObject var voiceRecordingVM: VoiceRecordingViewModel
    @Binding var autocompleteDebounceTimer: Timer?
    @State private var showVerifySheet = false
    @ThemedPalette private var palette

    let headerHeight: CGFloat
    let onSendMessage: () -> Void

    #if os(iOS)
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSourceType: UIImagePickerController.SourceType
    #else
    @Binding var showMacImagePicker: Bool
    #endif
    var showsCloseButton = true

    private func modalPresentationState(
        includingVoiceAlert: Bool
    ) -> ContentPeopleSheetModalPresentationState {
        #if os(iOS)
        let isMediaPickerPresented = showImagePicker
        #else
        let isMediaPickerPresented = showMacImagePicker
        #endif

        return ContentPeopleSheetModalPresentationState(
            isImagePreviewPresented: imagePreviewURL != nil,
            isVerificationSheetPresented: showVerifySheet,
            legacyPrivateMediaConsentRequest:
                conversationUIModel.legacyPrivateMediaConsentRequest,
            isVoiceAlertPresented: includingVoiceAlert && voiceRecordingVM.showAlert,
            isMediaPickerPresented: isMediaPickerPresented
        )
    }

    private var hasModalPresentation: Bool {
        modalPresentationState(includingVoiceAlert: true).hasPresentation
    }

    /// The voice alert cannot defer to itself: its own binding must keep
    /// reporting `true` while it is the presented modal.
    private var hasModalPresentationBesidesVoiceAlert: Bool {
        modalPresentationState(includingVoiceAlert: false).hasPresentation
    }

    private var bluetoothAlertBinding: Binding<Bool> {
        Binding(
            get: {
                scenePhase == .active
                    && appChromeModel.showBluetoothAlert
                    && !hasModalPresentation
            },
            set: { isPresented in
                guard !isPresented,
                      scenePhase == .active,
                      !hasModalPresentation else {
                    return
                }
                appChromeModel.showBluetoothAlert = false
            }
        )
    }

    /// Voice recording happens inside this sheet, so its error alert must
    /// present from here as well: the root copy defers whenever this sheet
    /// is up, exactly like the Bluetooth alert above. Presenting from the
    /// root instead would force-dismiss the sheet and end the conversation.
    private var voiceAlertBinding: Binding<Bool> {
        Binding(
            get: {
                scenePhase == .active
                    && voiceRecordingVM.showAlert
                    && !hasModalPresentationBesidesVoiceAlert
            },
            set: { isPresented in
                guard !isPresented,
                      scenePhase == .active,
                      !hasModalPresentationBesidesVoiceAlert else {
                    return
                }
                voiceRecordingVM.showAlert = false
            }
        )
    }

    var body: some View {
        let legacyConsentRequest = conversationUIModel.legacyPrivateMediaConsentRequest
        NavigationStack {
            Group {
                if privateConversationModel.selectedPeerID != nil {
                    #if os(iOS)
                    ContentPrivateChatSheetView(
                        showSidebar: $showSidebar,
                        messageText: $messageText,
                        selectedMessageSender: $selectedMessageSender,
                        selectedMessageSenderID: $selectedMessageSenderID,
                        imagePreviewURL: $imagePreviewURL,
                        windowCountPublic: $windowCountPublic,
                        windowCountPrivate: $windowCountPrivate,
                        isAtBottomPrivate: $isAtBottomPrivate,
                        isTextFieldFocused: isTextFieldFocused,
                        voiceRecordingVM: voiceRecordingVM,
                        autocompleteDebounceTimer: $autocompleteDebounceTimer,
                        headerHeight: headerHeight,
                        onSendMessage: onSendMessage,
                        showImagePicker: $showImagePicker,
                        imagePickerSourceType: $imagePickerSourceType
                    )
                    #else
                    ContentPrivateChatSheetView(
                        showSidebar: $showSidebar,
                        messageText: $messageText,
                        selectedMessageSender: $selectedMessageSender,
                        selectedMessageSenderID: $selectedMessageSenderID,
                        imagePreviewURL: $imagePreviewURL,
                        windowCountPublic: $windowCountPublic,
                        windowCountPrivate: $windowCountPrivate,
                        isAtBottomPrivate: $isAtBottomPrivate,
                        isTextFieldFocused: isTextFieldFocused,
                        voiceRecordingVM: voiceRecordingVM,
                        autocompleteDebounceTimer: $autocompleteDebounceTimer,
                        headerHeight: headerHeight,
                        onSendMessage: onSendMessage,
                        showMacImagePicker: $showMacImagePicker
                    )
                    #endif
                } else {
                    ContentPeopleListView(
                        showSidebar: $showSidebar,
                        showVerifySheet: $showVerifySheet,
                        showsCloseButton: showsCloseButton
                    )
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { appChromeModel.showingFingerprintFor != nil && (showSidebar || privateConversationModel.selectedPeerID != nil) },
                set: { isPresented in
                    if !isPresented {
                        appChromeModel.clearFingerprint()
                    }
                }
            )) {
                if let peerID = appChromeModel.showingFingerprintFor {
                    FingerprintView(peerID: peerID)
                        .environmentObject(verificationModel)
                }
            }
            // This sheet covers the root header where the connectivity
            // banner lives; a person sitting in the people list or a DM
            // would otherwise get no persistent signal that the radio is
            // off or tor is stalled. Mirror it here.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let issue = ConnectivityIssue.resolve(
                    bluetoothState: appChromeModel.bluetoothState,
                    torBlocked: appChromeModel.torBlocked
                ) {
                    ConnectivityStatusBanner(issue: issue)
                }
            }
        }
        .themedSheetBackground()
        .foregroundColor(palette.primary)
        .confirmationDialog(
            String(
                localized: "content.private_media.legacy_warning.title",
                defaultValue: "Send without end-to-end encryption?",
                comment: "Title warning before sending private media to an older client in a clear signed envelope"
            ),
            isPresented: Binding(
                get: { legacyConsentRequest != nil },
                set: { isPresented in
                    if !isPresented, let requestID = legacyConsentRequest?.id {
                        conversationUIModel.resolveLegacyPrivateMediaConsent(
                            requestID: requestID,
                            approved: false
                        )
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                String(
                    localized: "content.private_media.legacy_warning.send",
                    defaultValue: "send visible file",
                    comment: "Destructive confirmation action for one legacy clear private-media send"
                ),
                role: .destructive
            ) {
                if let requestID = legacyConsentRequest?.id {
                    conversationUIModel.resolveLegacyPrivateMediaConsent(
                        requestID: requestID,
                        approved: true
                    )
                }
            }
            Button("common.cancel", role: .cancel) {
                if let requestID = legacyConsentRequest?.id {
                    conversationUIModel.resolveLegacyPrivateMediaConsent(
                        requestID: requestID,
                        approved: false
                    )
                }
            }
        } message: {
            if let request = legacyConsentRequest {
                Text(
                    String(
                        format: String(
                            localized: "content.private_media.legacy_warning.message",
                            defaultValue: "%@'s client does not advertise encrypted private media. This file will be signed but not end-to-end encrypted, so mesh relays can see it. Send this file anyway?",
                            comment: "Warning explaining the confidentiality loss for one legacy private-media send; parameter is the peer name"
                        ),
                        locale: .current,
                        request.peerName
                    )
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { showImagePicker && (showSidebar || privateConversationModel.selectedPeerID != nil) },
            set: { newValue in
                if !newValue {
                    showImagePicker = false
                }
            }
        )) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                conversationUIModel.processSelectedImage(image)
            }
            .ignoresSafeArea()
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showMacImagePicker) {
            MacImagePickerView { url in
                showMacImagePicker = false
                conversationUIModel.processSelectedImage(from: url)
            }
        }
        #endif
        .alert(Text(String(localized: "voice.error.title", defaultValue: "recording error", comment: "Title of the voice recording error alert")), isPresented: voiceAlertBinding, actions: {
            Button("common.ok", role: .cancel) {}
            if voiceRecordingVM.state == .permissionDenied {
                Button("location_channels.action.open_settings") {
                    SystemSettings.microphone.open()
                }
            }
        }, message: {
            Text(voiceRecordingVM.state.alertMessage)
        })
        .alert(
            "content.alert.bluetooth_required.title",
            isPresented: bluetoothAlertBinding
        ) {
            Button("content.alert.bluetooth_required.settings") {
                // Powered-off needs the radio controls, not the privacy pane.
                (appChromeModel.bluetoothState == .poweredOff
                    ? SystemSettings.bluetoothPower
                    : SystemSettings.bluetooth).open()
            }
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(appChromeModel.bluetoothAlertMessage)
        }
    }
}

private struct ContentPeopleListView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @Environment(\.dismiss) private var dismiss
    @ThemedPalette private var palette

    @Binding var showSidebar: Bool
    @Binding var showVerifySheet: Bool
    let showsCloseButton: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(peopleSheetTitle)
                        .bitchatFont(size: 18)
                        .foregroundColor(palette.primary)
                    Spacer()
                    if case .mesh = locationChannelsModel.selectedChannel {
                        Button(action: { showVerifySheet = true }) {
                            Image(systemName: "qrcode")
                                .font(.bitchatSystem(size: 14))
                        }
                        .buttonStyle(.plain)
                        // .help maps to the accessibility *hint* on iOS, so the
                        // button still needs a spoken name.
                        .accessibilityLabel(
                            String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
                        )
                        .help(
                            String(localized: "content.help.verification", comment: "Help text for verification button")
                        )
                    }
                    if showsCloseButton {
                        SheetCloseButton {
                            withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                                dismiss()
                                showSidebar = false
                                showVerifySheet = false
                                privateConversationModel.endConversation()
                            }
                        }
                    }
                }

                // The mesh sheet titles its sections inline (#mesh / across
                // the bridge / groups) — no subtitle or count up here.
                // Location channels keep their geohash subtitle.
                if case .location(let channel) = locationChannelsModel.selectedChannel {
                    Text(verbatim: "#\(channel.geohash.lowercased())")
                        .bitchatFont(size: 12)
                        .foregroundColor(palette.locationAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .themedSurface()

            ScrollView {
                // spacing 0: every section supplies its own rhythm (header
                // top 12 / bottom 4, rows vertical 4), so inter-child spacing
                // here would make the first section's gap read differently.
                VStack(alignment: .leading, spacing: 0) {
                    if case .location = locationChannelsModel.selectedChannel {
                        GeohashPeopleList(
                            onTapPerson: {
                                showSidebar = true
                            }
                        )
                        // Direct conversations survive channel switches; the
                        // geoDM someone opened from another cell must stay
                        // reachable here too.
                        RecentChatList(
                            chats: peerListModel.recentChatRows,
                            onTapChat: { peerID in
                                peerListModel.startConversation(with: peerID)
                                showSidebar = true
                            }
                        )
                    } else {
                        PeopleSectionHeader(
                            icon: "antenna.radiowaves.left.and.right",
                            iconColor: palette.accentBlue,
                            title: "#mesh"
                        )
                        MeshPeerList(
                            onTapPeer: { peerID in
                                peerListModel.startConversation(with: peerID)
                                showSidebar = true
                            },
                            onToggleFavorite: { peerID in
                                peerListModel.toggleFavorite(peerID: peerID)
                            },
                            onShowFingerprint: { peerID in
                                appChromeModel.showFingerprint(for: peerID)
                            },
                            onToggleBlock: { peer in
                                if peer.isBlocked {
                                    conversationUIModel.unblock(peerID: peer.peerID, displayName: peer.displayName)
                                } else {
                                    conversationUIModel.block(peerID: peer.peerID, displayName: peer.displayName)
                                }
                            }
                        )
                        // People in this area but beyond radio range, and
                        // private groups: one sheet for the whole room.
                        BridgePeopleList()
                        GroupChatList(
                            groups: peerListModel.groupRows,
                            onTapGroup: { peerID in
                                peerListModel.startConversation(with: peerID)
                                showSidebar = true
                            }
                        )
                        // Conversations with people no roster above lists
                        // anymore — without this, a read DM from an offline
                        // non-favorite had no row anywhere in the UI.
                        RecentChatList(
                            chats: peerListModel.recentChatRows,
                            onTapChat: { peerID in
                                peerListModel.startConversation(with: peerID)
                                showSidebar = true
                            }
                        )
                    }
                }
                .padding(.top, 4)
                // Full width even when every row is narrow (empty mesh, no
                // groups): without this the VStack hugs its widest child and
                // the ScrollView centers it — headers and empty states
                // floated mid-screen on iPhone.
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(peerListModel.renderID)
            }
        }
        .sheet(isPresented: $showVerifySheet) {
            VerificationSheetView(isPresented: $showVerifySheet)
                .environmentObject(verificationModel)
        }
    }
}

private extension ContentPeopleListView {
    var peopleSheetTitle: String {
        String(localized: "content.header.people", comment: "Title for the people list sheet").lowercased()
    }

}

private struct ContentPrivateChatSheetView: View {
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel

    @Binding var showSidebar: Bool
    @Binding var messageText: String
    @Binding var selectedMessageSender: String?
    @Binding var selectedMessageSenderID: PeerID?
    @Binding var imagePreviewURL: URL?
    @Binding var windowCountPublic: Int
    @Binding var windowCountPrivate: [PeerID: Int]
    @Binding var isAtBottomPrivate: Bool
    var isTextFieldFocused: FocusState<Bool>.Binding
    @ObservedObject var voiceRecordingVM: VoiceRecordingViewModel
    @Binding var autocompleteDebounceTimer: Timer?
    @Environment(\.appTheme) private var theme
    @ThemedPalette private var palette

    let headerHeight: CGFloat
    let onSendMessage: () -> Void

    #if os(iOS)
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSourceType: UIImagePickerController.SourceType
    #else
    @Binding var showMacImagePicker: Bool
    #endif

    var body: some View {
        if theme.usesGlassChrome {
            iMessageBody
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        VStack(spacing: 0) {
            if let headerState = privateConversationModel.selectedHeaderState {
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                            privateConversationModel.endConversation()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.bitchatSystem(size: 12))
                            .foregroundColor(palette.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "content.accessibility.back_to_main_chat", comment: "Accessibility label for returning to main chat")
                    )

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        ContentPrivateHeaderInfoButton(
                            headerState: headerState,
                            headerHeight: headerHeight
                        )

                        if headerState.supportsFavoriteToggle {
                            Button(action: {
                                privateConversationModel.toggleFavoriteForSelectedConversation()
                            }) {
                                Image(systemName: headerState.isFavorite ? "star.fill" : "star")
                                    .font(.bitchatSystem(size: 14))
                                    .foregroundColor(headerState.isFavorite ? Color.yellow : palette.primary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle().inset(by: -6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                headerState.isFavorite
                                ? String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
                                : String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    SheetCloseButton {
                        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                            privateConversationModel.endConversation()
                            showSidebar = true
                        }
                    }
                }
                .frame(minHeight: headerHeight)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .modifier(PrivateHeaderChrome())
            }

            conversationMessageList

            Divider()
            privacyCaption
            composerView
        }
        .themedSheetBackground()
        .foregroundColor(palette.primary)
    }

    private var iMessageBody: some View {
        VStack(spacing: 0) {
            if let headerState = privateConversationModel.selectedHeaderState {
                IMessageConversationHeader(
                    headerState: headerState,
                    headerHeight: headerHeight,
                    onBack: leaveConversation
                )
            }

            conversationMessageList
                .background(IMessageChatBackdrop())

            composerView
        }
        .background(IMessageChatBackdrop())
        .foregroundColor(.white)
    }

    private var conversationMessageList: some View {
        MessageListView(
            privatePeer: privateConversationModel.selectedPeerID,
            isAtBottom: $isAtBottomPrivate,
            messageText: $messageText,
            selectedMessageSender: $selectedMessageSender,
            selectedMessageSenderID: $selectedMessageSenderID,
            imagePreviewURL: $imagePreviewURL,
            windowCountPublic: $windowCountPublic,
            windowCountPrivate: $windowCountPrivate,
            showSidebar: $showSidebar,
            isTextFieldFocused: isTextFieldFocused
        )
        .themedSurface()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep the horizontal edge gesture on the timeline so the composer
        // retains its press-and-hold voice interaction.
        .highPriorityGesture(swipeToLeaveGesture)
    }

    @ViewBuilder
    private var composerView: some View {
        #if os(iOS)
        ContentComposerView(
            messageText: $messageText,
            isTextFieldFocused: isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: onSendMessage,
            showImagePicker: $showImagePicker,
            imagePickerSourceType: $imagePickerSourceType
        )
        #else
        ContentComposerView(
            messageText: $messageText,
            isTextFieldFocused: isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: onSendMessage,
            showMacImagePicker: $showMacImagePicker
        )
        #endif
    }

    private func leaveConversation() {
        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
            privateConversationModel.endConversation()
        }
    }

    private var swipeToLeaveGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard horizontal > 80, vertical < 60 else { return }
                withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                    showSidebar = true
                    privateConversationModel.endConversation()
                }
            }
    }

    /// Persistent one-line reminder that this composer feeds a private
    /// conversation — the DM sheet otherwise renders identically to the
    /// public timeline. Claims end-to-end encryption only once the session
    /// is actually secured.
    private var privacyCaption: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.bitchatSystem(size: 9))
                // Optical centering: lock.fill's ink is bottom-heavy, so
                // geometric centering reads low next to the caption text.
                .offset(y: -1)
            Text(verbatim: privacyCaptionText)
                .bitchatFont(size: 11, weight: .medium)
        }
        .foregroundColor(Color.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        // The orange text is signature enough; a tinted band here reads as a
        // stray strip against the untinted composer chrome below it, so the
        // caption sits on the same surface as the rest of the bottom chrome.
        .themedSurface()
        .accessibilityElement(children: .combine)
    }

    private var privacyCaptionText: String {
        // Group chats are ChaCha20-Poly1305 sealed to the roster's shared key.
        if privateConversationModel.selectedPeerID?.isGroup == true {
            return String(localized: "content.private.caption_group", comment: "Caption above the group chat composer noting messages are encrypted to group members")
        }
        // Geohash DMs use BitChat's private-envelope encryption over Nostr —
        // always end-to-end encrypted,
        // even though they carry no Noise session status. Mesh DMs earn the
        // "encrypted" claim only once the Noise handshake has secured — or
        // when the peer is reachable only over Nostr, where delivery is
        // gift-wrapped end-to-end without a Noise session.
        let isGeoDM = privateConversationModel.selectedPeerID?.isGeoDM == true
        let noiseSecured: Bool = {
            switch privateConversationModel.selectedHeaderState?.encryptionStatus {
            case .noiseSecured, .noiseVerified: return true
            default: return false
            }
        }()
        let nostrTransport = privateConversationModel.selectedHeaderState?.availability == .nostrAvailable
        if isGeoDM || noiseSecured || nostrTransport {
            return String(localized: "content.private.caption_encrypted", comment: "Caption above the private chat composer once the session is end-to-end encrypted")
        }
        return String(localized: "content.private.caption", comment: "Caption above the private chat composer before encryption is established")
    }
}

/// Full-screen private conversation chrome for the glass theme. The original
/// BitChat transport remains behind this view; this is only the contact-first
/// presentation used after a peer has been selected.
private struct IMessageConversationHeader: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel

    let headerState: PrivateConversationHeaderState
    let headerHeight: CGFloat
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(localized: "content.accessibility.back_to_main_chat", comment: "Accessibility label for returning to main chat")
                )

                Spacer()

                if headerState.supportsFavoriteToggle {
                    Button(action: toggleFavorite) {
                        Image(systemName: headerState.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(headerState.isFavorite ? Color.yellow : Color.white)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        headerState.isFavorite
                        ? String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
                        : String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
                    )
                }

                Button(action: showContactDetails) {
                    Image(systemName: headerState.isGroupConversation ? "person.2.fill" : "info.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    headerState.isGroupConversation
                    ? String(localized: "content.accessibility.group_chat", comment: "Accessibility label for the group chat indicator")
                    : String(localized: "content.accessibility.private_chat_header", comment: "Accessibility label describing the private chat header")
                )

                Button(action: { appChromeModel.presentAppInfo() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(localized: "content.accessibility.settings", defaultValue: "Settings", comment: "Accessibility label for the settings button in the chat header")
                )
            }
            .padding(.horizontal, 12)
            .frame(minHeight: max(42, headerHeight))

            VStack(spacing: 5) {
                IMessageContactAvatar(name: headerState.displayName, size: 64, statusColor: statusColor)

                Text(headerState.displayName)
                    .font(.headline.weight(.semibold))
                        .foregroundColor(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.26), lineWidth: 0.7))

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color.white.opacity(0.86))
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 3)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    private func toggleFavorite() {
        privateConversationModel.toggleFavoriteForSelectedConversation()
    }

    private func showContactDetails() {
        if !headerState.isGroupConversation {
            appChromeModel.showFingerprint(for: headerState.headerPeerID)
        } else {
            appChromeModel.presentAppInfo()
        }
    }

    private var statusText: String {
        let transport: String
        switch headerState.availability {
        case .bluetoothConnected:
            transport = String(localized: "content.private.status.nearby", defaultValue: "nearby", comment: "Status for a private peer connected over Bluetooth mesh")
        case .meshReachable:
            transport = String(localized: "content.private.status.mesh", defaultValue: "mesh reachable", comment: "Status for a private peer reachable through the mesh")
        case .nostrAvailable:
            transport = String(localized: "content.private.status.internet", defaultValue: "available over relay", comment: "Status for a private peer available through the relay")
        case .offline:
            transport = String(localized: "content.private.status.offline", defaultValue: "offline", comment: "Status for an unavailable private peer")
        }

        switch headerState.encryptionStatus {
        case .noiseSecured, .noiseVerified:
            return transport + " · " + String(localized: "content.private.status.encrypted", defaultValue: "end-to-end encrypted", comment: "Private chat status when the session is encrypted")
        default:
            return transport
        }
    }

    private var statusColor: Color {
        switch headerState.availability {
        case .offline: return Color.white.opacity(0.58)
        case .nostrAvailable: return Color.purple
        default: return Color.green
        }
    }
}

private struct IMessageContactAvatar: View {
    let name: String
    let size: CGFloat
    let statusColor: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.96), Color.cyan.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Text(initials)
                        .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                        .foregroundColor(Color.blue.opacity(0.78))
                }
                .overlay(Circle().stroke(Color.white.opacity(0.86), lineWidth: 2))
                .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)

            Circle()
                .fill(statusColor)
                .frame(width: size * 0.24, height: size * 0.24)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }

    private var initials: String {
        let cleaned = name
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(2)).uppercased()
    }
}

private struct IMessageChatBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.02, green: 0.10, blue: 0.24), Color(red: 0.02, green: 0.23, blue: 0.38), Color(red: 0.02, green: 0.07, blue: 0.17)]
                    : [Color(red: 0.10, green: 0.43, blue: 0.72), Color(red: 0.22, green: 0.64, blue: 0.84), Color(red: 0.08, green: 0.31, blue: 0.60)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 26)
                .offset(x: -120, y: -180)

            Circle()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.13 : 0.2))
                .frame(width: 360, height: 360)
                .blur(radius: 34)
                .offset(x: 150, y: 180)

            IMessageWaterRibbon()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 22)
                .blur(radius: 13)
                .rotationEffect(.degrees(-18))
                .offset(y: 100)

            IMessageWaterRibbon()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15), lineWidth: 1.2)
                .rotationEffect(.degrees(-18))
                .offset(y: 100)
        }
        .ignoresSafeArea()
    }
}

private struct IMessageWaterRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX - 30, y: midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 30, y: midY),
            control1: CGPoint(x: rect.width * 0.25, y: midY - rect.height * 0.3),
            control2: CGPoint(x: rect.width * 0.7, y: midY + rect.height * 0.3)
        )
        return path
    }
}

/// Chrome for the private-chat header. Matrix keeps its orange privacy wash
/// over an opaque themed surface. Glass gets the same floating panel as the
/// main header instead: an orange wash over the backdrop gradient reads as a
/// muddy gray-beige band, and the DM signature is already carried by the
/// orange lock, caption, and composer accents.
private struct PrivateHeaderChrome: ViewModifier {
    @Environment(\.appTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.usesGlassChrome {
            content.themedChromePanel(edge: .top)
        } else {
            // Orange tint before themedSurface so it layers in front of the
            // opaque themed background rather than behind it.
            content
                .background(Color.orange.opacity(0.06))
                .themedSurface()
        }
    }
}

private struct ContentPrivateHeaderInfoButton: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @ThemedPalette private var palette

    let headerState: PrivateConversationHeaderState
    let headerHeight: CGFloat

    var body: some View {
        Button(action: {
            // A group has no single fingerprint to show.
            guard !headerState.isGroupConversation else { return }
            appChromeModel.showFingerprint(for: headerState.headerPeerID)
        }) {
            HStack(spacing: 6) {
                if headerState.isGroupConversation {
                    Image(systemName: "person.3.fill")
                        .font(.bitchatSystem(size: 14))
                        .foregroundColor(palette.primary)
                        .accessibilityLabel(String(localized: "content.accessibility.group_chat", comment: "Accessibility label for the group chat indicator"))
                } else {
                    switch headerState.availability {
                    case .bluetoothConnected:
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(palette.primary)
                            .accessibilityLabel(String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator"))
                    case .meshReachable:
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(palette.primary)
                            .accessibilityLabel(String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator"))
                    case .nostrAvailable:
                        Image(systemName: "globe")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(.purple)
                            .accessibilityLabel(String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator"))
                    case .offline:
                        // Slashed variant of the connected glyph — offline as
                        // the negation of connected, no text label (a leading
                        // one read as part of the name: "sin conexión bob").
                        // VoiceOver still says it.
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.bitchatSystem(size: 14))
                            .foregroundColor(palette.secondary)
                            .accessibilityLabel(String(localized: "mesh_peers.state.offline", comment: "State label for a peer that is not currently reachable"))
                    }
                }

                Text(headerState.displayName)
                    .bitchatFont(size: 16, weight: .medium)
                    .foregroundColor(palette.primary)
                    // Middle truncation keeps the identity suffix visible on
                    // long nicknames instead of wrapping into the fixed-height
                    // header.
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let encryptionStatus = headerState.encryptionStatus,
                   let icon = encryptionStatus.icon {
                    Image(systemName: icon)
                        .font(.bitchatSystem(size: 14))
                        // Optical centering: the lock glyphs' ink is bottom-heavy
                        // (solid body, thin shackle), so geometric centering reads
                        // ~1pt low next to the name. The seal badge is symmetric
                        // and needs no lift.
                        .offset(y: icon.hasPrefix("lock") ? -1 : 0)
                        .foregroundColor(
                            encryptionStatus == .noiseVerified || encryptionStatus == .noiseSecured
                            ? palette.primary
                            : Color.red
                        )
                        .accessibilityLabel(
                            String(
                                format: String(localized: "content.accessibility.encryption_status", comment: "Accessibility label announcing encryption status"),
                                locale: .current,
                                encryptionStatus.accessibilityDescription
                            )
                        )
                }

            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(localized: "content.accessibility.private_chat_header", comment: "Accessibility label describing the private chat header"),
                locale: .current,
                headerState.displayName
            )
        )
        .accessibilityHint(
            headerState.isGroupConversation
            ? ""
            : String(localized: "content.accessibility.view_fingerprint_hint", comment: "Accessibility hint for viewing encryption fingerprint")
        )
        .frame(minHeight: headerHeight)
    }
}
