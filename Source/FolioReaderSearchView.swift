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
  
    private var searchBar: UISearchBar!
    private var table: UITableView!
    private var matchesStrArray:[String] = []
    private var isSearching: Bool = false
    private var total: Int = 0
    private var isSearchCompleted: Bool = true {
        didSet {
            print("isSearchCompleted = \(isSearchCompleted)")
        }
    }
    private var currentFileIndex: Int = 0
    
    fileprivate var folioReader: FolioReader
    private var readerConfig: FolioReaderConfig
    private var searchResults: [SectionSearchResult] = []
    
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
        
        searchBar = UISearchBar();
        searchBar.delegate = self
        searchBar.frame = .zero
        searchBar.showsCancelButton = false
        searchBar.placeholder = "Search in this book"
        navigationItem.titleView = searchBar
        
        addTableView()
    
        let closeImage = UIImage(readerImageNamed: "icon-navbar-close")?.ignoreSystemTint(withConfiguration: readerConfig)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: closeImage, style: .plain, target: self, action: #selector(dismissView))
    
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
        renderingOperationQueue.cancelAllOperations()
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
                    var innerResults: [SearchResult] = []
                    var sectionSearchResult = SectionSearchResult.init()
                    sectionSearchResult.tocReference = tocRef
                    sectionSearchResult.results = innerResults
                    // Load html from file
                    let mHtml = try? String(contentsOfFile: tocRef?.resource?.fullHref ?? "", encoding: String.Encoding.utf8)
                    guard let document = try? SwiftSoup.parse(mHtml ?? ""),
                        let html = try? document.text(), !html.isEmpty
                    else {
                        return
                    }
                    var mMatches = regex.matches(input: html)
                    guard let matches = mMatches, matches.count > 0 else {
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
                    for i in 0..<matches.count {
                        if operation.isCancelled == true {
                            return
                        }
                        // Inner method
                        func checkPauseSearchingIfNeeded() {
                            if j == maxFileIndex - 1 && i == matches.count - 1 {
                                self.pauseSearchingIfNeeded(currentLoop: j, maxLoop: maxFileIndex)
                                if self.matchesStrArray.count < 30 {
                                    OperationQueue.main.addOperation {
                                        self.searchInThisBook(fileIndex: self.currentFileIndex)
                                    }
                                }
                            }
                        }
                        var matchStr = self.extractText(from: matches[i], fullHtml: html)
                        if matchStr.isEmpty {
                            checkPauseSearchingIfNeeded()
                            continue
                        }
                        matchStr = "...\(matchStr) ..."
                        let searchStringRange = (matchStr as NSString).range(of: searchText, options: .caseInsensitive)
                        let searchResult = SearchResult.init(fullText: matchStr, searchText: searchText, occurrenceInChapter: i + 1, highlightRange: searchStringRange)
                        innerResults.append(searchResult)
                        synchronized(self, {
                            self.matchesStrArray.append(matchStr)
                            if j == maxFileIndex - 1 && i == matches.count - 1 {
                                checkPauseSearchingIfNeeded()
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
                    DispatchQueue.main.async {
                        self.table.reloadData()
                    }
                }
                self.renderingOperationQueue.addOperation(operation)
            }
        }
        
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
        matchesStrArray.removeAll()
        searchResults.removeAll()
        table?.reloadData()
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchInThisBook()
        searchBar.resignFirstResponder()
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            clearAllSearchs()
        }
    }
}

extension FolioReaderSearchView: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        print("matchesStrArray.count \(self.matchesStrArray.count)")
        return searchResults.count
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
        cell.textLabel?.numberOfLines = 0
        
        let text = NSMutableAttributedString(string: section.results[indexPath.row].fullText)
        let range = NSRange(location: 0, length: text.length)
        text.addAttribute(NSAttributedStringKey.backgroundColor, value: UIColor.yellow, range: section.results[indexPath.row].highlightRange)
        cell.textLabel?.attributedText = text
        if isSearching == false &&
            isSearchCompleted == false &&
            table.rowCountUntilSection(section: indexPath.section - 1) + indexPath.row >= self.matchesStrArray.count - 20 {
            searchInThisBook(fileIndex: currentFileIndex)
        }
        return cell
    }
}

extension FolioReaderSearchView: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
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





