import XCTest
@testable import DriftApp

final class LoginItemServiceTests: XCTestCase {
    func testSuccessfulRegistrationUpdatesObservedStatus() {
        let system = FakeLoginItemSystem(status: .disabled)
        let service = LoginItemService(system: system)

        XCTAssertEqual(service.setEnabled(true), .success(.enabled))
        XCTAssertEqual(system.registerCallCount, 1)
    }

    func testFailedRegistrationReturnsFailure() {
        let system = FakeLoginItemSystem(status: .disabled, registerError: .operationFailed)
        let service = LoginItemService(system: system)

        XCTAssertEqual(service.setEnabled(true), .failure(.operationFailed))
        XCTAssertEqual(service.status(), .disabled)
    }

    func testSuccessfulUnregistrationUpdatesObservedStatus() {
        let system = FakeLoginItemSystem(status: .enabled)
        let service = LoginItemService(system: system)

        XCTAssertEqual(service.setEnabled(false), .success(.disabled))
        XCTAssertEqual(system.unregisterCallCount, 1)
    }

    func testRequiresApprovalDoesNotReportEnabled() {
        let system = FakeLoginItemSystem(status: .requiresApproval, statusAfterRegister: .requiresApproval)
        let service = LoginItemService(system: system)

        XCTAssertEqual(service.setEnabled(true), .failure(.requiresApproval))
        XCTAssertEqual(service.status(), .requiresApproval)
    }
}

private final class FakeLoginItemSystem: LoginItemSystemControlling {
    var observedStatus: LoginItemStatus
    var registerError: LoginItemError?
    var unregisterError: LoginItemError?
    var statusAfterRegister: LoginItemStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(
        status: LoginItemStatus,
        registerError: LoginItemError? = nil,
        unregisterError: LoginItemError? = nil,
        statusAfterRegister: LoginItemStatus = .enabled
    ) {
        observedStatus = status
        self.registerError = registerError
        self.unregisterError = unregisterError
        self.statusAfterRegister = statusAfterRegister
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        observedStatus = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        observedStatus = .disabled
    }
}
