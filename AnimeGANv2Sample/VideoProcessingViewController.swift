//
//  VideoProcessingViewController.swift
//  AnimeGANv2Sample
//
//  Created by 間嶋大輔 on 2024/01/21.
//

import UIKit
import Vision
import AVFoundation
import AVKit
import PhotosUI

class VideoProcessingViewController: UIViewController, PHPickerViewControllerDelegate {
    
    var vnCoreMLModel: VNCoreMLModel! {
        didSet {
            let coreMLRequest = VNCoreMLRequest(model: vnCoreMLModel)
            coreMLRequest.imageCropAndScaleOption = .scaleFill
            coreMLRequest.preferBackgroundProcessing = true
            self.coreMLRequest = coreMLRequest
            DispatchQueue.main.async { [weak self] in
                self?.descriptionLabel.isHidden = true
            }
        }
    }
    var coreMLRequest: VNCoreMLRequest!
    var originalCIImageSize = CGSize.zero
    var descriptionLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        presentPicker()
    }
    
    func performRequest(on image: CIImage) -> CIImage {
        //        guard let coreMLRequest = self.coreMLRequest else { return nil }
        //        let originalCIImageSize = originalCIImageSize
        //        return await withCheckedContinuation { continuation in
        //            DispatchQueue.global(qos: .userInitiated).async {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try requestHandler.perform([coreMLRequest])
            guard let result = coreMLRequest.results?.first as? VNPixelBufferObservation else {
                return image
            }
            let resultCIImage = CIImage(cvPixelBuffer: result.pixelBuffer)
            let resizedCIImage = resultCIImage.resize(as:originalCIImageSize)
            return resizedCIImage
        } catch {
            print("Error performing request: \(error)")
            return image
        }
    }
    
    
    func processVideo(videoURL:URL) {
        let start = Date()
        applyProcessingOnVideo(videoURL: videoURL) { ciImage in
            let processed = self.performRequest(on: ciImage)
            return processed
            
        } _: { err, processedVideoURL in
            let end = Date()
            let diff = end.timeIntervalSince(start)
            print(diff)
            let player = AVPlayer(url: processedVideoURL!)
            DispatchQueue.main.async { [weak self] in
                let controller = AVPlayerViewController()
                controller.player = player
                self?.present(controller, animated: true) {
                    player.play()
                }
            }
        }
    }
    
    private func presentPicker() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .videos
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        self.present(picker, animated: true)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let result = results.first else { return }
        guard let typeIdentifier = result.itemProvider.registeredTypeIdentifiers.first else { return }
        if result.itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] (url, error) in
                if let error = error { print("*** error: \(error)") }
                let start = Date()
                result.itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (url, error) in
                    self?.processVideo(videoURL: url as! URL)
                }
            }
        }
    }
    
    let ciContext = CIContext()
    
    private func applyProcessingOnVideo(videoURL:URL, _ processingFunction: @escaping ((CIImage) -> CIImage?), _ completion: ((_ err: NSError?, _ processedVideoURL: URL?) -> Void)?) {
        var frame:Int = 0
        var isFrameRotated = false
        let asset = AVURLAsset(url: videoURL)
        let duration = asset.duration.value
        let frameRate = asset.preferredRate
        let totalFrame = frameRate * Float(duration)
        let err: NSError = NSError.init(domain: "SemanticImage", code: 999, userInfo: [NSLocalizedDescriptionKey: "Video Processing Failed"])
        guard let writingDestinationUrl: URL  = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("\(Date())" + ".mp4") else { print("nil"); return}
        
        // setup
        
        guard let reader: AVAssetReader = try? AVAssetReader.init(asset: asset) else {
            completion?(err, nil)
            return
        }
        guard let writer: AVAssetWriter = try? AVAssetWriter(outputURL: writingDestinationUrl, fileType: AVFileType.mov) else {
            completion?(err, nil)
            return
        }
        
        // setup finish closure
        
        var audioFinished: Bool = false
        var videoFinished: Bool = false
        let writtingFinished: (() -> Void) = {
            if audioFinished == true && videoFinished == true {
                writer.finishWriting {
                    completion?(nil, writingDestinationUrl)
                }
                reader.cancelReading()
            }
        }
        
        // prepare video reader
        
        let readerVideoOutput: AVAssetReaderTrackOutput = AVAssetReaderTrackOutput(
            track: asset.tracks(withMediaType: AVMediaType.video)[0],
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            ]
        )
        
        reader.add(readerVideoOutput)
        
        // prepare audio reader
        
        var readerAudioOutput: AVAssetReaderTrackOutput!
        if asset.tracks(withMediaType: AVMediaType.audio).count <= 0 {
            audioFinished = true
        } else {
            readerAudioOutput = AVAssetReaderTrackOutput.init(
                track: asset.tracks(withMediaType: AVMediaType.audio)[0],
                outputSettings: [
                    AVSampleRateKey: 44100,
                    AVFormatIDKey:   kAudioFormatLinearPCM,
                ]
            )
            if reader.canAdd(readerAudioOutput) {
                reader.add(readerAudioOutput)
            } else {
                print("Cannot add audio output reader")
                audioFinished = true
            }
        }
        
        // prepare video input
        
        let transform = asset.tracks(withMediaType: AVMediaType.video)[0].preferredTransform
        let radians = atan2(transform.b, transform.a)
        let degrees = (radians * 180.0) / .pi
        
        var writerVideoInput: AVAssetWriterInput
        switch degrees {
        case 90:
            
            self.originalCIImageSize = CGSize(width:asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.height, height: asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.width)
            let rotateTransform = CGAffineTransform(rotationAngle: 0)
            writerVideoInput = AVAssetWriterInput.init(
                mediaType: AVMediaType.video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.height,
                    AVVideoHeightKey: asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.width,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: asset.tracks(withMediaType: AVMediaType.video)[0].estimatedDataRate,
                    ],
                ]
            )
            writerVideoInput.expectsMediaDataInRealTime = false
            
            isFrameRotated = true
            writerVideoInput.transform = rotateTransform
        default:
            self.originalCIImageSize = CGSize(width:asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.width, height: asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.height)

            writerVideoInput = AVAssetWriterInput.init(
                mediaType: AVMediaType.video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.width,
                    AVVideoHeightKey: asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: asset.tracks(withMediaType: AVMediaType.video)[0].estimatedDataRate,
                    ],
                ]
            )
            writerVideoInput.expectsMediaDataInRealTime = false
            isFrameRotated = false
            writerVideoInput.transform = asset.tracks(withMediaType: AVMediaType.video)[0].preferredTransform
        }
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerVideoInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        
        writer.add(writerVideoInput)
        
        
        // prepare writer input for audio
        
        var writerAudioInput: AVAssetWriterInput! = nil
        if asset.tracks(withMediaType: AVMediaType.audio).count > 0 {
            let formatDesc: [Any] = asset.tracks(withMediaType: AVMediaType.audio)[0].formatDescriptions
            var channels: UInt32 = 1
            var sampleRate: Float64 = 44100.000000
            for i in 0 ..< formatDesc.count {
                guard let bobTheDesc: UnsafePointer<AudioStreamBasicDescription> = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc[i] as! CMAudioFormatDescription) else {
                    continue
                }
                channels = bobTheDesc.pointee.mChannelsPerFrame
                sampleRate = bobTheDesc.pointee.mSampleRate
                break
            }
            writerAudioInput = AVAssetWriterInput.init(
                mediaType: AVMediaType.audio,
                outputSettings: [
                    AVFormatIDKey:         kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: channels,
                    AVSampleRateKey:       sampleRate,
                    AVEncoderBitRateKey:   128000,
                ]
            )
            writerAudioInput.expectsMediaDataInRealTime = true
            writer.add(writerAudioInput)
        }
        
        
        // write
        
        let videoQueue = DispatchQueue.init(label: "videoQueue")
        let audioQueue = DispatchQueue.init(label: "audioQueue")
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: CMTime.zero)
        
        // write video
        
        writerVideoInput.requestMediaDataWhenReady(on: videoQueue) {
            while writerVideoInput.isReadyForMoreMediaData {
                autoreleasepool {
                    if let buffer = readerVideoOutput.copyNextSampleBuffer(),let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) {
                        frame += 1
                        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        if isFrameRotated {
                            ciImage = ciImage.oriented(CGImagePropertyOrientation.right)
                        }
                        guard let outCIImage = processingFunction(ciImage) else { print("Video Processing Failed") ; return }
                        
                        let presentationTime = CMSampleBufferGetOutputPresentationTimeStamp(buffer)
                        var pixelBufferOut: CVPixelBuffer?
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &pixelBufferOut)
                        self.ciContext.render(outCIImage, to: pixelBufferOut!)
                        pixelBufferAdaptor.append(pixelBufferOut!, withPresentationTime: presentationTime)
                        
                    } else {
                        writerVideoInput.markAsFinished()
                        DispatchQueue.main.async {
                            videoFinished = true
                            writtingFinished()
                        }
                    }
                }
            }
        }
        if writerAudioInput != nil {
            writerAudioInput.requestMediaDataWhenReady(on: audioQueue) {
                while writerAudioInput.isReadyForMoreMediaData {
                    autoreleasepool {
                        let buffer = readerAudioOutput.copyNextSampleBuffer()
                        if buffer != nil {
                            writerAudioInput.append(buffer!)
                        } else {
                            writerAudioInput.markAsFinished()
                            DispatchQueue.main.async {
                                audioFinished = true
                                writtingFinished()
                            }
                        }
                    }
                }
            }
        }
    }
}
