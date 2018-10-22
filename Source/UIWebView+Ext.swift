//
//  UIWebView+Ext.swift
//  AEXML
//
//  Created by Dung Le on 10/20/18.
//

import Foundation

extension UIWebView {
    open func isFinishedLoad() -> Bool {
        let string = self.stringByEvaluatingJavaScript(from: "document.readyState") ?? ""
        return string == "complete" && !self.isLoading
    }
    
    open var didFinishLoadEmptyString: Bool {
        let length = self.stringByEvaluatingJavaScript(from: "document.getElementsByTagName('body')[0].innerHTML.length") ?? "0"
        return Int(length) == 0
    }
    
    open var offsetHeight: CGFloat {
        let heightString = self.stringByEvaluatingJavaScript(from: "document.body.offsetHeight")
        return CGFloat((heightString as NSString? ?? "").doubleValue)
    }
    
    open var offsetWidth: CGFloat {
        let widthString = self.stringByEvaluatingJavaScript(from: "document.body.offsetWidth")
        return CGFloat((widthString as NSString? ?? "").doubleValue)
    }
    
    open var scrollHeight: CGFloat {
        let heightString = self.stringByEvaluatingJavaScript(from: "document.body.scrollHeight")
        return CGFloat((heightString as NSString? ?? "").doubleValue)
    }
    
    open var scrollWidth: CGFloat {
        let widthString = self.stringByEvaluatingJavaScript(from: "document.body.scrollWidth")
        return CGFloat((widthString as NSString? ?? "").doubleValue)
    }
}
