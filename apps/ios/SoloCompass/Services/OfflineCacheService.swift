import Foundation
import CoreData
import Network
import Observation

/// Caches POIs for visited cities in Core Data, TTL 7 days, LRU eviction at 100 MB.
@Observable
@MainActor
public final class OfflineCacheService {
    public static let shared = OfflineCacheService()

    // MARK: - Constants
    private static let ttlSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let maxCacheSizeBytes: Int64 = 100 * 1024 * 1024

    // MARK: - Core Data stack

    @ObservationIgnored
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "OfflineCache", managedObjectModel: Self.makeModel())
        let description = container.persistentStoreDescriptions.first
        description?.setOption(FileProtectionType.complete as NSObject,
                               forKey: NSPersistentStoreFileProtectionKey)
        container.loadPersistentStores { _, error in
            if let error { print("[OfflineCacheService] Core Data load error: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    private var context: NSManagedObjectContext { persistentContainer.viewContext }

    private init() {}

    // MARK: - Public API

    /// Store a batch of experiences for the given city. Overwrites existing entry.
    public func cacheExperiences(_ experiences: [Experience], forCity cityCode: String) {
        let now = Date()
        let context = self.context
        let json = (try? JSONEncoder().encode(experiences)) ?? Data()

        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedCity")
        fetchRequest.predicate = NSPredicate(format: "cityCode == %@", cityCode)

        let existing = (try? context.fetch(fetchRequest))?.first
        let entry = existing ?? NSEntityDescription.insertNewObject(forEntityName: "CachedCity", into: context)
        entry.setValue(cityCode, forKey: "cityCode")
        entry.setValue(now, forKey: "cachedAt")
        entry.setValue(json, forKey: "payload")
        entry.setValue(Int64(json.count), forKey: "sizeBytes")

        try? context.save()
        evictIfNeeded()
    }

    /// Load cached experiences for a city. Returns nil if cache miss or expired.
    public func loadExperiences(forCity cityCode: String) -> [Experience]? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedCity")
        fetchRequest.predicate = NSPredicate(format: "cityCode == %@", cityCode)
        guard let entry = (try? context.fetch(fetchRequest))?.first else { return nil }

        let cachedAt = entry.value(forKey: "cachedAt") as? Date ?? .distantPast
        if Date().timeIntervalSince(cachedAt) > Self.ttlSeconds {
            context.delete(entry)
            try? context.save()
            return nil
        }

        // Update access time for LRU tracking
        entry.setValue(Date(), forKey: "lastAccessedAt")
        try? context.save()

        guard let data = entry.value(forKey: "payload") as? Data else { return nil }
        return try? JSONDecoder().decode([Experience].self, from: data)
    }

    /// Returns true when there is a valid (non-expired) cache entry for the city.
    public func hasCachedData(forCity cityCode: String) -> Bool {
        loadExperiences(forCity: cityCode) != nil
    }

    // MARK: - LRU Eviction

    private func evictIfNeeded() {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedCity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "lastAccessedAt", ascending: true)]
        guard let all = try? context.fetch(fetchRequest) else { return }

        let total = all.compactMap { $0.value(forKey: "sizeBytes") as? Int64 }.reduce(0, +)
        guard total > Self.maxCacheSizeBytes else { return }

        var running = total
        for entry in all {
            guard running > Self.maxCacheSizeBytes else { break }
            running -= (entry.value(forKey: "sizeBytes") as? Int64 ?? 0)
            context.delete(entry)
        }
        try? context.save()
    }

    // MARK: - Expired entry cleanup

    public func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-Self.ttlSeconds)
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedCity")
        fetchRequest.predicate = NSPredicate(format: "cachedAt < %@", cutoff as NSDate)
        guard let expired = try? context.fetch(fetchRequest) else { return }
        expired.forEach { context.delete($0) }
        try? context.save()
    }

    // MARK: - Core Data Model (programmatic, no .xcdatamodeld needed)

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "CachedCity"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            return a
        }

        entity.properties = [
            attr("cityCode", .stringAttributeType),
            attr("cachedAt", .dateAttributeType),
            attr("lastAccessedAt", .dateAttributeType),
            attr("payload", .binaryDataAttributeType),
            attr("sizeBytes", .integer64AttributeType),
        ]
        model.entities = [entity]
        return model
    }
}
