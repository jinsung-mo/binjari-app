// Creates an explicitly simulated overlay on a short excerpt of the bundled
// parking-lot video. No model is loaded and no inference is performed.
// Run: swift -module-cache-path /private/tmp/binjari-swift-cache \
//   scripts/generate_mock_demo.swift videos/library2.mp4 docs/media/simulated-parking-demo.mp4

import AVFoundation
import AppKit
import CoreGraphics
import CoreText
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate_mock_demo.swift INPUT.mp4 OUTPUT.mp4")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let asset = AVURLAsset(url: inputURL)
guard let track = asset.tracks(withMediaType: .video).first else {
    fatalError("Input has no video track")
}

let size = track.naturalSize
let width = Int(size.width)
let height = Int(size.height)
let reader = try AVAssetReader(asset: asset)
reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 6, preferredTimescale: 600))
let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
readerOutput.alwaysCopiesSampleData = false
reader.add(readerOutput)

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: outputURL.path) {
    try FileManager.default.removeItem(at: outputURL)
}
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
])
writerInput.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height
])
writer.add(writerInput)

func label(_ value: String, at point: CGPoint, size: CGFloat, color: CGColor, in context: CGContext) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attrs))
    context.textPosition = point
    CTLineDraw(line, context)
}

// Rectangles are hand-selected solely to illustrate the proposed UI overlay.
// They are NOT detections or model predictions.
let exampleSpaces: [(CGRect, String, CGColor)] = [
    (CGRect(x: 141, y: 143, width: 61, height: 77), "EMPTY", CGColor(red: 0.2, green: 0.92, blue: 0.46, alpha: 1)),
    (CGRect(x: 205, y: 138, width: 83, height: 81), "OCCUPIED", CGColor(red: 1, green: 0.36, blue: 0.22, alpha: 1)),
    (CGRect(x: 338, y: 137, width: 49, height: 82), "OCCUPIED", CGColor(red: 1, green: 0.36, blue: 0.22, alpha: 1)),
    (CGRect(x: 383, y: 139, width: 56, height: 80), "OCCUPIED", CGColor(red: 1, green: 0.36, blue: 0.22, alpha: 1))
]

func overlay(_ buffer: CVPixelBuffer, frame: Int) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer),
          let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
          ) else { return }

    // Flip the drawing coordinates so positions below match the video frame.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(CGColor(gray: 0, alpha: 0.78))
    context.fill(CGRect(x: 0, y: 0, width: width, height: 81))
    context.fill(CGRect(x: 0, y: height - 49, width: width, height: 49))

    // CoreText needs a local flip to stay upright after the frame transform.
    context.saveGState()
    context.translateBy(x: 0, y: 39)
    context.scaleBy(x: 1, y: -1)
    label("SIMULATED DEMO  |  NOT YOLO INFERENCE", at: CGPoint(x: 24, y: 0), size: 26,
          color: CGColor(gray: 1, alpha: 1), in: context)
    context.restoreGState()
    context.saveGState()
    context.translateBy(x: 0, y: 69)
    context.scaleBy(x: 1, y: -1)
    label("GREEN: EXAMPLE EMPTY  /  ORANGE: EXAMPLE OCCUPIED", at: CGPoint(x: 24, y: 0), size: 18,
          color: CGColor(gray: 1, alpha: 1), in: context)
    context.restoreGState()

    let scanWidth: CGFloat = 120
    let scanX = CGFloat((frame * 11) % max(width - Int(scanWidth), 1))
    context.setFillColor(CGColor(red: 0.2, green: 0.75, blue: 1, alpha: 0.17))
    context.fill(CGRect(x: scanX, y: 82, width: scanWidth, height: CGFloat(height - 132)))

    for (rect, _, color) in exampleSpaces {
        context.setStrokeColor(color)
        context.setLineWidth(4)
        context.stroke(rect)
    }

    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(height - 18))
    context.scaleBy(x: 1, y: -1)
    label("Illustrative boxes selected by hand  |  No model weights or predictions", at: CGPoint(x: 24, y: 0),
          size: 19, color: CGColor(gray: 1, alpha: 1), in: context)
    context.restoreGState()
}

guard reader.startReading(), writer.startWriting() else {
    fatalError("Could not start video processing: \(String(describing: reader.error)) \(String(describing: writer.error))")
}
writer.startSession(atSourceTime: .zero)
var frame = 0
while let sample = readerOutput.copyNextSampleBuffer() {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    while !writerInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    overlay(buffer, frame: frame)
    if !adaptor.append(buffer, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample)) {
        fatalError("Video writer failed: \(String(describing: writer.error))")
    }
    frame += 1
}
writerInput.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("Export failed: \(String(describing: writer.error))") }
let posterURL = outputURL.deletingPathExtension().appendingPathExtension("png")
let previewAsset = AVURLAsset(url: outputURL)
let imageGenerator = AVAssetImageGenerator(asset: previewAsset)
let posterFrame = try imageGenerator.copyCGImage(at: CMTime(seconds: 2, preferredTimescale: 600), actualTime: nil)
let poster = NSBitmapImageRep(cgImage: posterFrame)
try poster.representation(using: .png, properties: [:])!.write(to: posterURL)
print("Wrote \(frame) frames to \(outputURL.path)")
print("Wrote poster to \(posterURL.path)")
