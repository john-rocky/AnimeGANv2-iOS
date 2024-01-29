//
//  ImageExtensions.swift
//  AnimeGANv2Sample
//
//  Created by 間嶋大輔 on 2024/01/20.
//

import UIKit
import PhotosUI


extension CIImage {
    func resize(as size: CGSize) -> CIImage {
        let selfSize = extent.size
        let transform = CGAffineTransform(scaleX: size.width / selfSize.width, y: size.height / selfSize.height)
        return transformed(by: transform)
    }
    
}


extension CIImage {
    func resizeWithNewAspectRatio(to size: CGSize) -> CIImage? {
        // 新しいサイズに対する幅と高さのスケールファクターを計算
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height

        // 'CILanczosScaleTransform'フィルターを作成
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }

        // フィルターにパラメーターを設定
        filter.setValue(self, forKey: kCIInputImageKey)
        filter.setValue(scaleX, forKey: kCIInputScaleKey)
        filter.setValue(scaleY / scaleX, forKey: kCIInputAspectRatioKey)

        // フィルター処理後の画像を取得
        return filter.outputImage
    }
}


extension UIImage {
        
    func getCorrectOrientationCIImage() -> CIImage? {
        var correctOrientationCIImage:CIImage?
        guard let ciImage =  CIImage(image: self) else { return nil }
        switch self.imageOrientation.rawValue {
        case 1:
            correctOrientationCIImage = ciImage.oriented(CGImagePropertyOrientation.down)
        case 3:
            correctOrientationCIImage = ciImage.oriented(CGImagePropertyOrientation.right)
        default:
            correctOrientationCIImage = ciImage
        }
        return correctOrientationCIImage
    }
}

func saveVideoToPhotoLibrary(url: URL, completion: @escaping (Bool, Error?) -> Void) {
    PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { saved, error in
                DispatchQueue.main.async {
                    if saved {
                        completion(true, nil)
                    } else {
                        completion(false, error)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                completion(false, NSError(domain: "com.yourapp", code: 0, userInfo: [NSLocalizedDescriptionKey: "Access denied to photo library"]))
            }
        }
    }
}

