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
        let game = Game(minBet: 1)
        game.shoe = (0..<52).filter { !draws.contains($0) } + draws.reversed()
        game.pause = { _ in await Task.yield() }
        game.setBet(10)
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
        require(credited.count == 1 && credited[0].credit == 25 && credited[0].net == 15,
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
        require(doubled.hands[0].bet == 20 && doubled.hands[0].cards.count == 3 &&
                doubleResult?.credit == 40 && doubleResult?.net == 20, "Double must keep its original accounting")
        print("PASS: double accounting")

        let split = Game.fixture([7, 9, 20, 6, 2, 22])
        _ = await split.deal()
        _ = await split.split()
        require(split.hands.count == 2 && split.hands[0].fromSplit && split.hands[1].fromSplit,
                "A split must create two ordinary hands")
        _ = await split.stand()
        require(split.active == 1 && split.hands[1].cards.count == 2, "Split must advance to the next hand")
        let splitResult = await split.stand()
        require(splitResult?.credit == 20 && splitResult?.net == 0 &&
                splitResult?.wins == 1 && splitResult?.losses == 1, "Split settlement must account for both stakes")
        print("PASS: split sequencing and accounting")

        require(LadyPreference.normalized(2) == 1 && LadyPreference.normalized(0) == 0,
                "The removed voice option must migrate to text without changing Off")
        let suite = "BlackJack.GameChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(4200, forKey: Key.balance)
        defaults.set(300, forKey: Key.xp)
        defaults.set("Player", forKey: Key.name)
        defaults.set(true, forKey: Key.afterDark)
        defaults.set(false, forKey: Key.sounds)
        ProgressStore.reset(in: defaults)
        require(defaults.object(forKey: Key.balance) == nil && defaults.object(forKey: Key.xp) == nil,
                "An explicit reset must remove progress")
        require(defaults.string(forKey: Key.name) == "Player" && defaults.bool(forKey: Key.afterDark) &&
                defaults.object(forKey: Key.sounds) as? Bool == false, "A reset must preserve preferences")
        print("PASS: option migration and explicit progress reset")
        print("All game checks passed.")
    }
}
