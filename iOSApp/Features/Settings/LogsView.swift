import SwiftUI
import UIKit

struct LogsView: View {
    @State private var logText: String = ""
    @State private var isSharing: Bool = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 12) {
                ScrollView {
                    Text(logText.isEmpty ? "No logs yet." : logText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                HStack {
                    Button {
                        AppLogger.shared.clear()
                        logText = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        isSharing = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationTitle("Logs")
        .onAppear { logText = AppLogger.shared.readLogText() }
        .sheet(isPresented: $isSharing) {
            ShareSheet(activityItems: [AppLogger.shared.logFileURL])
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


