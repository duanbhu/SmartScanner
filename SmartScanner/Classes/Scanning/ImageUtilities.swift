//
//  ImageUtilities.swift
//  MobileExt
//
//  Created by Duanhu on 2024/3/22.
//

import CoreMedia
import UIKit

class ImageUtilities {
    static func resetSampleBuffer(sampleBuffer: CMSampleBuffer, rect: CGRect, ratio: CGFloat) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!)
        let height = CVPixelBufferGetHeight(imageBuffer!)
        let type = CVPixelBufferGetPixelFormatType(imageBuffer!)
        
        if type == kCVPixelFormatType_32BGRA {
            let top = Int(ceil(rect.minY))
            let rheight = rect.height * ratio
            let rheightInt = Int(rheight) + Int(top)
            
            for index in 0..<height {
                if index < top || index > rheightInt {
                    memset(baseAddress! + index * bytesPerRow, 0xFF, bytesPerRow)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags(rawValue: 0))
    }

    static func cropImageFromSampleBuffer(sampleBuffer: CMSampleBuffer, cropRect: CGRect) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let context = CGContext(data: baseAddress,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo)

        guard let cgImage = context?.makeImage() else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        let croppedCGImage = cgImage.cropping(to: cropRect)
        let croppedImage = UIImage(cgImage: croppedCGImage!)
        return croppedImage
    }
}

extension UIImage {
    func crop(_ cropRect: CGRect) -> UIImage? {
        let originalImage = self
        // 将裁剪矩形转换为图片的坐标系
        let scaledCropRect = CGRect(
            x: cropRect.origin.x * originalImage.scale,
            y: cropRect.origin.y * originalImage.scale,
            width: cropRect.size.width * originalImage.scale,
            height: cropRect.size.height * originalImage.scale
        )
        // 利用 Core Graphics 进行图片裁剪
        if let cgImage = originalImage.cgImage?.cropping(to: scaledCropRect) {
            let croppedImage = UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
            return croppedImage
        }
        return nil
    }
}

