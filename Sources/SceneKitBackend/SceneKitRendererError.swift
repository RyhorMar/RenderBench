import Foundation

/// What can keep the SceneKit backend from delivering a frame.
public enum SceneKitRendererError: Error, Sendable, Equatable {
    /// No Metal device on this host: `SCNRenderer` and the on-screen `SCNView` both need one to
    /// render, and there is nowhere to build it lazily without swallowing the failure `encode(_:)`
    /// must see before it draws.
    case noDevice
    /// `SCNRenderer.snapshot(atTime:with:antialiasingMode:)` produced no image, or the bitmap its
    /// pixels were copied into could not be created — a fact about the host, not a rendering
    /// failure.
    case noSnapshot
}
