import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics
import tiff_ios



struct ContentView : View {
    @StateObject var arViewModel = ARViewModel()
    let previewCornerRadius: CGFloat = 15.0

    var body: some View {

        GeometryReader { geometry in
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {

                    let width = geometry.size.width
                    let height = width * 4 / 3 // 4:3 aspect ratio

                    ARViewContainer(arViewModel: arViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                        .frame(width: width, height: height)
                    CaptureButtonPanelView(model: arViewModel,  width: geometry.size.width)

                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}




func writeDepthMapToRawFile(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    }

    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
        return false
    }

    // 총 픽셀 수
    let totalPixels = width * height
    // 메모리에서 Float32로 바로 읽기
    let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
    let bufferPointer = UnsafeBufferPointer(start: floatBuffer, count: totalPixels)

    do {
        // NSData로 변환 후 저장
        let data = Data(buffer: bufferPointer)
        try data.write(to: url)
        return true
    } catch {
        print("Failed to write .raw file: \(error)")
        return false
    }
}


func writeDepthMapToTIFFWithLibTIFF(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    
    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        return false
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
    
    guard let rasters = TIFFRasters(width: Int32(width), andHeight: Int32(height), andSamplesPerPixel: 1, andSingleBitsPerSample: 32) else {
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        return false
    }
    
    for y in 0..<height {
        let pixelBytes = baseAddress.advanced(by: y * bytesPerRow)
        let pixelBuffer = UnsafeBufferPointer<Float>(start: pixelBytes.assumingMemoryBound(to: Float.self), count: width)
        for x in 0..<width {
            rasters.setFirstPixelSampleAtX(Int32(x), andY: Int32(y), withValue: NSDecimalNumber(value: pixelBuffer[x]))
        }
    }
    
    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    
    let rowsPerStrip = UInt16(rasters.calculateRowsPerStrip(withPlanarConfiguration: Int32(TIFF_PLANAR_CONFIGURATION_CHUNKY)))
    
    guard let directory = TIFFFileDirectory() else {
        return false
    }
    directory.setImageWidth(UInt16(width))
    directory.setImageHeight(UInt16(height))
    directory.setBitsPerSampleAsSingleValue(32)
    directory.setCompression(UInt16(TIFF_COMPRESSION_NO))
    directory.setPhotometricInterpretation(UInt16(TIFF_PHOTOMETRIC_INTERPRETATION_BLACK_IS_ZERO))
    directory.setSamplesPerPixel(1)
    directory.setRowsPerStrip(rowsPerStrip)
    directory.setPlanarConfiguration(UInt16(TIFF_PLANAR_CONFIGURATION_CHUNKY))
    directory.setSampleFormatAsSingleValue(UInt16(TIFF_SAMPLE_FORMAT_FLOAT))
    directory.writeRasters = rasters
    
    guard let tiffImage = TIFFImage() else {
        return false
    }
    tiffImage.addFileDirectory(directory)
    
    TIFFWriter.writeTiff(withFile: url.path, andImage: tiffImage)
    
    return true
}

func saveImage(image: CVPixelBuffer, url: URL) {
    let ciImage = CIImage(cvPixelBuffer: image)
    let context = CIContext()
    if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
       let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) {
        do {
            try jpegData.write(to: url)
        } catch {
            print("Failed to save image: \(error)")
        }
    }
}


