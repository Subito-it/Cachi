import Foundation
import os
import Vapor
import Vaux

struct ResultsStatRouteHTML: Routable {
    static let path: String = "/html/results_stat"

    let method = HTTPMethod.GET
    let description: String = "Stats of results in html"

    func respond(to req: Request) throws -> Response {
        os_log("HTML results request received", log: .default, type: .info)

        guard let components = req.urlComponents() else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let allTargets = State.shared.allTargets()

        guard allTargets.count > 0 else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "No targets found..."))
        }

        let queryItems = components.queryItems ?? []
        let typeFilter = ResultBundle.TestStatsType(rawValue: queryItems.first(where: { $0.name == ResultBundle.TestStatsType.queryName })?.value ?? "") ?? .flaky
        let selectedTarget = queryItems.first(where: { $0.name == "target" })?.value ?? allTargets.first!
        var rawSelectedDevice = queryItems.first(where: { $0.name == "device" })?.value
        let rawWindowSize = queryItems.first(where: { $0.name == "window_size" })?.value ?? ""

        let backUrl = components.queryItems?.backUrl ?? ""

        let allDevices = State.shared.allDevices(in: selectedTarget)

        guard allDevices.count > 0 else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "No target or device found..."))
        }

        if rawSelectedDevice == nil || !allDevices.map(\.description).contains(rawSelectedDevice!) {
            rawSelectedDevice = allDevices.first!.description
        }

        guard let selectedDevice = State.Device(rawDescription: rawSelectedDevice) else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Empty selected device..."))
        }

        let windowSize = Int(rawWindowSize) ?? State.defaultStatWindowSize

        let testStats = State.shared.resultsTestStats(target: selectedTarget, device: selectedDevice, type: typeFilter, windowSize: windowSize)

        let document = html {
            head {
                title("Cachi - Results")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(targets: allTargets, selectedTarget: selectedTarget, devices: allDevices.map(\.description), selectedDevice: rawSelectedDevice!, typeFilter: typeFilter, windowSize: windowSize, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(testStats: testStats, selectedTarget: selectedTarget, selectedDevice: rawSelectedDevice!, statType: typeFilter, backUrl: backUrl) }
                }.class("main-container background")
                script(filepath: Filepath(name: ScriptRoute.resultStatsUrlString(), path: ""))
            }
        }

        return document.httpResponse()
    }

    static func urlString(backUrl: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func floatingHeaderHTML(targets: [String], selectedTarget: String, devices: [String], selectedDevice: String, typeFilter: ResultBundle.TestStatsType, windowSize: Int, backUrl: String) -> HTML {
        div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: ImageRoute.arrowLeftImageUrl())
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    "Test statistics"
                }.class("header")
            }.class("row light-bordered-container indent1")
            div {
                select {
                    forEach(targets) { target in
                        option { target }.attr(target == selectedTarget ? "selected" : "", nil)
                    }
                }.id("target")
                select {
                    forEach(devices) { device in
                        option { device }.attr(device == selectedDevice ? "selected" : "", nil)
                    }
                }.id("device")
                "&nbsp;&nbsp;"
                span {
                    span { "Window size" }.id("filter-placeholder")
                    input().id("filter-input")
                        .attr("value", "\(windowSize)")
                        .style([.init(key: "width", value: "25px")])
                }
                .id("filter-search")
                .style([.init(key: "width", value: "140px")])

                "&nbsp;&nbsp;&nbsp;&nbsp;"
                link(url: "\(currentUrl(selectedTarget: selectedTarget, selectedDevice: selectedDevice, statType: .flaky, backUrl: backUrl))") { ResultBundle.TestStatsType.flaky.rawValue.capitalized }.class(typeFilter == .flaky ? "button-selected" : "button")
                link(url: "\(currentUrl(selectedTarget: selectedTarget, selectedDevice: selectedDevice, statType: .slowest, backUrl: backUrl))") { ResultBundle.TestStatsType.slowest.rawValue.capitalized }.class(typeFilter == .slowest ? "button-selected" : "button")
                link(url: "\(currentUrl(selectedTarget: selectedTarget, selectedDevice: selectedDevice, statType: .fastest, backUrl: backUrl))") { ResultBundle.TestStatsType.fastest.rawValue.capitalized }.class(typeFilter == .fastest ? "button-selected" : "button")
            }.class("row light-bordered-container indent2")
        }
    }

    private func resultsTableHTML(testStats: [ResultBundle.TestStats], selectedTarget: String, selectedDevice: String, statType: ResultBundle.TestStatsType, backUrl: String) -> HTML {
        table {
            columnGroup(styles: [TableColumnStyle(span: 1, styles: [StyleAttribute(key: "wrap-word", value: "break-word")]),
                                 TableColumnStyle(span: 2, styles: [StyleAttribute(key: "width", value: "105px")]),
                                 TableColumnStyle(span: 1, styles: [StyleAttribute(key: "width", value: "80px")]),
                                 TableColumnStyle(span: 1, styles: [StyleAttribute(key: "width", value: "140px")])])

            tableRow {
                tableHeadData { "Test" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "Success Min" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "Success Max" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "Avg" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "Success ratio" }.alignment(.left).scope(.column).class("row dark-bordered-container")

            }.id("table-header")

            forEach(testStats) { testStat in
                HTMLBuilder.buildBlock(
                    tableRow {
                        tableData {
                            link(url: TestStatRouteHTML.urlString(testSummaryIdentifier: testStat.first_summary_identifier, source: nil, backUrl: currentUrl(selectedTarget: selectedTarget, selectedDevice: selectedDevice, statType: statType, backUrl: backUrl))) {
                                div {
                                    image(url: ImageRoute.grayTestImageUrl())
                                        .attr("title", "Test stats")
                                        .iconStyleAttributes(width: 14)
                                        .class("icon")
                                    testStat.group_name + "/" + testStat.test_name
                                }
                            }.class("color-text")
                        }.class("row indent2 wrap-word")
                        tableData {
                            div { hoursMinutesSeconds(in: testStat.success_min_s) }
                        }.alignment(.left).class("row indent1")
                        tableData {
                            div { hoursMinutesSeconds(in: testStat.success_max_s) }
                        }.alignment(.left).class("row indent1")
                        tableData {
                            div { hoursMinutesSeconds(in: testStat.average_s) }
                        }.alignment(.left).class("row indent1")
                        tableData {
                            div { progress {}.attr("max", "1").attr("value", testStat.success_ratio.description).style([StyleAttribute(key: "width", value: "100px")]) }
                        }.alignment(.left).class("row indent1")
                    }.class("light-bordered-container")
                )
            }
        }.style([StyleAttribute(key: "table-layout", value: "fixed")])
    }

    private func currentUrl(selectedTarget: String, selectedDevice: String, statType: ResultBundle.TestStatsType, backUrl: String) -> String {
        var components = URLComponents(string: Self.path)!
        components.queryItems = [
            .init(name: "target", value: selectedTarget),
            .init(name: "device", value: selectedDevice),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation),
            .init(name: type(of: statType).queryName, value: statType.rawValue)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }
}

private extension ResultBundle.TestStatsType {
    static let queryName = "type"
}
