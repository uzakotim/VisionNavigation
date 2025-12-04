import Foundation
import Vision
import CoreML
import UIKit
import Accelerate

struct DepthAnalysisResult {
    let colorizedImage: UIImage
    let regionAverages: [CGFloat]
}

final class DepthProcessor {
    private let vnModel: VNCoreMLModel
    private let requestQueue = DispatchQueue(label: "depth.processor.queue", qos: .userInitiated)
    private var request: VNCoreMLRequest!

    init?() {
        guard let model = try? DepthAnythingV2SmallF16(configuration: MLModelConfiguration()).model,
              let vnModel = try? VNCoreMLModel(for: model) else {
            print("❌ Failed to load DepthAnythingV2.mlmodel")
            return nil
        }

        self.vnModel = vnModel
        self.request = VNCoreMLRequest(model: vnModel)
        self.request.imageCropAndScaleOption = .scaleFill
    }

    // Keep the original API for callers that have CMSampleBuffer
    func process(sampleBuffer: CMSampleBuffer, completion: @escaping (DepthAnalysisResult?) -> Void) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil)
            return
        }
        process(pixelBuffer: pixelBuffer, completion: completion)
    }

    // New API that matches what VisionNavigator publishes
    func process(pixelBuffer: CVPixelBuffer, completion: @escaping (DepthAnalysisResult?) -> Void) {
        requestQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            do {
                try handler.perform([self.request])
            } catch {
                print("❌ Vision error: \(error)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let pbObs = self.request.results?.first as? VNPixelBufferObservation else {
                print("⚠️ No VNPixelBufferObservation result")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let depthBuffer = pbObs.pixelBuffer
            let (depthValues, width, height) = self.extractFloats(from: depthBuffer)

            guard !depthValues.isEmpty else {
                print("⚠️ Depth buffer empty")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let (minVal, maxVal) = self.minMax(of: depthValues)
            let normalized = depthValues.map {
                CGFloat((($0 - minVal) / (maxVal - minVal + 1e-6)).clamped(to: 0...1))
            }

            let colorImage = self.colorMap(from: normalized, width: width, height: height)
            let regionAverages = self.computeRegionAverages(from: normalized, width: width, height: height)

            DispatchQueue.main.async {
                completion(DepthAnalysisResult(colorizedImage: colorImage, regionAverages: regionAverages))
            }
        }
    }

    // MARK: - Depth extraction from Grayscale16Half
    private func extractFloats(from pixelBuffer: CVPixelBuffer) -> ([Float], Int, Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let count = width * height
        var floats = [Float](repeating: 0, count: count)

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return ([], width, height)
        }

        // Convert Float16 → Float32
        let rowBytesSrc = CVPixelBufferGetBytesPerRow(pixelBuffer)

        floats.withUnsafeMutableBytes { dstBytes in
            var srcBuffer = vImage_Buffer(
                data: base,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: rowBytesSrc
            )
            var dstBuffer = vImage_Buffer(
                data: dstBytes.baseAddress!,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width * MemoryLayout<Float>.size
            )
            vImageConvert_Planar16FtoPlanarF(&srcBuffer, &dstBuffer, 0)
        }

        return (floats, width, height)
    }

    private func minMax(of arr: [Float]) -> (Float, Float) {
        var minVal = Float.greatestFiniteMagnitude
        var maxVal = -Float.greatestFiniteMagnitude
        for v in arr where v.isFinite {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
        }
        return (minVal, maxVal)
    }

    // MARK: - Visualization
    private func colorMap(from normalized: [CGFloat], width: Int, height: Int) -> UIImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for i in 0..<width * height {
            let v = 1.0 - normalized[i] // invert so near = red
            let (r, g, b) = jetColor(for: v)
            pixels[i*4+0] = r
            pixels[i*4+1] = g
            pixels[i*4+2] = b
            pixels[i*4+3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width*4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }

    private func computeRegionAverages(from normalized: [CGFloat], width: Int, height: Int) -> [CGFloat] {
        guard width > 0, height > 0 else { return [0, 0, 0] }
        let regionWidth = max(1, width / 3)
        var sums = [CGFloat](repeating: 0, count: 3)
        var counts = [Int](repeating: 0, count: 3)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let r = min(x / regionWidth, 2)
                sums[r] += normalized[idx]
                counts[r] += 1
            }
        }
        return zip(sums, counts).map { total, c in
            c > 0 ? total / CGFloat(c) : 0
        }
    }

    // MARK: - Jet colormap
    private func jetColor(for v: CGFloat) -> (UInt8, UInt8, UInt8) {
        let x = max(0, min(1, v))
        let r = CGFloat(jetComponent(x, start: 0.35, end: 0.85))
        let g = CGFloat(jetComponent(x, start: 0.125, end: 0.875))
        let b = CGFloat(jetComponent(x, start: 0.0, end: 0.65))
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    private func jetComponent(_ x: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        let mid = (start + end) / 2
        if x < start { return 0 }
        if x < mid { return (x - start) / (mid - start) }
        if x < end { return 1 - (x - mid) / (end - mid) }
        return 0
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
