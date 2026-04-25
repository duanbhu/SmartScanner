//
//  ViewController.swift
//  SwiftyCamera
//
//  Created by dbh on 07/10/2024.
//  Copyright (c) 2024 dbh. All rights reserved.
//

import UIKit
import SmartScanner

class ViewController: UIViewController, CameraScanViewable {
    private let pilotAutoResetDelay: TimeInterval = 1.0
    
    private let debugImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        iv.layer.borderColor = UIColor.red.cgColor
        iv.layer.borderWidth = 1
        return iv
    }()
    
    private let resultLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .left
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.text = "试点模式：ImageDetectorUpgrade + AppleEngine\n等待识别结果..."
        return label
    }()
    
    private lazy var pilotDetector: ImageDetector = {
        let options: DetecteOptions = .virtualPhone
        return ImageDetector(options: options, engines: PaddleEngine(options: options))
    }()
    
    private var pendingAutoResetWorkItem: DispatchWorkItem?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraCapturer?.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cameraCapturer?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private lazy var cameraScanView: CameraScanView  = {
        let scanView = CameraScanView(frame: view.bounds)
//            .notes(notes: "请对准手机号扫描", position: .top(offset: 64 + 15))
//            .visibleArea(notesOffset: 25, width: 375 - 32, height: 210)
            .visibleArea(top: 88 + 25, width: 414 - 44, height: 82)
            .notes(notes: "请对准手机号扫描", position: .line(offset: 25))
            .flashingLine()
//            .backgroundMode(.maskClip(isFullScreen: true))
            .backgroundMode(.none)
        return scanView
    }()
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraCapturer?.setRegionRectInPreview(cameraScanView.textScanArea(for: .withinBox))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        view = cameraScanView
        
        DetectorConfig.shared.logEnabled = true

        configRecognize(detector: pilotDetector) { [weak self] result in
            debugPrint("ret: // \(result.phoneOrVirtual())")
            let phoneOrVirtual = result.phoneOrVirtual()
            guard !phoneOrVirtual.isEmpty else { return }
            
            self?.resultLabel.text = "试点模式：ImageDetectorUpgrade + AppleEngine\n识别结果：\(phoneOrVirtual)\n\(Int((self?.pilotAutoResetDelay ?? 1) * 1000))ms 后自动重置"
            SoundUtils.vibrate()
            self?.schedulePilotReset()
        }
        
        let nextButton = UIButton(frame: CGRect(x: 32, y: 500, width: 120, height: 44))
        nextButton.backgroundColor = .red
        nextButton.setTitle("默认扫描页", for: .normal)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.addTarget(self, action: #selector(nextAction), for: .touchUpInside)
        view.addSubview(nextButton)
        
        let resetButton = UIButton(frame: CGRect(x: 164, y: 500, width: 120, height: 44))
        resetButton.backgroundColor = .orange
        resetButton.setTitle("重置试点", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.addTarget(self, action: #selector(resetPilotAction), for: .touchUpInside)
        view.addSubview(resetButton)
        
        // 调试预处理图像展示
        view.addSubview(debugImageView)
        debugImageView.frame = CGRect(x: 16, y: 360, width: 200, height: 120)
        
        view.addSubview(resultLabel)
        resultLabel.frame = CGRect(x: 16, y: 630, width: view.bounds.width - 32, height: 88)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePreprocessedImage(_:)), name: .init("ImagePreprocessor"), object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    var preview: UIView {
        self.view
    }
    
    func isNeedAutoTakePhoto() -> Bool {
        false
    }
    
    @objc func nextAction(_ sender: UIButton) {
        
        ScanItViewController.show(at: self, itType: .phone(options: .virtualPhone)) { ret, _ in
            debugPrint("ret：\(ret)")
        }
    }
    
    @objc func resetPilotAction(_ sender: UIButton) {
        resetPilotDetector(message: "试点模式：ImageDetectorUpgrade + AppleEngine\n已手动重置，等待下一次识别...")
    }
    
    @objc private func handlePreprocessedImage(_ noti: Notification) {
        guard let image = noti.userInfo?["image"] as? UIImage else { return }
        DispatchQueue.main.async {
            self.debugImageView.image = image
        }
    }
    
    deinit {
        pendingAutoResetWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func schedulePilotReset() {
        pendingAutoResetWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.resetPilotDetector(message: "已自动重置，可继续连续扫描...")
        }
        pendingAutoResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pilotAutoResetDelay, execute: workItem)
    }
    
    private func resetPilotDetector(message: String) {
        pendingAutoResetWorkItem?.cancel()
        pendingAutoResetWorkItem = nil
        pilotDetector.reset(detecteOptions: .virtualPhone)
//        resultLabel.text = message
    }
}
