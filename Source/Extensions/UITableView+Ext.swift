//
//  UITableView+Ext.swift
//  AEXML
//
//  Created by Dung Le on 11/14/18.
//

import Foundation

extension UITableView {
    var rowsCount: Int {
        let sections = self.numberOfSections
        if sections == 0 {
            return 0
        }
        var rows = 0
        for i in 0...sections - 1 {
            rows += self.numberOfRows(inSection: i)
        }
        return rows
    }
    
    func rowCountUntilBeforeSection(section: Int) -> Int {
        guard section > 0 else {
            return 0
        }
        let sections = min(self.numberOfSections, section)
        var rows = 0
        for i in 0...sections - 1 {
            rows += self.numberOfRows(inSection: i)
        }
        return rows
    }
}
