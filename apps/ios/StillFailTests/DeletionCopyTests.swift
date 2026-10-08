import XCTest
@testable import StillFail

final class DeletionCopyTests: XCTestCase {
    func testDeletionRemainsUnconditionallyLocked() {
        XCTAssertTrue(AccountDeletionView.finalDeletionLocked)
        XCTAssertEqual(AccountDeletionView.Copy.lockedTitle, "暂时无法删除账号")
        XCTAssertEqual(AccountDeletionView.Copy.lockedExplanation, "删除的数据范围和保留期限尚未核实，暂不能提交删除请求。")
    }

    func testIntendedEffectsAreExplicitlyAnUnimplementedProposal() {
        XCTAssertEqual(AccountDeletionView.Copy.proposalHeading, "删除方案（尚未实现或验证）")
        XCTAssertEqual(AccountDeletionView.Copy.proposalNote, "以下仅说明拟实施的删除范围，不代表已提交请求或已完成删除。")
        XCTAssertEqual(AccountDeletionView.Copy.accountPlan, "你的个人资料、登录身份、个人偏好和工作区成员关系会被删除，服务会撤销这个账号的登录和访问权限。")
        XCTAssertEqual(AccountDeletionView.Copy.summaryUnavailable, "暂时无法读取账号状态。请检查网络后重试。")
        XCTAssertFalse(AccountDeletionView.Copy.summaryUnavailable.contains("删除结果"))
    }

    func testOfflineAccessIsPendingVerificationAndNotAContentErasureTimer() {
        XCTAssertEqual(AccountDeletionView.Copy.offlineHeading, "拟定访问规则（尚待验证）")
        XCTAssertEqual(AccountDeletionView.Copy.offlinePolicy, "未连接服务的电脑可能仍接受旧凭据访问，最长30天。它重新连接后会收到撤销通知。这个访问期限不代表电脑上的相关内容会在30天内自动清除。")
        XCTAssertTrue(AccountDeletionView.Copy.offlineGrantNote.contains("从原始授权签发时起算"))
        XCTAssertTrue(AccountDeletionView.Copy.offlineGrantNote.contains("仍待实现或验证"))
    }

    func testCopyHasNoInstantAllDevicePromiseOrBlanketNodeFileExemption() {
        XCTAssertEqual(AccountDeletionView.Copy.computerBoundary, "这不会清空电脑，也不会删除与这个账号无关的文件。")
        let copy = [
            AccountDeletionView.Copy.lockedTitle,
            AccountDeletionView.Copy.lockedExplanation,
            AccountDeletionView.Copy.proposalHeading,
            AccountDeletionView.Copy.proposalNote,
            AccountDeletionView.Copy.accountPlan,
            AccountDeletionView.Copy.computerBoundary,
            AccountDeletionView.Copy.offlineHeading,
            AccountDeletionView.Copy.offlinePolicy,
            AccountDeletionView.Copy.offlineGrantNote,
            AccountDeletionView.Copy.summaryUnavailable,
        ].joined(separator: "\n")
        for unsafe in ["这个账号会在所有设备上退出登录", "目标电脑上的软件和本地文件也不会因此被删除", "不会擦除目标电脑上的软件和本地文件"] {
            XCTAssertFalse(copy.contains(unsafe), unsafe)
        }
    }
}
