//
//  GuildChatView.swift
//  HealthBar
//
//  Created by Claude on 6/21/26.
//

import SwiftUI
import UIKit   // OCCLUSION-1 D3: keyboardWillShow/Hide notifications (UIResponder)

/// Guild chat (Guilds Prompt G3): a real-time message list with a single
/// screen-scoped listener (started on appear, removed on disappear). Pushed from
/// GuildDetailView.
///
/// In-app real-time only — there are NO push notifications (that needs server
/// infrastructure the app doesn't have); you see messages while the chat is open.
struct GuildChatView: View {

    // MARK: - Properties

    @State private var viewModel: GuildChatViewModel
    private let coordinator: AppCoordinator

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Sender whose profile sheet is open (friends only).
    @State private var profileSender: GuildMessageDTO? = nil
    /// Message pending delete confirmation.
    @State private var messageToDelete: GuildMessageDTO? = nil
    /// UGC-1c: sender pending block confirmation (Report fires directly — no pending
    /// state — mirroring FriendProfileView, where only Block confirms).
    @State private var senderToBlock: GuildMessageDTO? = nil
    /// OCCLUSION-1 D3: true while the software keyboard is up. When it is, the composer
    /// rides above the keyboard (system avoidance) and the tab bar is hidden behind the
    /// keyboard, so the bar-clearing bottom padding is dropped to avoid a dead gap.
    @State private var keyboardVisible = false

    // MARK: - Init

    init(coordinator: AppCoordinator, code: String, isOwner: Bool) {
        self.coordinator = coordinator
        self._viewModel = State(initialValue: GuildChatViewModel(
            coordinator: coordinator,
            code: code,
            isOwner: isOwner,
            myUid: coordinator.currentUserId ?? ""
        ))
    }

    private var inputBinding: Binding<String> {
        Binding(get: { viewModel.input }, set: { viewModel.input = $0 })
    }

    private var ejectedBinding: Binding<Bool> {
        Binding(get: { viewModel.wasEjected }, set: { if !$0 { viewModel.wasEjected = false } })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            tc.primaryBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                messagesScroll
                inputBar
            }
            // OCCLUSION-1 D2 (fixed-bar anatomy): this screen is pushed inside the Guilds
            // tab's NavigationStack, which the TabView's `.safeAreaInset` tab bar does NOT
            // reach — so the input bar would lay out at the true screen bottom, under the bar
            // (which then wins hit-testing → SMOKE-3 "sends resolve to the Battle slot").
            // Clear the bar with the shared token. The messages ScrollView needs no separate
            // margin: the composer now occupies the cleared space beneath it.
            // D3: while the keyboard is up, gate the padding to 0 (composer rides above the
            // keyboard; the bar sits behind it) so no dead gap opens between them.
            .padding(.bottom, keyboardVisible ? 0 : DesignSystem.Metrics.tabBarHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Chat")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert("You're no longer in this guild", isPresented: ejectedBinding) {
            Button("OK") { dismiss() }
        } message: {
            Text("This guild is no longer available to you.")
        }
        .confirmationDialog(
            "Delete Message?",
            isPresented: Binding(
                get: { messageToDelete != nil },
                set: { if !$0 { messageToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let message = messageToDelete {
                    Task { await viewModel.delete(message) }
                }
                messageToDelete = nil
            }
            Button("Cancel", role: .cancel) { messageToDelete = nil }
        } message: {
            Text("This removes the message for everyone.")
        }
        // UGC-1c: block confirmation — copy mirrored verbatim from FriendProfileView.
        .confirmationDialog(
            "Block @\(senderToBlock?.senderUsername ?? "")?",
            isPresented: Binding(
                get: { senderToBlock != nil },
                set: { if !$0 { senderToBlock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                if let message = senderToBlock {
                    Task { await viewModel.block(message) }
                }
                senderToBlock = nil
            }
            Button("Cancel", role: .cancel) { senderToBlock = nil }
        } message: {
            Text("They'll be removed from your friends, hidden from your lists, and won't be able to challenge or friend you.")
        }
        // UGC-1c: post-report confirmation — mirrors FriendProfileView's "Report submitted"
        // success feedback. Report has no pre-submit dialog (see the context menu); this
        // fires after a successful (or silently-deduped) submit.
        .alert("Report submitted", isPresented: Binding(
            get: { viewModel.reportConfirmation },
            set: { if !$0 { viewModel.reportConfirmation = false } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $profileSender) { message in
            FriendProfileView(
                coordinator: coordinator,
                friendUid: message.senderUid,
                username: message.senderUsername,
                displayName: message.senderDisplayName
            )
        }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.sm) {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .padding(.top, DesignSystem.Spacing.xxl)
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: GuildMessageDTO) -> some View {
        let isOwn = viewModel.isOwnMessage(message)
        HStack {
            if isOwn { Spacer(minLength: DesignSystem.Spacing.xl) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
                // Sender line (others only). Tappable to a profile if a friend.
                if !isOwn {
                    senderLabel(message)
                }

                Text(message.text)
                    .font(AppFont.regular(15))
                    .foregroundColor(isOwn ? .white : tc.textPrimary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isOwn ? tc.primary : tc.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isOwn ? tc.primaryDark : tc.primary.opacity(0.25), lineWidth: 1)
                    )

                Text(timeText(message.createdAt))
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
            }
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)

            if !isOwn { Spacer(minLength: DesignSystem.Spacing.xl) }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .contextMenu {
            // UGC-1c: Report / Block on others' messages (never own — no self-report/block).
            // Order is an invariant: Report Message → Block User → Delete.
            if !isOwn {
                Button {
                    Task { await viewModel.report(message) }
                } label: {
                    Label("Report Message", systemImage: "flag")
                }
                Button(role: .destructive) {
                    senderToBlock = message
                } label: {
                    Label("Block User", systemImage: "hand.raised")
                }
            }
            if viewModel.canDelete(message) {
                Button(role: .destructive) {
                    messageToDelete = message
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func senderLabel(_ message: GuildMessageDTO) -> some View {
        let name = message.senderDisplayName.isEmpty ? "@\(message.senderUsername)" : message.senderDisplayName
        if viewModel.canOpenProfile(message) {
            Button {
                profileSender = message
            } label: {
                Text(name)
                    .font(AppFont.bold(11))
                    .foregroundColor(tc.primary)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            Text(name)
                .font(AppFont.bold(11))
                .foregroundColor(tc.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)
            Text("No messages yet — say hi")
                .font(AppFont.regular(14))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            if let banner = viewModel.banner {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.danger)
                    Text(banner)
                        .font(AppFont.regular(12))
                        .foregroundColor(DesignSystem.Colors.danger)
                    Spacer()
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField("Message", text: inputBinding, axis: .vertical)
                    .font(AppFont.regular(15))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1...4)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(tc.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(tc.primary.opacity(0.3), lineWidth: 1)
                    )
                    .disabled(viewModel.wasEjected)

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: viewModel.isSending ? "hourglass" : "paperplane.fill")
                        .font(AppFont.bold(16))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(viewModel.canSend ? tc.primary : tc.primary.opacity(0.4))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.canSend)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(tc.primaryBackground)
    }

    // MARK: - Helpers

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "sending…" }
        return date.formatted(.relative(presentation: .numeric))
    }
}
