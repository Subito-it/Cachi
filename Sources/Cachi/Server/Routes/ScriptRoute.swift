import Foundation
import HTTPKit
import os

struct ScriptRoute: Routable {
    let path = "/script"
    let description = "Script route, used for html rendering"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Script request received", log: .default, type: .info)
        
        let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let scriptType = queryItems.first(where: { $0.name == "type" })?.value ?? ""
        
        var scriptContent: String?
        switch scriptType {
        case "screenshot":
            scriptContent = scriptScreenshot()
        case "coverage-files":
            let resultBundles = State.shared.resultBundles
            
            if let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
               let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier }) {
                scriptContent = scriptFilesCoverage(resultBundle: resultBundle)
            }
        default:
            break
        }

        guard scriptContent != nil else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let res = HTTPResponse(headers: HTTPHeaders([("Content-Type", "application/javascript")]), body: HTTPBody(string: scriptContent!))
        return promise.succeed(res)
    }
    
    private func scriptScreenshot() -> String {
        return """
            var topBarElementRect = null;
            var tableHeaderElementRect = null;

            var screenshotImageElement = null;
            var screenshotImageTopOffset = 10;
        
            window.onload = function() {
                topBarElementRect = document.getElementById('top-bar').getBoundingClientRect();
                tableHeaderElementRect = document.getElementById('table-header').getBoundingClientRect();

                screenshotImageElement = document.getElementById('screenshot-image')

                window.onscroll();
            }
        
            window.onscroll = function() {
                if (screenshotImageElement == null) { return; }
        
                if (window.pageYOffset != undefined) {
                    if (pageYOffset <= screenshotImageTopOffset + tableHeaderElementRect.height) {
                        screenshotImageElement.style.position = "absolute";
                        screenshotImageElement.style.top = `${screenshotImageTopOffset + topBarElementRect.height + tableHeaderElementRect.height + screenshotImageTopOffset}px`;
                    } else {
                        screenshotImageElement.style.position = "fixed";
                        screenshotImageElement.style.top = `${screenshotImageTopOffset + topBarElementRect.height}px`;
                    }
                }
            }
        
            function onMouseEnter(source_element, result_identifier, test_identifier, attachment_identifier, content_type) {
                var destination_src = `\(AttachmentRoute().path)?result_id=${result_identifier}&test_id=${test_identifier}&id=${attachment_identifier}&content_type=${content_type}`;
                if (!document.getElementById('screenshot-image').src.includes(destination_src)) {
                    document.getElementById('screenshot-image').src = '';
                    setTimeout(function () {
                        document.getElementById('screenshot-image').src = destination_src;
                    }, 50);
                }
        
                Array.from(document.getElementsByClassName('screenshot')).forEach(
                    function(element, index, array) {
                        if (element.getAttribute("attachment_identifier") === attachment_identifier) {
                            element.classList.add('color-selected');
                        } else {
                            element.classList.remove('color-selected');
                        }
                    }
                );
            }
        """
    }

    private func scriptFilesCoverage(resultBundle: ResultBundle) -> String {
        guard let summaryUrl = resultBundle.codeCoverageJsonSummaryUrl,
              let coverageRawDictionary = try? String(contentsOf: summaryUrl) else {
            return "{}"
        }
        
        let fileCoverage = """
            const dict = \(coverageRawDictionary)

            const queryString = window.location.search;
            const urlParams = new URLSearchParams(queryString);

            let parentParams = [];
            urlParams.forEach((value,name) => parentParams.push(`${name}=${value}`));
            parentParams = parentParams.filter(t => !t.startsWith('id=') && !t.startsWith('q='));

            const inputHandler = function(e) {
                var filteredFiles = [];

                const query = e == null ? '' : e.target.value.toLowerCase();
                
                for (var file of dict['d'][0]['f']) {
                    if (query == null || file.n.toLowerCase().includes(query)) {
                        filteredFiles.push(file);
                    }
                }

                filteredFiles = filteredFiles.sort(function(a,b) {
                    return b.n - a.n
                });

                const filterInput = document.getElementById('filter-input');
                const inputQuery = filterInput.value ?? '';

                var val = '';
                for (var i = 0; i < filteredFiles.length; i++) {
                    const file = filteredFiles[i]
                    const rowClass = i % 2 == 0 ? 'even-row' : 'odd-row'
                    val += `<tr class='${rowClass}'><td class='filename-col'><a href='/html/coverage-file?id=\(resultBundle.identifier)&path=${file.n}&q=${inputQuery}&${parentParams.join('&')}'>${file.n}</a></td><td class='progress-col'><progress value='${file.s.l.p}' max='100'></progress></td><td class='coverage-col color-subtext'>${Number(file.s.l.p).toFixed(1)}%</td><td class='absorbing-column'></td></tr>`;
                }

                const coverageTable = document.getElementById('coverage-table');
                coverageTable.innerHTML = val;
            }

            window.onload = function() {
                const filterInput = document.getElementById('filter-input');
                const inputQuery = urlParams.get('q');
                filterInput.value = inputQuery;
                
                filterInput.addEventListener('input', inputHandler);
                inputHandler();
            };
        """
        
        let minifiedFileCoverage = fileCoverage
            .replacingOccurrences(of: #""files":"#, with: #""f":"#)
            .replacingOccurrences(of: #""filename":"#, with: #""n":"#)
            .replacingOccurrences(of: #""functions":"#, with: #""fn":"#)
            .replacingOccurrences(of: #""count":"#, with: #""cn":"#)
            .replacingOccurrences(of: #""covered":"#, with: #""c":"#)
            .replacingOccurrences(of: #""notcovered":"#, with: #""nc":"#)
            .replacingOccurrences(of: #""regions":"#, with: #""r":"#)
            .replacingOccurrences(of: #""percent":"#, with: #""p":"#)
            .replacingOccurrences(of: #""instantiations":"#, with: #""i":"#)
            .replacingOccurrences(of: #""lines":"#, with: #""l":"#)
            .replacingOccurrences(of: #""summary":"#, with: #""s":"#)
            .replacingOccurrences(of: #""data":"#, with: #""d":"#)
        
        
        return minifiedFileCoverage
    }
}
