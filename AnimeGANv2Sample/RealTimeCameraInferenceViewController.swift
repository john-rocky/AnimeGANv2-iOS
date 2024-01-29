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
            let coreMLRequest = VNCoreMLRequest(model: vnCoreMLModel)
            coreMLRequest.imageCropAndScaleOption = .scaleFill
            self.coreMLRequest = coreMLRequest
            DispatchQueue.main.async { [weak self] in
                self?.descriptionLabel.isHidden = true
            }
        }
    }
    private var coreMLRequest: VNCoreMLRequest?
    
    // capture
    private var captureSession = AVCaptureSession()
    private var captureVideoOutput = AVCaptureVideoDataOutput()
    private let captureAudioOutput = AVCaptureAudioDataOutput()
    
    private enum CameraMode {
        case photo
        case video
    }
    
    private var cameraMode: CameraMode = .photo
    
    // take a photo
    private var takingPhoto = false
    
    // video writing
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
    
    // view
    private var imageView = UIImageView()
    private var descriptionLabel = UILabel()
    private var recordButton = CustomButton()
    private var switchCameraButton = CustomButton()
    private var photoVideoSegmentControl = UISegmentedControl(items: ["photo","video"])
    let largeConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular, scale: .default)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupCaptureSession() // setup caputure session
        setupVideoWriter()
    }
    
    private func predict(pixelBuffer: CVPixelBuffer)->CIImage? {
        guard let coreMLRequest = coreMLRequest else {
            processing = false
            return nil
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,orientation: .right, options: [:])
        do {
            try handler.perform([coreMLRequest])
            guard let result:VNPixelBufferObservation = coreMLRequest.results?.first as? VNPixelBufferObservation else {
                processing = false
                return nil}
            let end = Date()
            let inferenceTime = end.timeIntervalSince(startTime)
            print(inferenceTime)
            let pixelBuffer:CVPixelBuffer = result.pixelBuffer
            let resultCIImage = CIImage(cvPixelBuffer: pixelBuffer)
            let resizedCIImage = resultCIImage.resize(as: videoSize)
            return resizedCIImage
        } catch {
            print("Vision error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: -Video
    
    private func shootPhoto() {
        
    }
    
    private func recordVideo() {
        if isRecording {
            if videoWriter.status == .writing {
                videoWriterVideoInput.markAsFinished()
                videoWriterAudioInput.markAsFinished()
                videoWriter.finishWriting { [weak self] in
                    guard let self = self else { return }
                    let outputURL = self.videoWriter.outputURL
                    saveVideoToPhotoLibrary(url: outputURL, completion: {  success, error in
                        if success {
                            self.presentAlert(title: "video saved!", message: "Saved in photo libraty!")
                        } else {
                            self.presentAlert(title: "failed to save video", message: String(describing: error))
                        }
                    })
                }
            }
        } else {
            if videoWriter.status == .unknown {
                self.videoWriter.startWriting()
                self.videoWriter.startSession(atSourceTime: .zero)
            }
        }
        isRecording.toggle()
        updateRecordingUI()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if let videoDataOutput = output as? AVCaptureVideoDataOutput,
           !processing {
            processing = true
            
            // Proceed to processing only when the previous frame has finished processing
            // process a video frame here
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) { // this is a video frame
                currentSampleBuffer = sampleBuffer
                startTime = Date()
                guard let processedCIImage = predict(pixelBuffer: pixelBuffer) else {
                    return
                }
                
                // Update preview
                updatePreview(processedCIImage: processedCIImage)
                
                if takingPhoto {
                    takingPhoto = false
                    
                }
                
                if isRecording {
                    
                    let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    writeProcessedVideoFrame(processedCIImage: processedCIImage, presentationTimeStamp: presentationTimeStamp)
                }
            }
            processing = false
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
    
    private func saveProcessedImageInPhotoLibrary(processedCIImage: CIImage) {
        guard let cgImage = ciContext.createCGImage(processedCIImage, from: processedCIImage.extent) else { fatalError("save error")}
        let uiImage = UIImage(cgImage: cgImage)
        UIImageWriteToSavedPhotosAlbum(uiImage, self, #selector(imageSaved), nil)
    }
    
    private func writeProcessedVideoFrame(processedCIImage: CIImage, presentationTimeStamp: CMTime) {
        
        // get the time of this video frame.
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
    
    private func updatePreview(processedCIImage: CIImage) {
        let cgImage = ciContext.createCGImage(processedCIImage, from: processedCIImage.extent)
        
        let processedUIImage = UIImage(cgImage: cgImage!)
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
            captureVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
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
        videoWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
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
    
    // MARK: -User Interaction
    
    @objc func recordButtonTapped() {
        switch cameraMode {
        case .photo:
            shootPhoto()
        case .video:
            recordVideo()
        }
    }
    
    @objc private func switchCamera() {
        captureSession.beginConfiguration()

        if let currentCameraInput = captureSession.inputs.first(where: { input in
            if let deviceInput = input as? AVCaptureDeviceInput, deviceInput.device.hasMediaType(.video) {
                return true
            }
            return false
        }) as? AVCaptureDeviceInput {
            captureSession.removeInput(currentCameraInput)

            let newCameraPosition: AVCaptureDevice.Position = (currentCameraInput.device.position == .back) ? .front : .back
            guard let newCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newCameraPosition) else {
                captureSession.commitConfiguration()
                return
            }

            do {
                let newCameraInput = try AVCaptureDeviceInput(device: newCameraDevice)
                if captureSession.canAddInput(newCameraInput) {
                    captureSession.addInput(newCameraInput)
                }
            } catch {
                print("Error adding new camera input: \(error)")
                captureSession.commitConfiguration()
                return
            }
        }

        captureSession.commitConfiguration()
    }
    
    @objc func segmentControlValueChanged(sender: UISegmentedControl) {
        if sender.tag == 0 { // photo
            cameraMode = .photo
        } else { // video
            cameraMode = .video
        }
        switchUITo(mode: cameraMode)
    }
    
    // MARK: -View
    private func setupView() {
        view.backgroundColor = .black
        imageView.frame = view.bounds
        descriptionLabel.frame = CGRect(x: 0, y: view.center.y, width: view.bounds.width, height: 100)
        recordButton.frame = CGRect(x: view.center.x - 50, y: view.bounds.maxY - 200, width: 100, height: 100)
        switchCameraButton.frame = CGRect(x: view.bounds.maxX - 100, y: 100, width: 100, height: 100)
        switchCameraButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera",withConfiguration: largeConfig), for: .normal)
        photoVideoSegmentControl.frame =  CGRect(x: view.center.x - 50, y: view.bounds.maxY - 260, width: 100, height: 40)
        view.addSubview(imageView)
        view.addSubview(descriptionLabel)
        view.addSubview(recordButton)
        view.addSubview(switchCameraButton)
        view.addSubview(photoVideoSegmentControl)
        
        imageView.contentMode = .scaleAspectFit
        descriptionLabel.text = "Core ML model is initializing./n please wait a few seconds..."
        descriptionLabel.numberOfLines = 2
        descriptionLabel.textAlignment = .center
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        photoVideoSegmentControl.addTarget(self, action: #selector(segmentControlValueChanged), for: .valueChanged)
    }
    
    private func updateRecordingUI() {
        if isRecording {
            DispatchQueue.main.async { [weak self] in
                self?.recordButton.tintColor = .red
                self?.switchCameraButton.isHidden = true
                self?.photoVideoSegmentControl.isHidden = true
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.recordButton.tintColor = .white
                self?.switchCameraButton.isHidden = false
                self?.photoVideoSegmentControl.isHidden = false
            }
        }
    }
       
    private func switchUITo(mode: CameraMode) {
        DispatchQueue.main.async { [weak self] in
            switch mode {
            case .photo:
                self?.recordButton.setImage(UIImage(systemName: "camera.circle.fill",withConfiguration: self?.largeConfig), for: .normal)
                self?.switchCameraButton.isHidden = false
            case .video:
                self?.recordButton.setImage(UIImage(systemName: "video.circle.fill",withConfiguration: self?.largeConfig), for: .normal)
                self?.switchCameraButton.isHidden = true
            }
        }
    }
    // completion patern
    
    //    private func inference(pixelBuffer: CVPixelBuffer) {
    //        guard let coreMLRequest = coreMLRequest else {
    //            processing = false
    //            return
    //        }
    //        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,orientation: .right, options: [:])
    //        do {
    //            try handler.perform([coreMLRequest])
    //        } catch {
    //            print("Vision error: \(error.localizedDescription)")
    //            processing = false
    //
    //        }
    //    }
    
    //    func coreMLRequestCompletionHandler(request:VNRequest?, error:Error?) {
    //        guard let result:VNPixelBufferObservation = coreMLRequest?.results?.first as? VNPixelBufferObservation else {
    //            processing = false
    //            return }
    //        let end = Date()
    //        //        let inferenceTime = end.timeIntervalSince(startTime)
    //        let pixelBuffer:CVPixelBuffer = result.pixelBuffer
    //        let resultCIImage = CIImage(cvPixelBuffer: pixelBuffer)
    //        let resizedCIImage = resultCIImage.resize(as: videoSize)
    //        let resultUIImage = UIImage(ciImage: resizedCIImage)
    //        if isRecording {
    //            writeProcessedVideoFrame(processedCIImage: resizedCIImage, sampleBuffer: currentSampleBuffer)
    //        }
    //
    //        DispatchQueue.main.async { [weak self] in
    //            self?.imageView.image = resultUIImage
    //        }
    //        processing = false
    //
    //    }
    
    
}

