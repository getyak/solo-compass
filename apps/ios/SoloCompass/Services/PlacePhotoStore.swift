import Foundation
import UIKit

/// Persists photos a user attaches to a place they create.
///
/// Phase 1 stores images in the app's Application Support directory and returns
/// `file://` URLs, which go straight into `ExperienceLocation.photoUrls`. When
/// Phase 2 adds upload sync, the same field is repopulated with remote https
/// URLs and these local files can be cleaned up — the schema doesn't change.
enum PlacePhotoStore {
    /// Subdirectory under Application Support that holds user place photos.
    private static let folderName = "UserPlacePhotos"

    private static var folderURL: URL? {
        guard
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Write a single image to disk as JPEG and return its `file://` URL string.
    /// Returns nil when the image can't be encoded or the directory is missing.
    ///
    /// - Parameters:
    ///   - image: the picked or captured image.
    ///   - uuid: a caller-supplied unique id so filenames stay deterministic
    ///           for tests (e.g. `UUID().uuidString`).
    ///   - quality: JPEG compression quality (0–1). Defaults to 0.8.
    static func save(_ image: UIImage, uuid: String, quality: CGFloat = 0.8) -> String? {
        guard
            let dir = folderURL,
            let data = image.jpegData(compressionQuality: quality)
        else { return nil }
        let fileURL = dir.appendingPathComponent("photo_\(uuid).jpg")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL.absoluteString
        } catch {
            return nil
        }
    }

    /// Save several images, returning the `file://` URL strings that succeeded.
    /// The `uuids` array must be at least as long as `images`; extra ids are
    /// ignored. Indices are paired positionally so retries stay deterministic.
    static func save(_ images: [UIImage], uuids: [String]) -> [String] {
        zip(images, uuids).compactMap { save($0, uuid: $1) }
    }
}
