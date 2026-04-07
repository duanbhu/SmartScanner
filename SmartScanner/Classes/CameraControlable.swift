//
//  CameraControlable.swift
//  SwiftyCamera_Example
//
//  Created by Duanhu on 2024/7/11.
//  Copyright © 2024 CocoaPods. All rights reserved.
//

import UIKit

fileprivate var CameraFlashlightButtonContext: UInt8 = 0
fileprivate var CameraSettingsButtonContext: UInt8 = 0

public protocol CameraControlable: CameraScannable  {
    /// 开启/关闭手电筒的开关
    var flashlightButton: UIButton { get }
    
    /// 设置开关
    var settingsButton: UIButton { get }
}

extension CameraControlable {
    /// 开启/关闭手电筒的开关
    public var flashlightButton: UIButton {
        if let button = objc_getAssociatedObject(self, &CameraFlashlightButtonContext) as? UIButton {
            return button
        } else {
            let button = UIButton(type: .custom)
            
            button.setImage(Icon.navFlashlight.image, for: .normal)
            button.setImage(Icon.navFlashlightPre.image, for: .selected)
            button.addActionBlock { [weak cameraCapturer] sender in
                sender.isSelected = !sender.isSelected
                cameraCapturer?.setTorch(sender.isSelected)
            }
            objc_setAssociatedObject(self, &CameraFlashlightButtonContext, button, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return button
        }
    }
    
    /// 设置开关
    public var settingsButton: UIButton {
        if let button = objc_getAssociatedObject(self, &CameraSettingsButtonContext) as? UIButton {
            return button
        } else {
            let button = UIButton(type: .custom)
            button.setImage(Icon.navSettings.image, for: .normal)
            button.setImage(Icon.navSettings.image, for: .selected)
            objc_setAssociatedObject(self, &CameraSettingsButtonContext, button, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return button
        }
    }
}

extension UIButton {
    // 定义关联的Key
    private struct AssociatedKeys {
        static var actionKey: UInt8 = 0
    }
    func addActionBlock(_ closure: @escaping (_ sender: UIButton) -> Void,
                            for controlEvents: UIControl.Event = .touchUpInside) {
        //把闭包作为一个值 先保存起来
        objc_setAssociatedObject(self, &AssociatedKeys.actionKey, closure, objc_AssociationPolicy.OBJC_ASSOCIATION_COPY)
        //给按钮添加传统的点击事件，调用写好的方法
        self.addTarget(self, action: #selector(my_ActionForTapGesture), for: controlEvents)
    }
    
    @objc private func my_ActionForTapGesture() {
        //获取闭包值
        let obj = objc_getAssociatedObject(self, &AssociatedKeys.actionKey)
        if let action = obj as? (_ sender:UIButton)->() {
            //调用闭包
            action(self)
        }
    }
}
