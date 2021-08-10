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
}
