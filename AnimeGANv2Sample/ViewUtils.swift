//
//  ViewUtils.swift
//  AnimeGANv2Sample
//
//  Created by 間嶋大輔 on 2024/01/29.
//

import Foundation
import UIKit

extension UIViewController {
    func presentAlert(title: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            let ac = UIAlertController(title: NSLocalizedString(title,value: title, comment: ""), message: NSLocalizedString(message,value: message, comment: ""), preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(ac, animated: true)
        }
    }
    
    @objc func imageSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            presentAlert(title: "Save error", message: error.localizedDescription)
        } else {
            presentAlert(title: "saved!", message: "Saved in photo library!")
        }
    }
}

class CustomButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureButton()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureButton()
    }


    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                animateButton()
//                triggerHapticFeedback()
            }
        }
    }

    private func animateButton() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }) { (_) in
            UIView.animate(withDuration: 0.1) {
                self.transform = .identity
            }
        }
    }

    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    private func configureButton() {
        var config = UIButton.Configuration.filled()
        config.imagePlacement = .top
        config.imagePadding = 10
        config.baseBackgroundColor = .clear
        self.configuration = config
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
}
