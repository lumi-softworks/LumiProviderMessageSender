import Foundation
import ProviderMessage

/// 编辑并重发用户消息的草稿。
///
/// 编辑不是原地改写：提交后会删除目标消息及其之后的全部消息，
/// 再把这份草稿作为同一会话里的一个新回合发出。
public struct MessageEditDraft: Sendable, Equatable {
    public let targetMessageID: UUID
    public let conversationID: UUID
    /// 编辑器原文，**不得预先 trim**；折叠块以它为坐标系。
    public let content: String
    public let imageAttachments: [UserImageAttachment]
    public let fileAttachments: [UserFileAttachment]
    public let collapsedBlocks: [CollapsedContentBlock]

    public init(
        targetMessageID: UUID,
        conversationID: UUID,
        content: String,
        imageAttachments: [UserImageAttachment] = [],
        fileAttachments: [UserFileAttachment] = [],
        collapsedBlocks: [CollapsedContentBlock] = []
    ) {
        self.targetMessageID = targetMessageID
        self.conversationID = conversationID
        self.content = content
        self.imageAttachments = imageAttachments
        self.fileAttachments = fileAttachments
        self.collapsedBlocks = collapsedBlocks
    }
}

/// 一条用户消息当前能否进入编辑。
public enum MessageEditEligibility: Sendable, Equatable {
    case allowed
    /// 不是该会话最新的一条真实用户消息（更早的消息、合成行或其它角色）。
    case notLatestRealUserMessage
    /// 会话的自动回复被抑制（ACP 托管、子代理会话、UI 测试种子消息）。
    case autoReplySuppressed
    /// 会话里还有排队待发的消息。
    case queuedMessagesPending
    /// 仍有附件在读取，此刻进入编辑会让迟到的附件落进错误的草稿。
    case attachmentsStillLoading
    case alreadyEditing
    /// 正文为空且没有附件。
    case emptyContent
}

/// 编辑会话生命周期事件。
@MainActor
public enum MessageEditingEvent {
    case began(MessageEditDraft)
    case ended(conversationID: UUID)
}

@MainActor
public protocol MessageEditingObserverHandle: AnyObject {
    /// 停止接收编辑事件。重复调用无副作用。
    func cancel()
}

/// 编辑并重发最新用户消息的能力协议。
///
/// 只有会话里最新的一条**真实**用户消息可编辑；合成行（后台任务通知、
/// 时间线卡片）与自动回复被抑制的会话一律不可编辑。
@MainActor
public protocol MessageEditingProviding: AnyObject {
    func eligibility(for message: Message, in conversationID: UUID) -> MessageEditEligibility
    /// 让编辑会话开始并发布 `.began`；消息不可编辑时返回 `false`。
    @discardableResult
    func beginEditing(message: Message, in conversationID: UUID) -> Bool
    /// 结束编辑会话并发布 `.ended`，不改动时间线。
    func cancelEditing(in conversationID: UUID)
    /// 删除目标消息及其之后的全部消息，再把草稿作为新回合发出。
    ///
    /// 返回已落库（未排队）的提交；取消超时或提交被排队时抛错。
    func submitEdit(_ draft: MessageEditDraft) async throws -> MessageSendCommit
    @discardableResult
    func addObserver(_ callback: @escaping (MessageEditingEvent) -> Void) -> any MessageEditingObserverHandle
}

@MainActor
private final class NoopMessageEditingObserverHandle: MessageEditingObserverHandle {
    func cancel() {}
}

public extension MessageEditingProviding {
    @discardableResult
    func addObserver(_ callback: @escaping (MessageEditingEvent) -> Void) -> any MessageEditingObserverHandle {
        NoopMessageEditingObserverHandle()
    }
}
