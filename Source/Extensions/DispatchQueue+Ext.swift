//
//  DispatchQueue+Ext.swift
//  ebook
//
//  Created by Dung Le on 10/9/18.
//  Copyright © 2018 DB Rent GmbH. All rights reserved.
//

import Foundation

extension DispatchQueue {
    static func runTaskOnMainThread(_ block: @escaping ()->()) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
}
