//
//  FolioReaderPage.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import SafariServices
import MenuItemKit
import JSQWebViewController

/// Protocol which is used from `FolioReaderPage`s.
@objc public protocol FolioReaderPageDelegate: class {

    /**
     Notify that the page will be loaded. Note: The webview content itself is already loaded at this moment. But some java script operations like the adding of class based on click listeners will happen right after this method. If you want to perform custom java script before this happens this method is the right choice. If you want to modify the html content (and not run java script) you have to use `htmlContentForPage()` from the `FolioReaderCenterDelegate`.

     - parameter page: The loaded page
     */
    @objc optional func pageWillLoad(_ page: FolioReaderPage)

    /**
     Notifies that page did load. A page load doesn't mean that this page is displayed right away, use `pageDidAppear` to get informed about the appearance of a page.

     - parameter page: The loaded page
     */
    @objc optional func pageDidLoad(_ page: FolioReaderPage)
    
    /**
     Notifies that page receive tap gesture.
     
     - parameter recognizer: The tap recognizer
     */
    @objc optional func pageTap(_ recognizer: UITapGestureRecognizer)
}

open class FolioReaderPage: UICollectionViewCell, UIWebViewDelegate, UIGestureRecognizerDelegate {
    weak var delegate: FolioReaderPageDelegate?
    weak var readerContainer: FolioReaderContainer?

    /// The index of the current page. Note: The index start at 1!
    open var pageNumber: Int!
    open var webView: FolioReaderWebView?
    open var resource: FRResource?

    fileprivate var colorView: UIView!
    fileprivate var shouldShowBar = true
    fileprivate var menuIsVisible = false

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

    // MARK: - View life cicle

