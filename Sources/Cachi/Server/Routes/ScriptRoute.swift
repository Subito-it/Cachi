import Foundation
import HTTPKit
import os

struct ScriptRoute: Routable {
    let path = "/script"
    let description = "Script route, used for html rendering"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Script request received", log: .default, type: .info)
        
        guard let scriptIdentifier = req.url.query else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let scriptContent: String?
        switch scriptIdentifier {
        case "screenshot": scriptContent = scriptScreenshot()
        default: scriptContent = nil
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
            var screenshotTopAnchorY = 0;
            var screenshotPositionSticky = true;
            var screenshotImageElement = null;
            var screenshotImageTopOffset = 10;
        
            window.onload = function() {
                screenshotTopAnchorY = document.getElementById('screenshot-column').getBoundingClientRect().top + window.scrollY;
                screenshotImageElement = document.getElementById('screenshot-image')
                window.onscroll();
            }
        
            window.onscroll = function() {
                if (screenshotImageElement == null) { return; }
        
                if (window.pageYOffset != undefined) {
                    if (pageYOffset <= screenshotTopAnchorY && screenshotPositionSticky) {
                        screenshotImageElement.style.position = "absolute";
                        screenshotImageElement.style.top = `${screenshotTopAnchorY + screenshotImageTopOffset}px`;
                        screenshotPositionSticky = false;
                    } else {
                        screenshotImageElement.style.position = "fixed";
                        screenshotImageElement.style.top = `${screenshotImageTopOffset}px`;
                        screenshotPositionSticky = true;
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
