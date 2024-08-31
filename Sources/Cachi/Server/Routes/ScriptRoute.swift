import Foundation
import os
import Vapor

struct ScriptRoute: Routable {
    static let path = "/script"

    let method = HTTPMethod.GET
    let description = "Script route, used for html rendering"

    func respond(to req: Request) throws -> Response {
        os_log("Script request received", log: .default, type: .info)

        let components = req.urlComponents()
        let queryItems = components?.queryItems ?? []
        let scriptType = queryItems.first(where: { $0.name == "type" })?.value ?? ""

        var scriptContent: String?
        switch scriptType {
        case "capture":
            scriptContent = scriptCapture()
        case "coverage-files":
            let resultBundles = State.shared.resultBundles

            if let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
               let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier })
            {
                scriptContent = scriptFilesCoverage(resultBundle: resultBundle)
            }
        case "coverage-folders":
            let resultBundles = State.shared.resultBundles

            if let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
               let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier })
            {
                scriptContent = scriptFoldersCoverage(resultBundle: resultBundle)
            }
        case "result-stat":
            scriptContent = scriptResulsStat()
        default:
            break
        }

        guard scriptContent != nil else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        return Response(headers: HTTPHeaders([("Content-Type", "application/javascript")]), body: Response.Body(string: scriptContent!))
    }

    static func captureUrlString() -> String {
        urlString(type: "capture")
    }

    static func fileCoverageUrlString(resultIdentifier: String) -> String {
        urlString(type: "coverage-files", resultIdentifier: resultIdentifier)
    }

    static func foldersCoverageUrlString(resultIdentifier: String) -> String {
        urlString(type: "coverage-folders", resultIdentifier: resultIdentifier)
    }

    static func resultStatsUrlString() -> String {
        urlString(type: "result-stat")
    }

    private static func urlString(type: String, resultIdentifier: String? = nil) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: resultIdentifier),
            .init(name: "type", value: type),
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func scriptCapture() -> String {
        """
            var topBarElementRect = null;
            var tableHeaderElementRect = null;

            var captureImageElement = null;
            var captureImageTopOffset = 10;

            window.onload = function() {
                topBarElementRect = document.getElementById('top-bar').getBoundingClientRect();
                tableHeaderElementRect = document.getElementById('table-header').getBoundingClientRect();

                captureImageElement = document.getElementById('screen-capture')

                window.onscroll();
            }

            window.onscroll = function() {
                if (captureImageElement == null) { return; }

                if (window.pageYOffset != undefined) {
                    if (pageYOffset <= captureImageTopOffset + tableHeaderElementRect.height) {
                        captureImageElement.style.position = "absolute";
                        captureImageElement.style.top = `${captureImageTopOffset + topBarElementRect.height + tableHeaderElementRect.height + captureImageTopOffset}px`;
                    } else {
                        captureImageElement.style.position = "fixed";
                        captureImageElement.style.top = `${captureImageTopOffset + topBarElementRect.height}px`;
                    }
                }
            }

            function updateScreenCapturePosition(source_element, position) {
                var video = document.getElementById('screen-capture');
                video.currentTime = position;
            }

            function updateScreenCapture(source_element, result_identifier, test_identifier, attachment_identifier, content_type) {
                var destination_src = `\(AttachmentRoute.path)?result_id=${result_identifier}&test_id=${test_identifier}&id=${attachment_identifier}&content_type=${content_type}`;
                if (!document.getElementById('screen-capture').src.includes(destination_src)) {
                    document.getElementById('screen-capture').src = '';
                    setTimeout(function () {
                        document.getElementById('screen-capture').src = destination_src;
                    }, 50);
                }

                Array.from(document.getElementsByClassName('capture')).forEach(
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
        guard let url = resultBundle.codeCoverageJsonSummaryUrl,
              let coverageRaw = try? String(contentsOf: url)
        else {
            return "{}"
        }

        let coverage = """
            const data = \(coverageRaw)

            const queryString = window.location.search;
            const urlParams = new URLSearchParams(queryString);

            let parentParams = [];
            urlParams.forEach((value,name) => parentParams.push(`${name}=${value}`));
            parentParams = parentParams.filter(t => !t.startsWith('id=') && !t.startsWith('q=') && !t.startsWith('qq=') && !t.startsWith('path=') && !t.startsWith('back_url='));

            const inputHandler = function(e) {
                var filteredItems = [];

                const query = e == null ? '' : e.target.value.toLowerCase();

                const folder = urlParams.get('folder');

                for (var file of data['d'][0]['f']) {
                    const matchesQuery = query == null || file.n.toLowerCase().includes(query);
                    const matchesFolder = folder == null || file.n.startsWith(folder);
                    if (matchesQuery && matchesFolder) {
                        filteredItems.push(file);
                    }
                }

                filteredItems = filteredItems.sort(function(a,b) {
                    return b.n.localeCompare(a.n);
                });

                const filterInput = document.getElementById('filter-input');
                const inputQuery = filterInput.value ?? '';

                let inputQueryParam = '';
                if (folder == null) {
                    inputQueryParam = `&q=${inputQuery}`;
                } else {
                    inputQueryParam = `&q=${urlParams.get('q') ?? ''}&qq=${inputQuery}`;
                }

                var val = '';
                for (var i = 0; i < filteredItems.length; i++) {
                    const item = filteredItems[i]
                    const rowClass = i % 2 == 0 ? 'even-row' : 'odd-row'
                    val += `<tr class='${rowClass}'><td class='filename-col'><a href='/html/coverage-file?id=\(resultBundle.identifier)&path=${item.n}${inputQueryParam}&${parentParams.join('&')}'>${item.n}</a></td><td class='progress-col'><progress value='${item.s.l.p}' max='100'></progress></td><td class='coverage-col color-subtext'>${Number(item.s.l.p).toFixed(1)}%</td><td class='absorbing-column'></td></tr>`;
                }

                const coverageTable = document.getElementById('coverage-table');
                coverageTable.innerHTML = val;
            }

            window.onload = function() {
                const filterInput = document.getElementById('filter-input');

                if (urlParams.has('folder')) {
                    filterInput.value = urlParams.get('qq') ?? '';
                } else {
                    filterInput.value = urlParams.get('q') ?? '';
                }

                const event = new Event('input');
                event.value = filterInput.value;

                filterInput.addEventListener('input', inputHandler);
                filterInput.dispatchEvent(event);
            };
        """

        let minifiedCoverage = coverage
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

        return minifiedCoverage
    }

    private func scriptFoldersCoverage(resultBundle: ResultBundle) -> String {
        guard let url = resultBundle.codeCoveragePerFolderJsonUrl,
              let coverageRaw = try? String(contentsOf: url)
        else {
            return "{}"
        }

        let coverage = """
            const data = \(coverageRaw)

            const queryString = window.location.search;
            const urlParams = new URLSearchParams(queryString);

            let parentParams = [];
            urlParams.set('coverage_show', 'files');
            urlParams.forEach((value,name) => parentParams.push(`${name}=${value}`));
            parentParams = parentParams.filter(t => !t.startsWith('id=') && !t.startsWith('q=') && !t.startsWith('qq=') && !t.startsWith('path='));

            const inputHandler = function(e) {
                var filteredItems = [];

                const query = e == null ? '' : e.target.value.toLowerCase();

                const folder = urlParams.get('folder');

                for (var item of data) {
                    const matchesQuery = query == null || item.f.toLowerCase().includes(query);
                    const matchesFolder = folder == null || item.f.startsWith(folder);
                    if (matchesQuery && matchesFolder) {
                        filteredItems.push(item);
                    }
                }

                filteredItems = filteredItems.sort(function(a,b) {
                    return b.n - a.n
                });

                const filterInput = document.getElementById('filter-input');
                const inputQuery = filterInput.value ?? '';

                let inputQueryParam = '';
                if (folder == null) {
                    inputQueryParam = `&q=${inputQuery}`;
                } else {
                    inputQueryParam = `&q=${urlParams.get('q') ?? ''}&qq=${inputQuery}`;
                }

                var val = '';
                for (var i = 0; i < filteredItems.length; i++) {
                    const item = filteredItems[i];
                    const rowClass = i % 2 == 0 ? 'even-row' : 'odd-row'
                    val += `<tr class='${rowClass}'><td class='filename-col'><a href='/html/coverage?id=\(resultBundle.identifier)&folder=${item.f}${inputQueryParam}&${parentParams.join('&')}'>${item.f}</a></td><td class='progress-col'><progress value='${item.p}' max='100'></progress></td><td class='coverage-col color-subtext'>${Number(item.p).toFixed(1)}%</td><td class='absorbing-column'></td></tr>`;
                }

                const coverageTable = document.getElementById('coverage-table');
                coverageTable.innerHTML = val;
            }

            window.onload = function() {
                const filterInput = document.getElementById('filter-input');

                if (urlParams.has('folder')) {
                    filterInput.value = urlParams.get('qq') ?? '';
                } else {
                    filterInput.value = urlParams.get('q') ?? '';
                }

                const event = new Event('input');
                event.value = filterInput.value;

                filterInput.addEventListener('input', inputHandler);
                filterInput.dispatchEvent(event);
            };
        """

        let minifiedCoverage = coverage
            .replacingOccurrences(of: #""path":"#, with: #""f":"#)
            .replacingOccurrences(of: #""percent":"#, with: #""p":"#)

        return minifiedCoverage
    }

    private func scriptResulsStat() -> String {
        """
                    function updateLocation() {
                        const currentLocation = window.location;
                        const params = new URLSearchParams(currentLocation.search)
                        const typeParam = params.get('test')

                        const updatedParams = `target=${document.getElementById('target').value}&device=${document.getElementById('device').value}&type=typeParam&window_size=${document.getElementById('filter-input').value}`;

                        window.location = '/html/results_stat?' + updatedParams;
                    }

                    document.getElementById('target').onchange = function() {
                        updateLocation();
                    };
                    document.getElementById('device').onchange = function() {
                        updateLocation();
                    };
                    document.getElementById('filter-input').onkeydown = function(e) {
                        if (e.keyCode == 13) {
                            updateLocation();
                        }
                    };
        """
    }
}
