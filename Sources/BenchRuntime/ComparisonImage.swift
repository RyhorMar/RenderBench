/// The pinned format every backend's reference image is produced at.
///
/// It lives here rather than in the backend that happened to need it first, because the moment a
/// second backend wants to be compared it either imports the first — making the backends depend on
/// each other, which the comparison is supposed to rule out — or copies the numbers, and two
/// copies of a constant are two constants waiting to disagree.
///
/// The size is arbitrary and that is the point: what matters is that it never changes, since a
/// stored image compared against a render at another size compares two different questions.
public enum ComparisonImage {
    /// Width in points.
    public static let width = 1_024
    /// Height in points.
    public static let height = 768
    /// 8-bit BGRA, premultiplied, sRGB.
    public static let bytesPerPixel = 4

    /// Byte count of a render at a given device scale.
    public static func byteCount(scale: Double) -> Int {
        let pixelWidth = Int((Double(width) * scale).rounded())
        let pixelHeight = Int((Double(height) * scale).rounded())
        return pixelWidth * pixelHeight * bytesPerPixel
    }
}
