import CachiKit
import Foundation
import os
import Vapor
import Vaux
import ZippyJSON

struct CoverageRouteHTML: Routable {
    static let path: String = "/html/coverage"

    let method = HTTPMethod.GET
    let description: String = "Coverage in html (pass identifier)"

    func respond(to req: Request) throws -> Response {
        os_log("HTML coverage request received", log: .default, type: .info)

        let resultBundles = State.shared.resultBundles

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier })
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
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
                    script(filepath: Filepath(name: ScriptRoute.fileCoverageUrlString(resultIdentifier: resultBundle.identifier), path: ""))
                case .folders:
                    script(filepath: Filepath(name: ScriptRoute.foldersCoverageUrlString(resultIdentifier: resultBundle.identifier), path: ""))
                }
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, state: state, backUrl: backUrl) }.class("sticky-top").id("top-bar")

                    div { table(child: {}).id("coverage-table") }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    static func urlString(resultIdentifier: String, backUrl: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: resultIdentifier),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func floatingHeaderHTML(result: ResultBundle, state: RouteState, backUrl: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.testStartDate)

        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"

        return div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: ImageRoute.arrowLeftImageUrl())
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
                            link(url: currentUrl(result: result, state: linkState, backUrl: backUrl)) { linkState.showFilter.rawValue.capitalized }.class(state.showFilter == linkState.showFilter ? "button-selected" : "button")
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
        var components = URLComponents(string: Self.path)!
        components.queryItems = [
            .init(name: "id", value: result.identifier),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString + state.description
    }
}

private extension CoverageRouteHTML {
    struct RouteState: Codable, CustomStringConvertible {
        static let key = "state"

        enum ShowFilter: String, Codable, CaseIterable {
            case files, folders
        }

        var showFilter: ShowFilter
        var filterQuery: String
        var hideFilters: Bool

        init(queryItems: [URLQueryItem]?) {
            self.init(hexadecimalRepresentation: queryItems?.first(where: { $0.name == Self.key })?.value)
        }

        init(hexadecimalRepresentation: String?) {
            if let hexadecimalRepresentation,
               let data = Data(hexadecimalRepresentation: hexadecimalRepresentation),
               let state = try? ZippyJSONDecoder().decode(RouteState.self, from: data) {
                self.showFilter = state.showFilter
                self.filterQuery = state.filterQuery
                self.hideFilters = state.hideFilters
            } else {
                self.showFilter = .files
                self.filterQuery = ""
                self.hideFilters = false
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

private enum CoverageShowFilter: String, CaseIterable {
    case files, folders

    func params() -> String {
        "&\(Self.queryName)=\(rawValue)"
    }

    static let queryName = "coverage_show"
}
