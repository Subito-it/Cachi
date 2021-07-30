import Foundation
import HTTPKit
import os

struct CSSRoute: Routable {
    let path = "/css"
    let description = "CSS route, used for html rendering"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("CSS request received", log: .default, type: .info)
        
        guard let imageIdentifier = req.url.query else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let cssContent: String?
        switch imageIdentifier {
        case "main": cssContent = mainCSS()
        default: cssContent = nil
        }

        guard cssContent != nil else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let res = HTTPResponse(headers: HTTPHeaders([("Content-Type", "text/css")]), body: HTTPBody(string: cssContent!))
        return promise.succeed(res)
    }
    
    private func mainCSS() -> String {
        return
"""
        body {
            font-family: "SF Text", -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 14px;
            margin: 0px;
            margin-bottom: 30px;
        }
        
        table {
            width: 100%;
            border: 0px;
            border-collapse: collapse;
        }

        .log {
            padding-top: 8px;
            font-family: Courier;
        }

        .col50 {
            width: 50%;
            vertical-align: top;
            font-family: Courier;
            word-break: break-all;
        }
        
        th {
            font-weight: 600;
        }

        #top-bar {
            z-index: 999;
        }
        
        #screenshot-column {
            width: 35%;
        }
        
        #screenshot-image {
            top: 0px;
            right: 2.5%;
            width: 30%;
            height: auto;
            max-height: 85%;
            object-fit: contain;
            display:block;
        }

        a:link {
            text-decoration: none;
        }

        a:visited {
            text-decoration: none;
        }
        
        .main-container {
            margin: 0px;
            margin-top: 10px;
        }
        
        @media (prefers-color-scheme: light) {
            .background {
                color: rgb(0,0,0);
                background-color: rgb(255,255,255);
            }

            .warning-container {
                color: rgb(255,255,255);
                background-color: rgb(255,127,0);
                padding: 10px;
            }
            
            .light-bordered-container {
                background-color: rgb(255,255,255);
                border-bottom: 1px solid rgb(230,230,230);
            }

            .dark-bordered-container {
                background-color: rgb(234,234,234);
                border-bottom: 1px solid rgb(199,199,199);
            }
            
            .color-text {
                color: rgb(0,0,0);
            }
            
            .color-subtext {
                color: rgb(120,120,120);
            }
        
            .color-retry {
                color: rgb(255,127,0);
            }

            .color-error {
                color: rgb(236,77,61);
            }
        
            .color-selected {
                color: rgb(236,77,61) !important;
            }
            
            .color-svg-text {
                filter: brightness(0%) invert(0);
            }
        
            .color-svg-subtext {
                filter: brightness(0%) invert(0.45);
            }

            .button {
                border: 1px solid rgb(230,230,230);
                border-radius: 3px;
                color: rgb(90, 90, 90);
                padding: 3px 8px 3px 8px;
                text-align: center;
                text-decoration: none;
                display: inline-block;
                margin-right: 4px;
            }
            
            .button-selected {
                background-color: rgb(0,122,255);
                border-radius: 3px;
                border: none;
                color: white;
                padding: 3px 8px 3px 8px;
                text-align: center;
                text-decoration: none;
                display: inline-block;
                margin-right: 4px;
            }
        }
        
        @media (prefers-color-scheme: dark) {
            .background {
                color: rgb(255,255,255);
                background-color: rgb(39,39,39);
            }
        
            .warning-container {
                color: rgb(0,0,0);
                background-color: rgb(255,127,0);
                padding: 10px;
            }
            
            .light-bordered-container {
                background-color: rgb(39,39,39);
                border-bottom: 1px solid rgb(60,60,60);
            }

            .dark-bordered-container {
                background-color: rgb(55,55,55);
                border-bottom: 1px solid rgb(79,79,79);
            }
            
            .color-text {
                color: rgb(255,255,255);
            }
            
            .color-subtext {
                color: rgb(165,165,165);
            }
        
            .color-retry {
                color: rgb(255,127,0);
            }

            .color-error {
                color: rgb(236,77,61);
            }
        
            .color-selected {
                color: rgb(236,77,61) !important;
            }
            
            .color-svg-text {
                filter: brightness(0%) invert(1);
            }
        
            .color-svg-subtext {
                filter: brightness(0%) invert(0.65);
            }

            .button {
                border: 1px solid rgb(80,80,80);
                border-radius: 3px;
                color: rgb(165,165,165);
                padding: 3px 8px 3px 8px;
                text-align: center;
                text-decoration: none;
                display: inline-block;
                margin-right: 4px;
            }
            
            .button-selected {
                background-color: rgb(0,122,255);
                border-radius: 3px;
                border: none;
                color: white;
                padding: 3px 8px 3px 8px;
                text-align: center;
                text-decoration: none;
                display: inline-block;
                margin-right: 4px;
            }
        }
                
        .header {
            font-weight: 600;
            font-size: 125%;
        }
        
        .bold {
            font-weight: 600;
        }

        .row {
            padding-top: 5px;
            padding-bottom: 5px;
        }
        
        .icon {
            vertical-align: middle;
        }
        
        .indent1 {
            padding-left: 10px;
            padding-right: 10px;
        }
        
        .indent2 {
            padding-left: 20px;
            padding-right: 20px;
        }
        
        .indent3 {
            padding-left: 30px;
            padding-right: 30px;
        }
        
        .button-padded {
            padding-top: 3px;
            padding-bottom: 3px;
        }

        .sticky-top {
            position: -webkit-sticky; /* Safari */
            position: sticky;
            top: 0;
        }
"""
    }
}
