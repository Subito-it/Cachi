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
        
        let state = RouteState(queryItems: queryItems)
        let backUrl = queryItems.backUrl
        
        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                switch state.showFilter {
                case .files:
                    script(filepath: Filepath(name: "/script?type=coverage-files&id=\(resultBundle.identifier)", path: ""))
                case .folders:
                    script(filepath: Filepath(name: "/script?type=coverage-folders&id=\(resultBundle.identifier)", path: ""))
                }
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, state: state, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    
                    div { table(child: {}).id("coverage-table") }
                }.class("main-container background")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, state: RouteState, backUrl: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.date)
        
        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
                        
        return div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: "/image?imageArrorLeft")
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    resultTitle
                }.class("header")
                div { resultSubtitle }.class("color-subtext subheader")
                div { resultDate }.class("color-subtext indent1").floatRight()
                div { resultDevice }.class("color-subtext subheader")
            }.class("row light-bordered-container indent1")
            div {
                div {
                    var blocks = [HTML]()
                    
                    if state.hideFilters {
                        blocks.append(span { state.showFilter.rawValue.capitalized; "&nbsp;" }.class("bold"))
                    } else {
                        var mState = state
                        let linkForState: (RouteState) -> HTML = { linkState in
                            return link(url: currentUrl(result: result, state: linkState, backUrl: backUrl)) { linkState.showFilter.rawValue.capitalized }.class(state.showFilter == linkState.showFilter ? "button-selected" : "button")
                        }
                        
                        mState.showFilter = .files
                        blocks.append(linkForState(mState))

                        mState.showFilter = .folders
                        blocks.append(linkForState(mState))
                    }
                    
                    blocks.append(span { span { "Filter" }.id("filter-placeholder"); input().id("filter-input").attr("placeholder", state.showFilter == .files ? "File name" : "Folder name") }.id("filter-search"))
                    
                    return HTMLBuilder.buildBlocks(blocks)
                }
            }.class("row light-bordered-container indent2")
        }
    }
    
    private func currentUrl(result: ResultBundle, state: RouteState, backUrl: String) -> String {
        "\(self.path)?id=\(result.identifier)\(state)&back_url=\(backUrl.hexadecimalRepresentation)"
    }
}

private extension CoverageRouteHTML {
    struct RouteState: Codable, CustomStringConvertible {
        static let key = "state"
        
        enum ShowFilter: String, Codable, CaseIterable { case files, folders }
        
        var showFilter: ShowFilter
        var filterQuery: String
        var hideFilters: Bool
        
        init(queryItems: [URLQueryItem]?) {
            self.init(hexadecimalRepresentation: queryItems?.first(where: { $0.name == Self.key})?.value)
        }

        init(hexadecimalRepresentation: String?) {
            if let hexadecimalRepresentation = hexadecimalRepresentation,
               let data = Data(hexadecimalRepresentation: hexadecimalRepresentation),
               let state = try? JSONDecoder().decode(RouteState.self, from: data) {
                showFilter = state.showFilter
                filterQuery = state.filterQuery
                hideFilters = state.hideFilters
            } else {
                showFilter = .files
                filterQuery = ""
                hideFilters = false
            }
        }
        
        var description: String {
            guard let hexRepresentation = (try? JSONEncoder().encode(self))?.hexadecimalRepresentation else {
                return ""
            }
            
            return "&\(Self.key)=" + hexRepresentation
        }
    }
}
