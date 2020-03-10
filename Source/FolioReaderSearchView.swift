//
//  FolioReaderSearchView.swift
//  Pods
//
//  Created by taku on 2016/03/08.
//
//

import UIKit

public struct FolioSearchResult {
    let fullText: String
    let searchText: String
    let occurrenceInChapter: Int
    let wordRange: NSRange
    let rangy: String
}

private struct ExtractedSearchResult {
    let displayedText: String
    let wordRange: NSRange
}

protocol FolioReaderSearchViewDelegate: class {
    func didClearAllSearch(view: FolioReaderSearchView)
    func searchingDidStart(keyword: String, view: FolioReaderSearchView)
    func searchingDidReturn(keyword: String, view: FolioReaderSearchView)
    func didSelectSearchResult(keyword: String, result: FolioSearchResult, section: FolioSearchDBSectionResult,
                               chapterName: String, view: FolioReaderSearchView)
}

class FolioReaderSearchView: UIViewController {
  
    // Constants
    let defaultTextColor = UIColor.darkGray
    let darkModeTextColor = UIColor(white: 1, alpha: 0.5)
    let defaultNavigationBarBackgroundColor = UIColor.white
    let darkModeNavigationBarBackgroundColor = UIColor(rgba: "#333333")
    let defaultSearchBarBackgroundColor = UIColor.init(rgba: "#F0F0F0")
    let darkModeSearchBarBackgroundColor = UIColor.init(rgba: "#262627")
    let defaultHeaderBackgroundColor = UIColor.init(rgba: "#F0F0F0")
    let darkModeHeaderBackgroundColor = UIColor.init(rgba: "#474747")
    let defaultHeaderTextColor = UIColor.init(white: 0, alpha: 0.7)
    let darkModeHeaderTextColor = UIColor.init(rgba: "#B0B0B0")
    
    var debugMode: Bool = false
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
                    self.table.tableFooterView = self.viewForLoadingMore(withText: self.footerText)
                }
            }
        }
    }
    private var currentSectionIndex: Int = 0
    private var searchResults: [FolioSearchDBSectionResult] = []
    private var currentSearchText: String?
    
    fileprivate var folioReader: FolioReader
    private var readerConfig: FolioReaderConfig
    weak var delegate: FolioReaderSearchViewDelegate?
    lazy var searchingOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var searchingDidReturn: Bool = false
    
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
    
    override var preferredStatusBarStyle : UIStatusBarStyle {
        return self.folioReader.isNight(.lightContent, .default)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if (searchBar.text?.count ?? 0) == 0 {
            searchBar.becomeFirstResponder()
        }
        configureNavBar()
        table.backgroundColor = self.folioReader.isNight(self.readerConfig.nightModeMenuBackground, self.readerConfig.menuBackgroundColor)
        table.separatorColor = self.folioReader.isNight(self.readerConfig.nightModeSeparatorColor, self.readerConfig.menuSeparatorColor)
        table.reloadData()
    }
    
    func configureNavBar() {
        let navBackground = self.folioReader.isNight(darkModeNavigationBarBackgroundColor, defaultNavigationBarBackgroundColor)
        let tintColor = self.readerConfig.tintColor
        let navText = self.folioReader.isNight(UIColor.white, UIColor.black)
        let font = UIFont(name: "Avenir-Light", size: 17)!
        setTranslucentNavigation(false, color: navBackground, tintColor: tintColor, titleColor: navText, andFont: font)
        if #available(iOS 13, *) {
            searchBar.searchTextField.backgroundColor = self.folioReader.isNight(darkModeSearchBarBackgroundColor, defaultSearchBarBackgroundColor)
            searchBar.searchTextField.textColor = self.folioReader.isNight(darkModeTextColor, defaultTextColor)
        } else {
            if let txfSearchField = searchBar.value(forKey: "_searchField") as? UITextField {
                txfSearchField.backgroundColor = self.folioReader.isNight(darkModeSearchBarBackgroundColor, defaultSearchBarBackgroundColor)
                txfSearchField.textColor = self.folioReader.isNight(darkModeTextColor, defaultTextColor)
            }
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
        table.dataSource = self
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
    
    private var footerText: String {
        if self.matchesStrArray.count == 1 {
            return "Found \(self.matchesStrArray.count) result"
        }
        return "Found \(self.matchesStrArray.count) results"
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
        guard let searchIndexFilePath = folioReader.readerContainer?.readerConfig.searchIndexFilePath,
            searchIndexFilePath.isEmpty == false else {
            return []
        }
        var sections = FolioSearcher().search(term: searchTerm, dbPath: searchIndexFilePath) ?? []
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
        let pattern = "\(searchText)"
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
        let regex = RegExp(escapedPattern)

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
                        if self.debugMode {
                            self.searchResults.append(section)
                        }
                        if section.title.isEmpty {
                            section.title = section.fileName
                        }
                        return
                    }
                    if section.title.isEmpty {
                        section.title = self.title(of: rawHtml) ?? section.fileName
                    }
                    html = self.cleanHtml(html: html)
                    if operation.isCancelled == true {
                        return
                    }
                    var mMatches = regex.matches(input: html)
                    guard let matches = mMatches, matches.count > 0 else {
                        checkPauseSearchingInGlobalLoopIfNeeded()
                        if self.debugMode {
                            self.searchResults.append(section)
                        }
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
                        let rangy = (section.dbResults.count > i) ? section.dbResults[i].path : ""
                        let searchResult = FolioSearchResult.init(fullText: extractedResult.displayedText, searchText: searchText, occurrenceInChapter: i + 1, wordRange: extractedResult.wordRange, rangy: rangy)
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
                        if self.searchingDidReturn == false {
                            self.searchingDidReturn = true
                            self.delegate?.searchingDidReturn(keyword: searchText, view: self)
                        }
                        if self.isSearchCompleted == true {
                            self.table.tableFooterView = self.viewForLoadingMore(withText: self.footerText)
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
                            .replacingOccurrences(of: "\u{00a0}", with: " ")
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
        if let idx = matchStr.lastIndex(of: " "),
            idx.encodedOffset >= wordRange.location + wordRange.length {
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
        delegate?.didClearAllSearch(view: self)
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
        self.delegate?.searchingDidStart(keyword: searchText, view: self)
        self.searchingDidReturn = false
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
        headerView.backgroundColor = folioReader.isNight(darkModeHeaderBackgroundColor, defaultHeaderBackgroundColor)
        let label = UILabel()
        label.frame = CGRect.init(x: 15, y: 0, width: headerView.frame.width - 30, height: headerView.frame.height)
        label.font = UIFont.boldSystemFont(ofSize: 15)
        label.textColor = folioReader.isNight(darkModeHeaderTextColor, defaultHeaderTextColor)
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
        cell.backgroundColor = UIColor.clear
        cell.contentView.backgroundColor = UIColor.clear
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
        cell.textLabel?.textColor = self.folioReader.isNight(UIColor(white: 1, alpha: 0.5), UIColor.darkGray)

        let text = NSMutableAttributedString(string: result.fullText)
        if text.string.rangeIsValid(range: result.wordRange) {
            text.addAttribute(NSAttributedStringKey.backgroundColor, value: UIColor.yellow, range: result.wordRange)
            text.addAttribute(NSAttributedStringKey.foregroundColor, value: UIColor.darkGray, range: result.wordRange)
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
        var chapterName = ""
        if searchResults.count > indexPath.section {
            chapterName = searchResults[indexPath.section].title
        }
        self.delegate?.didSelectSearchResult(keyword: currentSearchText ?? "", result: searchResult, section: section, chapterName: chapterName, view: self)
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






