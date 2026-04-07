//
//  RecognitionResponse.swift
//  SwiftyCamera_Example
//
//  Created by Duanhu on 2024/7/10.
//  Copyright © 2024 CocoaPods. All rights reserved.
//

import Foundation

public class RecognitionResponse {
    /// 条码
    let barCountedSet = NSCountedSet()
    
    /// 二维码
    let qrCountedSet = NSCountedSet()
    
    /// 普通手机号
    let phoneCountedSet = NSCountedSet()
    
    /// 隐私号码
    let privacyCountedSet = NSCountedSet()
    
    /// 虚拟号码
    let virtualCountedSet = NSCountedSet()
    
    var barLastTime: Double = 0
    
    var qrLastTime: Double = 0
    
    func cleanAll() {
        [barCountedSet, phoneCountedSet, virtualCountedSet, privacyCountedSet, qrCountedSet].forEach {
            $0.removeAllObjects()
        }
    }
    
    func addBarcode(_ code: String) {
        // 换另一个单扫描，清除所有数据
        if let most = barCountedSet.mostElement(max: 2), code != most {
            cleanAll()
        }
        // 有些快递单条码遮住一部分，也能识别出来， -- 这个判断不利于识别货架号
        guard code.count > 5 else {
            return
        }
        
        barCountedSet.add(code)
        barLastTime = CFAbsoluteTimeGetCurrent()
    }
    
    func addQrcode(_ code: String) {
        // 换另一个单扫描，清除所有数据
        if let most = qrCountedSet.mostElement(max: 2), code != most {
            checkClean2()
        }
        
        qrCountedSet.add(code)
        qrLastTime = CFAbsoluteTimeGetCurrent()
    }
    
    func checkClean() {
        let end = CFAbsoluteTimeGetCurrent()
        if (end - barLastTime)*1000 > 500 {
            cleanAll()
        }
    }
    
    func checkClean2() {
        let end = CFAbsoluteTimeGetCurrent()
        if (end - qrLastTime)*1000 > 500 {
            cleanAll()
        }
    }
}
