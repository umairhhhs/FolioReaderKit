//
//  RWLastRead.swift
//  ebook
//
//  Created by Christian Denker on 15.01.18.
//  Copyright © 2018 ZWEIDENKER GmbH. All rights reserved.
//

import Foundation
import RealmSwift

class PageSize {
    var width: CGFloat
    var height: CGFloat
    
    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
}

open class FolioLastRead: Object {
    
    // MARK: Properties
    @objc open dynamic var bookId : Int = -1
    @objc open dynamic var accountId : Int = -1
    @objc open dynamic var filePath : String?
    @objc open dynamic var position : String?
    @objc open dynamic var created: Date?
    @objc open dynamic var modified: Date?
    @objc open dynamic var page: Int = 0
    @objc open dynamic var subPage: Int = 0
    @objc open dynamic var pageSize: String?
    @objc open dynamic var isSynced: Bool = false
    @objc open dynamic var pageOffsetX: CGFloat = 0
    @objc open dynamic var pageOffsetY: CGFloat = 0
    @objc open dynamic var isVertical: Bool = false
    @objc open dynamic var isLandscape: Bool = false
    @objc open dynamic var fontSize: Int = 2
    
    var pageSizeObject: PageSize? {
        guard let sizes = self.pageSize?.split(separator: "x"),
            sizes.count >= 2 else {
            return nil
        }
        let width = ( String.init(sizes[0]) as NSString).floatValue
        let height = ( String.init(sizes[1]) as NSString).floatValue
        return PageSize.init(width: CGFloat(width), height: CGFloat(height))
    }
    
    var rangyId: String? {
        guard let elements = position?.split(separator: "$"),
            elements.count > 2
        else {
            return nil
        }
        return String.init(elements[2])
    }
    
    override open class func primaryKey()-> String {
        return "bookId"
    }
}

extension FolioLastRead {
    public static func lastRead(from bookId: Int) -> FolioLastRead? {
        do {
            let realm = try Realm()
            return realm.object(ofType: FolioLastRead.self, forPrimaryKey: bookId)
        } catch {
            return nil
        }
    }
}
