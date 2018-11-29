//
//  FolioReaderSearchView.swift
//  Pods
//
//  Created by taku on 2016/03/08.
//
//

import UIKit
import SwiftSoup

public struct FolioSearchResult {
    let fullText: String
    let searchText: String
    let occurrenceInChapter: Int
    let wordRange: NSRange
}

private struct ExtractedSearchResult {
    let displayedText: String
    let wordRange: NSRange
}

class FolioReaderSearchView: UIViewController {
  
    private let minimumResultsOfPossible = 20
    private let loadMoreTriggerThreshold = 10
    private var searchBar: UISearchBar!
    private var table: UITableView!
    private var matchesStrArray:[String] = []
    private var isSearching: Bool = false
    private var total: Int = 0
    private var isSearchCompleted: Bool = true {
        didSet {
            debugLog("isSearchCompleted \(isSearchCompleted)")
            if self.isSearchCompleted == true {
                DispatchQueue.runTaskOnMainThread {
                    self.table.tableFooterView = self.viewForLoadingMore(withText: "Found \(self.matchesStrArray.count) results")
                }
            }
        }
    }
    private var currentSectionIndex: Int = 0
    private var searchResults: [FolioSearchDBSectionResult] = []
    private var currentSearchText: String?
    
    fileprivate var folioReader: FolioReader
    private var readerConfig: FolioReaderConfig
    
    lazy var searchingOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if (searchBar.text?.count ?? 0) == 0 {
            searchBar.becomeFirstResponder()
        }
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
        self.currentSectionIndex = maxLoop
    }
    
    private func pauseSearching() {
        self.isSearchCompleted = true
        self.isSearching = false
    }
    
    public func getChapterName(page: Int) -> String? {
        for item in self.folioReader.readerContainer?.book.flatTableOfContents ?? [] {
            guard
                let reference = self.folioReader.readerContainer?.book.spine.spineReferences[safe: page],
                let resource = item.resource,
                (resource == reference.resource),
                let title = item.title else {
                continue
            }
            return title
        }
        return nil
    }
    
    func indexedData(for searchTerm: String) -> [FolioSearchDBSectionResult] {
        // setup data
        var sections = FolioSearcher().search(term: searchTerm, bookId: "4610") ?? []
        let spineRefs = self.folioReader.readerContainer?.book.spine.spineReferences ?? []
        for section in sections {
            guard let index = spineRefs.firstIndex(where: { $0.resource.href == section.fileName }) else {
                continue
            }
            let spineRef = spineRefs[index].resource
            section.resource = spineRef
            section.pageIndex = index
            section.title = self.getChapterName(page: index) ?? ""
        }
        sections = sections.sorted { $0.pageIndex < $1.pageIndex }
        return sections
    }
    
    func searchInThisBook(sectionIndex: Int) {
        guard let searchText = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !searchText.isEmpty
        else {
            pauseSearching()
            return
        }
        currentSearchText = searchText
        let sections = indexedData(for: searchText)
        total = sections.count
        guard total > 0, sectionIndex < total else {
            pauseSearching()
            return
        }
        
        // begin search
        isSearching = true
        isSearchCompleted = false
        let pattern = "([a-zA-Z0-9]|.){0,0}\(searchText)([a-zA-Z0-9]|.){0,0}"
        let regex = RegExp(pattern)
        let maxIndex = min(sections.count, sectionIndex + 8)
        DispatchQueue.global(qos: .default).async {
            for j in sectionIndex..<maxIndex {
                let section = sections[j]
                let operation = BlockOperation.init()
                operation.addExecutionBlock({ [weak self] in
                    guard let `self` = self else {
                        return
                    }
                    if operation.isCancelled == true {
                        return
                    }
                    var innerResults: [FolioSearchResult] = []
                    section.results = innerResults
                    
                    func checkPauseSearchingInGlobalLoopIfNeeded() {
                        guard j == maxIndex - 1 else {
                            return
                        }
                        self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxIndex)
                        if self.matchesStrArray.count < self.minimumResultsOfPossible {
                            OperationQueue.main.addOperation {
                                self.searchInThisBook(sectionIndex: self.currentSectionIndex)
                            }
                        }
                    }
                    
                    // Load html from file
                    let rawHtml = String.loadSync(contentsOfFile: section.resource?.fullHref ?? "",
                                                config: self.readerConfig)
                    let data = Data(rawHtml.utf8)
                    let attributedString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
                    guard var html = attributedString?.string, !html.isEmpty else {
                        checkPauseSearchingInGlobalLoopIfNeeded()
                        return
                    }
                    if section.title.isEmpty {
                        section.title = self.title(of: rawHtml) ?? ""
                    }
                    html = self.cleanHtml(html: html)
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
                            guard j == maxIndex - 1 && i == matches.count - 1 else {
                                return
                            }
                            self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxIndex)
                            if self.matchesStrArray.count < self.minimumResultsOfPossible {
                                OperationQueue.main.addOperation {
                                    self.searchInThisBook(sectionIndex: self.currentSectionIndex)
                                }
                            }
                        }
                        let extractedResult = self.extractText(from: matches[i], fullHtml: html)
                        if extractedResult.displayedText.isEmpty {
                            checkPauseSearchingInMatchesLoopIfNeeded()
                            continue
                        }
                        let searchResult = FolioSearchResult.init(fullText: extractedResult.displayedText, searchText: searchText, occurrenceInChapter: i + 1, wordRange: extractedResult.wordRange)
                        innerResults.append(searchResult)
                        synchronized(self, {
                            self.matchesStrArray.append(extractedResult.displayedText)
                            if j == maxIndex - 1 && i == matches.count - 1 {
                                checkPauseSearchingInMatchesLoopIfNeeded()
                            }
                        })
                        
                    }
                    section.results = innerResults
                    synchronized(self, {
                        if section.results.count > 0 {
                            self.searchResults.append(section)
                        }
                    })
                })
                operation.completionBlock = {
                    DispatchQueue.runTaskOnMainThread {
                        self.searchResults.sort { $0.pageIndex < $1.pageIndex }
                        self.table.reloadData()
                        if self.isSearchCompleted == true {
                            self.table.tableFooterView = self.viewForLoadingMore(withText: "Found \(self.matchesStrArray.count) results")
                        }
                    }
                }
                self.searchingOperationQueue.addOperation(operation)
            }
        }
    }
    
    private func title(of html: String) -> String? {
        let startPoint = "<title>"
        let endPoint = "</title>"
        guard let startRange = html.range(of: startPoint),
            let endRange = html.range(of: endPoint) else {
            return nil
        }
        let title = html[startRange.upperBound..<endRange.lowerBound]
        return String(title)
        
    }
    
    private func cleanHtml(html: String) -> String {
        let finalHtml = html.trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "\n", with: " ", options: .regularExpression)
                            .replacingOccurrences(of: "\u{e2}", with: " ")
        return finalHtml
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
    
    private func extractText(from match: NSTextCheckingResult, fullHtml: String) -> ExtractedSearchResult {
        let location = max(0, match.range.location - 40)
        let length = min(fullHtml.count - location, 80)
        var wordRange = NSRange(location: match.range.location - location, length: match.range.length)
        let range = NSRange.init(location: location, length: length)
        var matchStr = (fullHtml as NSString).substring(with: range)
        if match.range.location == 0 {
            if let idx = matchStr.lastIndex(of: " ") {
                matchStr = String(matchStr[..<idx])
            }
            return ExtractedSearchResult(displayedText: matchStr, wordRange: wordRange)
        }
        if let idx = matchStr.firstIndex(of: " "),
            wordRange.location - idx.encodedOffset >= 0 {
            matchStr = String(matchStr[idx...])
            wordRange.location -= idx.encodedOffset
        }
        if let idx = matchStr.lastIndex(of: " ") {
            matchStr = String(matchStr[..<idx])
        }
        return ExtractedSearchResult(displayedText: matchStr, wordRange: wordRange)
    }
    
    private func stripTags(from html:String)-> String {
        var htmlStr = html
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
        total = 0
        currentSearchText = nil
        cancelAllSearchingOperations()
        matchesStrArray.removeAll()
        searchResults.removeAll()
        table?.reloadData()
        table.tableFooterView = UIView()
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard let searchText = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !searchText.isEmpty, currentSearchText != searchText
        else {
            return
        }
        table.tableFooterView = viewForLoadingMore(withText: nil)
        clearAllSearchs()
        searchInThisBook(sectionIndex: 0)
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearAllSearchs()
        }
    }
}

