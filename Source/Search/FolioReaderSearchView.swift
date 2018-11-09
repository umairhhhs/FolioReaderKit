//
//  FolioReaderSearchView.swift
//  Pods
//
//  Created by taku on 2016/03/08.
//
//

import UIKit
import SwiftSoup

class FolioReaderSearchView: UIViewController, UISearchBarDelegate, UIAlertViewDelegate {
  
    private var searchBar: UISearchBar!
    private var table: UITableView!
    private var barHeight: CGFloat?
    private var displayWidth: CGFloat?
    private var displayHeight: CGFloat?
    private let SEARCHBAR_HEIGHT: CGFloat = 44
    private var matchesStrArray:[String] = []
    private var bodyHtmlArray:[String] = []
    private var pageMappedArray:[Int] = []
    private var tempPage:Int? = nil
    private var isSearching: Bool = false
    private var isSearchCompleted: Bool = true
    private var currentFileIndex: Int = 0
    private var currentMaximum: Int = 50
    
    fileprivate var folioReader: FolioReader
    private var readerConfig: FolioReaderConfig
    
    lazy var renderingOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    lazy var loadHtmlQueue: DispatchQueue = {
        DispatchQueue.global(qos: .default)
    }()
    
    // MARK: Init
    
    init(folioReader: FolioReader, readerConfig: FolioReaderConfig) {
        self.folioReader = folioReader
        self.readerConfig = readerConfig
        super.init(nibName: nil, bundle: Bundle.frameworkBundle())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        renderingOperationQueue.cancelAllOperations()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        barHeight = UIApplication.shared.statusBarFrame.size.height  //0
        displayWidth = self.view.frame.width
        displayHeight = self.view.frame.height
        
        searchBar = UISearchBar();
        searchBar.delegate = self
        searchBar.frame = CGRect.init(x:0, y:0, width:displayWidth!, height:SEARCHBAR_HEIGHT)
        searchBar.layer.position = CGPoint(x: self.view.bounds.width/2, y: 80)
        searchBar.showsCancelButton = false
        searchBar.placeholder = "Search in this book"
        navigationItem.titleView = searchBar
        
        addTableView()
    
        let closeImage = UIImage(readerImageNamed: "icon-navbar-close")?.ignoreSystemTint(withConfiguration: readerConfig)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: closeImage, style: .plain, target: self, action: #selector(dismissView))
    }
    
