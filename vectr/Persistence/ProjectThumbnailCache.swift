//
//  ProjectThumbnailCache.swift
//  vectr
//

import UIKit

/// Decoded gallery thumbnails, keyed by path + modification date.
@MainActor
enum ProjectThumbnailCache {
    private static let images = NSCache<NSString, UIImage>()

    static func image(for url: URL, modifiedAt: Date) -> UIImage? {
        images.object(forKey: key(url: url, modifiedAt: modifiedAt))
    }

    static func store(_ image: UIImage, for url: URL, modifiedAt: Date) {
        images.setObject(image, forKey: key(url: url, modifiedAt: modifiedAt))
    }

    private static func key(url: URL, modifiedAt: Date) -> NSString {
        "\(url.path)|\(modifiedAt.timeIntervalSince1970)" as NSString
    }
}
