import Foundation
import os
import Vapor

struct CSSRoute: Routable {
    static let path = "/css"

    let method = HTTPMethod.GET
    let description = "CSS route, used for html rendering"

    func respond(to req: Request) throws -> Response {
        os_log("CSS request received", log: .default, type: .info)

        guard let imageIdentifier = req.url.query else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let cssContent: String? = switch imageIdentifier {
        case "main": mainCSS()
        default: nil
        }

        guard cssContent != nil else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        return Response(headers: HTTPHeaders([("Content-Type", "text/css")]), body: Response.Body(string: cssContent!))
    }

    private func mainCSS() -> String {
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

                .wrap-word {
                    word-wrap: break-word;
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
                    text-align: left;
                }

                #top-bar {
                    z-index: 999;
                }

                #capture-column {
                    width: 35%;
                }

                #screen-capture {
                    top: 0px;
                    right: 2.5%;
                    width: 30%;
                    height: auto;
                    max-height: 85%;
                    object-fit: contain;
                    display:block;
                }

                #coverage-table {
                    table-layout: auto;
                    border-collapse: collapse;
                    width: 100%;
                    margin-top: 10px;
                }

                #coverage-table .filename-col {
                    padding-left: 20px;
                }

                #coverage-table .progress-col {
                    padding-right: 10px;
                }

                #coverage-table .coverage-col {
                    font-size: 90%;
                }

                #coverage-table td {
                    padding-top: 5px;
                    padding-bottom: 5px;
                    padding-right: 20px;
                }

                #coverage-table td a, a:hover, a:focus, a:active {
                    text-decoration: none;
                    color: inherit;
                }

                #coverage-table .absorbing-column {
                    width: 100%;
                }

                #filter-search {
                    display: inline-flex;
                    align-items: center;
                    border: 1px solid;
                    border-radius: 3px;
                    width: 450px;
                }

                #filter-placeholder {
                    border-top-left-radius: 3px;
                    border-bottom-left-radius: 3px;
                    height: 100%;
                    padding-left: 10px;
                    padding-right: 10px;
                    padding-top: 3px;
                    padding-bottom: 3px;
                    line-height: 20px;
                }

                #filter-input {
                    padding-left: 5px;
                    height: 100%;
                    font-size: 100%;
                    border: 0px;
                    line-height: 20px;
                    background: transparent;
                }

                a:link {
                    text-decoration: none;
                }

                a:visited {
                    text-decoration: none;
                }

                input:focus {
                    outline: none;
                }

                .main-container {
                    margin: 0px;
                    margin-top: 10px;
                }

                @media (prefers-color-scheme: light) {
                    body {
                        background-color: rgb(255,255,255);
                    }

                    .background {
                        color: rgb(39,39,39);
                        background-color: rgb(255,255,255);
                    }

                    .background-error {
                        background: rgb(248,233,231);
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
                        color: rgb(39,39,39);
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

                    input {
                        color: rgb(90, 90, 90);
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

                    #filter-search {
                        border-color: rgb(230,230,230);
                    }

                    #filter-placeholder {
                        background: rgb(230,230,230);
                        color: rgb(90, 90, 90);
                    }

                    #coverage-table .odd-row {
                        background: rgb(245,245,245);
                    }
                }

                @media (prefers-color-scheme: dark) {
                    body {
                        background-color: rgb(39,39,39);
                    }

                    .background {
                        color: rgb(225,225,225);
                        background-color: rgb(39,39,39);
                    }

                    .background-error {
                        background: rgb(105,42,42);
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
                        color: rgb(225,225,225);
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

                    input {
                        color: rgb(165,165,165);
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

                    #filter-search {
                        border-color: rgb(80,80,80);
                    }

                    #filter-placeholder {
                        background: rgb(80,80,80);
                        color: rgb(165,165,165);
                    }

                    #coverage-table .odd-row {
                        background: rgb(15,15,15);
                    }
                }

                .header {
                    font-weight: 600;
                    font-size: 125%;
                }

                .subheader {
                    padding-left: 0px;
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
