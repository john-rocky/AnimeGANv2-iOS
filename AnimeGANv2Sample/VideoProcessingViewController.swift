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
        }
    }
    var coreMLRequest: VNCoreMLRequest!
    var originalCIImageSize = CGSize.zero
    var processedVideoURL:URL?
    var descriptionLabel = UILabel()
    var imageView = UIImageView()
    var avPlayerView = AVPlayerView()
    var videoButton = UIButton()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        presentPicker()
        
    }
    
    func performRequest(on image: CIImage) -> CIImage {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try requestHandler.perform([coreMLRequest])
            guard let result = coreMLRequest.results?.first as? VNPixelBufferObservation else {
                return image
            }
            let resultCIImage = CIImage(cvPixelBuffer: result.pixelBuffer)
            let resizedCIImage = resultCIImage.resize(as:originalCIImageSize)
            DispatchQueue.main.async {
                self.imageView.image = UIImage(ciImage: resizedCIImage)
            }
            return resizedCIImage
        } catch {
            print("Error performing request: \(error)")
            return image
        }
    }
    
    
    func processVideo(videoURL:URL) {
        let start = Date()
        DispatchQueue.main.async { [weak self] in
            self?.imageView.isHidden = false
        }
        applyProcessingOnVideo(videoURL: videoURL) { ciImage in
            let processed = self.performRequest(on: ciImage)
            return processed
            
        } completion: { err, processedVideoURL in
            let end = Date()
            let diff = end.timeIntervalSince(start)
            print(diff)
            guard let processedVideoURL = processedVideoURL else { return }
            self.processedVideoURL = processedVideoURL
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.imageView.isHidden = true
                self.avPlayerView.isHidden = false
                self.avPlayerView.loadVideo(url: processedVideoURL)
                self.avPlayerView.play()
            }
        } progressHandler: { progress in
            DispatchQueue.main.async {
                self.descriptionLabel.text = "video processing \(floor(progress*100))%\n\naudio will be played when the processing done"
            }
        }
    }
    
    @objc func saveVideo() {
        if let processedVideoURL = processedVideoURL {
            saveVideoToPhotoLibrary(url: processedVideoURL, completion: {  success, error in
                if success {
                    self.presentAlert(title: "video saved!", message: "Saved in photo libraty!")
                } else {
                    self.presentAlert(title: "failed to save video", message: String(describing: error))
                }
            })
        }
    }
    
    @objc private func presentPicker() {
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
                    DispatchQueue.main.async {
                        self?.descriptionLabel.text = "video processing...\naudio will be played when the processing done"
                    }
                    self?.processVideo(videoURL: url as! URL)
                }
            }
        }
    }
    
    let ciContext = CIContext()
    
    private func applyProcessingOnVideo(videoURL: URL, processingFunction: @escaping ((CIImage) -> CIImage?), completion: ((_ error: NSError?, _ processedVideoURL: URL?) -> Void)?, progressHandler: ((_ progress: Double) -> Void)?) {
        var frame:Int = 0
        var isFrameRotated = false
        let asset = AVURLAsset(url: videoURL)
        
        let duration = asset.duration.value
        let frameRate = asset.tracks(withMediaType: AVMediaType.video).first?.nominalFrameRate ?? 30
        let durationInSeconds = Double(asset.duration.value) / Double(asset.duration.timescale)
        let totalFrames = Int(durationInSeconds * Double(frameRate))
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
                        let progress = Double(frame) / Double(totalFrames)
                        progressHandler?(progress)

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
    
    private func setupView() {
        view.backgroundColor = .black
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        descriptionLabel.frame = CGRect(x: 0, y: view.bounds.height * 0.8, width: view.bounds.width, height: view.bounds.height*0.1)
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 2
        descriptionLabel.text = "select a video using the button above"
        descriptionLabel.textColor = .white
        view.addSubview(descriptionLabel)
        avPlayerView.frame = self.view.bounds
        view.addSubview(self.avPlayerView)
        avPlayerView.isHidden = true
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveVideo))
        let selectButton = UIBarButtonItem(title:"video",style: .plain, target: self, action: #selector(presentPicker))

        navigationItem.rightBarButtonItems = [selectButton,saveButton]
        
    }
}
