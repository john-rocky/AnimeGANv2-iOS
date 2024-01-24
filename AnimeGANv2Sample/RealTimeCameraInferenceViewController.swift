//
//  RealTimeCameraInferenceViewController.swift
//  AnimeGANv2Sample
//
//  Created by 間嶋大輔 on 2024/01/21.
//

import UIKit
import Vision
import AVFoundation
import Photos

class RealTimeCameraInferenceViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    var vnCoreMLModel: VNCoreMLModel! {
        didSet {
            let coreMLRequest = VNCoreMLRequest(model: vnCoreMLModel, completionHandler: coreMLRequestCompletionHandler)
            coreMLRequest.imageCropAndScaleOption = .scaleFill
            self.coreMLRequest = coreMLRequest
            DispatchQueue.main.async { [weak self] in
                self?.descriptionLabel.isHidden = true
            }
        }
    }
    private var coreMLRequest: VNCoreMLRequest?
    
    // Capture
    private var captureSession = AVCaptureSession()
    private var captureVideoOutput = AVCaptureVideoDataOutput()
    private let captureAudioOutput = AVCaptureAudioDataOutput()
    
    // Video Writing
    private var videoWriter:AVAssetWriter!
    private var videoWriterVideoInput:AVAssetWriterInput!
    private var videoWriterPixelBufferAdaptor:AVAssetWriterInputPixelBufferAdaptor!
    private var videoWriterAudioInput:AVAssetWriterInput!
    
    private var videoSize: CGSize = .zero
    private var processing:Bool = false
    private var currentSampleBuffer:CMSampleBuffer!
    private let ciContext = CIContext()
    private var isRecording = false
    private var startTime:Date!
    private var recordingStartTime:CMTime?
    
    // View
    private var imageView = UIImageView()
    private var descriptionLabel = UILabel()
    private var recordButton = UIButton()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupCaptureSession() // setup caputure session
        setupVideoWriter()
    }
    
    private func inference(pixelBuffer: CVPixelBuffer) {
        guard let coreMLRequest = coreMLRequest else {
            processing = false
            return
        }
        processing = true
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,orientation: .right, options: [:])
        do {
            try handler.perform([coreMLRequest])
        } catch {
            print("Vision error: \(error.localizedDescription)")
        }
    }
    
    func coreMLRequestCompletionHandler(request:VNRequest?, error:Error?) {
        guard let result:VNPixelBufferObservation = coreMLRequest?.results?.first as? VNPixelBufferObservation else {
            processing = false
            return }
        let end = Date()
        let inferenceTime = end.timeIntervalSince(startTime)
        let pixelBuffer:CVPixelBuffer = result.pixelBuffer
        let resultCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let resizedCIImage = resultCIImage.resize(as: videoSize)
        let resultUIImage = UIImage(ciImage: resizedCIImage)
        if isRecording {
            
            let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(currentSampleBuffer)
            let duration = CMSampleBufferGetDuration(currentSampleBuffer)
            
            
            print(videoWriter.status.rawValue)
            if videoWriter.status == .unknown {
                
                if videoWriter.startWriting() {
                    recordingStartTime = presentationTimeStamp
                    videoWriter.startSession(atSourceTime: presentationTimeStamp)
                }
            }
            
            if self.videoWriter.status == .writing,
               self.videoWriterVideoInput.isReadyForMoreMediaData == true {
                var pixelBufferOut: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, videoWriterPixelBufferAdaptor.pixelBufferPool!, &pixelBufferOut)
                self.ciContext.render(resizedCIImage, to: pixelBufferOut!)
                let spanTime = CMTimeSubtract(recordingStartTime!, presentationTimeStamp)
                self.videoWriterPixelBufferAdaptor.append(pixelBufferOut!, withPresentationTime: presentationTimeStamp)
            }
            
        }
        
        processing = false
        
        DispatchQueue.main.async { [weak self] in
            self?.imageView.image = resultUIImage
        }
    }
    
    // MARK: -Video
    
    @objc func recordVideo() {
        if isRecording {
            if videoWriter.status == .writing {
                videoWriterVideoInput.markAsFinished()
                videoWriterAudioInput.markAsFinished()
                videoWriter.finishWriting { [weak self] in
                    guard let self = self else { return }
                    let outputURL = self.videoWriter.outputURL
                    self.saveVideoToPhotoLibrary(url: outputURL)
                }
            }
        } else {
            if videoWriter.status == .unknown {
//                DispatchQueue.global(qos: .userInitiated).async {
                    print("tapped")
                    self.videoWriter.startWriting()
                    print("startWriting")

                    self.videoWriter.startSession(atSourceTime: .zero)
                    print("startSession")

//                }
            }
        }
        isRecording.toggle()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        if let videoDataOutput = output as? AVCaptureVideoDataOutput,
           !processing {
            processing = true

            // Proceed to processing only when the previous frame has finished processing
            // process a video frame here
            
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) { // this is a video frame
                
                //               let processedCIImage = processVideoFrame(pixelBuffer: pixelBuffer) {
                
                // Update preview
                updatePreview(processedCIImage: CIImage(cvPixelBuffer: pixelBuffer))
                
                if isRecording {
                    //                        DispatchQueue.global(qos: .userInitiated).async {

                    let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    print(presentationTimeStamp)
                    let duration = CMSampleBufferGetDuration(sampleBuffer)
//                    if videoWriter.status == .unknown {
//                            self.videoWriter.startWriting()
//                            self.videoWriter.startSession(atSourceTime: presentationTimeStamp)
////                        }
//                        
//                    }
                    print(videoWriter.status.rawValue)
//                    if self.videoWriter.status == .writing,
//                       self.videoWriterVideoInput.isReadyForMoreMediaData == true {
                        
                        // CIImage -> CVPixelBuffer
//                        var processedPixelBuffer: CVPixelBuffer?
//                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, videoWriterPixelBufferAdaptor.pixelBufferPool!, &processedPixelBuffer)
//                        self.ciContext.render(processedCIImage, to: processedPixelBuffer!)
//                        guard let processedPixelBuffer = processedPixelBuffer else { return }
                        
                        // write
//                        self.videoWriterPixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTimeStamp)
//                    }
                    
                    writeProcessedVideoFrame(processedCIImage: CIImage(cvPixelBuffer: pixelBuffer), sampleBuffer: sampleBuffer)
                }
            }
            processing = false
            //            currentSampleBuffer = sampleBuffer
            //            startTime = Date()
            //            inference(pixelBuffer: pixelBuffer)
            
        } else if let audioDataOutput = output as? AVCaptureAudioDataOutput {
            if isRecording ,
            let recordingStartTime = recordingStartTime{
                if videoWriterAudioInput.isReadyForMoreMediaData,
                   videoWriter.status == .writing {
                    var copyBuffer : CMSampleBuffer?
                    var count: CMItemCount = 1
                    var info = CMSampleTimingInfo()
                    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)
                    info.presentationTimeStamp = CMTimeSubtract(info.presentationTimeStamp, recordingStartTime)
                    CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,sampleBuffer: sampleBuffer,sampleTimingEntryCount: 1,sampleTimingArray: &info,sampleBufferOut: &copyBuffer)

                    videoWriterAudioInput.append(copyBuffer!)
                }
            }
            
        }
    }
    
    func writeProcessedVideoFrame(processedCIImage: CIImage, sampleBuffer: CMSampleBuffer) {
        
        // get the time of this video frame.
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if self.videoWriter.status == .writing,
           self.videoWriterVideoInput.isReadyForMoreMediaData == true {
            if recordingStartTime == nil {
                self.recordingStartTime = presentationTimeStamp
            }

            // CIImage -> CVPixelBuffer
            var processedPixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, videoWriterPixelBufferAdaptor.pixelBufferPool!, &processedPixelBuffer)
            self.ciContext.render(processedCIImage, to: processedPixelBuffer!)
            guard let processedPixelBuffer = processedPixelBuffer else { return }
            let time = CMTimeSubtract(presentationTimeStamp, recordingStartTime!)
            // write
            self.videoWriterPixelBufferAdaptor.append(processedPixelBuffer, withPresentationTime: time)
        }
    }
    
    func processVideoFrame(pixelBuffer: CVPixelBuffer) -> CIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciFilter = CIFilter(name: "CIEdgeWork", parameters: [kCIInputImageKey: ciImage])
        guard let processedCIImage = ciFilter?.outputImage else {
            return nil
        }
        return processedCIImage
    }
    
    func updatePreview(processedCIImage: CIImage) {
        
        let processedUIImage = UIImage(ciImage: processedCIImage)
        DispatchQueue.main.async {
            self.imageView.image = processedUIImage
        }
    }
    
    private func setupCaptureSession() {
        
        do {
            // video input
            let captureDevice:AVCaptureDevice = AVCaptureDevice.default(for: .video)!
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            let dimensions = CMVideoFormatDescriptionGetDimensions(captureDevice.activeFormat.formatDescription)
            videoSize = CGSize(width: CGFloat(dimensions.height), height: CGFloat(dimensions.width))
            
            // video output
            captureVideoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            captureVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
            if captureSession.canAddOutput(captureVideoOutput) {
                captureSession.addOutput(captureVideoOutput)
            }
            
            // audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            }
            
            // audio output
            captureAudioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
            if captureSession.canAddOutput(captureAudioOutput) {
                captureSession.addOutput(captureAudioOutput)
            }
            // start session
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        } catch {
            print("Error setting up capture session: \(error.localizedDescription)")
        }
    }
    

    private func setupVideoWriter() {
        if recordingStartTime != nil {
            recordingStartTime = nil
        }
        // set writing destination url
        guard let outputURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("video.mov") else { fatalError() }
        try? FileManager.default.removeItem(at: outputURL)
        
        // initialize video writer
        videoWriter = try! AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // set video input
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height
        ]
        videoWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: captureVideoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov))
        videoWriterVideoInput.expectsMediaDataInRealTime = true
        
        // use adaptor for write processed pixelbuffer
        videoWriterPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterVideoInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        
        // set audio input
        let audioOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]
        videoWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
        videoWriterAudioInput.expectsMediaDataInRealTime = true
        
        if videoWriter.canAdd(videoWriterVideoInput) {
            videoWriter.add(videoWriterVideoInput)
        }
        if videoWriter.canAdd(videoWriterAudioInput) {
            videoWriter.add(videoWriterAudioInput)
        }
    }
    
    func saveVideoToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { saved, error in
                    DispatchQueue.main.async {
                        if saved {
                            print("Video saved in photo library")
                            self.setupVideoWriter()
                        } else {
                            print("Failed saving: \(String(describing: error))")
                        }
                    }
                }
            } else {
                print("フォトライブラリへのアクセスが拒否されました")
            }
        }
    }
    
    // MARK: -View
    private func setupView() {
        imageView.frame = view.bounds
        descriptionLabel.frame = CGRect(x: 0, y: view.center.y, width: view.bounds.width, height: 100)
        recordButton.frame = CGRect(x: view.center.x - 50, y: view.bounds.maxY - 150, width: 100, height: 100)
        
        view.addSubview(imageView)
        view.addSubview(descriptionLabel)
        view.addSubview(recordButton)
        
        imageView.contentMode = .scaleAspectFit
        descriptionLabel.text = "Core ML model is initializing./n please wait a few seconds..."
        descriptionLabel.numberOfLines = 2
        descriptionLabel.textAlignment = .center
        recordButton.setImage(UIImage(systemName: "video.circle.fill"), for: .normal)
        recordButton.addTarget(self, action: #selector(recordVideo), for: .touchUpInside)
    }
    
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destination.
     // Pass the selected object to the new view controller.
     }
     */
    
}
