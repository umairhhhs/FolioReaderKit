//
//  SearchDB.swift
//  ebook
//
//  Created by Christian Denker on 07.06.17.
//  Copyright © 2017 ZWEIDENKER GmbH. All rights reserved.
//

import UIKit
import SQLite

class FolioSearchDBResult {
    let fileName: String
    let path: String
    init(fileName: String, path: String) {
        self.fileName = fileName
        self.path = path
    }
}

class FolioSearchDBSectionResult {
    var fileName: String = ""
    var dbResults: [FolioSearchDBResult] = []
    var resource: FRResource?
    var pageIndex: Int = -1
    var title: String = ""
    var results: [FolioSearchResult] = []
}

extension FolioSearchDBSectionResult: Equatable {
    static func == (lhs: FolioSearchDBSectionResult, rhs: FolioSearchDBSectionResult) -> Bool {
        return lhs.fileName == rhs.fileName
    }
}

class FolioSearcher: NSObject {

    func search(term: String, bookId: String) -> [FolioSearchDBSectionResult]? {
        guard let path = Bundle.main.path(forResource: bookId, ofType: "db") else {
            return nil
        }
        guard let db = try? Connection(path, readonly: true) else {
            return nil
        }
        guard let dbresult = try? db.prepare("SELECT filename, path FROM structure WHERE docid IN (SELECT docid FROM epub WHERE epub MATCH '\"\(term)*\"')") else {
            return nil
        }
        var results : [FolioSearchDBSectionResult] = []
        for row in dbresult {
            guard row.count >= 2,
                let fileName = row[0] as? String, !fileName.isEmpty,
                let path = row[1] as? String, !path.isEmpty
            else {
                continue
            }
            let result = FolioSearchDBResult.init(fileName: fileName, path: path)
            if let index = results.firstIndex(where: { $0.fileName == fileName }) {
                let section = results[index]
                section.dbResults.append(result)
                results[index] = section
            } else {
                let sectionResult = FolioSearchDBSectionResult.init()
                sectionResult.fileName = fileName
                sectionResult.dbResults.append(result)
                results.append(sectionResult)
            }
        }
        return results
    }
    
}
