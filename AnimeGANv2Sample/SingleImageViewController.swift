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
    private var vnCoreMLModel: VNCoreMLModel!
    private  var coreMLRequest: VNCoreMLRequest!
    private let context = CIContext()
    private var originalCIImageSize:CGSize!
    private var resizedCIImage:CIImage!

    private var imageView = UIImageView()
    private var imageButton = CustomButton()
    private var videoButton = CustomButton()
    private var cameraButton = CustomButton()
    private var imageLabel = UILabel()
    private var videoLabel = UILabel()
    private var cameraLabel = UILabel()
    private let largeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)

    private var saveButton = UIButton()
    private var descriptionLabel = UILabel()
    private var startTime:Date!

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
        picker.view.subviews.forEach { uiview in
            uiview.backgroundColor  = .black
        }
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
        guard let resizedCIImage = resizedCIImage else { return }
        guard let cgImage = context.createCGImage(resizedCIImage, from: resizedCIImage.extent) else { fatalError("save error")}
        UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), self, #selector(imageSaved), nil)
    }
    
    // MARK: - View
    
    func upDateResultUI(resultUIImage:UIImage, inferenceTime:TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.imageView.image = resultUIImage
            self?.descriptionLabel.text = "It took \(floor(inferenceTime*1000)/1000) sec to process"
        }
    }
    
    func setupView() {
        view.backgroundColor = .black
        imageView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height*0.8)
        imageButton.frame = CGRect(x: view.bounds.width*0.13, y: view.bounds.height*0.83, width: view.bounds.width*0.16, height: view.bounds.width*0.16)
        videoButton.frame = CGRect(x: view.bounds.width * 0.42, y: view.bounds.height*0.83, width: view.bounds.width*0.16, height: view.bounds.width*0.16)

        cameraButton.frame = CGRect(x: view.bounds.width * 0.71, y: view.bounds.height*0.83, width: view.bounds.width*0.16, height: view.bounds.width*0.16)
        imageLabel.frame = CGRect(x: imageButton.center.x-view.bounds.width*0.2/2, y: view.bounds.height*0.87, width: view.bounds.width*0.2, height: view.bounds.height*0.1)
        videoLabel.frame = CGRect(x: videoButton.center.x-view.bounds.width*0.2/2, y: view.bounds.height*0.87, width: view.bounds.width*0.2, height: view.bounds.height*0.1)
        cameraLabel.frame = CGRect(x: cameraButton.center.x-view.bounds.width*0.2/2, y: view.bounds.height*0.87, width: view.bounds.width*0.2, height: view.bounds.height*0.1)
        
        descriptionLabel.frame = CGRect(x: 0, y: view.bounds.height*0.72, width: view.bounds.width, height: view.bounds.height*0.1)
        
        view.addSubview(imageView)
        view.addSubview(imageLabel)
        view.addSubview(videoLabel)
        view.addSubview(cameraLabel)
        view.addSubview(imageButton)
        view.addSubview(videoButton)
        view.addSubview(cameraButton)
        view.addSubview(descriptionLabel)

        imageView.contentMode = .scaleAspectFit
        imageButton.setImage(UIImage(systemName: "photo",withConfiguration: largeConfig), for: .normal)
        videoButton.setImage(UIImage(systemName: "play.rectangle",withConfiguration: largeConfig), for: .normal)
        cameraButton.setImage(UIImage(systemName: "camera",withConfiguration: largeConfig), for: .normal)
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 2
        descriptionLabel.text = "The Core ML model takes a few seconds\n to initialize only on first startup.Please wait."
        descriptionLabel.textColor = .white
        imageButton.addTarget(self, action: #selector(presentPicker), for: .touchUpInside)
        videoButton.addTarget(self, action: #selector(videoProcessingSegue), for: .touchUpInside)
        cameraButton.addTarget(self, action: #selector(realTimeCameraSegue), for: .touchUpInside)
        
        imageLabel.textAlignment = .center
        videoLabel.textAlignment = .center
        cameraLabel.textAlignment = .center
        imageLabel.text = "Image"
        videoLabel.text = "Video"
        cameraLabel.text = "Camera"
        imageLabel.textColor = .white
        videoLabel.textColor = .white
        cameraLabel.textColor = .white

        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveImage))
        navigationItem.rightBarButtonItem = saveButton

        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.navigationBar.tintColor = .white
    }
}


