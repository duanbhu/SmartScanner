//
//  ImagePreprocessor.swift
//  SwiftyCamera
//
//  Created for OCR image preprocessing
//

import UIKit
import CoreImage

/// 图片预处理器
/// 提供多种图片预处理方法以提高 OCR 识别准确度
class ImagePreprocessor {
    
    private static let context = CIContext(options: nil)
    
    // MARK: - 预处理选项
    
    /// 预处理选项
    public struct PreprocessOptions: OptionSet {
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        /// 灰度化
        static let grayscale = PreprocessOptions(rawValue: 1 << 0)
        /// 对比度增强
        static let enhanceContrast = PreprocessOptions(rawValue: 1 << 1)
        /// 锐化
        static let sharpen = PreprocessOptions(rawValue: 1 << 2)
        /// 降噪
        static let denoise = PreprocessOptions(rawValue: 1 << 3)
        /// 二值化
        static let binarize = PreprocessOptions(rawValue: 1 << 4)
        /// 自适应增亮
        static let normalizeExposure = PreprocessOptions(rawValue: 1 << 5)
        /// 缩放放大
        static let upscale = PreprocessOptions(rawValue: 1 << 6)
        /// 透视矫正
        static let perspectiveCorrection = PreprocessOptions(rawValue: 1 << 7)
        
        /// 推荐的 OCR 预处理组合
        static let recommended: PreprocessOptions = [.normalizeExposure, .grayscale, .enhanceContrast, .sharpen]
        
        /// 全部预处理
        static let all: PreprocessOptions = [.normalizeExposure, .grayscale, .enhanceContrast, .sharpen, .denoise, .binarize, .upscale, .perspectiveCorrection]
    }
    
    struct Candidate {
        let name: String
        let image: UIImage
    }
    
    // MARK: - 公共方法
    
