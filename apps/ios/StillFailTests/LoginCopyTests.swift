import XCTest
@testable import StillFail

final class LoginCopyTests: XCTestCase {
    func testPreparationIsAvailabilityNotUserFailure() {
        XCTAssertEqual(LoginCopy.appleUnavailable, "Apple 登录暂时不可用。请重试。")
    }
    func testCancellationIsSilentOnlyForKnownCancellation() {
        XCTAssertNil(LoginCopy.completion(provider: "google", error: CoreFailure(code: "auth_cancelled")))
        XCTAssertEqual(LoginCopy.completion(provider: "google", error: NSError(domain: "test", code: 1)), "未能用 Google 登录。请重试。")
    }
    func testCompletionUsesProviderStageAndSafeReauthentication() {
        XCTAssertEqual(LoginCopy.completion(provider: "apple", error: CoreFailure(code: "auth_failed")), "未能通过 Apple 登录。请重试。")
        XCTAssertEqual(LoginCopy.completion(provider: "google", error: CoreFailure(code: "auth_invalid_callback")), "未能完成登录。请重新登录。")
        XCTAssertEqual(LoginCopy.completion(provider: "apple", error: CoreFailure(code: "login_expired")), "这次登录已过期。请重新登录。")
    }
    func testUnknownCodesNeverSurfaceAndUncertaintyStaysDistinct() {
        for code in ["auth_failed", "arbitrary_unknown_code", "apple_not_configured"] {
            XCTAssertFalse(CoreFailure(code: code).message.contains(code))
        }
        let unknown = CoreFailure(code: "arbitrary_unknown_code")
        XCTAssertEqual(unknown.message, "暂时无法完成这个操作。请重试。")
        let uncertain = CoreFailure(code: "timeout_uncertain")
        XCTAssertTrue(uncertain.outcomeUncertain)
        XCTAssertTrue(uncertain.message.contains("结果尚不确定"))
        XCTAssertFalse(uncertain.message.contains("timeout_uncertain"))
    }
}
