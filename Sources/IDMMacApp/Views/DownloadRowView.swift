import SwiftUI
import SwiftData

struct DownloadRowView: View {
    @Bindable var item: DownloadItem
    var pauseAction: () -> Void
    var resumeAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let host = item.url.host {
                    Text(host)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .animation(.easeInOut(duration: 0.2), value: item.progress)

                Text(secondaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .strokeBorder(.quaternary, lineWidth: 6)
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
        .padding(.vertical, 8)
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