    func addTableView(){
        table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        // align table from the left and right
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[view]-0-|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: ["view": table]));
        // align table from the top and bottom
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[view]-0-|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: ["view": table]));
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        table.rowHeight = 74
        table.estimatedRowHeight = 74
        table.delegate = self
        table.dataSource = self;
    }
    
    @objc func dismissView() {
        dismiss(animated: true, completion: nil)
        renderingOperationQueue.cancelAllOperations()
    }

    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        return true
    }
    
    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        bodyHtmlArray.removeAll()
        pageMappedArray.removeAll()
        matchesStrArray.removeAll()
        table?.reloadData()
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {   //protocolの実装
        searchInThisBook()
        searchBar.resignFirstResponder()
    }
    
    private func pauseSearchingIfNeeded(currentLoop: Int, maxLoop: Int) {
        let total = (self.folioReader.readerCenter?.totalPages ?? 0)
        if currentLoop == total - 1 {
            self.isSearchCompleted = true
        }
        self.isSearching = false
        self.currentFileIndex = maxLoop
    }
    
    func searchInThisBook(fileIndex: Int = 0){
        isSearching = true
        isSearchCompleted = false
        let pattern = "([a-zA-Z0-9]|.){0,2}\(searchBar.text!)([a-zA-Z0-9]|.){0,2}"
        let total = (self.folioReader.readerCenter?.totalPages ?? 0)
        guard fileIndex < total else {
            return
        }
        let regex = RegExp(pattern)
        let maxFileIndex = min(total, fileIndex + 7)
        DispatchQueue.global(qos: .default).async {
            for j in fileIndex..<maxFileIndex {
                let indexPath = IndexPath(row: j, section: 0)
                let resource = self.folioReader.readerContainer?.book.spine.spineReferences[indexPath.row].resource
                let operation = BlockOperation.init()
                operation.addExecutionBlock({ [weak self] in
                    guard let `self` = self else {
                        return
                    }
                    let mHtml = try? String(contentsOfFile: resource?.fullHref ?? "", encoding: String.Encoding.utf8)
                    guard let document = try? SwiftSoup.parse(mHtml ?? "") else {
                        return
                    }
                    guard let html = try? document.text(), !html.isEmpty else {
                        return
                    }
                    var matches = regex.matches(input: html)
                    guard let matchesCount = matches?.count, matchesCount > 0 else {
                        if j == maxFileIndex - 1 {
                            self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxFileIndex)
                            if self.matchesStrArray.count < 30 {
                                OperationQueue.main.addOperation {
                                    self.searchInThisBook(fileIndex: self.currentFileIndex)
                                }
                            }
                        }
                        return
                    }
                    
                    for i in 0..<matchesCount {
                        if operation.isCancelled == true {
                            return
                        }
                        let location = max(0, matches![i].range.location - 40)
                        let length = min(html.count - location, 80)
                        let range = NSRange.init(location: location, length: length)
                        let matchHtmlStr = (html as NSString).substring(with: range)
                        var matchStr = self.stripTagsFromStr(aHtmlStr: matchHtmlStr)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: "", options: .regularExpression)
                        if let idx = matchStr.firstIndex(of: " ") {
                            matchStr = matchStr.substring(from: idx)
                        }
                        if let idx = matchStr.lastIndex(of: " ") {
                            matchStr = matchStr.substring(to: idx)
                        }
                        matchStr = "...\(matchStr)..."
                        if matchStr.isEmpty {
                            continue
                        }
                        synchronized(self, {
                            self.matchesStrArray.append(matchStr)
                            self.pageMappedArray.append( j )
                            if j == maxFileIndex - 1 && i == matchesCount - 1 {
                                self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxFileIndex)
                                if self.matchesStrArray.count < 30 {
                                    OperationQueue.main.addOperation {
                                        self.searchInThisBook(fileIndex: self.currentFileIndex)
                                    }
                                }
                            }
                        })
                    }
                })
                operation.completionBlock = {
                    print("reloadData")
                    DispatchQueue.main.async {
                        self.table.reloadData()
                    }
                }
                self.renderingOperationQueue.addOperation(operation)
            }
        }
        
    }
    
    func stripTagsFromStr(aHtmlStr:String)-> String {
        var htmlStr = aHtmlStr
        htmlStr = htmlStr.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        htmlStr = htmlStr.replacingOccurrences(of: "<[^>]*", with: "", options: .regularExpression, range: nil)
        htmlStr = htmlStr.replacingOccurrences(of: "[^<]*>", with: "", options: .regularExpression, range: nil)
        return htmlStr.trimmingCharacters(in: .whitespaces)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension FolioReaderSearchView: UITableViewDataSource {
    func tableView(_ table: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        print("カウントは\(self.matchesStrArray.count)")
        return self.matchesStrArray.count
    }
    
    func tableView(_ table: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        guard self.matchesStrArray.count > indexPath.row else {
            return cell
        }
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = "\(self.matchesStrArray[indexPath.row])"
        if isSearching == false &&
            isSearchCompleted == false &&
            indexPath.row >= self.matchesStrArray.count - 20 {
            searchInThisBook(fileIndex: currentFileIndex)
        }
        
        return cell
    }
}

extension FolioReaderSearchView: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

    }
}

extension String {
    func index(from: Int) -> Index {
        return self.index(startIndex, offsetBy: from)
    }
    
    func substring(from: Int) -> String {
        let fromIndex = index(from: from)
        return substring(from: fromIndex)
    }
    
    func substring(to: Int) -> String {
        let toIndex = index(from: to)
        return substring(to: toIndex)
    }
    
    func substring(with r: Range<Int>) -> String {
        let startIndex = index(from: r.lowerBound)
        let endIndex = index(from: r.upperBound)
        return substring(with: startIndex..<endIndex)
    }
}

func synchronized<T>(_ lock: AnyObject, _ body: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    return try body()
}

enum SearchStatus: Int {
    case notStart
    case running
    case completed
}

struct PaginationViewModel<T> {
    
    public typealias PageIndex = Int
    
    let pageSize: Int
    let preloadMargin: Int
    var pagedArray: [Int: SearchStatus] = [:]
    public fileprivate(set) var elements = [Int: [T]]()
    var total: Int = 0
    
    public init(pageSize: Int = 50,
                preloadMargin: Int = 30) {
        self.pageSize = pageSize
        self.preloadMargin = preloadMargin
    }
    
