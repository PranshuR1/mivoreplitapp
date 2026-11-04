import Foundation
import Vision

/// Reads the words in a photo on the device. The Mivo AI only reads text, so a
/// photo of a notebook or a screenshot reaches it as the words in the picture.
enum MivoPhotoText {
    /// The text found in each photo, in order. Photos with no readable text are skipped.
    static func read(_ images: [Data]) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            images.compactMap { data -> String? in
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(data: data, options: [:])
                guard (try? handler.perform([request])) != nil else { return nil }
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        }.value
    }
}
