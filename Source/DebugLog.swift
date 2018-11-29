//
//  DebugLog.swift
//  AEXML
//
//  Created by Dung Le on 11/28/18.
//

import UIKit

public func debugLog<T>(_ object: @autoclosure () -> T, _ file: String = #file, _ function: String = #function, _ line: Int = #line) {
    #if DEBUG
    let value = object()
    let fileURL = (file as NSString).lastPathComponent
    let queue = Thread.isMainThread ? "UI" : "BG"
    
    print("<\(queue)> \(fileURL) \(function)[\(line)]: " + String(describing: value))
    #endif
}
