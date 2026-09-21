import Foundation

// MARK: - Draft

/// Editable field values for the create/edit itinerary form.
///
/// Extracted from `ItineraryFormView` so the prefill, validation, and
/// edit-preservation rules stay pure and unit-testable without SwiftUI.
public struct ItineraryCreationDraft: Equatable {
    /// Traveler-facing itinerary title.
    public var title: String
    /// Storage city code scoping the itinerary (mirrors `ExperienceLocation.cityCode`).
    public var cityCode: String
    /// Inclusive start date.
    public var startDate: Date
    /// Inclusive end date.
    public var endDate: Date
    /// Optional trip note.
    public var note: String
    /// Whether the owner is open to companions.
    public var openToCompanions: Bool

    /// Creates a draft from explicit field values.
    public init(
        title: String,
        cityCode: String,
        startDate: Date,
        endDate: Date,
        note: String,
        openToCompanions: Bool
    ) {
        self.title = title
        self.cityCode = cityCode
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.openToCompanions = openToCompanions
    }
}

// MARK: - Rules

/// Pure rules backing `ItineraryFormView`: date storage, source-city
/// inference, default prefills, and `Itinerary` construction.
///
/// Living outside the view lets tests prove the contract that defaults apply
/// only to new itineraries and that editing never overwrites saved data.
public enum ItineraryCreationRules {
    /// Formats `date` as the `YYYY-MM-DD` string the `Itinerary` schema stores (UTC).
    public static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Parses a stored `YYYY-MM-DD` string (UTC) back to a `Date`.
    /// Returns nil for nil or malformed input.
    public static func date(fromStored string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }

    /// City code of the experience with `experienceId`, or nil when it is not
    /// loaded. Never invents a city.
    public static func sourceCityCode(experienceId: String, in experiences: [Experience]) -> String? {
        experiences.first(where: { $0.id == experienceId })?.location.cityCode
    }

    /// Initial form values.
    ///
    /// - When `editing` is present its saved values are used verbatim; defaults
    ///   must never overwrite existing record data.
    /// - When creating, the title is the localized `suggestedTitle`, the city
    ///   is `sourceCityCode` (empty when unknown — never invented), and both
    ///   dates are `now`.
    public static func initialDraft(
        editing: Itinerary?,
        sourceCityCode: String?,
        now: Date,
        suggestedTitle: String
    ) -> ItineraryCreationDraft {
        if let editing {
            let start = date(fromStored: editing.startDate) ?? now
            let end = date(fromStored: editing.endDate) ?? start
            return ItineraryCreationDraft(
                title: editing.title,
                cityCode: editing.cityCode,
                startDate: start,
                endDate: end,
                note: editing.note ?? "",
                openToCompanions: editing.openToCompanions
            )
        }
        return ItineraryCreationDraft(
            title: suggestedTitle,
            cityCode: sourceCityCode ?? "",
            startDate: now,
            endDate: now,
            note: "",
            openToCompanions: false
        )
    }

    /// Builds the `Itinerary` persisted by the form.
    ///
    /// Editing preserves the record identity, owner, `createdAt`, and existing
    /// experience ids. Creating generates a fresh id/owner and appends
    /// `pinnedExperienceIds` (the source experience) in order.
    public static func itinerary(
        from draft: ItineraryCreationDraft,
        editing: Itinerary?,
        pinnedExperienceIds: [String],
        now: Date,
        generatedId: String
    ) -> Itinerary {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespaces)
        let trimmedNote = draft.note.trimmingCharacters(in: .whitespaces)

        var experienceIds = editing?.experienceIds ?? []
        if editing == nil {
            for id in pinnedExperienceIds where !experienceIds.contains(id) {
                experienceIds.append(id)
            }
        }

        let nowString = ISO8601DateFormatter().string(from: now)
        return Itinerary(
            id: editing?.id ?? ItineraryId(rawValue: generatedId),
            ownerId: editing?.ownerId ?? "local",
            title: trimmedTitle,
            cityCode: draft.cityCode,
            startDate: dateString(from: draft.startDate),
            endDate: dateString(from: draft.endDate),
            experienceIds: experienceIds,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            openToCompanions: draft.openToCompanions,
            createdAt: editing?.createdAt ?? nowString,
            updatedAt: nowString
        )
    }

    /// Whether `draft` can be saved: non-empty title and city, end on or after start.
    public static func isValid(_ draft: ItineraryCreationDraft) -> Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !draft.cityCode.isEmpty &&
        draft.endDate >= draft.startDate
    }
}
