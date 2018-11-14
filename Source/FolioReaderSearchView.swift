//
//  FolioReaderSearchView.swift
//  Pods
//
//  Created by taku on 2016/03/08.
//
//

import UIKit
import SwiftSoup

public struct SearchResult {
    let fullText: String
    let searchText: String
    let occurrenceInChapter: Int
    let highlightRange: NSRange
}

open class SectionSearchResult {
    var tocReference: FRTocReference?
    var results: [SearchResult] = []
}

class FolioReaderSearchView: UIViewController {
  
    private let minimumResultsOfPossible = 20
    private let loadMoreTriggerThreshold = 15
    private var searchBar: UISearchBar!
    private var table: UITableView!
    private var matchesStrArray:[String] = []
    private var isSearching: Bool = false
    private var total: Int = 0
    private var isSearchCompleted: Bool = true {
        didSet {
            print("isSearchCompleted = \(isSearchCompleted)")
            if isSearchCompleted == true {
                DispatchQueue.runTaskOnMainThread {
                    self.table.tableFooterView = self.viewForLoadingMore(withText: "Found \(self.matchesStrArray.count) results")
                }
            }
        }
    }
    private var currentFileIndex: Int = 0
    
    fileprivate var folioReader: FolioReader
    private var readerConfig: FolioReaderConfig
    private var searchResults: [SectionSearchResult] = []
    
    lazy var searchingOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8
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
        cancelAllSearchingOperations()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchBar = UISearchBar();
        searchBar.delegate = self
        searchBar.showsCancelButton = false
        searchBar.placeholder = "Search in this book"
        navigationItem.titleView = searchBar
        
        addTableView()
    
        if UIDevice.current.userInterfaceIdiom == .phone {
            let closeImage = UIImage(readerImageNamed: "icon-navbar-close")?.ignoreSystemTint(withConfiguration: readerConfig)
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: closeImage, style: .plain, target: self, action: #selector(dismissView))
        }
        total = self.folioReader.readerContainer?.book.flatTableOfContents.count ?? 0
    }
    
    private func addTableView(){
        table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.tableFooterView = UIView()
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
    }
    
    func willDeinitView() {
        cancelAllSearchingOperations()
    }
    
    private func cancelAllSearchingOperations() {
        searchingOperationQueue.cancelAllOperations()
    }
    
    private func pauseSearchingIfNeeded(currentLoop: Int, maxLoop: Int) {
        if currentLoop == total - 1 {
            self.isSearchCompleted = true
        }
        self.isSearching = false
        self.currentFileIndex = maxLoop
    }
    
    func searchInThisBook(fileIndex: Int = 0){
        guard let searchText = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !searchText.isEmpty
        else {
            return
        }
        guard fileIndex < total else {
            return
        }
        isSearching = true
        isSearchCompleted = false
        let pattern = "([a-zA-Z0-9]|.){0,2}\(searchText)([a-zA-Z0-9]|.){0,2}"
        let regex = RegExp(pattern)
        let maxFileIndex = min(total, fileIndex + 8)
        DispatchQueue.global(qos: .default).async {
            for j in fileIndex..<maxFileIndex {
                let indexPath = IndexPath(row: j, section: 0)
                let tocRef = self.folioReader.readerContainer?.book.flatTableOfContents[indexPath.row]
                let operation = BlockOperation.init()
                operation.addExecutionBlock({ [weak self] in
                    guard let `self` = self else {
                        return
                    }
                    if operation.isCancelled == true {
                        return
                    }
                    var innerResults: [SearchResult] = []
                    var sectionSearchResult = SectionSearchResult.init()
                    sectionSearchResult.tocReference = tocRef
                    sectionSearchResult.results = innerResults
                    
                    func checkPauseSearchingInGlobalLoopIfNeeded() {
                        if j == maxFileIndex - 1 {
                            self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxFileIndex)
                            if self.matchesStrArray.count < self.minimumResultsOfPossible {
                                OperationQueue.main.addOperation {
                                    self.searchInThisBook(fileIndex: self.currentFileIndex)
                                }
                            }
                        }
                    }
                    // Load html from file
                    let mHtml = String.loadSync(contentsOfFile: tocRef?.resource?.fullHref ?? "",
                                                config: self.readerConfig)
                    guard let document = try? SwiftSoup.parse(mHtml),
                        let html = try? document.text(), !html.isEmpty
                    else {
                        checkPauseSearchingInGlobalLoopIfNeeded()
                        return
                    }
                    if operation.isCancelled == true {
                        return
                    }
                    var mMatches = regex.matches(input: html)
                    guard let matches = mMatches, matches.count > 0 else {
                        checkPauseSearchingInGlobalLoopIfNeeded()
                        return
                    }
                    for i in 0..<matches.count {
                        if operation.isCancelled == true {
                            return
                        }
                        // Inner method
                        func checkPauseSearchingInMatchesLoopIfNeeded() {
                            if j == maxFileIndex - 1 && i == matches.count - 1 {
                                self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxFileIndex)
                                if self.matchesStrArray.count < self.minimumResultsOfPossible {
                                    OperationQueue.main.addOperation {
                                        self.searchInThisBook(fileIndex: self.currentFileIndex)
                                    }
                                }
                            }
                        }
                        var matchStr = self.extractText(from: matches[i], fullHtml: html)
                        if matchStr.isEmpty {
                            checkPauseSearchingInMatchesLoopIfNeeded()
                            continue
                        }
                        matchStr = "...\(matchStr) ..."
                        let searchStringRange = (matchStr as NSString).range(of: searchText, options: .caseInsensitive)
                        let searchResult = SearchResult.init(fullText: matchStr, searchText: searchText, occurrenceInChapter: i + 1, highlightRange: searchStringRange)
                        innerResults.append(searchResult)
                        synchronized(self, {
                            self.matchesStrArray.append(matchStr)
                            if j == maxFileIndex - 1 && i == matches.count - 1 {
                                checkPauseSearchingInMatchesLoopIfNeeded()
                            }
                        })
                    }
                    sectionSearchResult.results = innerResults
                    synchronized(self, {
                        if sectionSearchResult.results.count > 0 {
                            self.searchResults.append(sectionSearchResult)
                        }
                    })
                })
                operation.completionBlock = {
                    DispatchQueue.runTaskOnMainThread {
                        if self.table.rowsCount == self.matchesStrArray.count {
                            return
                        }
                        self.table.reloadData()
                    }
                }
                self.searchingOperationQueue.addOperation(operation)
            }
        }
    }
    
    func viewForLoadingMore(withText text: String?) -> UIView {
        let container = UIView(frame: CGRect(origin: .zero, size: CGSize(width: table.bounds.width, height: 44)))
        let sub: UIView
        if let mText = text {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = mText
            label.font = UIFont.systemFont(ofSize: 15)
            label.textAlignment = .center
            sub = label
        } else {
            let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            activityIndicator.startAnimating()
            sub = activityIndicator
        }
        container.addSubview(sub)
        centerView(sub, inContainer: container)
        return container
    }
    
    internal func centerView(_ view: UIView, inContainer container: UIView) {
        let attributes: [NSLayoutAttribute] = [.centerX, .centerY]
        apply(attributes, ofView: view, toView: container)
    }
    internal func apply(_ attributes: [NSLayoutAttribute], ofView childView: UIView, toView containerView: UIView) {
        let constraints = attributes.map {
            return NSLayoutConstraint(item: childView, attribute: $0, relatedBy: .equal,
                                      toItem: containerView, attribute: $0, multiplier: 1, constant: 0)
        }
        containerView.addConstraints(constraints)
    }

    
    private func extractText(from match: NSTextCheckingResult, fullHtml: String) -> String {
        let location = max(0, match.range.location - 40)
        let length = min(fullHtml.count - location, 80)
        let range = NSRange.init(location: location, length: length)
        let matchHtmlStr = (fullHtml as NSString).substring(with: range)
        var matchStr = self.stripTagsFromStr(aHtmlStr: matchHtmlStr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "", options: .regularExpression)
        if let idx = matchStr.firstIndex(of: " ") {
            matchStr = matchStr.substring(from: idx)
        }
        if let idx = matchStr.lastIndex(of: " ") {
            matchStr = matchStr.substring(to: idx)
        }
        return matchStr
    }
    
    private func stripTagsFromStr(aHtmlStr:String)-> String {
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

extension FolioReaderSearchView: UISearchBarDelegate {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        return true
    }
    
    private func clearAllSearchs() {
        cancelAllSearchingOperations()
        matchesStrArray.removeAll()
        searchResults.removeAll()
        table?.reloadData()
        table.tableFooterView = UIView()
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchInThisBook()
        table.tableFooterView = viewForLoadingMore(withText: nil)
        searchBar.resignFirstResponder()
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearAllSearchs()
        }
    }
}

