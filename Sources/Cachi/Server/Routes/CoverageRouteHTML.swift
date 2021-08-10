import Foundation
import HTTPKit
import os
import Vaux
import CachiKit


private enum CoverageShowFilter: String, CaseIterable {
    case files, folders
    
    func params() -> String {
        return "&\(Self.queryName)=\(self.rawValue)"
    }
    
    static let queryName = "coverage_show"
}

struct CoverageRouteHTML: Routable {
    let path: String = "/html/coverage"
    let description: String = "Coverage in html (pass identifier)"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML coverage request received", log: .default, type: .info)
        
        let resultBundles = State.shared.resultBundles
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier }) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        var parentParameters = ""
        if let backShowQueryItem = queryItems.first(where: { $0.name == "show" }) {
            parentParameters = "&\(backShowQueryItem.name)=\(backShowQueryItem.value ?? "")"
        }
        
        let coverageShowFilter = CoverageShowFilter(rawValue: queryItems.first(where: { $0.name == CoverageShowFilter.queryName })?.value ?? "") ?? .files

        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                script(filepath: Filepath(name: "/script?type=coverage-files&id=\(resultBundle.identifier)\(parentParameters)", path: ""))
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, coverageShowFilter: coverageShowFilter, parentParameters: parentParameters) }.class("sticky-top").id("top-bar")
                    
                    div { table(child: {}).id("coverage-table") }
                }.class("main-container background")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, coverageShowFilter: CoverageShowFilter, parentParameters: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.date)
        
        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
                
        return div {
            div {
                div {
                    link(url: "result?id=\(result.identifier)\(parentParameters)") {
                        image(url: "/image?imageArrorLeft")
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    resultTitle
                }.class("header")
                div { resultSubtitle }.class("color-subtext indent1")
                div { resultDate }.class("color-subtext indent1").floatRight()
                div { resultDevice }.class("color-subtext indent1")
            }.class("row light-bordered-container indent1")
            div {
                div {
                    var blocks = [HTML]()
                    
                    let filteringFiles = coverageShowFilter == CoverageShowFilter.files
                    let filteringFolders = coverageShowFilter == CoverageShowFilter.folders
                    
                    blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(parentParameters)\(CoverageShowFilter.files.params())") { CoverageShowFilter.files.rawValue.capitalized }.class(filteringFiles ? "button-selected" : "button"))
                    blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(parentParameters)\(CoverageShowFilter.folders.params())") { CoverageShowFilter.folders.rawValue.capitalized }.class(filteringFolders ? "button-selected" : "button"))
                    
                    blocks.append(span { span { "Filter" }.id("filter-placeholder"); input().id("filter-input").attr("placeholder", filteringFiles ? "File name" : "Folder name") }.id("filter-search"))
                    
                    return HTMLBuilder.buildBlocks(blocks)
                }
            }.class("row light-bordered-container indent2")
        }
    }
}
