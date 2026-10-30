import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One photo chosen by the user, carried as a lazy payload so the composer can
/// keep its existing decode/progress pipeline for both photo pickers.
struct CompatiblePickedPhoto: Identifiable {
    let id = UUID()
    let loadData: () async throws -> Data

    init(loadData: @escaping () async throws -> Data) {
        self.loadData = loadData
    }

    init(data: Data) {
        self.loadData = { data }
    }
}

/// `PhotosPicker` replacement.
///
/// iOS 16 hands back `PhotosPickerItem` values that load their payload
/// asynchronously. On iOS 15 the same `PHPickerViewController` the system picker
/// is built on is presented directly and the selected images are delivered as
/// data, so both paths resolve to `CompatiblePickedPhoto`.
struct CompatibleImagePickerButton<Label: View>: View {
    private let selectionLimit: Int
    private let isDisabled: Bool
    private let onPick: ([CompatiblePickedPhoto]) -> Void
    private let label: Label

    @State private var isPresentingLegacyPicker = false

    init(
        selectionLimit: Int,
        isDisabled: Bool,
        onPick: @escaping ([CompatiblePickedPhoto]) -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.selectionLimit = selectionLimit
        self.isDisabled = isDisabled
        self.onPick = onPick
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ModernPhotoPickerButton(
                selectionLimit: selectionLimit,
                isDisabled: isDisabled,
                onPick: onPick,
                label: label
            )
        } else {
            Button {
                isPresentingLegacyPicker = true
            } label: {
                label
            }
            .disabled(isDisabled)
            .sheet(isPresented: $isPresentingLegacyPicker) {
                CompatibleLegacyPhotoPicker(
                    selectionLimit: selectionLimit,
                    onPick: { photos in
                        isPresentingLegacyPicker = false
                        onPick(photos)
                    },
                    onCancel: {
                        isPresentingLegacyPicker = false
                    }
                )
            }
        }
    }
}

@available(iOS 16.0, *)
private struct ModernPhotoPickerButton<Label: View>: View {
    let selectionLimit: Int
    let isDisabled: Bool
    let onPick: ([CompatiblePickedPhoto]) -> Void
    let label: Label

    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: selectionLimit,
            matching: .images,
            preferredItemEncoding: .current
        ) {
            label
        }
        .disabled(isDisabled)
        .compatibleOnChange(of: selection) { _, items in
            guard items.isEmpty == false else { return }
            selection = []
            onPick(items.map { item in
                CompatiblePickedPhoto {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ContentSubmissionValidationError.invalidImage
                    }
                    return data
                }
            })
        }
    }
}

private struct CompatibleLegacyPhotoPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPick: ([CompatiblePickedPhoto]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(selectionLimit, 1)
        configuration.preferredAssetRepresentationMode = .current

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: ([CompatiblePickedPhoto]) -> Void
        var onCancel: () -> Void

        init(
            onPick: @escaping ([CompatiblePickedPhoto]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard results.isEmpty == false else {
                onCancel()
                return
            }

            // Preserve the user's selection order: the groups complete in
            // whatever order the image data arrives.
            var payloads = [Data?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                group.enter()
                _ = result.itemProvider.loadDataRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { data, _ in
                    lock.lock()
                    payloads[index] = data
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                let photos = payloads
                    .compactMap { $0 }
                    .map(CompatiblePickedPhoto.init(data:))
                self.onPick(photos)
            }
        }
    }
}
