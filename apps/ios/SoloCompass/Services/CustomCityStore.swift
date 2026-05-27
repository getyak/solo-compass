import Foundation
import Observation

@MainActor
@Observable
final class CustomCityStore {
    static let shared = CustomCityStore()

    private let key = "saved_custom_cities"

    private(set) var cities: [SavedCity] = []

    private init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedCity].self, from: data) else { return }
        cities = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cities) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ city: SavedCity) {
        cities.removeAll { $0.id == city.id }
        cities.insert(city, at: 0)
        persist()
    }

    func remove(id: String) {
        cities.removeAll { $0.id == id }
        persist()
    }

    func remove(at offsets: IndexSet) {
        cities.remove(atOffsets: offsets)
        persist()
    }
}
