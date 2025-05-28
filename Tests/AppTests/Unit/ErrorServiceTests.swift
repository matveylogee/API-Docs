import XCTest
import Vapor
import Fluent
@testable import App

final class ErrorServiceTests: XCTestCase {

    func test_handleError_withAbort_returnsSameStatusAndReason() {
        let abort = Abort(.badRequest, reason: "Bad input!")
        let result = ErrorService.shared.handleError(abort) as? Abort

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .badRequest)
        XCTAssertEqual(result?.reason, "Bad input!")
    }

    func test_handleError_withDatabaseError_returnsInternalServerError() {
        struct FakeDatabaseError: DatabaseError, Error {
            var isSyntaxError: Bool
            var isConstraintFailure: Bool
            var isConnectionClosed: Bool
            var description: String
            var isClosed: Bool
        }

        let dbError = FakeDatabaseError(
            isSyntaxError: false,
            isConstraintFailure: false,
            isConnectionClosed: false,
            description: "Mock DB error",
            isClosed: false
        )

        let result = ErrorService.shared.handleError(dbError) as? Abort

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .internalServerError)
        XCTAssertTrue(result?.reason.contains("Database error occurred") ?? false)
        XCTAssertTrue(result?.reason.contains("Mock DB error") ?? false)
    }

    func test_handleError_withGenericError_returnsInternalServerError() {
        enum Dummy: Error {
            case fail
        }
        let error = Dummy.fail
        let result = ErrorService.shared.handleError(error) as? Abort

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .internalServerError)
        let reason = result?.reason ?? ""
        XCTAssertTrue(
            reason.contains("The operation couldn’t be completed") ||
            reason.contains("Dummy")
        )
    }
}
