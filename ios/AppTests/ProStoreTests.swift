// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import murmur

@MainActor @Suite struct ProStoreTests {
    let file: StoreKitFile
    let product = ProRules.productId

    init() throws {
        file = try StoreKitFile.read(storeKitFileURL)
    }

    @Test func theMarkSaysWhoYouAre() {
        #expect(ProCopy.mark(.free) == nil)
        #expect(ProCopy.mark(.pro(since: .now, founder: false)) == "Supporter")
        #expect(ProCopy.mark(.pro(since: .now, founder: true)) == "Founding member")
    }

    @Test func proStartsFreeAtTheFilesPrice() async {
        let store = ProStore(shop: ScriptedShop(file), product: product)
        await store.start()
        #expect(store.status == .free)
        #expect(store.price == "$39.99")
    }

    @Test func aPurchaseMakesProAndARefundEndsIt() async throws {
        let shop = ScriptedShop(file)
        let store = ProStore(shop: shop, product: product)
        await store.start()
        await store.buy()
        #expect(store.status.isPro)
        #expect(!store.status.isFounder)
        shop.refund(product)
        try await waitUntil { store.status == .free }
        #expect(store.status == .free)
    }

    @Test func aNewPhoneRestoresPro() async {
        let shop = ScriptedShop(file)
        shop.buy(product, code: nil)
        let phone = ProStore(shop: ScriptedShop(file, bought: shop.bought), product: product)
        await phone.restore()
        #expect(phone.status.isPro)
        #expect(phone.message == nil)
    }

    @Test func aCodeRedeemedElsewhereMakesAFoundingMember() async throws {
        let shop = ScriptedShop(file)
        let store = ProStore(shop: shop, product: product)
        await store.start()
        #expect(shop.buy(product, code: ProRules.foundersCode))
        try await waitUntil { store.status.isFounder }
        #expect(store.status.isFounder)
        #expect(!shop.buy(product, code: "not-a-code"))
    }

    @Test(arguments: [(ProBuy.cancelled, nil), (.pending, ProCopy.pending), (.failed, ProCopy.buyFailed)] as [(ProBuy, String?)])
    func aPurchaseThatDoesNotFinishSaysWhy(_ outcome: ProBuy, _ message: String?) async {
        let store = ProStore(shop: FixedShop(outcome: outcome), product: product)
        await store.buy()
        #expect(store.status == .free)
        #expect(store.message == message)
        #expect(store.busy == nil)
    }

    @Test func restoringWithNothingBoughtSaysSo() async {
        let store = ProStore(shop: ScriptedShop(file), product: product)
        await store.restore()
        #expect(store.message == ProCopy.nothingToRestore)
        let offline = ProStore(shop: FixedShop(outcome: .failed, synced: false), product: product)
        await offline.restore()
        #expect(offline.message == ProCopy.restoreFailed)
    }

    /// No App Store answer: no price to show, and the free app goes on.
    @Test func withNoPriceProIsNotForSale() async {
        let store = ProStore(shop: FixedShop(outcome: .failed), product: product)
        await store.start()
        #expect(store.price == nil)
        #expect(store.status == .free)
    }

    func waitUntil(_ done: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !done() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    struct FixedShop: ProShop {
        let outcome: ProBuy
        var synced = true
        func price(_ product: String) async -> String? { nil }
        func purchases(_ product: String) async -> [ProPurchase] { [] }
        func buy(_ product: String) async -> ProBuy { outcome }
        func restore() async -> Bool { synced }
        func updates() -> AsyncStream<Void> { AsyncStream { _ in } }
    }
}

/// The real StoreKit, in Xcode's test environment, on ios/murmur.storekit.
/// One session plays the whole story in order, since every test shares the
/// one StoreKit test environment, and each step waits for StoreKit to
/// settle: a purchase, a refund, a founders code, and a restore.
@MainActor @Suite(.serialized) struct ProStoreKitTests {
    let product = ProRules.productId

    /// Refreshes until the store says so, or five seconds pass.
    func settle(_ store: ProStore, until done: @MainActor () -> Bool) async throws {
        for _ in 0..<50 where !done() {
            try await Task.sleep(for: .milliseconds(100))
            await store.refresh()
        }
    }

    @Test func aPurchaseARefundAFoundersCodeAndARestore() async throws {
        let session = try SKTestSession(contentsOf: storeKitFileURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        let store = ProStore(shop: StoreKitShop(), product: product)
        await store.start()
        try await settle(store) { store.status == .free }
        #expect(store.status == .free)
        #expect(store.price == "$39.99")

        let bought = try await session.buyProduct(identifier: product)
        try await settle(store) { store.status.isPro }
        #expect(store.status.isPro)
        #expect(!store.status.isFounder)

        try session.refundTransaction(identifier: UInt(bought.id))
        try await settle(store) { store.status == .free }
        #expect(store.status == .free)

        let coded = try await session.buyProduct(identifier: product, options: [.codeOffer(referenceName: ProRules.foundersCode)])
        #expect(StoreKitShop.purchase(coded).code == ProRules.foundersCode)
        try await settle(store) { store.status.isFounder }
        #expect(store.status.isFounder)

        await store.restore()
        #expect(store.status.isFounder)
        #expect(store.message == nil)
    }
}