    func nextPage(for index: Int) -> Int {
        return index / self.pageSize + 1
    }
    
    func offset(for page: Int) -> Int {
        return page * self.pageSize
    }
    
    func needsLoadDataForPage(_ page: Int) -> Bool {
        if pagedArray[page] == nil {
            return true
        }
        if let status = pagedArray[page],
            (status == .running || status == .completed) {
            return false
        }
        return true
    }
    
    func elements(until page: PageIndex) -> [T] {
        if page < 0 {
            return []
        }
        let sorted = elements.filter { $0.0 <= page }.sorted { $0.0 < $1.0}
        let mElements = Array(sorted.map({ $0.value })).flatMap { $0 }
        return mElements
    }
    
    public mutating func set(_ elements: [T], forPage page: PageIndex) {
        assert(page >= 0, "Page index out of bounds")
        self.elements[page] = elements
    }
    
    /// Removes the elements corresponding to the page, replacing them with `nil` values
    public mutating func remove(_ page: PageIndex) {
        elements[page] = nil
    }
    
    /// Removes all loaded elements, replacing them with `nil` values
    public mutating func removeAllPages() {
        elements.removeAll(keepingCapacity: true)
    }
}

public extension NSString {
    
    public func byConvertingHTMLToPlainText() -> String {
    
        let stopCharacters = CharacterSet(charactersIn: "< \t\n\r\(0x0085)\(0x000C)\(0x2028)\(0x2029)")
        let newLineAndWhitespaceCharacters = CharacterSet(charactersIn: " \t\n\r\(0x0085)\(0x000C)\(0x2028)\(0x2029)")
        let tagNameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        
        let result = NSMutableString(capacity: length)
        let scanner = Scanner(string: self as String)
        scanner.charactersToBeSkipped = nil
        scanner.caseSensitive = true
        var str: NSString? = nil
        var tagName: NSString? = nil
        var dontReplaceTagWithSpace = false
        
        repeat {
            // Scan up to the start of a tag or whitespace
            if scanner.scanUpToCharacters(from: stopCharacters, into: &str), let s = str {
                result.append(s as String)
                str = nil
            }
            // Check if we've stopped at a tag/comment or whitespace
            if scanner.scanString("<", into: nil) {
                // Stopped at a comment, script tag, or other tag
                if scanner.scanString("!--", into: nil) {
                    // Comment
                    scanner.scanUpTo("-->", into: nil)
                    scanner.scanString("-->", into: nil)
                } else if scanner.scanString("script", into: nil) {
                    // Script tag where things don't need escaping!
                    scanner.scanUpTo("</script>", into: nil)
                    scanner.scanString("</script>", into: nil)
                } else {
                    // Tag - remove and replace with space unless it's
                    // a closing inline tag then dont replace with a space
                    if scanner.scanString("/", into: nil) {
                        // Closing tag - replace with space unless it's inline
                        tagName = nil
                        dontReplaceTagWithSpace = false
                        if scanner.scanCharacters(from: tagNameCharacters, into: &tagName), let t = tagName {
                            tagName = t.lowercased as NSString
                            dontReplaceTagWithSpace =
                                tagName == "a" ||
                                tagName == "b" ||
                                tagName == "i" ||
                                tagName == "q" ||
                                tagName == "span" ||
                                tagName == "em" ||
                                tagName == "strong" ||
                                tagName == "cite" ||
                                tagName == "abbr" ||
                                tagName == "acronym" ||
                                tagName == "label"
                        }
                        // Replace tag with string unless it was an inline
                        if !dontReplaceTagWithSpace && result.length > 0 && !scanner.isAtEnd {
                            result.append(" ")
                        }
                    }
                    // Scan past tag
                    scanner.scanUpTo(">", into: nil)
                    scanner.scanString(">", into: nil)
                }
            } else {
                // Stopped at whitespace - replace all whitespace and newlines with a space
                if scanner.scanCharacters(from: newLineAndWhitespaceCharacters, into: nil) {
                    if result.length > 0 && !scanner.isAtEnd {
                        result.append(" ") // Dont append space to beginning or end of result
                    }
                }
            }
        } while !scanner.isAtEnd
        
        // Cleanup
        
        // Decode HTML entities and return (this isn't included in this gist, but is often important)
        // let retString = (result as String).stringByDecodingHTMLEntities
        
        // Return
        return result as String // retString;
    }
    
}