extension FolioReaderSearchView: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        print("matchesStrArray.count \(self.matchesStrArray.count)")
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView.init(frame: CGRect.init(x: 0, y: 0, width: tableView.frame.width, height: 34))
        headerView.backgroundColor = UIColor(red: 247/255, green: 247/255, blue: 247/255, alpha: 1)
        let label = UILabel()
        label.frame = CGRect.init(x: 15, y: 0, width: headerView.frame.width - 30, height: headerView.frame.height)
        label.font = UIFont.boldSystemFont(ofSize: 15)
        headerView.addSubview(label)
        guard searchResults.count > section else {
            return nil
        }
        label.text = searchResults[section].tocReference?.title
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 34
    }
    
    func tableView(_ table: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard searchResults.count > section else {
            return 0
        }
        return searchResults[section].results.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard searchResults.count > section else {
            return nil
        }
        return searchResults[section].tocReference?.title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        guard searchResults.count > indexPath.section else {
            return cell
        }
        let section = searchResults[indexPath.section]
        guard section.results.count > indexPath.row else {
            return cell
        }
        cell.textLabel?.adjustsFontSizeToFitWidth = true
        cell.textLabel?.minimumScaleFactor = 0.8
        cell.textLabel?.numberOfLines = 2
        let text = NSMutableAttributedString(string: section.results[indexPath.row].fullText)
        text.addAttribute(NSAttributedStringKey.backgroundColor, value: UIColor.yellow, range: section.results[indexPath.row].highlightRange)
        cell.textLabel?.attributedText = text
        
        if shouldLoadMore(for: indexPath) {
            searchInThisBook(fileIndex: currentFileIndex)
        }
        return cell
    }
    
    private func shouldLoadMore(for indexPath: IndexPath) -> Bool {
        if isSearching == false &&
            isSearchCompleted == false &&
            table.rowCountUntilBeforeSection(section: indexPath.section) + indexPath.row + 1 >= self.matchesStrArray.count - loadMoreTriggerThreshold {
            return true
        }
        return false
    }
}

extension FolioReaderSearchView: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard searchResults.count > indexPath.section else {
            return
        }
        let section = searchResults[indexPath.section]
        guard let ref = section.tocReference,
            section.results.count > indexPath.row else {
            return
        }
        let searchResult = section.results[indexPath.row]
        self.folioReader.readerCenter?.changePageWith(reference: ref, searchResult: searchResult)
        self.dismiss()
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





