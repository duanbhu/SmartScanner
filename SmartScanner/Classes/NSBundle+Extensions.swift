//
//  NSBundle+Extensions.swift
//  SwiftMessages
//
//  Created by Timothy Moose on 8/8/16.
//  Copyright © 2016 SwiftKick Mobile LLC. All rights reserved.
//

import Foundation

private class BundleToken {}

extension Bundle {
    // This is copied method from SPM generated Bundle.module for CocoaPods support
    static func sca_frameworkBundle() -> Bundle {
        let currentBundle = Bundle(for: BundleToken.self)

        // CocoaPods static frameworks keep resources inside the framework bundle.
        if currentBundle.bundleURL.pathExtension == "framework" {
            return currentBundle
        }

        let candidates = [
            // Bundle should be present here when the package is linked into an App.
            Bundle.main.resourceURL,

            // Bundle should be present here when the package is linked into a framework.
            currentBundle.resourceURL,

            // For command-line tools.
            Bundle.main.bundleURL,
        ]

        let bundleNames = [
            // For Swift Package Manager
            "SmartScanner_SmartScanner",

            // For Carthage
            "SmartScanner",
        ]

        for bundleName in bundleNames {
            for candidate in candidates {
                let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
                if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                    return bundle
                }
            }
        }
        return currentBundle
    }
}
