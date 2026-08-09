import ServiceManagement

public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

public enum LoginItemError: Error, Equatable {
    case operationFailed
    case requiresApproval
    case statusMismatch(LoginItemStatus)
}

public protocol LoginItemManaging: AnyObject {
    func status() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemError>
}

public protocol LoginItemSystemControlling: AnyObject {
    var observedStatus: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public final class NullLoginItemService: LoginItemManaging {
    public init() {}
    public func status() -> LoginItemStatus { .disabled }
    public func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemError> {
        .success(.disabled)
    }
}

public final class LoginItemService: LoginItemManaging {
    private let system: LoginItemSystemControlling

    public init(system: LoginItemSystemControlling = SystemLoginItemService()) {
        self.system = system
    }

    public func status() -> LoginItemStatus {
        system.observedStatus
    }

    public func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemError> {
        do {
            if enabled {
                try system.register()
            } else {
                try system.unregister()
            }
        } catch let error as LoginItemError {
            return .failure(error)
        } catch {
            return .failure(.operationFailed)
        }

        let observed = system.observedStatus
        if enabled, observed == .enabled {
            return .success(observed)
        }
        if !enabled, observed == .disabled {
            return .success(observed)
        }
        if observed == .requiresApproval {
            return .failure(.requiresApproval)
        }
        return .failure(.statusMismatch(observed))
    }
}

public final class SystemLoginItemService: LoginItemSystemControlling {
    public init() {}

    public var observedStatus: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .notRegistered:
            .disabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
