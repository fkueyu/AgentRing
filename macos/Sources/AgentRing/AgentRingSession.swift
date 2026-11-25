// AgentRingSession.swift — the URLSession used for all local daemon traffic.
//
// A shared URLSession keeps a CFNetwork storage database, and every request can
// make macOS hold a short "PreventUserIdleSystemSleep" assertion. This app polls
// continuously, so use an ephemeral session with no cache/cookies: it is a
// status client, not a browser, and should not contribute to sleep prevention.

import Foundation

enum AgentRingSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 4
        return URLSession(configuration: configuration)
    }()
}
