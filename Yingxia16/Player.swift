import SwiftUI
import AVKit

struct PlayerController: UIViewControllerRepresentable {
    let url: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed) {
            let player = AVPlayer(url: u)
            controller.player = player
            player.play()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct PlayerView: View {
    let url: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayerController(url: url)
                .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(radius: 3)
                }
                .padding(16)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .shadow(radius: 2)
            }
        }
        .background(Color.black)
    }
}
