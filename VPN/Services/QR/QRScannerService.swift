import Vision
import UIKit

enum QRScannerService {
    static func scan(image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(image.imageOrientation))
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            for obs in observations {
                if let payload = obs.payloadStringValue, !payload.isEmpty {
                    return payload
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func cgOrientation(_ ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
