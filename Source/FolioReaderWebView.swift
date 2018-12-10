//
//  FolioReaderWebView.swift
//  FolioReaderKit
//
//  Created by Hans Seiffert on 21.09.16.
//  Copyright (c) 2016 Folio Reader. All rights reserved.
//

import UIKit

/// The custom WebView used in each page
open class FolioReaderWebView: UIWebView {
    var isColors = false
    var isShare = false
    var isOneWord = false

    fileprivate weak var readerContainer: FolioReaderContainer?

    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    override init(frame: CGRect) {
        fatalError("use init(frame:readerConfig:book:) instead.")
    }

    init(frame: CGRect, readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer

        super.init(frame: frame)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIMenuController

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard readerConfig.useReaderMenuController else {
            return super.canPerformAction(action, withSender: sender)
        }

        if isShare {
            return false
        } else if isColors {
            return false
        } else {
            if action == #selector(highlight(_:))
                || action == #selector(highlightWithNote(_:))
                || action == #selector(updateHighlightNote(_:))
                || (action == #selector(define(_:)) && isOneWord)
                || (action == #selector(play(_:)) && (book.hasAudio || readerConfig.enableTTS))
                || (action == #selector(share(_:)) && readerConfig.allowSharing)
                || (action == #selector(copy(_:)) && readerConfig.allowSharing) {
                return true
            }
            return false
        }
    }

    // MARK: - UIMenuController - Actions

    @objc func share(_ sender: UIMenuController) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let shareImage = UIAlertAction(title: self.readerConfig.localizedShareImageQuote, style: .default, handler: { (action) -> Void in
            if self.isShare {
                if let textToShare = self.js("getHighlightContent()") {
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)
                }
            } else {
                if let textToShare = self.js("getSelectedText()") {
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)

                    self.clearTextSelection()
                }
            }
            self.setMenuVisible(false)
        })

        let shareText = UIAlertAction(title: self.readerConfig.localizedShareTextQuote, style: .default) { (action) -> Void in
            if self.isShare {
                if let textToShare = self.js("getHighlightContent()") {
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            } else {
                if let textToShare = self.js("getSelectedText()") {
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            }
            self.setMenuVisible(false)
        }

        let cancel = UIAlertAction(title: self.readerConfig.localizedCancel, style: .cancel, handler: nil)

        alertController.addAction(shareImage)
        alertController.addAction(shareText)
        alertController.addAction(cancel)

        if let alert = alertController.popoverPresentationController {
            alert.sourceView = self.folioReader.readerCenter?.currentPage
            alert.sourceRect = sender.menuFrame
        }

        self.folioReader.readerCenter?.present(alertController, animated: true, completion: nil)
    }

    func colors(_ sender: UIMenuController?) {
        isColors = true
        createMenu(options: false)
        setMenuVisible(true)
    }

    func remove(_ sender: UIMenuController?) {
        if let removedId = js("removeThisHighlight()") {
            Highlight.removeById(withConfiguration: self.readerConfig, highlightId: removedId)
        }
        setMenuVisible(false)
    }

    @objc func addHighlight(_ sender: UIMenuController?) -> Highlight? {
        // Persist
        guard let bookId = self.book.bookId else {
            return nil
        }
        let pageNumber = folioReader.readerCenter?.currentPageNumber ?? 0
        let migrationPageNumber = max(0, pageNumber - 1)

        let highlightAndReturn = js("highlightString('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))', '\(bookId)', \(migrationPageNumber) )")
        guard let jsonData = highlightAndReturn?.data(using: String.Encoding.utf8) else {
            return nil
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? NSArray,
                let dic = json.firstObject as? [String: String]
            else {
                return nil
            }
            guard let rangies = dic["rangy"] else {
                return nil
            }
            guard let text = dic["content"] else {
                return nil
            }
            guard let identifier = dic["id"] else {
                return nil
            }
            if let dicRect = dic["rect"] {
                let rect = CGRectFromString(dicRect)
                createMenu(options: true)
                setMenuVisible(true, andRect: rect)
            }
            // MARK: Move to method
            // get matching rang
            var rangeString = FolioUtils.getRangy(rangies, with: identifier)
            
            // New id - migration to sync highlight
            var rangy = rangeString
            rangy = rangy.replacingOccurrences(of: Highlight.typeTextContentWithLine, with: "")
            let elements = rangy.split(separator: "$")
            var newId = identifier
            if elements.count >= 2 {
                newId = bookId + "_" + String(migrationPageNumber) + "_"
                newId += elements[0] + "_"
                newId += elements[1]
            }
            if elements.count >= 3 {
                var newRangeString = rangeString.split(separator: "$")
                newRangeString[2] = Substring.init(newId)
                rangeString = newRangeString.joined(separator: "$")
            }
            let match = Highlight.MatchingHighlight(text: text, id: newId, bookId: bookId, currentPage: migrationPageNumber, rangy:  rangeString)
            let highlight = Highlight.matchHighlight(match)
            return highlight
            
        } catch {
            print("Could not receive JSON")
        }
        return nil

    }

    @objc func highlight(_ sender: UIMenuController?) {
        let highlight = addHighlight(sender)
        highlight?.persist(withConfiguration: self.readerConfig)
    }
    
    
    
    @objc func highlightWithNote(_ sender: UIMenuController?) {
        if let highlight = addHighlight(sender) {
           self.folioReader.readerCenter?.presentAddHighlightNote(highlight, edit: false)
        }
    }
    
    @objc func updateHighlightNote (_ sender: UIMenuController?) {
        if let highlightId = js("currentHighlightId()"),
            let highlightNote = Highlight.getById(withConfiguration: readerConfig, highlightId: highlightId) {
            self.folioReader.readerCenter?.presentAddHighlightNote(highlightNote, edit: true)
        }
    }

    @objc func define(_ sender: UIMenuController?) {
        guard let selectedText = js("getSelectedText()") else {
            return
        }

        self.setMenuVisible(false)
        self.clearTextSelection()

        let vc = UIReferenceLibraryViewController(term: selectedText)
        vc.view.tintColor = self.readerConfig.tintColor(isNightMode: folioReader.nightMode)
        guard let readerContainer = readerContainer else { return }
        readerContainer.show(vc, sender: nil)
    }

    @objc func play(_ sender: UIMenuController?) {
        self.folioReader.readerAudioPlayer?.play()

        self.clearTextSelection()
    }

    func setYellow(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .yellow)
    }

    func setGreen(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .green)
    }

