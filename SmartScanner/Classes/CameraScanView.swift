//
//  CameraScanView.swift
//  SwiftyCamera_Example
//
//  Created by Duanhu on 2024/7/10.
//  Copyright © 2024 CocoaPods. All rights reserved.
//

import UIKit
import QuartzCore

/// The Icon enum provides type-safe access to the included icons.
public enum Icon: String {
    
    case navBack = "icon_nav_back_white"
    case scanLine = "icon_scan_line"
    case scanBox = "icon_scan_box"
    case navSettings = "icon_nav_settings"
    case navFlashlight = "icon_nav_flashlight"
    case navFlashlightPre = "icon_nav_flashlight_pre"
    case photoAlbum = "icon_photo_album_line"
    case photoFlashlight = "icon_photo_flashlight"
    
    /// Returns the associated image.
    public var image: UIImage? {
        let bundle = Bundle.sca_frameworkBundle()
        return UIImage(named: rawValue, in: bundle, compatibleWith: nil) ?? UIImage(named: rawValue)
    }
}

extension CameraScanView {
    // 提示文案的位置
    public enum NotesPosition {
        case top(offset: CGFloat)
        case areaCenter
        case line(offset: CGFloat) // 在红线上方， 偏移 offset
    }
    
    // 背景遮罩
    public enum BackgroundMode {
        case none // 全部高亮，没有遮罩
        case maskClip(isFullScreen: Bool) // 仅识别区域高亮，其余位置为暗色  isFullScreen = true, 宽度适应屏幕
    }
    
    /// 扫描区域
    public enum ScanAreaType {
        case withinBox // 在框内
        case nearLine // 横线附近
    }
}

@objc(SmartScannerCameraScanView)
open class CameraScanView: UIView {
    /// 识别的有效区域
    open lazy var areaImageView: UIImageView  = {
        let imageView = UIImageView()
        imageView.image = Icon.scanBox.image?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = .white
        addSubview(imageView)
        return imageView
    }()
    
    /// 内侧的
    open lazy var insideAreaView: UIImageView  = {
        let imageView = UIImageView()
        imageView.image = Icon.scanBox.image?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = .red
        imageView.isHidden = true
        addSubview(imageView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: lineImageView.centerYAnchor),
            imageView.centerXAnchor.constraint(equalTo: lineImageView.centerXAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            imageView.heightAnchor.constraint(equalToConstant: 82)
        ])
        return imageView
    }()
    
    /// 闪烁的红线
    open lazy var lineImageView: UIImageView  = {
        let imageView = UIImageView()
        imageView.image = Icon.scanLine.image
        imageView.backgroundColor = .red.withAlphaComponent(0.5)
        addSubview(imageView)
        return imageView
    }()
    
    /// 提示的文本
    open lazy var notesLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        return label
    }()
    
    /// 蒙版
    open lazy var backgroundLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor(white: 0, alpha: 0.7).cgColor
        layer.frame = self.bounds
        layer.mask = shapeLayer
        return layer
    }()
    
    /// 蒙版上高亮的区域
    open lazy var shapeLayer: CAShapeLayer = {
        let shapeLayer = CAShapeLayer()
        shapeLayer.fillRule = .evenOdd
        return shapeLayer
    }()
    
    private lazy var areaTopLayoutConstraint: NSLayoutConstraint = {
        return areaImageView.topAnchor.constraint(equalTo: topAnchor, constant: 0)
    }()
    
    // MARK: - data
    
    /// 扫描提示文案
    public var notes: String? {
        didSet {
            notesLabel.text = notes
        }
    }
    
    public var isHiddenInsideArea: Bool = false {
        didSet {
            insideAreaView.isHidden = isHiddenInsideArea
        }
    }
    
    public var areaOffsetTop: CGFloat = -1 {
        didSet {
            guard areaOffsetTop > 0 else {
                return
            }
            areaTopLayoutConstraint.constant = areaOffsetTop
        }
    }
    
    public var backgroundMode: BackgroundMode = .none
    
    /// 高亮部分的区域
    var validRect: CGRect = .zero {
        didSet {
            mask(cropRect: validRect)
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        makeUI()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func makeUI() {
        backgroundColor = .black
        layer.addSublayer(backgroundLayer)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        var maskClipRect = CGRect.zero
        switch backgroundMode {
        case .none:
            break
        case .maskClip(let isFullScreen):
            maskClipRect = areaImageView.frame
            if isFullScreen {
                maskClipRect.origin.x = 0
                maskClipRect.size.width = self.bounds.width
            }
        }
        mask(cropRect: maskClipRect)
    }
    
    func mask(cropRect: CGRect) {
        guard cropRect != .zero else {
            return
        }
        let basicPath = UIBezierPath(rect: self.bounds)
        let maskPath = UIBezierPath(rect: cropRect)
        basicPath.append(maskPath)
        shapeLayer.path = basicPath.cgPath
    }
}

extension CameraScanView {
    /// 增加横线闪烁效果
    public func startFlashing() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 0.5
        animation.repeatCount = .infinity
        animation.autoreverses = true
        lineImageView.layer.add(animation, forKey: nil)
    }
}

