//
//  Highlight.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 11/08/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import RealmSwift

/// A Highlight object
open class Highlight: Object {
    
    public static let typeTextContent: String = "type:textContent"
    public static let typeTextContentWithLine: String = "type:textContent|"
    
    @objc open dynamic var bookId: String?
    @objc open dynamic var content: String?
    @objc open dynamic var contentPost: String?
    @objc open dynamic var contentPre: String?
    @objc open dynamic var date: Date?
    @objc open dynamic var highlightId: String?
    @objc open dynamic var page: Int = 0
    @objc open dynamic var type: Int = 0
    @objc open dynamic var startOffset: Int = -1
    @objc open dynamic var endOffset: Int = -1
    @objc open dynamic var noteForHighlight: String?
    @objc open dynamic var rangy: String?
    @objc open dynamic var serverId: Int = -1
    @objc open dynamic var accountId: Int = -1
    @objc open dynamic var filePath: String?
    @objc open dynamic var isSynced: Bool = false
    @objc open dynamic var numOfTry: Int = 0
    @objc open dynamic var isDeleted: Bool = false
    @objc open dynamic var title: String?

    override open class func primaryKey()-> String {
        return "highlightId"
    }
}

extension Results {
    public func toArray<T>(_ ofType: T.Type) -> [T] {
        return compactMap { $0 as? T }
    }
}
