import Foundation

/// What can keep the Core Image backend from delivering a frame.
public enum CoreImageRendererError: Error, Sendable, Equatable {
    /// No Metal device on this host: `CIContext(mtlDevice:)` needs one, and there is nowhere to
    /// build it lazily without swallowing the failure `encode(_:)` must see before it draws.
    case noDevice
    /// `CoreGraphicsReference.renderCGImage(_:scale:)` returned `nil` for this frame — a fact
    /// about the host (a bitmap context could not be created), not a filter failure.
    case noReference
    /// `CIColorControls`'s `outputImage` was `nil`.
    case filterUnavailable
}
