import UIKit

// MARK: - Why there is no "secure canvas" here
//
// There was one. It crashed the app on launch, and it has been removed.
//
// The technique: a `UITextField` with `isSecureTextEntry = true` owns a layer
// that UIKit excludes from screen captures, so re-parenting the app's view
// hierarchy into that layer makes captured frames come out black. It is widely
// copied, undocumented, and unsupported.
//
// The implementation that shipped here did this:
//
//     window.addSubview(field)                  // field.layer is now a
//                                               // DESCENDANT of window.layer
//     window.layer.superlayer?.addSublayer(secureLayer)
//     secureLayer.addSublayer(window.layer)     // <- cycle
//
// `window.layer.superlayer` is nil on a UIWindow, so the third line was a
// no-op and the fourth made `window.layer` a child of its own descendant.
// CoreAnimation hits that cycle on the first layout pass and the process dies
// before the first frame.
//
// DO NOT RE-ADD THIS without a device to test on. A correct version must host
// the secure layer somewhere that is NOT inside the window it is trying to
// contain, and even then it is private behaviour that Apple can remove in any
// release. It is a nice-to-have; a launch crash is not a trade worth making
// for it.
//
// What protects iOS content instead, all of it documented and working:
//   * Recording / mirroring detection -> playback pauses behind an opaque
//     panel (`UIScreen.capturedDidChangeNotification`).
//   * Screenshot detection -> the event is queued and attributed to the
//     student (`UIApplication.userDidTakeScreenshotNotification`).
//   * The app-switcher cover below.
//   * The watermark, which is the layer that actually makes a leak
//     attributable.
//
// iOS cannot block a screenshot. It never could. See
// `lib/core/security/README.md`.

/// Opaque cover shown over the window while the app is backgrounded.
///
/// Without this the OS snapshots whatever is on screen for the multitasking
/// card — which, in a video app, is a frame of the lesson. `FLAG_SECURE` gives
/// Android this for free; iOS needs it done by hand.
///
/// Unlike the removed canvas, this only *adds* a subview and removes it again.
/// It never re-parents anything.
final class AppSwitcherCover {

    private var cover: UIView?

    /// Whether the cover is currently installed.
    var isShowing: Bool { cover != nil }

    func show(in window: UIWindow) {
        guard cover == nil else { return }
        let view = UIView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Match the brand navy used by the launch screen so the card reads as
        // the app, not as a crash.
        view.backgroundColor = UIColor(
            red: 0x0F / 255.0, green: 0x1B / 255.0, blue: 0x3D / 255.0, alpha: 1
        )

        if let icon = UIImage(named: "AppIcon") ?? UIImage(named: "LaunchImage") {
            let imageView = UIImageView(image: icon)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 96),
                imageView.heightAnchor.constraint(equalToConstant: 96),
            ])
        }

        window.addSubview(view)
        window.bringSubviewToFront(view)
        cover = view
    }

    func hide() {
        cover?.removeFromSuperview()
        cover = nil
    }
}
