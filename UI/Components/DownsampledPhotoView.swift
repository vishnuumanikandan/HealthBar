//
//  DownsampledPhotoView.swift
//  HealthBar
//
//  Created by Claude on 8/4/26.
//

import SwiftUI
import UIKit
import ImageIO

/// Shared downsampled-thumbnail cache.
///
/// File scope, not a `static` on `DownsampledPhotoView`: Swift disallows stored static
/// properties inside generic types (the MEALROW-1 `static let` lesson), and the computed
/// `static var` workaround used for layout constants would hand out a FRESH cache on
/// every access — defeating caching entirely. One cache shared by every specialization.
private enum PhotoDecodeCache {

    /// Bounded so a long scroll cannot grow the cache without limit; `NSCache` also
    /// evicts on its own under memory pressure, so there is no manual handling.
    static let countLimit = 200

    /// Stores the already-downsampled thumbnail ONLY — never an original-resolution
    /// image. Keyed `"<cacheKey>#<pixelSize>"`, so the same photo rendered at two sizes
    /// is two entries by design.
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = countLimit
        return cache
    }()
}

/// PHOTOPERF-1: asynchronous, target-sized photo decode for scroll-hot list rows.
///
/// The food log's rows previously called `UIImage(data:)` during view construction,
/// decoding a full-resolution JPEG on the main thread for every visible cell. This view
/// decodes a thumbnail no larger than the frame it actually renders into, off the main
/// actor, and caches the downsampled result.
///
/// `targetSize` is the rendered frame of the IMAGE, in points — not the enclosing row or
/// cell. The placeholder occupies that identical frame, so layout never shifts when the
/// decode lands.
///
/// TODO-photo-decode-sweep: the sheet / one-off surfaces (`AddFoodFormView`,
/// `EditMealView`, `DescribeMealView`, `FoodDatabaseView`) still decode inline via
/// `UIImage(data:)`. They are not scroll-hot, so PHOTOPERF-1 deliberately left them out.
struct DownsampledPhotoView<Placeholder: View>: View {

    let photoData: Data
    /// Rendered frame of the image itself, in points.
    let targetSize: CGSize
    /// Stable per-entry identity (food entry id / bundle id) — the cache key's base.
    let cacheKey: String
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var decoded: UIImage?

    /// Integer thumbnail max-pixel dimension for the rendered point size.
    private var pixelSize: Int {
        Int((max(targetSize.width, targetSize.height) * displayScale).rounded())
    }

    /// Frozen key format. Also used as the `.task` id: a superset of `cacheKey` alone, so
    /// a rotation or display-scale change re-fires the decode at the new size instead of
    /// leaving a stale-resolution thumbnail on screen.
    private var fullCacheKey: String {
        "\(cacheKey)#\(pixelSize)"
    }

    var body: some View {
        Group {
            if let decoded {
                Image(uiImage: decoded)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipped()
        .task(id: fullCacheKey) { await load() }
    }

    private func load() async {
        // A zero frame is GeometryReader's first pass; `fullCacheKey` carries pixelSize,
        // so the task re-fires once a real size arrives.
        guard pixelSize > 0 else { return }

        let key = fullCacheKey as NSString

        if let cached = PhotoDecodeCache.images.object(forKey: key) {
            assign(cached)
            return
        }

        // Recycled row: drop the previous entry's image so its photo is never shown under
        // this row's identity while the new decode is in flight.
        if decoded != nil { assign(nil) }

        let data = photoData
        let maxPixelSize = pixelSize

        let image = await Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(from: data, maxPixelSize: maxPixelSize)
        }.value

        // A recycled row cancels its stale decode. `Task.detached` does not inherit
        // cancellation, so the work may finish anyway — the result is discarded here
        // rather than assigned or cached.
        guard !Task.isCancelled else { return }

        guard let image else {
            print("[PHOTOPERF-1] Thumbnail decode failed for \(cacheKey) — placeholder retained")
            return
        }

        PhotoDecodeCache.images.setObject(image, forKey: key)
        assign(image)
    }

    /// Swaps the image in without animation — list rows must not shimmer during fast
    /// scrolls.
    private func assign(_ image: UIImage?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { decoded = image }
    }

    /// Decodes a thumbnail bounded by `maxPixelSize`.
    ///
    /// `nonisolated` is load-bearing, not a formality: `View` conformance makes this type
    /// `@MainActor`, so without it the `Task.detached` below hops straight back to the
    /// main actor to make this call and the decode runs exactly where PHOTOPERF-1 is
    /// trying to get it off of.
    private nonisolated static func decodeThumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
        // Stop ImageIO from eagerly decoding the full-resolution image into its own
        // cache — the whole point is never to materialize the original bitmap.
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            // Always synthesize: an embedded EXIF thumbnail is often far too small or a
            // different aspect ratio.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // normalizes orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        // Pixels are physically rotated upright by the transform option above. Scale is
        // irrelevant: every call site renders `.resizable()` into an explicit frame.
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
