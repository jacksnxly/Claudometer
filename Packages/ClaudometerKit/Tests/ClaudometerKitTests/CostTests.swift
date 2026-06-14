import Testing
import Foundation
import Domain
@testable import Presentation

// Unit tests for the local token-spend feature. The domain is pure, so pricing
// and report assembly are verified without any I/O.

// MARK: - PricingPolicy

@Test func pricing_opus48_standard_appliesAllMultipliers() {
    // 1M of each bucket on Opus 4.8 ($5 input): 5 + 25 + 0.5 + 6.25 + 10 = 46.75.
    let usage = TokenUsage(
        input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000,
        cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000
    )
    let cost = PricingPolicy().cost(of: usage, modelID: "claude-opus-4-8", fast: false)
    #expect(cost == Money(usd: Decimal(string: "46.75")!))
}

@Test func pricing_perFamily_baseInputRates() {
    let policy = PricingPolicy()
    let oneMInput = TokenUsage(input: 1_000_000)
    #expect(policy.cost(of: oneMInput, modelID: "claude-opus-4-8", fast: false) == Money(usd: 5))
    #expect(policy.cost(of: oneMInput, modelID: "claude-sonnet-4-6", fast: false) == Money(usd: 3))
    #expect(policy.cost(of: oneMInput, modelID: "claude-haiku-4-5-20251001", fast: false) == Money(usd: 1))
    #expect(policy.cost(of: oneMInput, modelID: "claude-fable-5", fast: false) == Money(usd: 10))
    #expect(policy.cost(of: oneMInput, modelID: "claude-opus-4-8[1m]", fast: false) == Money(usd: 5)) // 1M ctx, no premium
}

@Test func pricing_fastMode_doublesOpus48_andUnknownIsUnpriced() {
    let policy = PricingPolicy()
    let oneMInput = TokenUsage(input: 1_000_000)
    #expect(policy.cost(of: oneMInput, modelID: "claude-opus-4-8", fast: true) == Money(usd: 10))
    #expect(policy.cost(of: oneMInput, modelID: "claude-opus-4-7", fast: true) == Money(usd: 30))
    #expect(policy.rate(forModelID: "<synthetic>", fast: false) == nil)
    #expect(policy.cost(of: oneMInput, modelID: "<synthetic>", fast: false) == nil)
}

// MARK: - CostReportBuilder

@Test func builder_groupsByWindow_totalsAndFlagsUnpriced() {
    let entries = [
        LedgerEntry(window: .sevenDays, modelID: "claude-opus-4-8", fast: false, usage: TokenUsage(input: 1_000_000)),
        LedgerEntry(window: .sevenDays, modelID: "<synthetic>", fast: false, usage: TokenUsage(input: 500)),
        LedgerEntry(window: .thirtyDays, modelID: "claude-opus-4-8", fast: false, usage: TokenUsage(input: 2_000_000)),
    ]
    let report = CostReportBuilder().build(from: entries)

    let week = report.window(.sevenDays)
    #expect(week?.totalCost == Money(usd: 5))                 // synthetic adds nothing
    #expect(week?.hasUnpricedTokens == true)
    #expect(week?.lines.count == 2)

    #expect(report.window(.fourteenDays) == nil)              // no entries in this window
    #expect(report.window(.thirtyDays)?.totalCost == Money(usd: 10))
}

@Test func builder_mergesDuplicateSlices() {
    let entries = [
        LedgerEntry(window: .sevenDays, modelID: "claude-opus-4-8", fast: false, usage: TokenUsage(input: 1_000_000)),
        LedgerEntry(window: .sevenDays, modelID: "claude-opus-4-8", fast: false, usage: TokenUsage(input: 1_000_000)),
    ]
    let week = CostReportBuilder().build(from: entries).window(.sevenDays)
    #expect(week?.lines.count == 1)
    #expect(week?.lines.first?.usage.input == 2_000_000)
    #expect(week?.totalCost == Money(usd: 10))
}

// MARK: - Value objects

@Test func tokenUsage_addAndFresh() {
    let a = TokenUsage(input: 10, output: 20, cacheRead: 30)
    let b = TokenUsage(input: 1, output: 2, cacheWrite1h: 3)
    let sum = a + b
    #expect(sum.input == 11)
    #expect(sum.output == 22)
    #expect(sum.cacheRead == 30)
    #expect(sum.cacheWrite1h == 3)
    #expect(sum.freshTokens == 11 + 22)   // input + output only
    #expect(sum.total == 11 + 22 + 30 + 3)
}

// MARK: - Presentation formatting (locale-independent)

@Test func tokenFormat_abbreviates() {
    #expect(TokenFormat.short(1_500_000_000) == "1.5B")
    #expect(TokenFormat.short(845_303_741) == "845M")
    #expect(TokenFormat.short(65_000) == "65K")
    #expect(TokenFormat.short(500) == "500")
}
