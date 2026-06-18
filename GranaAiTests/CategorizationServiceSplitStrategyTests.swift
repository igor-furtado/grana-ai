import Foundation
import Testing
@testable import GranaAi

@Suite("CategorizationServiceSplitStrategy")
struct CategorizationServiceSplitStrategyTests {
    @Test("na primeira tentativa de importacao o lote pode seguir inteiro")
    func keepsSingleBatchForInitialAttempt() {
        let drafts = makeDrafts(count: 80)

        #expect(CategorizationService.splitDraftsForRetry(drafts) != nil)
        #expect(CategorizationService.shouldSplitFailedChunk(drafts.count))
    }

    @Test("divide lote falho em duas metades antes do fallback final")
    func splitsFailedChunkInHalf() {
        let drafts = makeDrafts(count: 80)

        let split = CategorizationService.splitDraftsForRetry(drafts)

        #expect(split?.left.count == 40)
        #expect(split?.right.count == 40)
        #expect(split?.left.first?.id == drafts.first?.id)
        #expect(split?.right.first?.id == drafts[40].id)
    }

    @Test("nao divide lote pequeno que deve cair direto no fallback")
    func doesNotSplitSmallFailedChunk() {
        let drafts = makeDrafts(count: 25)

        #expect(!CategorizationService.shouldSplitFailedChunk(drafts.count))
        #expect(CategorizationService.splitDraftsForRetry(drafts) == nil)
    }

    private func makeDrafts(count: Int) -> [TransactionDraft] {
        (0 ..< count).map { index in
            TransactionDraft(
                id: UUID(),
                accountId: UUID(),
                importBatchId: UUID(),
                signedAmount: -100,
                isSignReliable: true,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(index)),
                description: "draft \(index)",
                notes: nil,
                externalId: nil
            )
        }
    }
}
