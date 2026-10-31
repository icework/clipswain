import Foundation

/// The content endpoint streams the file itself. Do not follow redirects to login pages or
/// storage hosts with the board credential; external work-product links open separately.
final class AttachmentDownloadDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
