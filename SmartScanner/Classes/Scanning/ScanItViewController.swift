//
//  ScanItViewController.swift
//  SwiftyCamera
//
//  Created by Duanhu on 2024/7/19.
//

import UIKit
import Photos

fileprivate var kStatusBarHeight: CGFloat {
    if #available(iOS 13.0, *) {
        let window: UIWindow? = UIApplication.shared.windows.first
        let statusBarHeight = (window?.windowScene?.statusBarManager?.statusBarFrame.height) ?? 0
        return statusBarHeight
    } else {
        // 防止界面没有出来获取为0的情况
        return UIApplication.shared.statusBarFrame.height > 0 ? UIApplication.shared.statusBarFrame.height : 44
    }
}

extension UIColor {
    static var background: UIColor = UIColor(white: 0.8, alpha: 0.6)
}

@objc(SmartScannerScanItViewController)
public class ScanItViewController: UIViewController, CameraScanViewable, CameraControlable, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public enum ItType {
        case barcode // 条形码
        case qrcode // 二维码
        case allcode
        case phone(options: DetecteOptions) // 手机号：仅限普通手机号、虚拟号， 扫描到哪个，就返回哪个
    }
    
    let itType: ItType
    
    /// 返回结果时，是否需要自动获取图片， 默认为 false
    var isNeedAutoImage = false
    
    /// 扫描结果回调
    var callback: ((String, UIImage?) -> ())?
    
    /// 结构化识别结果回调，供桥接层使用
    var detectResultCallback: ((DetectResult) -> Void)?
    
    // MARK: - private lazy var UI
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 18)
        return label
    }()
    
    /// 手电筒
    private lazy var torchButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(Icon.photoFlashlight.image?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.backgroundColor = UIColor(white: 0.8, alpha: 0.4)
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        return button
    }()
    
    /// 相册
    private lazy var albumButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(Icon.photoAlbum.image, for: .normal)
        button.backgroundColor = .background
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
        
    public init(itType: ItType, isNeedAutoImage: Bool = false, callback: ((String, UIImage?) -> Void)? = nil) {
        self.itType = itType
        self.isNeedAutoImage = isNeedAutoImage
        self.callback = callback
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - life cycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        makeUI()
        bindViewModel()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScan()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        switch itType {
        case .barcode, .qrcode, .allcode:
            break
        case .phone:
            cameraCapturer?.setRegionRectInPreview(scanView.textScanArea(for: .nearLine))
        }
    }
    
    // MARK: - make up
    func makeUI() {
        let topHeight = kStatusBarHeight + 44
        self.view = scanView
        
        let backButton = UIButton(frame: CGRect(x: 14, y: kStatusBarHeight, width: 40, height: 40))
        backButton.setImage(Icon.navBack.image, for: .normal)
        backButton.backgroundColor = .background
        backButton.layer.cornerRadius = 10
        backButton.layer.masksToBounds = true
        backButton.addTarget(self, action: #selector(backAction), for: .touchUpInside)
        
        scanView.addSubview(backButton)
        scanView.addSubview(titleLabel)
        
        scanView.addSubview(torchButton)
        scanView.addSubview(albumButton)
        
        torchButton.addActionBlock { [weak cameraCapturer] sender in
            sender.isSelected = !sender.isSelected
            sender.tintColor = sender.isSelected ? .black : .white
            sender.backgroundColor = sender.isSelected ? UIColor(white: 1, alpha: 0.8) : .background
            cameraCapturer?.setTorch(sender.isSelected)
        }
        
        albumButton.addActionBlock { [weak self] sender in
            self?.openPhotoAlbum()
        }
        
        NSLayoutConstraint.activate([
            albumButton.trailingAnchor.constraint(equalTo: scanView.trailingAnchor, constant: -14),
            albumButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -150),
            albumButton.widthAnchor.constraint(equalToConstant: 40),
            albumButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        NSLayoutConstraint.activate([
            torchButton.leadingAnchor.constraint(equalTo: scanView.leadingAnchor, constant: 14),
            torchButton.centerYAnchor.constraint(equalTo: albumButton.centerYAnchor),
            torchButton.widthAnchor.constraint(equalTo: albumButton.widthAnchor),
            torchButton.heightAnchor.constraint(equalTo: albumButton.heightAnchor)
        ])
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        switch itType {
        case .barcode:
            detector.reset(detecteOptions: .barcode)
            titleLabel.text = "扫描条形码"
        case .qrcode:
            detector.reset(detecteOptions: .qrcode)
            titleLabel.text = "扫描二维码"
        case .allcode:
            detector.reset(detecteOptions: [.barcode, .qrcode])
            titleLabel.text = "扫描二维码/条形码"
        case .phone(let options):
            albumButton.isHidden = true
            configTextUI(topHeight: topHeight)
            detector.reset(detecteOptions: options)
        }
    }
    
    func configTextUI(topHeight: CGFloat) {
        titleLabel.text = "扫一扫"
        scanView.notes(notes: "请将手机号靠近红线", position: .top(offset: topHeight + 26))
            .visibleArea(notesOffset: 15, width: view.bounds.width - 44, height: 82)
            .flashingLine()
            .backgroundMode(.maskClip(isFullScreen: false))
    }
    
    func bindViewModel() {
        configRecognize { [weak self] ret in
            guard let self = self else { return }
            self.handle(ret: ret)
        }
    }
    
    @objc func backAction(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func handle(ret: DetectResult) {
        switch itType {
        case .barcode:
            if let barcode = ret.barcode {
                finish(with: ret, content: barcode)
            }
        case .qrcode:
            if let qrcode = ret.qrcode {
                finish(with: ret, content: qrcode)
            }
        case .phone:
            let phone = ret.phoneOrVirtual()
            if !phone.isEmpty {
                finish(with: ret, content: phone)
            }
        case .allcode:
            if let barcode = ret.barcode {
                finish(with: ret, content: barcode)
            } else if let qrcode = ret.qrcode {
                finish(with: ret, content: qrcode)
            }
        }
    }
    
    // MARK: - Photo Album
    private func openPhotoAlbum() {
        stopScan()
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        
        imagePicker.providesPresentationContextTransitionStyle = true
        imagePicker.definesPresentationContext = true
        imagePicker.modalPresentationStyle = .overCurrentContext
        
        present(imagePicker, animated: false, completion: nil)
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: false, completion: nil)
        
        guard let selectedImage = info[.originalImage] as? UIImage else { return }
        processSelectedImage(selectedImage)
        startScanning()
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: false, completion: nil)
        startScanning()
    }
    
    /// 选择账号后
    private func processSelectedImage(_ image: UIImage) {
        detector.recognize(image: image) { [weak self] ret in
            guard let self = self else { return }
            self.handle(ret: ret)
        }
    }
    
    // MARK: - delegate
    public func isNeedAutoTakePhoto() -> Bool { isNeedAutoImage }
    
    // MARK: - public
    @discardableResult
    public func show(at viewController: UIViewController?) -> Self {
        providesPresentationContextTransitionStyle = true
        definesPresentationContext = true
        modalPresentationStyle = .overCurrentContext
        viewController?.present(self, animated: true)
        return self
    }
    
    public static func show(at viewController: UIViewController?, itType: ItType, isNeedAutoImage: Bool = false, callback: ((String, UIImage?) -> Void)? = nil) {
        let vc = ScanItViewController(itType: itType, isNeedAutoImage: isNeedAutoImage, callback: callback)
        vc.show(at: viewController)
    }
}

extension ScanItViewController {
    private func finish(with result: DetectResult, content: String) {
        dismiss(with: content, image: result.picture, result: result)
    }
    
    private func dismiss(with barcode: String, image: UIImage? = nil, result: DetectResult? = nil) {
        DispatchQueue.main.async {
            SoundUtils.vibrate()
            self.callback?(barcode, image)
            if let result = result {
                self.detectResultCallback?(result)
            }
            self.dismiss(animated: true, completion: nil)
        }
    }
}
