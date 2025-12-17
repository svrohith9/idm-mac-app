import SwiftUI
import SwiftData

struct DownloadRowView: View {
    @Bindable var item: DownloadItem
    var pauseAction: () -> Void
    var resumeAction: () -> Void
    var deleteAction: () -> Void
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.filename)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    statusBadge
                }

                if let host = item.url.host {
                    Text(host)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .animation(.easeInOut(duration: 0.2), value: item.progress)

                HStack(spacing: 8) {
                    Text(secondaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let etaText = etaText {
                        Text(etaText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color(.quaternaryLabelColor), lineWidth: 6)
                    .frame(width: 46, height: 46)

                Circle()
                    .trim(from: 0, to: CGFloat(item.progress))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: item.progress)

                Button(action: buttonAction) {
                    Image(systemName: buttonSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolEffect(.bounce, value: item.state == .completed)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .contextMenu {
            Button("Pause") { pauseAction() }
                .disabled(item.state != .downloading)
            Button("Resume") { resumeAction() }
                .disabled(item.state == .downloading || item.state == .completed)
            Divider()
            Button(role: .destructive, action: deleteAction) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var secondaryText: String {
        switch item.state {
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .paused:
            return "Paused"
        default:
            let speed = byteFormatter.string(fromByteCount: Int64(item.speedBytesPerSecond))
            let percent = Int((item.progress * 100).rounded())
            return "\(speed)/s • \(percent)%"
        }
    }

    private var etaText: String? {
        guard item.speedBytesPerSecond > 0, let total = item.totalBytes else { return nil }
        let remaining = Double(total - item.bytesReceived)
        let seconds = remaining / item.speedBytesPerSecond
        guard seconds.isFinite else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds)
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch item.state {
            case .completed: return ("Done", .green)
            case .paused: return ("Paused", .orange)
            case .failed: return ("Failed", .red)
            case .downloading: return ("Active", .blue)
            case .queued: return ("Queued", .gray)
            default: return ("", .clear)
            }
        }()

        return Group {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }

    private var iconName: String {
        switch item.category {
        case .documents: return "doc.text.fill"
        case .images: return "photo.fill"
        case .audio: return "waveform"
        case .video: return "film.fill"
        case .archives: return "archivebox.fill"
        case .other: return "doc.fill"
        }
    }

    private var buttonSymbol: String {
        switch item.state {
        case .downloading:
            return "pause.fill"
        case .completed:
            return "checkmark"
        default:
            return "play.fill"
        }
    }

    private func buttonAction() {
        switch item.state {
        case .downloading:
            pauseAction()
        case .completed:
            break
        default:
            resumeAction()
        }
    }

    private var byteFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }
}
