//
//  CameraPickerView.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import SwiftUI
import UIKit

/// UIViewControllerRepresentable wrapper for UIImagePickerController (Camera)
///
/// Presents the device camera for taking photos. On completion, calls the onImagePicked callback
/// with the captured UIImage. Handles permission denials gracefully.
struct CameraPickerView: UIViewControllerRepresentable {

    @Environment(\.dismiss) private var dismiss
    let onImagePicked: (UIImage) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Get the captured image
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }

            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
