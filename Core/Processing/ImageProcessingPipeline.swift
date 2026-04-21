import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

protocol ImageProcessingPipeline: Sendable {
    func normalize(_ image: UIImage) async throws -> UIImage
}

final class DefaultImageProcessingPipeline: ImageProcessingPipeline, @unchecked Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let maxInputDimension: CGFloat = 2200

    func normalize(_ image: UIImage) async throws -> UIImage {
        guard let input = CIImage(image: image) else { return image }

        let oriented = input.oriented(forExifOrientation: Int32(image.imageOrientation.exifOrientationValue.rawValue))
        let scaled = downscaledIfNeeded(oriented)
        let corrected = try whitenBackground(scaled)
        guard let outputCGImage = context.createCGImage(corrected, from: corrected.extent) else {
            return image
        }

        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: .up)
    }

    private func whitenBackground(_ input: CIImage) throws -> CIImage {
        let denoise = CIFilter.noiseReduction()
        denoise.inputImage = input
        denoise.noiseLevel = 0.02
        denoise.sharpness = 0.35

        let controls = CIFilter.colorControls()
        controls.inputImage = denoise.outputImage ?? input
        controls.saturation = 0.85
        controls.contrast = 1.08
        controls.brightness = 0.02

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = controls.outputImage
        gamma.power = 0.92

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = gamma.outputImage
        exposure.ev = 0.25

        // Advanced: Unsharp Masking to massively enhance faint edges for OCR
        let unsharp = CIFilter.unsharpMask()
        unsharp.inputImage = exposure.outputImage
        unsharp.radius = 2.5
        unsharp.intensity = 1.0

        let blend = CIFilter.sourceOverCompositing()
        blend.backgroundImage = CIImage(color: .white).cropped(to: input.extent)
        blend.inputImage = unsharp.outputImage

        return (blend.outputImage ?? input).cropped(to: input.extent)
    }

    private func downscaledIfNeeded(_ input: CIImage) -> CIImage {
        let extent = input.extent.integral
        let largestDimension = max(extent.width, extent.height)
        guard largestDimension > maxInputDimension, largestDimension > 0 else {
            return input
        }

        let scale = maxInputDimension / largestDimension
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return input.transformed(by: transform)
    }
}

private extension UIImage.Orientation {
    var exifOrientationValue: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