extension CameraScanView {
    @discardableResult
    /// 提示语， 如 请对准手机号识别
    /// - Parameters:
    ///   - notes: 提示文案
    ///   - position: 文案位置
    /// - Returns: Self
    public func notes(notes: String, position: NotesPosition) -> Self {
        notesLabel.text = notes
        notesLabel.translatesAutoresizingMaskIntoConstraints = false
        var list: [NSLayoutConstraint] = [
            notesLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            lineImageView.heightAnchor.constraint(equalToConstant: 1)
        ]
        
        switch position {
        case .top(let offset):
            list.append(
                notesLabel.topAnchor.constraint(equalTo: topAnchor, constant: offset)
            )
        case .areaCenter:
            list.append(
                notesLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            )
        case .line(let offset):
            list.append(
                notesLabel.bottomAnchor.constraint(equalTo: lineImageView.topAnchor, constant: -offset)
            )
        }
        NSLayoutConstraint.activate(list)
        return self
    }
    
    @discardableResult
    /// 设置扫描的区域
    /// - Parameter area: 坐标
    /// - Returns: Self
    public func visibleArea(top: CGFloat, width: CGFloat, height: CGFloat) -> Self {
        areaImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            areaTopLayoutConstraint,
            areaImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            areaImageView.widthAnchor.constraint(equalToConstant: width),
            areaImageView.heightAnchor.constraint(equalToConstant: height)
        ])
        areaOffsetTop = top
        return self
    }
    
    @discardableResult
    /// 设置扫描的区域
    /// - Parameter area: 坐标
    /// - Returns: Self
    public func visibleArea(notesOffset: CGFloat, width: CGFloat, height: CGFloat) -> Self {
        areaImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            areaImageView.topAnchor.constraint(equalTo: notesLabel.bottomAnchor, constant: notesOffset),
            areaImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            areaImageView.widthAnchor.constraint(equalToConstant: width),
            areaImageView.heightAnchor.constraint(equalToConstant: height)
        ])
        return self
    }
    
    @discardableResult
    /// 设置扫描的区域
    /// - Parameter area: 坐标
    /// - Returns: Self
    public func visibleArea(top: CGFloat, width: CGFloat, bottomView: UIView, offset: CGFloat) -> Self {
        areaImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            areaTopLayoutConstraint,
            areaImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            areaImageView.widthAnchor.constraint(equalToConstant: width),
            areaImageView.bottomAnchor.constraint(equalTo: bottomView.topAnchor, constant: -offset)
        ])
        areaOffsetTop = top
        return self
    }
    
    @discardableResult
    /// 闪烁的横线
    /// - Parameter offset: 相对areaImageView垂直中心的偏移量，默认是垂直居中
    /// - Returns: Self
    public func flashingLine(offset: CGFloat = 0) -> Self {
        lineImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lineImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            lineImageView.widthAnchor.constraint(equalTo: areaImageView.widthAnchor, multiplier: 0.8),
            lineImageView.heightAnchor.constraint(equalToConstant: 1),
            lineImageView.centerYAnchor.constraint(equalTo: areaImageView.centerYAnchor, constant: offset)
        ])
        startFlashing()
        return self
    }
    
    @discardableResult
    public func isHiddenInsideArea(_ isHidden: Bool) -> Self {
        self.isHiddenInsideArea = isHidden
        return self
    }
    
    @discardableResult
    public func backgroundMode(_ mode: BackgroundMode) -> Self {
        self.backgroundMode = mode
        return self
    }
    
    /// 文字扫描区域
    public func textScanArea(for type: ScanAreaType) -> CGRect {
        switch type {
        case .withinBox:
            return areaImageView.frame
        case .nearLine:
            var rect = lineImageView.frame
            rect.origin.y -= 60
            rect.size.height = 110
            return rect
        }
    }
}
