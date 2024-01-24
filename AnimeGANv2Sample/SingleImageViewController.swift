//
//  ViewController.swift
//  AnimeGANv2Sample
//
//  Created by Daisuke Majima on 2024/01/20.


import UIKit
import Vision
import PhotosUI
import AVKit

class SingleImageViewController: UIViewController, PHPickerViewControllerDelegate {
    var vnCoreMLModel: VNCoreMLModel!
    var coreMLRequest: VNCoreMLRequest!
    let context = CIContext()
    var originalCIImageSize:CGSize!
    var resizedCIImage:CIImage!

    var imageView = UIImageView()
    var selectInputButton = UIButton()
    var videoProcessingButton = UIButton()
    var realTimeCameraButton = UIButton()
    var saveButton = UIButton()
    var descriptionLabel = UILabel()
    var startTime:Date!

    // MARK: - App Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let sampleUIImage = UIImage(named: "sample"),
              let ciImage = CIImage(image: sampleUIImage) else { return }
        originalCIImageSize = ciImage.extent.size
        imageView.image = sampleUIImage

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupCoreMLRequest()
            self?.startTime = Date()
            self?.inference(ciImage:ciImage)
        }
        setupView()
    }

    // MARK: - ML things
    func setupCoreMLRequest() {
        let mlModelConfig = MLModelConfiguration()
        do {
            let coreMLModel:MLModel = try animeganHayao(configuration: mlModelConfig).model
            let vnCoreMLModel:VNCoreMLModel = try VNCoreMLModel(for: coreMLModel)
            let coreMLRequest:VNCoreMLRequest = VNCoreMLRequest(model: vnCoreMLModel, completionHandler: coreMLRequestCompletionHandler)
            coreMLRequest.imageCropAndScaleOption = .scaleFill
            self.vnCoreMLModel = vnCoreMLModel
            self.coreMLRequest = coreMLRequest
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }
    
    func inference(ciImage:CIImage) {
        do {
            let handler = VNImageRequestHandler(ciImage: ciImage)
            try handler.perform([coreMLRequest])
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }
    
    func coreMLRequestCompletionHandler(request:VNRequest?, error:Error?) {
        guard let result:VNPixelBufferObservation = coreMLRequest.results?.first as? VNPixelBufferObservation else { return }
        let pixelBuffer:CVPixelBuffer = result.pixelBuffer
        postProcess(resultPixelBuffer: pixelBuffer)
    }
    
    func postProcess(resultPixelBuffer:CVPixelBuffer ) {
        let end = Date()
        let inferenceTime = end.timeIntervalSince(startTime)
        let resultCIImage = CIImage(cvPixelBuffer: resultPixelBuffer)
        self.resizedCIImage = resultCIImage.resize(as: originalCIImageSize)
        let resultUIImage = UIImage(ciImage: resizedCIImage)
        upDateResultUI(resultUIImage: resultUIImage, inferenceTime: inferenceTime)
    }
    
    // MARK: User Interactions
    
    @objc func presentPicker() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        self.present(picker, animated: true)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        guard  result.itemProvider.canLoadObject(ofClass: UIImage.self) else { fatalError() }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error  in
            guard let image = image as? UIImage,
                  let safeSelf = self,
                  let correctOrientCIImage = image.getCorrectOrientationCIImage() else { fatalError() }
            safeSelf.originalCIImageSize = correctOrientCIImage.extent.size
            safeSelf.startTime = Date()
            safeSelf.inference(ciImage: correctOrientCIImage)
        }
    }
    
    @objc func realTimeCameraSegue() {
        performSegue(withIdentifier: "realTimeCamera", sender: nil)
    }
    
    @objc func videoProcessingSegue() {
        performSegue(withIdentifier: "videoProcessing", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "realTimeCamera" {
            if let rvc = segue.destination as? RealTimeCameraInferenceViewController {
                rvc.vnCoreMLModel = self.vnCoreMLModel
            }
        } else if segue.identifier == "videoProcessing" {
            if let vvc = segue.destination as? VideoProcessingViewController {
                vvc.vnCoreMLModel = self.vnCoreMLModel
            }
        }
    }
    
    @objc func saveImage() {
        let image = imageView.image!
        guard let cgImage = context.createCGImage(resizedCIImage, from: resizedCIImage.extent) else { fatalError("save error")}
        UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), self, #selector(imageSaved), nil)
    }
    
    @objc func imageSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        } else {
            let ac = UIAlertController(title: NSLocalizedString("saved!",value: "saved!", comment: ""), message: NSLocalizedString("Saved in photo library",value: "Saved in photo library", comment: ""), preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        }
    }
    
    // MARK: - View
    
    func upDateResultUI(resultUIImage:UIImage, inferenceTime:TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.imageView.image = resultUIImage
            self?.descriptionLabel.text = "\(inferenceTime) sec"
        }
    }
    
    func setupView() {
        imageView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height*0.8)
        selectInputButton.frame = CGRect(x: 0, y: view.bounds.height*0.9, width: view.bounds.width*0.25, height: view.bounds.height*0.1)
        realTimeCameraButton.frame = CGRect(x: view.bounds.width * 0.25, y: view.bounds.height*0.9, width: view.bounds.width*0.25, height: view.bounds.height*0.1)
        videoProcessingButton.frame = CGRect(x: view.bounds.width * 0.5, y: view.bounds.height*0.9, width: view.bounds.width*0.25, height: view.bounds.height*0.1)
        saveButton.frame = CGRect(x: view.bounds.width*0.75, y: view.bounds.height*0.9, width: view.bounds.width*0.25, height: view.bounds.height*0.1)
        descriptionLabel.frame = CGRect(x: 0, y: view.bounds.height*0.8, width: view.bounds.width, height: view.bounds.height*0.1)
        
        view.addSubview(imageView)
        view.addSubview(selectInputButton)
        view.addSubview(videoProcessingButton)
        view.addSubview(realTimeCameraButton)
        view.addSubview(saveButton)
        view.addSubview(descriptionLabel)

        imageView.contentMode = .scaleAspectFit
        selectInputButton.setImage(UIImage(systemName: "photo"), for: .normal)
        videoProcessingButton.setImage(UIImage(systemName: "play.rectangle"), for: .normal)
        realTimeCameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        saveButton.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        selectInputButton.backgroundColor = .black
        videoProcessingButton.backgroundColor = .gray
        realTimeCameraButton.backgroundColor = .black
        saveButton.backgroundColor = .gray
        selectInputButton.tintColor = .white
        videoProcessingButton.tintColor = .white
        realTimeCameraButton.tintColor = .white
        saveButton.tintColor = .white
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 2
        descriptionLabel.text = "Core ML model initializing.\nPlease wait few seconds."
        
        selectInputButton.addTarget(self, action: #selector(presentPicker), for: .touchUpInside)
        videoProcessingButton.addTarget(self, action: #selector(videoProcessingSegue), for: .touchUpInside)
        realTimeCameraButton.addTarget(self, action: #selector(realTimeCameraSegue), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveImage), for: .touchUpInside)
    }
}

