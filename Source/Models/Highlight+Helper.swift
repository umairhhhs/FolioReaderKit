//
//  Highlight+Helper.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 06/07/16.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import RealmSwift

/**
 HighlightStyle type, default is .Yellow.
 */
public enum HighlightStyle: Int {
    case yellow
    case green
    case blue
    case pink
    case underline
    
    var name: String {
        switch self {
        case .yellow: return "yellow"
        case .green: return "green"
        case .blue: return "blue"
        case .pink: return "pink"
        case .underline: return "underline"
        }
    }

    public init () {
        // Default style is `.yellow`
        self = .yellow
    }
    
    public static func name(from value: Int) -> String {
        guard let style = HighlightStyle.init(rawValue: value) else {
            return HighlightStyle.yellow.name
        }
        return style.name
    }
    
    public static func style(from string: String) -> HighlightStyle {
        if string.contains(HighlightStyle.green.name) {
            return .green
        }
        if string.contains(HighlightStyle.blue.name) {
            return .blue
        }
        if string.contains(HighlightStyle.pink.name) {
            return .pink
        }
        if string.contains(HighlightStyle.underline.name) {
            return .underline
        }
        return .yellow
    }

    /**
     Return HighlightStyle for CSS class.
     */
    public static func styleForClass(_ className: String) -> HighlightStyle {
        switch className {
        case "highlight-yellow":    return .yellow
        case "highlight-green":     return .green
        case "highlight-blue":      return .blue
        case "highlight-pink":      return .pink
        case "highlight-underline": return .underline
        default:                    return .yellow
        }
    }

    /**
     Return CSS class for HighlightStyle.
     */
    public static func classForStyle(_ style: Int) -> String {

        let enumStyle = (HighlightStyle(rawValue: style) ?? HighlightStyle())
        switch enumStyle {
        case .yellow:       return "highlight-yellow"
        case .green:        return "highlight-green"
        case .blue:         return "highlight-blue"
        case .pink:         return "highlight-pink"
        case .underline:    return "highlight-underline"
        }
    }

    /// Color components for the style
    ///
    /// - Returns: Tuple of all color compnonents.
    private func colorComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch self {
        case .yellow:       return (red: 255, green: 235, blue: 107, alpha: 0.9)
        case .green:        return (red: 192, green: 237, blue: 114, alpha: 0.9)
        case .blue:         return (red: 173, green: 216, blue: 255, alpha: 0.9)
        case .pink:         return (red: 255, green: 176, blue: 202, alpha: 0.9)
        case .underline:    return (red: 240, green: 40, blue: 20, alpha: 0.6)
        }
    }

    /**
     Return CSS class for HighlightStyle.
     */
    public static func colorForStyle(_ style: Int, nightMode: Bool = false) -> UIColor {
        let enumStyle = (HighlightStyle(rawValue: style) ?? HighlightStyle())
        let colors = enumStyle.colorComponents()
        return UIColor(red: colors.red/255, green: colors.green/255, blue: colors.blue/255, alpha: (nightMode ? colors.alpha : 1))
    }
}

/// Completion block
public typealias Completion = (_ error: NSError?) -> ()

extension Highlight {
    
    /// Save a Highlight with completion block
    ///
    /// - Parameters:
    ///   - readerConfig: Current folio reader configuration.
    ///   - completion: Completion block.
    public func persist(withConfiguration readerConfig: FolioReaderConfig, completion: Completion? = nil) {
        do {
            let realm = try Realm(configuration: readerConfig.realmConfiguration)
            realm.beginWrite()
            realm.add(self, update: true)
            try realm.commitWrite()
            completion?(nil)
        } catch let error as NSError {
            print("Error on persist highlight: \(error)")
            completion?(error)
        }
    }

//    public func addRangy(withConfiguration readerConfig: FolioReaderConfig, id: String, rangy: String) {
//        do {
//            let realm = try Realm(configuration: readerConfig.realmConfiguration)
//            realm.beginWrite()
//            self.rangy = rangy
//            self.highlightId = id
//            try realm.commitWrite()
//        } catch let error as NSError {
//            print("Error on persist highlight: \(error)")
//        }
//    }
    
    /// Remove a Highlight. Don't really delete it. Just mark is as deleted
    ///
    /// - Parameter readerConfig: Current folio reader configuration.
    public func remove(withConfiguration readerConfig: FolioReaderConfig) {
        guard let realm = try? Realm(configuration: readerConfig.realmConfiguration) else {
            return
        }
        do {
            try realm.write {
                self.isSynced = false
                self.isDeleted = true
                try realm.commitWrite()
            }
        } catch let error as NSError {
            print("Error on remove highlight: \(error)")
        }
    }

    /// Remove a Highlight by ID. Don't really delete it. Just mark is as deleted
    ///
    /// - Parameters:
    ///   - readerConfig: Current folio reader configuration.
    ///   - highlightId: The ID to be removed
    public static func removeById(withConfiguration readerConfig: FolioReaderConfig, highlightId: String) {
        var highlight: Highlight?
        let predicate = NSPredicate(format:"highlightId = %@", highlightId)

        do {
            let realm = try Realm(configuration: readerConfig.realmConfiguration)
            highlight = realm.objects(Highlight.self).filter(predicate).toArray(Highlight.self).first
            highlight?.remove(withConfiguration: readerConfig)
        } catch let error as NSError {
            print("Error on remove highlight by id: \(error)")
        }
    }
    
