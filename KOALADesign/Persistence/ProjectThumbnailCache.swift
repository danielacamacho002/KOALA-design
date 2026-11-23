//
//  ProjectThumbnailCache.swift
//  Koala
//

import UIKit

/// Decoded gallery thumbnails, keyed by path + modification date.
@MainActor
enum ProjectThumbnailCache {
    private static let images = NSCache<NSString, UIImage>()

    static func image(for url: URL) -> UIImage? {
        guard let stamp = modificationStamp(of: url) else { return nil }
        return images.object(forKey: key(url: url, stamp: stamp))
    }

    static func store(_ image: UIImage, for url: URL, stamp: TimeInterval) {
        images.setObject(image, forKey: key(url: url, stamp: stamp))
    }

    static func removeAll() {
        images.removeAllObjects()
    }

    static func modificationStamp(of url: URL) -> TimeInterval? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970
    }

    private static func key(url: URL, stamp: TimeInterval) -> NSString {
        "\(url.path)|\(stamp)" as NSString
    }
}