    public override init(frame: CGRect) {
        // Init explicit attributes with a default value. The `setup` function MUST be called to configure the current object with valid attributes.
        self.readerContainer = FolioReaderContainer(withConfig: FolioReaderConfig(), rwBook: nil, folioReader: FolioReader(), epubPath: "")
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear

        NotificationCenter.default.addObserver(self, selector: #selector(refreshPageMode), name: NSNotification.Name(rawValue: "needRefreshPageMode"), object: nil)
    }

    public func setup(withReaderContainer readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        guard let readerContainer = self.readerContainer else { return }

        if webView == nil {
            webView = FolioReaderWebView(frame: webViewFrame(), readerContainer: readerContainer)
            webView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView?.dataDetectorTypes = .link
            webView?.scrollView.showsVerticalScrollIndicator = false
            webView?.scrollView.showsHorizontalScrollIndicator = false
            webView?.backgroundColor = .clear
            self.contentView.addSubview(webView!)
        }
        webView?.delegate = self

        if colorView == nil {
            colorView = UIView()
            colorView.backgroundColor = self.readerConfig.nightModeBackground
            webView?.scrollView.addSubview(colorView)
        }

        // Remove all gestures before adding new one
        webView?.gestureRecognizers?.forEach({ gesture in
            webView?.removeGestureRecognizer(gesture)
        })
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        tapGestureRecognizer.delegate = self
        webView?.addGestureRecognizer(tapGestureRecognizer)
        
        //IID listen to UIMenue hide notification
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidHide), name: .UIMenuControllerDidHideMenu, object: nil)

    }
    
    open override func prepareForReuse() {
        super.prepareForReuse()
        webView?.alpha = 0
        if let blank =  URL.init(string: "about:blank") {
            webView?.loadRequest(URLRequest.init(url:blank))
        }
    }
    
    // IID
    @objc func menuDidHide() {
        self.menuIsVisible = false
        self.shouldShowBar = true
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    deinit {
        webView?.scrollView.delegate = nil
        webView?.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        webView?.setupScrollDirection()
        webView?.frame = webViewFrame()
    }

    func webViewFrame() -> CGRect {
        guard (self.readerConfig.hideBars == false) else {
            return bounds
        }

        let statusbarHeight = UIApplication.shared.statusBarFrame.size.height
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let navTotal = self.readerConfig.shouldHideNavigationOnTap ? 0 : statusbarHeight + navBarHeight
        let paddingTop: CGFloat = 20
        let paddingBottom: CGFloat = 30

        return CGRect(
            x: bounds.origin.x,
            y: self.readerConfig.isDirection(bounds.origin.y + navTotal, bounds.origin.y + navTotal + paddingTop, bounds.origin.y + navTotal),
            width: bounds.width,
            height: self.readerConfig.isDirection(bounds.height - navTotal, bounds.height - navTotal - paddingTop - paddingBottom, bounds.height - navTotal)
        )
    }

    func getHTML()-> String? {
        let html = self.webView?.js("getHTML()")
        return html
    }
    
    func getHTMLBody()-> String? {
        let htmlBody = self.webView?.js("getHTMLBody()")
        return htmlBody
    }
    
    func loadHTMLString(_ htmlContent: String!, baseURL: URL!) {
        // Insert the stored highlights to the HTML
        let tempHtmlContent = htmlContentWithInsertHighlights(htmlContent)
        // Load the html into the webview
        webView?.alpha = 0
        webView?.loadHTMLString(tempHtmlContent, baseURL: baseURL)
    }

    // MARK: - Highlights

    fileprivate func htmlContentWithInsertHighlights(_ htmlContent: String) -> String {
        let tempHtmlContent = htmlContent as NSString
        // Restore highlights
        guard let _ = (self.book.name as NSString?)?.deletingPathExtension else {
            return tempHtmlContent as String
        }
        return tempHtmlContent as String
    }

    // MARK: - UIWebView Delegate

    open func webViewDidFinishLoad(_ webView: UIWebView) {
        guard let webView = webView as? FolioReaderWebView else {
            return
        }
        guard !webView.didFinishLoadEmptyString else {
            return
        }
        let direction: ScrollDirection = self.folioReader.needsRTLChange ? .positive(withConfiguration: self.readerConfig) : .negative(withConfiguration: self.readerConfig)

        // If web page is scroll from page n to page n-1, and it did finish load before
        // scrollViewDidEndDecelerating, keep track it
        if let visibleIdxs = self.folioReader.readerCenter?.collectionView.indexPathsForVisibleItems,
            let firstIdx = visibleIdxs.first,
            self.folioReader.readerCenter?.pageScrollDirection == direction,
            self.readerConfig.scrollDirection != .horizontalWithVerticalContent {
            self.folioReader.readerCenter?.webViewDidLoadData.removeAll()
            // Find min indexPath
            var minIdx = firstIdx
            visibleIdxs.forEach { idx in
                minIdx = (minIdx.row < idx.row) ? minIdx : idx
            }
            self.folioReader.readerCenter?.webViewDidLoadData[minIdx] = true
        }
        delegate?.pageWillLoad?(self)

        // Add the custom class based onClick listener
        self.setupClassBasedOnClickListeners()

        refreshPageMode()

        if self.readerConfig.enableTTS && !self.book.hasAudio {
            webView.js("wrappingSentencesWithinPTags()")

            if let audioPlayer = self.folioReader.readerAudioPlayer, (audioPlayer.isPlaying() == true) {
                audioPlayer.readCurrentSentence()
            }
        }
        
        if (self.folioReader.readerCenter?.pageScrollDirection == direction &&
            self.readerConfig.scrollDirection != .horizontalWithVerticalContent &&
            (self.folioReader.readerCenter?.isScrolling == true ||
             self.folioReader.readerCenter?.shouldDelayScrollingToBottomUntilWebViewDidLoad == true) ) {
            self.folioReader.readerCenter?.shouldDelayScrollingToBottomUntilWebViewDidLoad = false
            scrollPageToBottom()
        }
        
        UIView.animate(withDuration: 0.2, animations: {webView.alpha = 1}, completion: { finished in
            webView.isColors = false
            self.webView?.createMenu(options: false)
        })
        delegate?.pageDidLoad?(self)

        // IID
        // add highlight
        guard let bookId = (self.book.name as NSString?)?.deletingPathExtension else {
            return
        }
        let page = pageNumber - 1
        let highlights = Highlight.allByBookId(withConfiguration: self.readerConfig, bookId: bookId, andPage: NSNumber(value: page))
        let rangies = highlights.reduce("type:textContent") { (string, highlight) -> String in
            if let aRangy = highlight.rangy {
                let range = aRangy.split(separator: "|").last
                return string + String("|\(range!)")
            }
            else {
                // migration needed
                let fullstring = "\(highlight.contentPre!)\(highlight.content!)\(highlight.contentPost!)"
                if  let response = self.webView?.js("migrateStringToRange('\(fullstring.stripHtml())', '\(highlight.content!.stripHtml())')")  {
                    let jsonData = response.data(using: String.Encoding.utf8)
                    if let bookmark = try? JSONSerialization.jsonObject(with: jsonData!, options: []) as? NSDictionary,
                        let start = bookmark?["start"],
                        let end = bookmark?["end"] {
                        // create highlight
                        let newHighlightId = [bookId, "\(page)", "\(start)", "\(end)"].joined(separator: "_")
                        let rangyPart = String("|\(start)$\(end)$\(newHighlightId)$\(HighlightStyle.classForStyle(highlight.type))$")
                        let rangyFull = String("type:textContent\(rangyPart)")
                        //create new highlight
                        let migrationPageNumber = max(0, page)
                        let match = Highlight.MatchingHighlight(text: highlight.content?.stripHtml() ?? "", id: newHighlightId, bookId: bookId, currentPage: migrationPageNumber , rangy:  rangyFull)
                        let newHighlight = Highlight.matchHighlight(match)
                        newHighlight?.persist(withConfiguration: self.readerConfig)
                        //delete old highlight
                        highlight.forceRemove(withConfiguration: self.readerConfig)
                        return string + rangyPart
                    }
                }
                return string
            }
        }
        if (rangies.count > 0) {
            self.webView?.js("setHighlight('\(rangies)')")
        }
    }

    open func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        guard
            let webView = webView as? FolioReaderWebView,
            let scheme = request.url?.scheme else {
                return true
        }

        guard let url = request.url else { return false }

        if scheme == "highlight" {
            shouldShowBar = false

            guard let decoded = url.absoluteString.removingPercentEncoding else { return false }
            let index = decoded.index(decoded.startIndex, offsetBy: 12)
            let rect = CGRectFromString(String(decoded[index...]))

            webView.createMenu(options: true)
            webView.setMenuVisible(true, andRect: rect)
            menuIsVisible = true

            return false
        } else if scheme == "play-audio" {
            guard let decoded = url.absoluteString.removingPercentEncoding else { return false }
            let index = decoded.index(decoded.startIndex, offsetBy: 13)
            let playID = String(decoded[index...])
            let chapter = self.folioReader.readerCenter?.getCurrentChapter()
            let href = chapter?.href ?? ""
            self.folioReader.readerAudioPlayer?.playAudio(href, fragmentID: playID)

            return false
        } else if scheme == "file" {

            let anchorFromURL = url.fragment

            // Handle internal url
            if !url.pathExtension.isEmpty {
                let pathComponent = (self.book.opfResource.href as NSString?)?.deletingLastPathComponent
                guard let base = ((pathComponent == nil || pathComponent?.isEmpty == true) ? self.book.name : pathComponent) else {
                    return true
                }

                let path = url.path
                let splitedPath = path.components(separatedBy: base)

                // Return to avoid crash
                if (splitedPath.count <= 1 || splitedPath[1].isEmpty) {
                    return true
                }

                let href = splitedPath[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let hrefPage = (self.folioReader.readerCenter?.findPageByHref(href) ?? 0) + 1
                
                // IID handle click on non linear item like a image. Show a zoomable single page
                // check if FRResource in FRSpine in non linear
                let spine = self.book.spine.spineReferences.filter { (aSpine) -> Bool in
                    return aSpine.resource.href == href && aSpine.linear != true
                }
                if let aSpine = spine.first {
                    openModal(resource: aSpine.resource)
                    return false
                }
                // END IID
                
                if (hrefPage == pageNumber) {
                    // Handle internal #anchor
                    if let anchor = anchorFromURL {
                        handleAnchor(anchor, avoidBeginningAnchors: false, animated: true)
                        return false
                    }
                } else {
                    self.folioReader.readerCenter?.tempAnchor = anchorFromURL
                    self.folioReader.readerCenter?.changePageWith(href: href, animated: true)
                }
                return false
            }

            // Handle internal #anchor
            if anchorFromURL != nil {
                handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animated: true)
                return false
            }

            return true
        } else if scheme == "mailto" {
            print("Email")
            return true
        } else if url.absoluteString != "about:blank" && scheme.contains("http") && navigationType == .linkClicked {

            if #available(iOS 9.0, *) {
                let safariVC = SFSafariViewController(url: request.url!)
                safariVC.view.tintColor = self.readerConfig.tintColor(isNightMode: folioReader.nightMode)
                self.folioReader.readerCenter?.present(safariVC, animated: true, completion: nil)
            } else {
                let webViewController = WebViewController(url: request.url!)
                let nav = UINavigationController(rootViewController: webViewController)
                nav.view.tintColor = self.readerConfig.tintColor(isNightMode: folioReader.nightMode)
                self.folioReader.readerCenter?.present(nav, animated: true, completion: nil)
            }
            return false
        } else {
            // Check if the url is a custom class based onClick listerner
            var isClassBasedOnClickListenerScheme = false
            for listener in self.readerConfig.classBasedOnClickListeners {

                if scheme == listener.schemeName,
                    let absoluteURLString = request.url?.absoluteString,
                    let range = absoluteURLString.range(of: "/clientX=") {
                    let baseURL = String(absoluteURLString[..<range.lowerBound])
                    let positionString = String(absoluteURLString[range.lowerBound...])
                    if let point = getEventTouchPoint(fromPositionParameterString: positionString) {
                        let attributeContentString = (baseURL.replacingOccurrences(of: "\(scheme)://", with: "").removingPercentEncoding)
                        // Call the on click action block
                        listener.onClickAction(attributeContentString, point)
                        // Mark the scheme as class based click listener scheme
                        isClassBasedOnClickListenerScheme = true
                    }
                }
            }

            if isClassBasedOnClickListenerScheme == false {
                // Try to open the url with the system if it wasn't a custom class based click listener
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.openURL(url)
                    return false
                }
            } else {
                return false
            }
        }

        return true
    }

    fileprivate func getEventTouchPoint(fromPositionParameterString positionParameterString: String) -> CGPoint? {
        // Remove the parameter names: "/clientX=188&clientY=292" -> "188&292"
        var positionParameterString = positionParameterString.replacingOccurrences(of: "/clientX=", with: "")
        positionParameterString = positionParameterString.replacingOccurrences(of: "clientY=", with: "")
        // Separate both position values into an array: "188&292" -> [188],[292]
        let positionStringValues = positionParameterString.components(separatedBy: "&")
        // Multiply the raw positions with the screen scale and return them as CGPoint
        if
            positionStringValues.count == 2,
            let xPos = Int(positionStringValues[0]),
            let yPos = Int(positionStringValues[1]) {
            return CGPoint(x: xPos, y: yPos)
        }
        return nil
    }

    // MARK: Gesture recognizer

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view is FolioReaderWebView {
            if otherGestureRecognizer is UILongPressGestureRecognizer {
                if UIMenuController.shared.isMenuVisible {
                    webView?.setMenuVisible(false)
                }
                return false
            }
            return true
        }
        return false
    }

    @objc open func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        self.delegate?.pageTap?(recognizer)
        
        if let _navigationController = self.folioReader.readerCenter?.navigationController, (_navigationController.isNavigationBarHidden == true) {
            let selected = webView?.js("getSelectedText()")
            
            guard (selected == nil || selected?.isEmpty == true) else {
                return
            }

            let delay = 0.4 * Double(NSEC_PER_SEC) // 0.4 seconds * nanoseconds per seconds
            let dispatchTime = (DispatchTime.now() + (Double(Int64(delay)) / Double(NSEC_PER_SEC)))
            
            DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: {
                if (self.shouldShowBar == true && self.menuIsVisible == false) {
                    self.folioReader.readerCenter?.toggleBars()
                }
            })
        } else if (self.readerConfig.shouldHideNavigationOnTap == true) {
            self.folioReader.readerCenter?.hideBars()
            self.menuIsVisible = false
        }
    }

    // MARK: - Public scroll postion setter

    /**
     Scrolls the page to a given offset

     - parameter offset:   The offset to scroll
     - parameter animated: Enable or not scrolling animation
     */
    open func scrollPageToOffset(_ offset: CGFloat, animated: Bool) {
        let pageOffsetPoint = self.readerConfig.isDirection(CGPoint(x: 0, y: offset), CGPoint(x: offset, y: 0), CGPoint(x: 0, y: offset))
        webView?.scrollView.setContentOffset(pageOffsetPoint, animated: animated)
    }

    /**
     Scrolls the page to bottom
     */
    open func scrollPageToBottom() {
        guard let webView = webView else { return }
        let scrollHeight = webView.scrollHeight
        let scrollWidth = webView.scrollWidth
        let bottomOffset = self.readerConfig.isDirection(
            CGPoint(x: 0, y: scrollHeight - webView.scrollView.bounds.height),
            CGPoint(x: scrollWidth - webView.scrollView.bounds.width, y: 0),
            CGPoint(x: scrollWidth - webView.scrollView.bounds.width, y: 0)
        )

        if bottomOffset.forDirection(withConfiguration: self.readerConfig) >= 0 {
            DispatchQueue.main.async {
                let javascript = "window.scrollBy(\(bottomOffset.x), \(bottomOffset.y))"
                self.webView?.stringByEvaluatingJavaScript(from: javascript)
//                self.webView?.scrollView.setContentOffset(bottomOffset, animated: false)
            }
        }
    }
    // IID
   
    open func scrollTo(_ highlightId: String, animated: Bool, verticalInset: Bool = true) {
        if !highlightId.isEmpty {
            var offset = getHighlightOffset(highlightId)
            if verticalInset &&
                self.readerConfig.scrollDirection.collectionViewScrollDirection() == UICollectionViewScrollDirection.vertical {
                offset = offset - 100
            }
            scrollPageToOffset(offset, animated: animated)
        }
    }
    
    func getHighlightOffset(_ highlightId: String) -> CGFloat {
        let horizontal = self.readerConfig.scrollDirection == .horizontal
        let function = "getHighlightOffset('\(highlightId)', \(horizontal))"
        if let strOffset = webView?.js(function) {
            return CGFloat((strOffset as NSString).floatValue)
        }
        
        return CGFloat(0)
    }
    
    func scrollTo(searchResult: FolioSearchResult, animated: Bool, verticalInset: Bool = true) {
        let horizontal = self.readerConfig.scrollDirection == .horizontal
        var offset: CGFloat = 0
        if let strOffset = webView?.js("highlightSearchResult('\(searchResult.searchText)', \(searchResult.occurrenceInChapter), \(horizontal))") {
            offset = CGFloat((strOffset as NSString).floatValue)
            if verticalInset &&
                self.readerConfig.scrollDirection.collectionViewScrollDirection() == UICollectionViewScrollDirection.vertical {
                offset = offset - 100
            }
        }
        scrollPageToOffset(offset, animated: true)
    }

    
    // IID END
    
    /**
     Handdle #anchors in html, get the offset and scroll to it

     - parameter anchor:                The #anchor
     - parameter avoidBeginningAnchors: Sometimes the anchor is on the beggining of the text, there is not need to scroll
     - parameter animated:              Enable or not scrolling animation
     */
    open func handleAnchor(_ anchor: String,  avoidBeginningAnchors: Bool, animated: Bool) {
        if !anchor.isEmpty {
            let offset = getAnchorOffset(anchor)

            switch self.readerConfig.scrollDirection {
            case .vertical, .defaultVertical:
                let isBeginning = (offset < frame.forDirection(withConfiguration: self.readerConfig) * 0.5)

                if !avoidBeginningAnchors {
                    scrollPageToOffset(offset, animated: animated)
                } else if avoidBeginningAnchors && !isBeginning {
                    scrollPageToOffset(offset, animated: animated)
                }
            case .horizontal, .horizontalWithVerticalContent:
                scrollPageToOffset(offset, animated: animated)
            }
        }
    }

    // MARK: Helper

    /**
     Get the #anchor offset in the page

     - parameter anchor: The #anchor id
     - returns: The element offset ready to scroll
     */
    func getAnchorOffset(_ anchor: String) -> CGFloat {
        let horizontal = self.readerConfig.scrollDirection == .horizontal
        if let strOffset = webView?.js("getAnchorOffset('\(anchor)', \(horizontal))") {
            return CGFloat((strOffset as NSString).floatValue)
        }

        return CGFloat(0)
    }

    // MARK: Mark ID

    /**
     Audio Mark ID - marks an element with an ID with the given class and scrolls to it

     - parameter identifier: The identifier
     */
    func audioMarkID(_ identifier: String) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage else {
            return
        }

        let playbackActiveClass = self.book.playbackActiveClass
        currentPage.webView?.js("audioMarkID('\(playbackActiveClass)','\(identifier)')")
    }

    // MARK: UIMenu visibility

    override open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard let webView = webView else { return false }

        if UIMenuController.shared.menuItems?.count == 0 {
            webView.isColors = false
            webView.createMenu(options: false)
        }

        if !webView.isShare && !webView.isColors {
            if let result = webView.js("getSelectedText()") , result.components(separatedBy: " ").count == 1 {
                webView.isOneWord = true
                webView.createMenu(options: false)
            } else {
                webView.isOneWord = false
            }
        }

        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: ColorView fix for horizontal layout
    @objc func refreshPageMode() {
        guard let webView = webView else { return }

        if (self.folioReader.nightMode == true) {
            // omit create webView and colorView
            let script = "document.documentElement.offsetHeight"
            let contentHeight = webView.stringByEvaluatingJavaScript(from: script)
            let frameHeight = webView.frame.height
            let lastPageHeight = frameHeight * CGFloat(webView.pageCount) - CGFloat(Double(contentHeight!)!)
            colorView.frame = CGRect(x: webView.frame.width * CGFloat(webView.pageCount-1), y: webView.frame.height - lastPageHeight, width: webView.frame.width, height: lastPageHeight)
        } else {
            colorView.frame = CGRect.zero
        }
    }
    
    // MARK: - Class based click listener
    
    fileprivate func setupClassBasedOnClickListeners() {
        for listener in self.readerConfig.classBasedOnClickListeners {
            self.webView?.js("addClassBasedOnClickListener(\"\(listener.schemeName)\", \"\(listener.querySelector)\", \"\(listener.attributeName)\", \"\(listener.selectAll)\")");
        }
    }
    
    // MARK: - Public Java Script injection
    
    /** 
     Runs a JavaScript script and returns it result. The result of running the JavaScript script passed in the script parameter, or nil if the script fails.
     
     - returns: The result of running the JavaScript script passed in the script parameter, or nil if the script fails.
     */
    open func performJavaScript(_ javaScriptCode: String) -> String? {
        return webView?.js(javaScriptCode)
    }
    
    //IID
    func openModal(resource: FRResource ) {
        //
        let dict: Dictionary =  ["fullHref" : resource.fullHref!]
        NotificationCenter.default.post(name: Notification.Name("ShowNonInlineContent"), object: nil, userInfo: dict)
    }
    //END IID
}
