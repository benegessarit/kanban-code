import SwiftUI
import AppKit

// MARK: - Duration picker dialog

struct ChannelShareDialog: View {
    @Binding var isPresented: Bool
    let channelName: String
    var onStart: (ShareDuration) -> Void
    @State private var selection: ShareDuration = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share #\(channelName) publicly")
                .font(.app(.title3, weight: .semibold))
            Text("Generates a temporary public URL anyone can open in their browser. Messages posted through the link are clearly flagged as external in the channel and in every agent's tmux session.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("How long should the link stay live?")
                    .font(.app(.caption, weight: .medium))
                Picker("", selection: $selection) {
                    ForEach(ShareDuration.allCases) { d in
                        Text(d.label).tag(d)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Start sharing") {
                    onStart(selection)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}

// MARK: - Active-share banner

/// Banner that sits under a channel's header while a share is active.
/// Shows the URL, a Copy button, a live countdown, and a Stop button.
struct ChannelShareBanner: View {
    let share: ChannelShareController.ActiveShare
    var onCopy: () -> Void = {}
    var onStop: () -> Void = {}

    @State private var now: Date = .now
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval {
        max(0, share.expiresAt.timeIntervalSince(now))
    }

    private var countdown: String {
        let s = Int(remaining)
        if s <= 0 { return "expired" }
        if s < 60 { return "\(s)s remaining" }
        let m = s / 60
        if m < 60 { return "\(m) min remaining" }
        let h = m / 60
        let rem = m % 60
        return rem > 0 ? "\(h)h \(rem)m remaining" : "\(h)h remaining"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.green)
                .help("This channel is publicly shared")

            HStack(spacing: 4) {
                Text(share.url)
                    .font(.app(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(share.url, forType: .string)
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.app(.caption))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy share URL")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.10))
            )

            Text(countdown)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button(role: .destructive, action: onStop) {
                Label("Stop sharing", systemImage: "xmark.circle")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(Color.green.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
        .onReceive(tick) { now = $0 }
    }
}

// MARK: - Starting (spinner) banner

struct ChannelShareStartingBanner: View {
    @State private var tookLong: Bool = false
    @State private var tookVeryLong: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            // Message ramps up as wait time grows, so a slow cloudflared
            // install or a cold Cloudflare edge doesn't feel like a silent
            // hang. We deliberately don't name a single culprit because the
            // stalls we've seen happen anywhere from DNS propagation, npx
            // fetching cloudflared on first run, or the edge waiting on
            // the connector to register.
            Text(tookVeryLong
                 ? "Still working — waiting for Cloudflare to route the tunnel. First run also downloads cloudflared."
                 : tookLong
                   ? "Opening a public tunnel…"
                   : "Starting share…")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.06))
        .task {
            try? await Task.sleep(for: .seconds(3))
            tookLong = true
            try? await Task.sleep(for: .seconds(7))
            tookVeryLong = true
        }
    }
}

// MARK: - Failure banner

struct ChannelShareFailedBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("Couldn't start share: \(message)")
                .font(.app(.caption))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}