    func setBlue(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .blue)
    }

    func setPink(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .pink)
    }

    func setUnderline(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .underline)
    }

    func changeHighlightStyle(_ sender: UIMenuController?, style: HighlightStyle) {
        self.folioReader.currentHighlightStyle = style.rawValue

        if let updateId = js("setHighlightStyle('\(HighlightStyle.classForStyle(style.rawValue))')") {
            if let rangies = js("getHighlights()") {
                let rangeString = FolioUtils.getRangy(rangies, with: updateId)
                Highlight.updateById(withConfiguration: self.readerConfig, highlightId: updateId, rangy: rangeString)
            }
        }
        
        //FIX: https://github.com/FolioReader/FolioReaderKit/issues/316
        setMenuVisible(false)
    }

    // MARK: - Create and show menu

    func createMenu(options: Bool) {
        guard (self.readerConfig.useReaderMenuController == true) else {
            return
        }

        isShare = options

        let colors = UIImage(readerImageNamed: "colors-marker")
        let share = UIImage(readerImageNamed: "share-marker")
        let remove = UIImage(readerImageNamed: "no-marker")
        let yellow = UIImage(readerImageNamed: "yellow-marker")
        let green = UIImage(readerImageNamed: "green-marker")
        let blue = UIImage(readerImageNamed: "blue-marker")
        let pink = UIImage(readerImageNamed: "pink-marker")
        let underline = UIImage(readerImageNamed: "underline-marker")

        let menuController = UIMenuController.shared

        let highlightItem = UIMenuItem(title: self.readerConfig.localizedHighlightMenu, action: #selector(highlight(_:)))
        let highlightNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(highlightWithNote(_:)))
        let editNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(updateHighlightNote(_:)))
        let playAudioItem = UIMenuItem(title: self.readerConfig.localizedPlayMenu, action: #selector(play(_:)))
        let defineItem = UIMenuItem(title: self.readerConfig.localizedDefineMenu, action: #selector(define(_:)))
        let colorsItem = UIMenuItem(title: "C", image: colors) { [weak self] _ in
            self?.colors(menuController)
        }
        let shareItem = UIMenuItem(title: "S", image: share) { [weak self] _ in
            self?.share(menuController)
        }
        let removeItem = UIMenuItem(title: "R", image: remove) { [weak self] _ in
            self?.remove(menuController)
        }
        let yellowItem = UIMenuItem(title: "Y", image: yellow) { [weak self] _ in
            self?.setYellow(menuController)
        }
        let greenItem = UIMenuItem(title: "G", image: green) { [weak self] _ in
            self?.setGreen(menuController)
        }
        let blueItem = UIMenuItem(title: "B", image: blue) { [weak self] _ in
            self?.setBlue(menuController)
        }
        let pinkItem = UIMenuItem(title: "P", image: pink) { [weak self] _ in
            self?.setPink(menuController)
        }
        let underlineItem = UIMenuItem(title: "U", image: underline) { [weak self] _ in
            self?.setUnderline(menuController)
        }

        var menuItems: [UIMenuItem] = []

        // menu on existing highlight
        if isShare {
            menuItems = [colorsItem, editNoteItem, removeItem]
            
            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
            
            isShare = false
        } else if isColors {
            // menu for selecting highlight color
            menuItems = [yellowItem, greenItem, blueItem, pinkItem, underlineItem]
        } else {
            // default menu
            menuItems = [highlightItem, defineItem, highlightNoteItem]

            if self.book.hasAudio || self.readerConfig.enableTTS {
                menuItems.insert(playAudioItem, at: 0)
            }

            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
        }
        
        menuController.menuItems = menuItems
    }
    
    open func setMenuVisible(_ menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRect.zero) {
        if !menuVisible && isShare || !menuVisible && isColors {
            isColors = false
            isShare = false
        }
        
        if menuVisible  {
            if !rect.equalTo(CGRect.zero) {
                UIMenuController.shared.setTargetRect(rect, in: self)
            }
        }
        
        UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
    }
    
    // MARK: - Java Script Bridge
    
    @discardableResult open func js(_ script: String) -> String? {
        let callback = self.stringByEvaluatingJavaScript(from: script)
        if callback!.isEmpty { return nil }
        return callback
    }
    
    // MARK: WebView
    
    func clearTextSelection() {
        // Forces text selection clearing
        // @NOTE: this doesn't seem to always work
        
        self.isUserInteractionEnabled = false
        self.isUserInteractionEnabled = true
    }
    
    func setupScrollDirection() {
        switch self.readerConfig.scrollDirection {
        case .vertical, .defaultVertical, .horizontalWithVerticalContent:
            scrollView.isPagingEnabled = false
            paginationMode = .unpaginated
            scrollView.bounces = true
            break
        case .horizontal:
            scrollView.isPagingEnabled = true
            paginationMode = .leftToRight
            paginationBreakingMode = .page
            scrollView.bounces = false
            break
        }
    }
}
