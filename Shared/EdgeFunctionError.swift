import Foundation
import Supabase

enum EdgeFunctionError: Error, Equatable {
    case notFound
    case rateLimited
    case unauthorized
    case generic(message: String)

    init(_ error: Error) {
        if let edgeFunctionError = error as? EdgeFunctionError {
            self = edgeFunctionError
            return
        }

        if isMissingSessionError(error) {
            self = .unauthorized
            return
        }

        guard let functionsError = error as? FunctionsError else {
            self = .generic(message: error.localizedDescription)
            return
        }

        switch functionsError {
        case let .httpError(code, _):
            switch code {
            case 401, 403:
                self = .unauthorized
            case 404:
                self = .notFound
            case 429:
                self = .rateLimited
            default:
                self = .generic(message: "Server error (\(code))")
            }
        case .relayError:
            self = .generic(message: "Unable to reach the server")
        }
    }

    var title: String {
        switch self {
        case .notFound:
            return "Not found"
        case .rateLimited:
            return "Too many requests"
        case .unauthorized:
            return "Session expired"
        case .generic:
            return "Something went wrong"
        }
    }

    var isGeneric: Bool {
        if case .generic = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .notFound:
            return "We couldn't find the requested information."
        case .rateLimited:
            return "Please wait a moment and try again."
        case .unauthorized:
            return "Please verify your email again in the Profile tab."
        case .generic(let detail):
            return detail
        }
    }

    var requiresReauthentication: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

private func isMissingSessionError(_ error: Error) -> Bool {
    String(describing: error).contains("sessionMissing")
}