    /// 预处理图片以提高 OCR 识别准确度
    /// - Parameters:
    ///   - image: 原始图片
    ///   - options: 预处理选项
    /// - Returns: 预处理后的图片，如果处理失败返回原图
    static func preprocess(_ image: UIImage, options: PreprocessOptions = .recommended) -> UIImage {
        guard var processedImage = makeCIImage(from: image) else {
            return image
        }
        
        // 0. 自动倾斜校正（透视矫正）
        if options.contains(.perspectiveCorrection) {
            processedImage = applyPerspectiveCorrection(to: processedImage)
        }
        
        // 0.5 自适应增亮
        if options.contains(.normalizeExposure) {
            processedImage = applyExposureNormalization(to: processedImage)
        }
        
        // 1. 灰度化
        if options.contains(.grayscale) {
            processedImage = applyGrayscale(to: processedImage)
        }
        
        // 2. 对比度增强
        if options.contains(.enhanceContrast) {
            processedImage = applyContrastEnhancement(to: processedImage)
        }
        
        // 3. 锐化
        if options.contains(.sharpen) {
            processedImage = applySharpen(to: processedImage)
            
            // 3.5 文字加粗（增强细小文字）
            processedImage = applyMorphology(to: processedImage)
        }
        
        // 4. 降噪
        if options.contains(.denoise) {
            processedImage = applyDenoise(to: processedImage)
        }
        
        // 5. 二值化
        if options.contains(.binarize) {
            processedImage = applyBinarization(to: processedImage)
        }
        
        if options.contains(.upscale) {
            processedImage = applyUpscale(to: processedImage)
        }
        
        // 转换回 UIImage
        guard let outputCGImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    /// 生成多份候选图片，供 OCR 融合识别
    static func preprocessCandidates(_ image: UIImage,
                                     baseOptions: PreprocessOptions = .recommended) -> [Candidate] {
        var candidates: [Candidate] = [.init(name: "original", image: image)]
        var seenFingerprints = Set<String>()
        seenFingerprints.insert(fingerprint(for: image))
        
        let optionSets: [(String, PreprocessOptions)] = [
            ("recommended", baseOptions),
            ("detail", [.perspectiveCorrection, .normalizeExposure, .grayscale, .enhanceContrast, .sharpen, .upscale]),
            ("clean", [.normalizeExposure, .grayscale, .enhanceContrast, .denoise, .binarize])
        ]
        
        for (name, options) in optionSets {
            let candidate = preprocess(image, options: options)
            let fingerprint = fingerprint(for: candidate)
            guard !seenFingerprints.contains(fingerprint) else { continue }
            seenFingerprints.insert(fingerprint)
            candidates.append(.init(name: name, image: candidate))
        }
        
        return candidates
    }
    
    // MARK: - 私有预处理方法
    
    private static func makeCIImage(from image: UIImage) -> CIImage? {
        if let cgImage = image.cgImage {
            return CIImage(cgImage: cgImage)
        }
        
        if let ciImage = image.ciImage {
            return ciImage
        }
        
        return nil
    }
    
    /// 灰度化
    private static func applyGrayscale(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIPhotoEffectMono")
        filter?.setValue(image, forKey: kCIInputImageKey)
        return filter?.outputImage ?? image
    }
    
    /// 对比度增强
    private static func applyContrastEnhancement(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(1.5, forKey: kCIInputContrastKey) // 增强对比度
        filter?.setValue(0.1, forKey: kCIInputBrightnessKey) // 轻微增加亮度
        return filter?.outputImage ?? image
    }
    
    /// 锐化
    private static func applySharpen(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CISharpenLuminance")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(0.55, forKey: kCIInputSharpnessKey)
        return filter?.outputImage ?? image
    }
    
    /// 降噪
    private static func applyDenoise(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CINoiseReduction")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(0.02, forKey: "inputNoiseLevel")
        filter?.setValue(0.3, forKey: "inputSharpness")
        return filter?.outputImage ?? image
    }
    
    /// 二值化（黑白化）
    private static func applyBinarization(to image: CIImage) -> CIImage {
        // 先转为灰度
        let grayImage = applyGrayscale(to: image)
        
        // 应用阈值（二值化）
        // Step 1: 提高对比度
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(grayImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(3.0, forKey: kCIInputContrastKey)
        contrastFilter?.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let highContrast = contrastFilter?.outputImage else { return image }
        
        // Step 2: 使用颜色矩阵实现硬阈值
        let threshold: Float = 0.52
        let thresholdFilter = CIFilter(name: "CIColorMatrix")
        thresholdFilter?.setValue(highContrast, forKey: kCIInputImageKey)
        
        // 将像素推向 0 或 1（黑/白）
        let t = threshold
        thresholdFilter?.setValue(CIVector(x: 10, y: 0, z: 0, w: 0), forKey: "inputRVector")
        thresholdFilter?.setValue(CIVector(x: 0, y: 10, z: 0, w: 0), forKey: "inputGVector")
        thresholdFilter?.setValue(CIVector(x: 0, y: 0, z: 10, w: 0), forKey: "inputBVector")
        thresholdFilter?.setValue(CIVector(x: -10 * CGFloat(t), y: -10 * CGFloat(t), z: -10 * CGFloat(t), w: 1), forKey: "inputBiasVector")
        
        return thresholdFilter?.outputImage ?? image
    }
    
    /// 形态学处理（膨胀）增强文字
    private static func applyMorphology(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIMorphologyMaximum")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(0.8, forKey: "inputRadius")
        return filter?.outputImage ?? image
    }
    
    /// 自动倾斜校正（透视矫正）
    private static func applyPerspectiveCorrection(to image: CIImage) -> CIImage {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        
        guard let detector = CIDetector(ofType: CIDetectorTypeRectangle,
                                        context: context,
                                        options: options) else {
            return image
        }
        
        let features = detector.features(in: image)
        guard let rectFeature = features.first as? CIRectangleFeature else {
            return image // 未检测到矩形，直接返回原图
        }
        
        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgPoint: rectFeature.topLeft), forKey: "inputTopLeft")
        filter?.setValue(CIVector(cgPoint: rectFeature.topRight), forKey: "inputTopRight")
        filter?.setValue(CIVector(cgPoint: rectFeature.bottomLeft), forKey: "inputBottomLeft")
        filter?.setValue(CIVector(cgPoint: rectFeature.bottomRight), forKey: "inputBottomRight")
        
        return filter?.outputImage ?? image
    }
    
    private static func applyExposureNormalization(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIExposureAdjust")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(0.35, forKey: kCIInputEVKey)
        return filter?.outputImage ?? image
    }
    
    private static func applyUpscale(to image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return image }
        
        let targetLongestEdge: CGFloat = 1800
        let longestEdge = max(extent.width, extent.height)
        guard longestEdge < targetLongestEdge else { return image }
        
        let scale = targetLongestEdge / longestEdge
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaled = image.transformed(by: transform)
        
        let filter = CIFilter(name: "CILanczosScaleTransform")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(scale, forKey: kCIInputScaleKey)
        filter?.setValue(1.0, forKey: kCIInputAspectRatioKey)
        
        return filter?.outputImage ?? scaled
    }
    
    private static func fingerprint(for image: UIImage) -> String {
        let size = image.size
        return "\(Int(size.width))x\(Int(size.height))-\(image.pngData()?.count ?? 0)"
    }
}
