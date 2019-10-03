import Foundation
import HTTPKit
import os

struct ImageRoute: Routable {
    let path = "/image"
    let description = "Image route, used for html rendering"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Image request received", log: .default, type: .info)
        
        guard let imageIdentifier = req.url.query else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let imageContent: StaticString?
        switch imageIdentifier {
        case "imageTestPass": imageContent = imageTestPass()
        case "imageTestFail": imageContent = imageTestFail()
        case "imageTestRetried": imageContent = imageTestRetried()
        case "imageTestGray": imageContent = imageTestGray()
        case "imageArrorLeft": imageContent = imageArrorLeft()
        case "imageArrorRight": imageContent = imageArrorRight()
        case "imageView": imageContent = imageView()
        case "imageAttachment": imageContent = imageAttachment()
        case "imageEmpty": imageContent = imageEmpty()
        default: imageContent = nil
        }

        guard imageContent != nil else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let res = HTTPResponse(headers: HTTPHeaders([("Content-Type", "image/svg+xml")]), body: HTTPBody(staticString: imageContent!))
        return promise.succeed(res)
    }
    
    private func imageTestPass() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="405.718" viewBox="0 0 405.718 405.718" width="405.718" xmlns="http://www.w3.org/2000/svg"><g transform="translate(-13.341 -321.774)"><path d="m33.843 474.454 132.178-132.177c27.337-27.337 71.658-27.337 98.995 0l133.54 133.54c27.337 27.336 27.337 71.658 0 98.995l-132.178 132.178c-27.336 27.336-71.658 27.336-98.995 0l-133.54-133.541c-27.337-27.337-27.337-71.658 0-98.995z" fill="#019638"/><path d="m140.126 503.514s49.05 49.05 49.05 49.05 100.372-100.371 100.372-100.371 27.25 29.067 27.25 29.067-128.076 124.442-128.076 124.442-75.392-75.392-75.392-75.392 26.796-26.796 26.796-26.796z" fill="#fff"/></g></svg>"##)
    }
    
    private func imageTestFail() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="405.718" viewBox="0 0 405.718 405.718" width="405.718" xmlns="http://www.w3.org/2000/svg"><g transform="translate(-344.203 -603.935)"><path d="m364.706 756.615 132.178-132.177c27.336-27.337 71.658-27.337 98.995 0l133.54 133.54c27.337 27.337 27.337 71.658 0 98.995l-132.178 132.178c-27.336 27.336-71.658 27.336-98.995 0l-133.54-133.541c-27.337-27.336-27.337-71.658 0-98.995z" fill="#e21515"/><path d="m438.651 786.883h216.823v39.822h-216.823z" fill="#fff"/></g></svg>"##)
    }

    private func imageTestRetried() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="405.718" viewBox="0 0 405.718 405.718" width="405.718" xmlns="http://www.w3.org/2000/svg"><g transform="translate(-520.789 -1041.153)"><path d="m541.292 1193.833 132.177-132.177c27.337-27.337 71.659-27.337 98.995 0l133.541 133.54c27.336 27.337 27.336 71.658 0 98.995l-132.178 132.178c-27.337 27.336-71.658 27.336-98.995 0l-133.54-133.541c-27.337-27.336-27.337-71.658 0-98.995z" fill="#ff7f00"/><path d="m615.236 1224.101h216.824v39.822h-216.824z" fill="#fff"/></g></svg>"##)
    }

    private func imageTestGray() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="405.638" viewBox="0 0 405.705 405.638" width="405.705" xmlns="http://www.w3.org/2000/svg"><g fill="#787877" transform="translate(-344.21 -46.555)"><path d="m549.732 46.555c17.63.895 33.438 8.347 46.14 20.422l133.54 133.541c27.337 27.336 27.337 71.658 0 98.995l-132.178 132.177c-27.336 27.337-71.658 27.337-98.994 0l-133.541-133.54c-27.336-27.337-27.336-71.658 0-98.995l132.178-132.178c15.533-14.991 31.577-20.422 52.855-20.422zm-.419 31.744c-16.873-.703-32.425 5.67-44.581 17.226l-111.486 111.485c-23.057 23.058-23.057 60.441 0 83.498l112.635 112.635c23.058 23.057 60.441 23.057 83.498 0l111.486-111.486c23.057-23.057 23.057-60.44 0-83.497l-112.635-112.635c-11.152-11.063-23.535-15.753-38.917-17.226z"/><path d="m438.651 229.463h216.824v39.822h-216.824z"/></g></svg>"##)
    }

    private func imageArrorLeft() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="401.636" viewBox="0 0 235.453 401.636" width="235.453" xmlns="http://www.w3.org/2000/svg"><g transform="translate(-577.297 -50.387)"><path d="m578.797 251.705s199.405 199.818 199.405 199.818 34.048-34.048 34.048-34.048-165.77-165.77-165.77-165.77 165.77-165.77 165.77-165.77-34.048-34.048-34.048-34.048-199.405 199.818-199.405 199.818z" fill="#787877"/><path d="m578.797 251.705s199.405 199.818 199.405 199.818 34.048-34.048 34.048-34.048-165.77-165.77-165.77-165.77 165.77-165.77 165.77-165.77-34.048-34.048-34.048-34.048-199.405 199.818-199.405 199.818z" fill="none" stroke="#000"/></g></svg>"##)
    }

    private func imageArrorRight() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="401.636" viewBox="0 0 235.66 401.636" width="235.66" xmlns="http://www.w3.org/2000/svg"><g transform="translate(-964.698 -50.387)"><path d="m966.198 417.475s34.048 34.048 34.048 34.048 199.612-199.61 199.612-199.61-199.612-200.026-199.612-200.026-34.048 34.048-34.048 34.048 165.77 165.77 165.77 165.77-165.77 165.77-165.77 165.77z" fill="#787877"/><path d="m966.198 417.475s34.048 34.048 34.048 34.048 199.612-199.61 199.612-199.61-199.612-200.026-199.612-200.026-34.048 34.048-34.048 34.048 165.77 165.77 165.77 165.77-165.77 165.77-165.77 165.77z" fill="none" stroke="#000"/></g></svg>"##)
    }
    
    private func imageView() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="326.329" viewBox="0 0 511.999 326.329" width="511.999" xmlns="http://www.w3.org/2000/svg"><g transform="translate(0 -92.835)"><path d="m508.745 246.041c-4.574-6.257-113.557-153.206-252.748-153.206s-248.179 146.949-252.748 153.2c-4.332 5.936-4.332 13.987 0 19.923 4.569 6.257 113.557 153.206 252.748 153.206s248.174-146.95 252.748-153.201c4.338-5.935 4.338-13.992 0-19.922zm-252.748 139.365c-102.529 0-191.33-97.533-217.617-129.418 26.253-31.913 114.868-129.395 217.617-129.395 102.524 0 191.319 97.516 217.617 129.418-26.253 31.912-114.868 129.395-217.617 129.395z"/><path d="m255.997 154.725c-55.842 0-101.275 45.433-101.275 101.275s45.433 101.275 101.275 101.275 101.275-45.433 101.275-101.275-45.433-101.275-101.275-101.275zm0 168.791c-37.23 0-67.516-30.287-67.516-67.516s30.287-67.516 67.516-67.516 67.516 30.287 67.516 67.516-30.286 67.516-67.516 67.516z"/></g></svg>"##)
    }
    
    private func imageAttachment() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="510" viewBox="0 0 459.962 510" width="459.962" xmlns="http://www.w3.org/2000/svg"><path d="m452.719 195.674-37.739 37.719-169.816 169.723c-31.297 31.047-81.816 30.953-112.996-.211s-31.274-81.658-.211-112.939l169.809-169.774c6.945-6.945 18.21-6.945 25.16 0 6.945 6.946 6.945 18.202 0 25.148l-169.809 169.773c-17.367 17.359-17.367 45.497 0 62.855 17.367 17.359 45.52 17.359 62.887 0l169.859-169.722 37.738-37.716c31.266-31.261 31.254-81.935-.019-113.181-31.277-31.246-81.973-31.238-113.238.023l-31.442 31.438-176.101 176.012-12.582 12.572c-43.977 45.329-43.418 117.542 1.25 162.192 44.672 44.645 116.922 45.203 162.273 1.249l188.68-188.588c4.496-4.49 11.047-6.243 17.183-4.599 6.141 1.643 10.938 6.434 12.582 12.571 1.645 6.138-.113 12.681-4.605 17.175l-188.68 188.585c-59.09 58.79-154.64 58.681-213.593-.246-58.958-58.924-59.067-154.426-.247-213.486l188.68-188.585 31.488-31.437c45.411-43.595 117.375-42.869 161.891 1.64 44.52 44.505 45.227 116.433 1.598 161.809zm0 0" transform="translate(-25.019)"/></svg>"##)
    }
    
    private func imageEmpty() -> StaticString {
        return StaticString(stringLiteral: ##"<svg height="1" viewBox="0 0 1 1" width="1" xmlns="http://www.w3.org/2000/svg"/>"##)
    }
}