extension FolioReaderSearchView: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        debugLog("matchesStrArray.count \(self.matchesStrArray.count)")
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
        label.text = searchResults[section].title
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
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        guard searchResults.count > indexPath.section else {
            return cell
        }
        let section = searchResults[indexPath.section]
        guard section.results.count > indexPath.row else {
            return cell
        }
        let result = section.results[indexPath.row]
        cell.textLabel?.adjustsFontSizeToFitWidth = true
        cell.textLabel?.minimumScaleFactor = 0.8
        cell.textLabel?.numberOfLines = 3
        let text = NSMutableAttributedString(string: result.fullText)
        if text.string.rangeIsValid(range: result.wordRange) {
            text.addAttribute(NSAttributedStringKey.backgroundColor, value: UIColor.yellow, range: result.wordRange)
            text.insert(NSAttributedString.init(string: "...", attributes: nil), at: 0)
            text.append(NSAttributedString.init(string: " ...", attributes: nil))
        }
        cell.textLabel?.attributedText = text
        
        if shouldLoadMore(for: indexPath) {
            searchInThisBook(sectionIndex: currentSectionIndex)
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
        guard section.pageIndex >= 0,
            section.results.count > indexPath.row else {
            return
        }
        let searchResult = section.results[indexPath.row]
        self.folioReader.readerCenter?.changePageWith(page: section.pageIndex, searchResult: searchResult)
        self.dismiss()
    }
}


func synchronized<T>(_ lock: AnyObject, _ body: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    return try body()
}

extension String {
    func rangeIsValid(range: NSRange) -> Bool {
        return range.location <= self.count &&
            range.location != NSNotFound &&
            (range.location + range.length <= self.count)
    }
}






