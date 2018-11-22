//
//  FolioUtils.swift
//  AEXML
//
//  Created by Dung Le on 11/21/18.
//

import Foundation

class FolioUtils {
    static func getRangy(_ rangies: String, with identifier: String) -> String {
        var rangylist = rangies.split(separator: "|")
        rangylist.remove(at: 0)
        guard let range = (rangylist.filter { (aRangy) -> Bool in
            guard aRangy.split(separator: "$").count > 2 else {
                return false
            }
            return aRangy.split(separator: "$")[2] == identifier
        }.first) else {
            return ""
        }
        let rangeString = String("\(Highlight.typeTextContentWithLine)\(range)")
        return rangeString
    }
    
    // currently, rangy can't serialize the range with contains all images without text
    // example: type:textContent|1000$1000$387753$last-read
    static func rangyIsValid(rangy: String) -> Bool {
        var mRangy = rangy
        if rangy.contains("type:textContent|") {
            mRangy = String(rangy.split(separator: "|").last ?? "")
        }
        if mRangy.split(separator: "$").count <= 1 {
            return false
        }
        return mRangy.split(separator: "$")[0] != mRangy.split(separator: "$")[1]
    }
}
