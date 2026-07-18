import CoreLocation
import PhotosUI
import SwiftUI

/// Form to register a new place at a long-pressed map coordinate.
///
/// This is the primary "add a place" path (the voice flow remains as a
/// secondary entry point). The user supplies only honest, mechanical facts:
/// name, category, a short description, and photos. Trust-critical fields
/// (Solo Score, confidence) are NOT user-settable — `Experience.userDraft`
/// fills them with safe, unverified defaults.
public struct CreateExperienceSheet: View {
    /// The map coordinate the user long-pressed. Photos and form text are
    /// gathered here; the coordinate is fixed.
    let coordinate: CLLocationCoordinate2D

    /// Called with the assembled fields when the user taps Save. Photo URLs are
    /// already-persisted `file://` strings.
    var onSave: (_ input: NewPlaceFormInput) -> Void

    /// Called when the user wants the secondary voice path instead of the form.
    var onUseVoice: () -> Void

    var onCancel: () -> Void

    @State private var placeName: String = ""
    @State private var placeNameLocal: String = ""
    @State private var oneLiner: String = ""
    @State private var description: String = ""
    @State private var category: ExperienceCategory = .hidden

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isShowingCamera = false

    @Environment(\.dismiss) private var dismiss

    public init(
        coordinate: CLLocationCoordinate2D,
        onSave: @escaping (_ input: NewPlaceFormInput) -> Void,
        onUseVoice: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.onSave = onSave
        self.onUseVoice = onUseVoice
        self.onCancel = onCancel
    }

    /// Save is meaningful only when there's at least a place name.
    private var canSave: Bool {
        !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Any field touched or photo added → protect against an accidental
    /// swipe-to-dismiss discarding the draft (HIG: guard unsaved edits).
    private var isDirty: Bool {
        !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !placeNameLocal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !oneLiner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                nameSection
                categorySection
                descriptionSection
                photosSection
                voiceSection
            }
            .navigationTitle(NSLocalizedString("userLocation.create.title", comment: "Add a place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("userLocation.form.save", comment: "Save")) {
                        submit()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker { captured in
                    if let captured { images.append(captured) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, newItems in
                Task { await loadPickedImages(newItems) }
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField(
                NSLocalizedString("userLocation.form.name.placeholder", comment: "Place name placeholder"),
                text: $placeName
            )
            TextField(
                NSLocalizedString("userLocation.form.nameLocal.placeholder", comment: "Local-language name placeholder"),
                text: $placeNameLocal
            )
            TextField(
                NSLocalizedString("userLocation.form.oneLiner.placeholder", comment: "One-line summary placeholder"),
                text: $oneLiner
            )
        } header: {
            Text(NSLocalizedString("userLocation.form.name.label", comment: "Place name section header"))
        }
    }

    private var categorySection: some View {
        Section {
            Picker(
                NSLocalizedString("userLocation.form.category.label", comment: "Category"),
                selection: $category
            ) {
                ForEach(ExperienceCategory.allCases) { cat in
                    Label(cat.localizedTitle, systemImage: cat.symbol).tag(cat)
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField(
                NSLocalizedString("userLocation.form.notes.placeholder", comment: "Notes placeholder"),
                text: $description,
                axis: .vertical
            )
            .lineLimit(3...6)
        } header: {
            Text(NSLocalizedString("userLocation.form.notes.label", comment: "Notes section header"))
        }
    }

    private var photosSection: some View {
        Section {
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(2)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Label(
                    NSLocalizedString("userLocation.form.photo.library", comment: "Choose from library"),
                    systemImage: "photo.on.rectangle"
                )
            }
            Button {
                isShowingCamera = true
            } label: {
                Label(
                    NSLocalizedString("userLocation.form.photo.camera", comment: "Take a photo"),
                    systemImage: "camera"
                )
            }
        } header: {
            Text(NSLocalizedString("userLocation.form.photo.label", comment: "Photos section header"))
        }
    }

    private var voiceSection: some View {
        Section {
            Button {
                onUseVoice()
                dismiss()
            } label: {
                Label(
                    NSLocalizedString("userLocation.form.useVoice", comment: "Describe with voice instead"),
                    systemImage: "mic"
                )
            }
        } footer: {
            Text(NSLocalizedString("userLocation.form.unverifiedNote", comment: "Unverified note"))
        }
    }

    // MARK: - Actions

    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        await MainActor.run { images.append(contentsOf: loaded); pickerItems = [] }
    }

    private func submit() {
        // Persist images to disk now so the form hands back ready-to-store URLs.
        let urls = PlacePhotoStore.save(images, uuids: images.map { _ in UUID().uuidString })
        let trimmedName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = NewPlaceFormInput(
            coordinate: coordinate,
            placeNameRomanized: trimmedName,
            placeNameLocal: placeNameLocal.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            // Title falls back to the place name when the user gives no one-liner action.
            title: oneLiner.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? trimmedName,
            oneLiner: oneLiner.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            photoUrls: urls.isEmpty ? nil : urls
        )
        onSave(input)
        dismiss()
    }
}

/// The fields the create-place form hands back. Coordinate is fixed from the
/// long-press; everything else is user-entered. Photo URLs are persisted
/// `file://` strings ready for `ExperienceLocation.photoUrls`.
public struct NewPlaceFormInput {
    public let coordinate: CLLocationCoordinate2D
    public let placeNameRomanized: String
    public let placeNameLocal: String?
    public let title: String
    public let oneLiner: String
    public let description: String
    public let category: ExperienceCategory
    public let photoUrls: [String]?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Camera picker (UIKit bridge)

/// Minimal `UIImagePickerController` wrapper for taking a photo. SwiftUI has no
/// native camera capture view, so we bridge UIKit. Library picking uses the
/// native `PhotosPicker` in the form above.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    CreateExperienceSheet(
        coordinate: CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938),
        onSave: { _ in },
        onUseVoice: {},
        onCancel: {}
    )
}
