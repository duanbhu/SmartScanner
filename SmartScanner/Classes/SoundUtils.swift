//
//  SoundUtils.swift
//  MobileExt
//
//  Created by Duanhu on 2024/4/15.
//

import Foundation
import AVFoundation

public class SoundUtils {
    
    /// 震动
    public static func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    public static func beep() {
        // 加载音效文件
        var soundID: SystemSoundID = 0
        let bundle = Bundle.sca_frameworkBundle()
        let path = bundle.path(forResource: "voice_scan", ofType: "caf")
            ?? Bundle.main.path(forResource: "voice_scan", ofType: "caf")
        if let path = path {
            // 将音效文件加载到soundID中
            let url = URL(fileURLWithPath: path)
            AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        }
        AudioServicesPlaySystemSound(soundID)
    }
    
    /// 拍照声音：咔嚓
    public static func snap() {
        AudioServicesPlaySystemSound(1108)
    }
}
