//
//  RawHTML.swift
//  Cachi
//
//  Created by tomas on 23/12/20.
//

import Foundation
import Vaux

class RawHTML: HTML {
    private let rawContent: String
    
    init(rawContent: String) {
        self.rawContent = rawContent.replacingOccurrences(of: "\n", with: "<br />\n").replacingOccurrences(of: "  ", with: "&nbsp;&nbsp;")
    }
    
    func renderAsHTML(into stream: HTMLOutputStream, attributes: [Attribute]) {
        var output = stream.output
        output.write(rawContent)
    }
    
    func getTag() -> String? {
        return nil
    }
}