    /// Return a Highlight by ID
    ///
    /// - Parameter:
    ///   - readerConfig: Current folio reader configuration.
    ///   - highlightId: The ID to be removed
    ///   - page: Page number
    /// - Returns: Return a Highlight
    public static func getById(withConfiguration readerConfig: FolioReaderConfig, highlightId: String) -> Highlight? {
        var highlight: Highlight?
        let predicate = NSPredicate(format:"highlightId = %@", highlightId)
        do {
            let realm = try Realm(configuration: readerConfig.realmConfiguration)
            highlight = realm.objects(Highlight.self).filter(predicate).toArray(Highlight.self).first
            return highlight
        } catch let error as NSError {
            print("Error getting Highlight : \(error)")
            return nil
        }
    }

    
    /// Update a Highlight by ID
    ///
    /// - Parameters:
    ///   - readerConfig: Current folio reader configuration.
    ///   - highlightId: The ID to be removed
    ///   - type: The `HighlightStyle`
    public static func updateById(withConfiguration readerConfig: FolioReaderConfig, highlightId: String, rangy: String) {
        var highlight: Highlight?
        let predicate = NSPredicate(format:"highlightId = %@", highlightId)
        do {
            let realm = try Realm(configuration: readerConfig.realmConfiguration)
            highlight = realm.objects(Highlight.self).filter(predicate).toArray(Highlight.self).first
            realm.beginWrite()
            highlight?.isSynced = false
            highlight?.rangy = rangy
            highlight?.type = styleForClass(forRangy: rangy)
            try realm.commitWrite()
            
        } catch let error as NSError {
            print("Error on updateById: \(error)")
        }

    }
    
    /// Update a Highlight
    public func update(note: String, withConfiguration readerConfig: FolioReaderConfig) {
        guard let realm = try? Realm(configuration: readerConfig.realmConfiguration) else {
            return
        }
        do {
            try realm.write {
                self.noteForHighlight = note
                self.isSynced = false
                try realm.commitWrite()
            }
        } catch let error as NSError {
            print("Error on update: \(error)")
        }
        
    }

    /// Return a list of Highlights with a given ID
    ///
    /// - Parameters:
    ///   - readerConfig: Current folio reader configuration.
    ///   - bookId: Book ID
    ///   - page: Page number
    /// - Returns: Return a list of Highlights
    public static func allByBookId(withConfiguration readerConfig: FolioReaderConfig, bookId: String, andPage page: NSNumber? = nil, sortBy: String? = nil, ascending: Bool = true) -> [Highlight] {
        var highlights: [Highlight]?
        var predicate = NSPredicate(format: "bookId = %@ && isDeleted = false", bookId)
        if let page = page {
            predicate = NSPredicate(format: "bookId = %@ && page = %@ && isDeleted = false", bookId, page)
        }

        do {
            let realm = try Realm(configuration: readerConfig.realmConfiguration)
            if let mSortBy = sortBy {
                highlights = realm.objects(Highlight.self).filter(predicate).sorted(byKeyPath: mSortBy, ascending: ascending).toArray(Highlight.self)
            } else {
                highlights = realm.objects(Highlight.self).filter(predicate).toArray(Highlight.self)
            }
            return (highlights ?? [])
        } catch let error as NSError {
            print("Error on fetch all by book Id: \(error)")
            return []
        }
    }

    /// Return all Highlights
    ///
    /// - Parameter readerConfig: - readerConfig: Current folio reader configuration.
    /// - Returns: Return all Highlights
    public static func all(withConfiguration readerConfig: FolioReaderConfig) -> [Highlight] {
        var highlights: [Highlight]?
        do {
            let realm = try Realm(configuration: readerConfig.realmConfiguration)
            highlights = realm.objects(Highlight.self).toArray(Highlight.self)
            return (highlights ?? [])
        } catch let error as NSError {
            print("Error on fetch all: \(error)")
            return []
        }
    }
}

// MARK: - HTML Methods

extension Highlight {

    public struct MatchingHighlight {
        var text: String
        var id: String
        var bookId: String
        var currentPage: Int
        var rangy: String

    }

    /**
     Match a highlight on string.
     */
    public static func matchHighlight(_ matchingHighlight: MatchingHighlight) -> Highlight? {
        
        let highlight = Highlight()
        highlight.highlightId = matchingHighlight.id
        highlight.date = Date()
        highlight.content = matchingHighlight.text
        highlight.page = matchingHighlight.currentPage
        highlight.bookId = matchingHighlight.bookId
        highlight.rangy = matchingHighlight.rangy
        highlight.type = styleForClass(forRangy: matchingHighlight.rangy)
        return highlight
        
    }
    
    static func styleForClass(forRangy rangy: String) -> Int {
        // type:textContent|125$132$324259$highlight-yellow$
        guard let colorClass = rangy.split(separator: "$").last else {
            return 0
        }
        return HighlightStyle.styleForClass( String(colorClass) ).rawValue
    }


    /// Remove a Highlight from HTML by ID
    ///
    /// - Parameters:
    ///   - page: The page containing the HTML.
    ///   - highlightId: The ID to be removed
    /// - Returns: The removed id
    @discardableResult public static func removeFromHTMLById(withinPage page: FolioReaderPage?, highlightId: String) -> String? {
        guard let currentPage = page else { return nil }
        
        if let removedId = currentPage.webView?.js("removeHighlightById('\(highlightId)')") {
            return removedId
        } else {
            print("Error removing Highlight from page")
            return nil
        }
    }
}
