import Foundation
import SwiftUI

@MainActor
private final class PauseGate {
    private(set) var reached = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        reached = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

extension Game {
    fileprivate static func fixture(_ draws: [Int]) -> Game {
        let game = Game(minBet: 100)
        game.shoe = (0..<52).filter { !draws.contains($0) } + draws.reversed()
        game.pause = { _ in await Task.yield() }
        game.setBet(1_000)
        return game
    }
    fileprivate func hold(_ duration: Duration, at gate: PauseGate) {
        pause = { requested in
            if requested == duration && !gate.reached { await gate.wait() }
            else { await Task.yield() }
        }
    }
}

@main
private struct GameChecks {
    @MainActor
    static func main() async {
        func require(_ condition: Bool, _ message: String) { precondition(condition, message) }
        func waitFor(_ gate: PauseGate) async {
            for _ in 0..<1000 {
                if gate.reached { return }
                await Task.yield()
            }
            preconditionFailure("Expected animation pause was not reached")
        }
        let aces = Score([Card(id: 0), Card(id: 13), Card(id: 8)])
        require(aces.total == 21 && aces.isSoft, "Multiple aces must use only one eleven")
        let hard = Score([Card(id: 0), Card(id: 13), Card(id: 8), Card(id: 21)])
        require(hard.total == 20 && !hard.isSoft, "Aces must fall back to one")
        print("PASS: ace scoring")

        let dealing = Game.fixture([4, 9, 5, 6, 2])
        let opening = PauseGate()
        dealing.hold(Pacing.opening, at: opening)
        let dealTask = Task { await dealing.deal() }
        await waitFor(opening)
        require(dealing.isAnimating && !dealing.canDeal, "Dealing must lock a second deal")
        let secondDeal = await dealing.deal()
        require(secondDeal == nil && dealing.hands.isEmpty, "A repeated deal must not change the round")
        opening.release()
        _ = await dealTask.value
        require(dealing.phase == .player && !dealing.isAnimating, "Input must reopen after dealing")
        print("PASS: dealing lock and release")

        let hitGate = PauseGate()
        dealing.hold(Pacing.card, at: hitGate)
        let hitTask = Task { await dealing.hit() }
        await waitFor(hitGate)
        require(dealing.hands[0].cards.count == 3, "The first hit must draw exactly one card")
        _ = await dealing.hit()
        _ = await dealing.stand()
        require(dealing.hands[0].cards.count == 3 && dealing.phase == .player,
                "Hit and stand must be ignored during a card animation")
        hitGate.release()
        _ = await hitTask.value
        require(!dealing.isAnimating && dealing.hands[0].score.total == 14, "A completed hit must reopen input")
        print("PASS: overlapping player actions")

        let natural = Game.fixture([0, 8, 12, 6])
        let resultGate = PauseGate()
        natural.hold(Pacing.result, at: resultGate)
        var credited = [Settlement]()
        natural.onSettle = { credited.append($0) }
        let naturalTask = Task { await natural.deal() }
        await waitFor(resultGate)
        require(natural.phase == .finished && natural.isAnimating, "The result must remain visible with input locked")
        natural.prepareNextRound(keepBet: false, limit: 500)
        require(natural.phase == .finished, "A new round must wait for the result pause")
        require(credited.count == 1 && credited[0].credit == 2_500 && credited[0].net == 1_500,
                "Blackjack must pay 3:2 exactly once before presentation finishes")
        resultGate.release()
        let returned = await naturalTask.value
        require(returned == nil && !natural.isAnimating && credited.count == 1,
                "An early-booked result must not be returned and credited twice")
        natural.prepareNextRound(keepBet: false, limit: 500)
        require(natural.phase == .betting, "The next round must become available")
        print("PASS: blackjack payout, result hold and single settlement")

        let doubled = Game.fixture([4, 9, 5, 6, 22])
        _ = await doubled.deal()
        let doubleResult = await doubled.doubleDown()
        require(doubled.hands[0].bet == 2_000 && doubled.hands[0].cards.count == 3 &&
                doubleResult?.credit == 4_000 && doubleResult?.net == 2_000, "Double must keep its original accounting")
        print("PASS: double accounting")

        let split = Game.fixture([7, 9, 20, 6, 2, 22])
        _ = await split.deal()
        _ = await split.split()
        require(split.hands.count == 2 && split.hands[0].fromSplit && split.hands[1].fromSplit,
                "A split must create two ordinary hands")
        _ = await split.stand()
        require(split.active == 1 && split.hands[1].cards.count == 2, "Split must advance to the next hand")
        let splitResult = await split.stand()
        require(splitResult?.credit == 2_000 && splitResult?.net == 0 &&
                splitResult?.wins == 1 && splitResult?.losses == 1, "Split settlement must account for both stakes")
        print("PASS: split sequencing and accounting")

        require(chipValues(for: 50_000, minBet: 100) == [1_000, 2_500, 5_000, 10_000], "€500 uses familiar €10/25/50/100 chips")
        require(chipValues(for: 500, minBet: 100) == [100, 200, 500], "Small bankrolls keep affordable denominations")
        require(chipValues(for: 99, minBet: 100).isEmpty, "Below-minimum funds cannot add chips")
        for bankroll in [100, 500, 50_000, 250_000, 10_000_000] {
            let values = chipValues(for: bankroll, minBet: 100)
            require(values.count <= 4 && values == values.sorted() && Set(values).count == values.count && values.allSatisfy { $0 <= bankroll && $0 >= 100 }, "Chip values stay ordered, unique and affordable")
        }
        print("PASS: familiar dynamic denominations and bankroll boundaries")

        var wager = WagerReservation(available: 50_000, chips: 0)
        wager = wager.setting(10_000)!
        require(wager.available == 40_000 && wager.chips == 10_000, "Placing chips debits available funds immediately")
        wager = wager.setting(wager.chips + 5_000)!
        require(wager.available == 35_000 && wager.chips == 15_000, "Additional chips add to the pot")
        require(wager.setting(50_001) == nil && wager.setting(-1) == nil, "An invalid wager cannot create funds")
        wager = wager.setting(50_000)!
        require(wager.available == 0 && wager.chips == 50_000, "All In uses available plus already reserved chips")
        wager = wager.setting(0)!
        require(wager.available == 50_000, "Reset or leaving refunds all undealt chips")
        print("PASS: immediate reservation, additions, all-in and refund")

        func settledRound(_ draws: [Int], bet: Int, action: String = "stand") async -> (Int, Settlement, Game) {
            let game = Game.fixture(draws)
            var wallet = WagerReservation(available: 50_000, chips: 0).setting(bet)!
            game.setBet(wallet.chips)
            var records = [Settlement]()
            game.onSettle = { result in wallet = WagerReservation(available: wallet.available + result.credit, chips: 0); records.append(result) }
            _ = await game.deal() // initial stake was already debited
            if game.phase == .player {
                if action == "double" {
                    wallet = WagerReservation(available: wallet.available - game.extraCost, chips: wallet.chips + game.extraCost)
                    _ = await game.doubleDown()
                } else if action == "split" {
                    wallet = WagerReservation(available: wallet.available - game.extraCost, chips: wallet.chips + game.extraCost)
                    _ = await game.split()
                    while game.phase == .player { _ = await game.stand() }
                } else if action == "hit" { _ = await game.hit() }
                else { _ = await game.stand() }
            }
            require(records.count == 1, "A round must settle exactly once")
            _ = await game.deal(); _ = await game.stand(); _ = await game.hit(); _ = await game.doubleDown(); _ = await game.split()
            require(records.count == 1, "Finished rounds must reject all repeated actions")
            return (wallet.available, records[0], game)
        }
        let oddNatural = await settledRound([0, 8, 12, 6], bet: 100)
        require(oddNatural.0 == 50_150 && oddNatural.1.credit == 250, "A €1 natural pays exactly €2.50 including stake")
        let quarterNatural = await settledRound([0, 8, 12, 6], bet: 150)
        require(quarterNatural.0 == 50_225 && quarterNatural.1.credit == 375, "Fractional-euro stakes retain exact 3:2")
        let pushed = await settledRound([9, 11, 7, 20], bet: 1_000)
        require(pushed.0 == 50_000 && pushed.1.pushes == 1, "A push returns only its stake")
        let bothNatural = await settledRound([0, 13, 12, 25], bet: 100)
        require(bothNatural.0 == 50_000 && bothNatural.1.pushes == 1, "Two naturals push")
        let lost = await settledRound([8, 9, 6, 7], bet: 1_000)
        require(lost.0 == 49_000 && lost.1.credit == 0, "Loss does not charge a stake twice")
        let busted = await settledRound([9, 8, 6, 7, 10], bet: 1_000, action: "hit")
        require(busted.0 == 49_000 && busted.1.busted, "Bust loses only the reserved stake")
        let dealerBust = await settledRound([9, 8, 7, 6, 11], bet: 1_000)
        require(dealerBust.0 == 51_000 && dealerBust.1.credit == 2_000, "Dealer bust returns twice the stake")
        let walletDouble = await settledRound([4, 9, 5, 6, 22], bet: 1_000, action: "double")
        require(walletDouble.0 == 52_000, "Double debits its extra stake once")
        let walletSplit = await settledRound([7, 9, 20, 6, 2, 22], bet: 1_000, action: "split")
        require(walletSplit.0 == 50_000, "Split accounts for both stakes and mixed results")
        let splitAces = await settledRound([0, 9, 13, 6, 12, 25], bet: 1_000, action: "split")
        require(splitAces.0 == 52_000 && splitAces.1.blackjacks == 0, "Split aces pay ordinary wins, never natural blackjack")
        let halfCent = await settledRound([0, 8, 12, 6], bet: 101)
        require(halfCent.1.credit == 253, "Only a half-cent is rounded to the next cent")
        let resplit = Game.fixture([7, 9, 20, 6, 33, 46, 2, 3, 4, 5])
        _ = await resplit.deal()
        for _ in 0..<3 { _ = await resplit.split() }
        require(resplit.hands.count == 4 && !resplit.canSplit && resplit.stake == 4_000, "Resplitting stops at four hands with four stakes")
        let splitDouble = Game.fixture([7, 9, 20, 6, 2, 22, 12])
        _ = await splitDouble.deal(); _ = await splitDouble.split()
        require(splitDouble.canDouble, "Double remains allowed after a non-ace split")
        _ = await splitDouble.doubleDown()
        let splitDoubleResult = await splitDouble.stand()
        require(splitDoubleResult?.credit == 6_000 && splitDoubleResult?.net == 3_000, "A doubled split hand settles with the undoubled hand once")
        print("PASS: wallet payouts in cents, natural, push, loss, bust, double and split")

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var rechargeBalance = 42_000
        var lastClaim = 0.0
        require(!NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: false, at: now), "Normal mode cannot use night recharge")
        require(NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: true, at: now), "First manual recharge works with existing balance")
        require(rechargeBalance == 142_000, "Recharge adds €1,000 instead of replacing the bankroll")
        require(!NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: true, at: now), "Repeated taps cannot recharge twice")
        require(!NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: true, at: now.addingTimeInterval(599)), "Recharge stays locked before ten minutes")
        require(NightRecharge(lastClaim: lastClaim).remaining(at: now.addingTimeInterval(599)) == 1, "Remaining cooldown is precise")
        require(NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: true, at: now.addingTimeInterval(600)), "Recharge unlocks exactly at ten minutes")
        let muchLater = now.addingTimeInterval(86_400)
        require(NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: true, at: muchLater), "Returning after a day allows one recharge")
        require(rechargeBalance == 342_000 && !NightRecharge.claim(balance: &rechargeBalance, lastClaim: &lastClaim, afterDark: true, at: muchLater), "Unused intervals never stack")
        let normalProtection = Protection(brokeSince: now.timeIntervalSince1970, lastRefillDay: "")
        require(!normalProtection.canRefill(at: now.addingTimeInterval(1799)) && normalProtection.canRefill(at: now.addingTimeInterval(1800)), "Normal rescue uses the chosen thirty minutes")
        let used = Protection(brokeSince: now.timeIntervalSince1970 - 3600, lastRefillDay: dayKey(now))
        require(!used.canRefill(at: now), "Normal rescue remains once per calendar day")
        print("PASS: mode separation, cooldown boundary, repeated claims and no stacking")

        require(Deck.standard == Deck.blue && Deck.selected(Deck.pro, proUnlocked: false) == Deck.blue, "Blue starts selected; Pro is locked")
        require(Deck.selected(Deck.pro, proUnlocked: true) == Deck.pro && Deck.selected(99, proUnlocked: false) == Deck.blue, "Unlocked Pro stays selectable and invalid decks fall back to blue")
        let night = try! JSONDecoder().decode(Lines.Night.self, from: Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["BLACKJACK_DIALOGUE_PATH"] ?? "BlackJack/AfterDark.json")))
        let events = ["tips", "greet", "luck", "win", "blackjack", "lose", "bust", "push", "broke", "emptyPockets"]
        for character in ["Emily", "Céline", "Isabella", "Layla", "Jade"] {
            for event in events { require(!night.pool(event: event, character: character).isEmpty, "Every character needs text for every event") }
            require(night.pool(event: "tips", character: character) != night.pool(event: "tips", character: character, repeatedTips: true), "Repeated tips use a separate text pool only")
        }
        var bag = LineBag()
        let firstCycle = (0..<3).map { _ in bag.next(["A", "B", "C"]) }
        require(Set(firstCycle).count == 3, "A bag must use all variants before repeating")
        require(bag.next(["Only"]) == "Only" && bag.next([]) == "", "Changing to a smaller or empty pool must be safe")
        require(eur(100) == "€1" && eur(250) == "€2.50" && eur(375) == "€3.75", "Currency formatting uses cents")
        print("PASS: blue default, locked Pro, character text coverage and changing line pools")

        require(LadyPreference.normalized(2) == 1 && LadyPreference.normalized(0) == 0,
                "The removed voice option must migrate to text without changing Off")
        let suite = "BlackJack.GameChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(4200, forKey: Key.balance)
        defaults.set(50, forKey: Key.reservedBet)
        MoneyStore.prepare(in: defaults)
        MoneyStore.prepare(in: defaults)
        require(defaults.integer(forKey: Key.balance) == 420_000, "Money migration runs once")
        WagerReservation.recover(in: defaults)
        WagerReservation.recover(in: defaults)
        require(defaults.integer(forKey: Key.balance) == 425_000, "Restart refunds undealt chips exactly once")
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastNightRecharge)
        let reopened = UserDefaults(suiteName: suite)!
        require(!NightRecharge(lastClaim: reopened.double(forKey: Key.lastNightRecharge)).canClaim(afterDark: true, at: now.addingTimeInterval(100)), "Cooldown survives reopening the persisted store")
        defaults.set(true, forKey: Key.proUnlocked)
        defaults.set(300, forKey: Key.xp)
        defaults.set("Player", forKey: Key.name)
        defaults.set(true, forKey: Key.afterDark)
        defaults.set(false, forKey: Key.sounds)
        ProgressStore.reset(in: defaults)
        require(defaults.object(forKey: Key.balance) == nil && defaults.object(forKey: Key.xp) == nil,
                "An explicit reset must remove progress")
        require(defaults.string(forKey: Key.name) == "Player" && defaults.bool(forKey: Key.afterDark) &&
                defaults.object(forKey: Key.sounds) as? Bool == false, "A reset must preserve preferences")
        require(defaults.double(forKey: Key.lastNightRecharge) == now.timeIntervalSince1970 && !defaults.bool(forKey: Key.proUnlocked), "Reset relocks Pro but cannot clear recharge cooldown")
        print("PASS: currency migration, restart recovery, cooldown persistence and explicit reset")
        print("All game checks passed.")
    }
}
