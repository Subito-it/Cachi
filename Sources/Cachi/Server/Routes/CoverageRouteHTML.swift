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
        
        var queryParameters = ""
        for queryItem in queryItems {
            guard queryItem.name != "id" else { continue }
            queryParameters += "&\(queryItem.name)=\(queryItem.value ?? "")"
        }

        let coverageShowFilter = CoverageShowFilter(rawValue: queryItems.first(where: { $0.name == CoverageShowFilter.queryName })?.value ?? "") ?? .files

        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                switch coverageShowFilter {
                case .files:
                    script(filepath: Filepath(name: "/script?type=coverage-files&id=\(resultBundle.identifier)\(queryParameters)", path: ""))
                case .folders:
                    script(filepath: Filepath(name: "/script?type=coverage-folders&id=\(resultBundle.identifier)\(queryParameters)", path: ""))
                }
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, coverageShowFilter: coverageShowFilter, queryItems: queryItems) }.class("sticky-top").id("top-bar")
                    
                    div { table(child: {}).id("coverage-table") }
                }.class("main-container background")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, coverageShowFilter: CoverageShowFilter, queryItems: [URLQueryItem]) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.date)
        
        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
        
        let filteredFolder = queryItems.first(where: { $0.name == "folder" })?.value
        let isFilteringFolders = filteredFolder != nil
        var queryParameters = ""
        for queryItem in queryItems {
            guard queryItem.name != "id" && queryItem.name != "coverage_show" && queryItem.name != "folder" && (queryItem.name != "q" || isFilteringFolders) else { continue }
            queryParameters += "&\(queryItem.name)=\(queryItem.value ?? "")"
        }
                
        return div {
            div {
                div {
                    if isFilteringFolders {
                        link(url: "\(self.path)?id=\(result.identifier)\(queryParameters)\(CoverageShowFilter.folders.params())") {
                            image(url: "/image?imageArrorLeft")
                                .iconStyleAttributes(width: 8)
                                .class("icon color-svg-text")
                        }

                    } else {
                        link(url: "result?id=\(result.identifier)\(queryParameters)") {
                            image(url: "/image?imageArrorLeft")
                                .iconStyleAttributes(width: 8)
                                .class("icon color-svg-text")
                        }
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
                    
                    if !isFilteringFolders {
                        blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(queryParameters)\(CoverageShowFilter.files.params())") { CoverageShowFilter.files.rawValue.capitalized }.class(coverageShowFilter == CoverageShowFilter.files ? "button-selected" : "button"))
                        blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(queryParameters)\(CoverageShowFilter.folders.params())") { CoverageShowFilter.folders.rawValue.capitalized }.class(coverageShowFilter == CoverageShowFilter.folders ? "button-selected" : "button"))
                    } else {
                        blocks.append(span { filteredFolder!; "&nbsp;" }.class("bold"))
                    }
                    
                    blocks.append(span { span { "Filter" }.id("filter-placeholder"); input().id("filter-input").attr("placeholder", coverageShowFilter == CoverageShowFilter.files ? "File name" : "Folder name") }.id("filter-search"))
                    
                    return HTMLBuilder.buildBlocks(blocks)
                }
            }.class("row light-bordered-container indent2")
        }
    }
}
