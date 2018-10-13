//
//  FolioRWBook.swift
//  AEXML
//
//  Created by Dung Le on 10/13/18.
//

import Foundation

public protocol FolioRWBook {
    // MARK: Properties
    var id : Int? { get set }
    var isStandalone : Bool? { get set }
    var isbn : String? { get set }
    var title : String? { get set }
    var subtitle : String? { get set }
    var topics : [Int]? { get set }
    var publisher : String? { get set }
    var releaseDate : String? { get set }
    var copyrightYear : Int? { get set }
    var editionNumber : Int? { get set }
    var editionText : String? { get set }
    var pageNumber : Int? { get set }
    var bookDescription : String? { get set }
    var claim : String? { get set }
    var usps : [String]? { get set }
    var keywords : [String]? { get set }
    var highlights : [String]? { get set }
    var fileSize : Int? { get set }
}

