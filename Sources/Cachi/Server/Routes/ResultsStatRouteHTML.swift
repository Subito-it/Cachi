import Foundation
import HTTPKit
import os
import Vaux

private extension ResultBundle.TestStatsType {
    func params() -> String {
        return "&\(Self.queryName)=\(self.rawValue)"
    }
    
    static let queryName = "type"
}

struct ResultsStatRouteHTML: Routable {
    let path: String = "/html/results_stat"
    let description: String = "Stats of results in html"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML results request received", log: .default, type: .info)
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        let allTargets = State.shared.allTargets()
        
        guard allTargets.count > 0 else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "No targets found..."))
            return promise.succeed(res)
        }
        
        let queryItems = components.queryItems ?? []
        let typeFilter = ResultBundle.TestStatsType(rawValue: queryItems.first(where: { $0.name == ResultBundle.TestStatsType.queryName })?.value ?? "") ?? .flaky
        let selectedTarget = queryItems.first(where: { $0.name == "target" })?.value ?? allTargets.first
        var rawSelectedDevice = queryItems.first(where: { $0.name == "device" })?.value
        
        let allDevices = State.shared.allDevices(in: selectedTarget!)
        
        guard selectedTarget != nil, allDevices.count > 0 else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "No target or device found..."))
            return promise.succeed(res)
        }
        
        rawSelectedDevice = rawSelectedDevice ?? allDevices.first?.description
        
        guard let selectedDevice = State.Device(rawDescription: rawSelectedDevice) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Empty selected device..."))
            return promise.succeed(res)
        }
        
        let testStats = State.shared.resultsTestStats(target: selectedTarget!, device: selectedDevice, type: typeFilter)
        
        let document = html {
            head {
                title("Cachi - Results")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(targets: allTargets, selectedTarget: selectedTarget, devices: allDevices.map(\.description), selectedDevice: rawSelectedDevice, typeFilter: typeFilter) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(testStats: testStats) }
                }.class("main-container background")
                script(filepath: Filepath(name: "/script?type=result-stat", path: ""))
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(targets: [String], selectedTarget: String?, devices: [String], selectedDevice: String?, typeFilter: ResultBundle.TestStatsType) -> HTML {
        return div {
            div {
                div {
                    link(url: "/html/results") {
                        image(url: "/image?imageArrorLeft")
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    image(url: "/image?imageTestGray")
                        .attr("title", "Test stats")
                        .iconStyleAttributes(width: 14)
                        .class("icon")
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
                "&nbsp;&nbsp;&nbsp;&nbsp;"
                link(url: "\(self.path)?target=\(selectedTarget!)&device=\(selectedDevice!)&\(ResultBundle.TestStatsType.flaky.params())") { ResultBundle.TestStatsType.flaky.rawValue.capitalized }.class(typeFilter == .flaky ? "button-selected" : "button")
                link(url: "\(self.path)?target=\(selectedTarget!)&device=\(selectedDevice!)&\(ResultBundle.TestStatsType.slowest.params())") { ResultBundle.TestStatsType.slowest.rawValue.capitalized }.class(typeFilter == .slowest ? "button-selected" : "button")
                link(url: "\(self.path)?target=\(selectedTarget!)&device=\(selectedDevice!)&\(ResultBundle.TestStatsType.fastest.params())") { ResultBundle.TestStatsType.fastest.rawValue.capitalized }.class(typeFilter == .fastest ? "button-selected" : "button")
            }.class("row light-bordered-container indent2")
        }
    }
    
    private func resultsTableHTML(testStats: [ResultBundle.TestStats]) -> HTML {
        return table {
            columnGroup(styles: [TableColumnStyle(span: 1, styles: [StyleAttribute(key: "wrap-word", value: "break-word")]),
                                 TableColumnStyle(span: 4, styles: [StyleAttribute(key: "width", value: "100")])])
            
            tableRow {
                tableHeadData { "Test" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "Min" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "Avg" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "Max" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "Success ratio" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                
            }.id("table-header")
            
            forEach(testStats) { testStat in
                return HTMLBuilder.buildBlock(
                    tableRow {
                        tableData {
                            link(url: "/html/teststats?id=\(testStat.first_summary_identifier)&show=all") {
                                div {
                                    image(url: "/image?imageTestGray")
                                        .attr("title", "Test stats")
                                        .iconStyleAttributes(width: 14)
                                        .class("icon")
                                    testStat.title
                                }
                            }.class("color-text")
                        }.class("row indent2")
                        tableData {
                            div { hoursMinutesSeconds(in: testStat.min_s) }
                        }.alignment(.left).class("row indent1")
                        tableData {
                            div { hoursMinutesSeconds(in: testStat.average_s) }
                        }.alignment(.left).class("row indent1")
                        tableData {
                            div { hoursMinutesSeconds(in: testStat.max_s) }
                        }.alignment(.left).class("row indent1")
                        tableData {
                            div { progress {}.attr("max", "1").attr("value", testStat.success_ratio.description) }
                        }.alignment(.left).class("row indent1")
                    }.class("light-bordered-container")
                )
            }
        }
    }
}
