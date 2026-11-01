//
//  ContentView.swift
//  BlackJack
//
//  Werbefreies Blackjack in Euro (€) – die komplette App in einer Datei.
//  Karten, Jetons und Tische sind SwiftUI-Vektoren; kleine Bilder liegen im Bundle.
//  Persistiert werden nur Int/Double/String/Bool
//  über @AppStorage (wenige hundert Byte).
//

import SwiftUI
import AudioToolbox
import ImageIO

// MARK: - App

@main
struct BlackJackApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Regeln, Schlüssel, Farben

private enum Rules {
    static let startBalance = 50_000
    static let refillAmount = 50_000
    static let nightRechargeAmount = 100_000
    static let nightRechargeCooldown: TimeInterval = 10 * 60
    static let cooldown: TimeInterval = 30 * 60   // Normalmodus: 30 Minuten, einmal täglich
    static let reshuffleBelow = 15                // Neu mischen unter 15 Karten
    static let maxHands = 4                       // bis zu 3× splitten
}

/// Pausen gehören zum Spielablauf; eine Animation darf nicht von der nächsten Aktion überholt werden.
private enum Pacing {
    static let cardAnimation = 0.5
    static let opening: Duration = .milliseconds(350)
    static let card: Duration = .milliseconds(550)
    static let handSwitch: Duration = .milliseconds(350)
    static let dealerOpening: Duration = .milliseconds(550)
    static let dealerFlip: Duration = .milliseconds(850)
    static let dealerCard: Duration = .milliseconds(850)
    static let result: Duration = .milliseconds(1600)

    static func readingTime(for text: String) -> Duration {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let seconds = max(5, min(18, Double(words) / 2.8 + 1.5))
        return .milliseconds(Int64(seconds * 1000))
    }
}

private enum LadyPreference {
    /// Die frühere Sprachoption wird beim Update zur Textoption.
    static func normalized(_ value: Int) -> Int { value == 0 ? 0 : 1 }
}

private enum Key {
    static let moneyVersion = "moneyVersion"
    static let balance = "balance"
    static let reservedBet = "reservedBet"
    static let lastNightRecharge = "lastNightRecharge"
    static let brokeSince = "brokeSince"
    static let lastRefillDay = "lastRefillDay"
    static let games = "games"
    static let wins = "wins"
    static let losses = "losses"
    static let pushes = "pushes"
    static let blackjacks = "blackjacks"
    static let splits = "splits"
    static let doubles = "doubles"
    static let tips = "tips"
    static let tipTotal = "tipTotal"
    static let streak = "streak"
    static let bestStreak = "bestStreak"
    static let highest = "highestBalance"
    static let xp = "xp"
    static let claimed = "claimedAchievements"
    static let venuesPlayed = "venuesPlayed"
    static let deck = "deckSet"
    static let venue = "venue"
    static let name = "playerName"
    static let standOn21 = "standOn21"
    static let showValues = "showValues"
    static let sounds = "sounds"
    static let haptics = "haptics"
    static let ladyMode = "ladyMode"              // 0 aus · 1 Text
    static let proUnlocked = "proUnlocked"
    static let afterDark = "afterDark"            // alternativer Modus (Standard: aus)
}

private enum ProgressStore {
    static let keys = [Key.balance, Key.reservedBet, Key.brokeSince, Key.lastRefillDay, Key.games, Key.wins,
                       Key.losses, Key.pushes, Key.blackjacks, Key.splits, Key.doubles,
                       Key.tips, Key.tipTotal, Key.streak, Key.bestStreak, Key.highest,
                       Key.xp, Key.claimed, Key.venuesPlayed, Key.venue, Key.proUnlocked]

    static func reset(in defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}

/// Geldbeträge intern in Cent. Alte Euro-Speicherstände einmalig umrechnen.
private enum MoneyStore {
    static func prepare(in defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: Key.moneyVersion) < 1 else { return }
        for key in [Key.balance, Key.reservedBet, Key.highest, Key.tipTotal] {
            if let amount = defaults.object(forKey: key) as? Int { defaults.set(amount * 100, forKey: key) }
        }
        defaults.set(1, forKey: Key.moneyVersion)
    }
}

/// Freies Guthaben und ungespielte Chips sind getrennte Beträge.
struct WagerReservation {
    let available: Int
    let chips: Int

    func setting(_ amount: Int) -> WagerReservation? {
        guard amount >= 0, amount <= available + chips else { return nil }
        return WagerReservation(available: available + chips - amount, chips: amount)
    }

    /// Ungespielte, persistierte Chips nach einem Neustart genau einmal zurückgeben.
    static func recover(in defaults: UserDefaults = .standard) {
        let chips = max(0, defaults.integer(forKey: Key.reservedBet))
        guard chips > 0 else { return }
        let available = defaults.object(forKey: Key.balance) as? Int ?? Rules.startBalance
        defaults.set(available + chips, forKey: Key.balance)
        defaults.removeObject(forKey: Key.reservedBet)
    }
}

/// Lokaler Zeitstempel, keine Serverzeit und keine geräteübergreifende Absicherung.
struct NightRecharge {
    let lastClaim: Double

    var cooldownEnd: Date? {
        lastClaim > 0 ? Date(timeIntervalSince1970: lastClaim + Rules.nightRechargeCooldown) : nil
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, cooldownEnd?.timeIntervalSince(now) ?? 0)
    }

    func canClaim(afterDark: Bool, at now: Date) -> Bool {
        afterDark && remaining(at: now) == 0
    }

    /// Ein manueller Claim; verstrichene Intervalle sammeln keine weiteren Claims an.
    static func claim(balance: inout Int, lastClaim: inout Double, afterDark: Bool, at now: Date) -> Bool {
        guard NightRecharge(lastClaim: lastClaim).canClaim(afterDark: afterDark, at: now) else { return false }
        lastClaim = now.timeIntervalSince1970
        balance += Rules.nightRechargeAmount
        return true
    }
}

private enum Palette {
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.30)
    static let goldDeep = Color(red: 0.74, green: 0.52, blue: 0.12)
    static let cardRed = Color(red: 0.82, green: 0.10, blue: 0.14)
    static let cardInk = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let win = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let lose = Color(red: 1.00, green: 0.42, blue: 0.38)
    static let play = Color(red: 0.16, green: 0.78, blue: 0.33)
    static let playDeep = Color(red: 0.05, green: 0.52, blue: 0.20)
    static let purple = Color(red: 0.70, green: 0.36, blue: 0.86)
    static let wood = Color(red: 0.62, green: 0.40, blue: 0.22)
    static let woodDeep = Color(red: 0.36, green: 0.21, blue: 0.10)
    static let afterDark = Color(red: 1.00, green: 0.30, blue: 0.62)
}

/// Typografie mit iOS-Systemschriften (0 KB): Didot für Titel und Kartennamen,
/// Avenir Next für Bedienelemente und Zahlen.
private enum Typo {
    static func display(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "Didot-Bold" : "Didot", size: size)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(avenir(weight), size: size)
    }

    static func ui(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .custom(avenir(weight), size: points(style), relativeTo: style)
    }

    private static func avenir(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: "AvenirNext-Regular"
        case .medium: "AvenirNext-Medium"
        case .semibold: "AvenirNext-DemiBold"
        case .bold: "AvenirNext-Bold"
        default: "AvenirNext-Heavy"
        }
    }

    private static func points(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

/// "€1,250" – englische Schreibweise.
private let euroFormat = FloatingPointFormatStyle<Double>.number
    .locale(Locale(identifier: "en_US")).precision(.fractionLength(0...2))

private func eur(_ n: Int) -> String {
    "€" + (Double(n) / 100).formatted(euroFormat.precision(.fractionLength(n % 100 == 0 ? 0 : 2)))
}

/// Kalendertag als schlanker String, z. B. "2026-10-31".
private func dayKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
}

/// Startet unter dem kleinsten spielbaren Einsatz (1 €) einmalig den Pleiteschutz.
private func syncBroke(_ balance: inout Int, _ brokeSince: inout Double) {
    if balance < 100 {
        balance = max(0, balance)
        if brokeSince == 0 { brokeSince = Date.now.timeIntervalSince1970 }
    } else if brokeSince != 0 {
        brokeSince = 0
    }
}

extension EnvironmentValues {
    @Entry var deckStyle: Int = 1
}

// MARK: - Fortschritt

private enum Progression {
    static func level(xp: Int) -> Int { Int((Double(max(xp, 0)) / 40).squareRoot()) + 1 }
    static func xpFor(level: Int) -> Int { (level - 1) * (level - 1) * 40 }
    static func progress(xp: Int) -> Double {
        let l = level(xp: xp)
        let lo = xpFor(level: l)
        let hi = xpFor(level: l + 1)
        return Double(xp - lo) / Double(max(hi - lo, 1))
    }
}

// MARK: - Karten & Hände

struct Card: Identifiable, Equatable {
    let id: Int                                   // 0...51, eindeutig im Deck

    var rank: Int { id % 13 + 1 }                 // 1 = Ass … 13 = König
    var suit: Int { id / 13 }                     // 0 ♠ · 1 ♥ · 2 ♦ · 3 ♣
    var points: Int { min(rank, 10) }             // Ass zählt hier 1
    var isRed: Bool { suit == 1 || suit == 2 }

    var label: String {
        switch rank {
        case 1: "A"
        case 11: "J"
        case 12: "Q"
        case 13: "K"
        default: String(rank)
        }
    }

    var symbol: String {
        ["suit.spade.fill", "suit.heart.fill", "suit.diamond.fill", "suit.club.fill"][suit]
    }

    var name: String {
        ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
         "Jack", "Queen", "King"][rank - 1]
    }

    var spoken: String {
        "\(name) of \(["Spades", "Hearts", "Diamonds", "Clubs"][suit])"
    }
}

struct Score: Equatable {
    let total: Int
    let isSoft: Bool                              // Ass wird als 11 gezählt

    init(_ cards: [Card]) {
        var sum = 0
        var aces = 0
        for card in cards {
            sum += card.points
            if card.rank == 1 { aces += 1 }
        }
        if aces > 0 && sum + 10 <= 21 {
            sum += 10
            isSoft = true
        } else {
            isSoft = false
        }
        total = sum
    }

    var isBust: Bool { total > 21 }
    var text: String { isBust ? "BUST" : (isSoft ? "Soft \(total)" : "\(total)") }
}

private func isNatural(_ cards: [Card]) -> Bool {
    cards.count == 2 && Score(cards).total == 21
}

enum Phase {
    case betting, dealing, player, dealer, finished
    var isIdle: Bool { self == .betting || self == .finished }
}

enum Verdict { case blackjack, win, lose, push }

struct Hand: Identifiable, Equatable {
    let id: Int
    var cards: [Card]
    var bet: Int
    var fromSplit = false
    var splitAces = false
    var doubled = false
    var done = false
    var verdict: Verdict?

    var score: Score { Score(cards) }
    /// Ein Blackjack zählt nur ohne Split (21 nach Split = normaler Sieg).
    var isNatural: Bool { !fromSplit && cards.count == 2 && score.total == 21 }
}

struct Outcome: Equatable {
    let verdict: Verdict
    let headline: String
    let net: Int
}

/// Ergebnis einer Runde – wird vom Tisch aufs Guthaben und in die Statistik gebucht.
struct Settlement {
    let credit: Int
    let net: Int
    let wins: Int
    let losses: Int
    let pushes: Int
    let blackjacks: Int
    let busted: Bool
}

// MARK: - Spiel-Engine

@MainActor @Observable
final class Game {
    let minBet: Int

    private(set) var phase: Phase = .betting
    private(set) var hands: [Hand] = []
    private(set) var active = 0
    private(set) var dealer: [Card] = []
    private(set) var holeHidden = true
    private(set) var outcome: Outcome?
    private(set) var bet = 0
    private(set) var lastBet = 0
    private(set) var dealtCount = 0               // Taktgeber für Sound
    private(set) var isAnimating = false

    @ObservationIgnored var standOn21 = true
    /// Bucht das Rundenergebnis, sobald es feststeht (vor der Dealer-Animation).
    @ObservationIgnored var onSettle: ((Settlement) -> Void)?
    @ObservationIgnored private var shoe: [Int] = []
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var pause: @MainActor (Duration) async -> Void = {
        try? await Task.sleep(for: $0)
    }

    private let dealSpring = Animation.spring(duration: Pacing.cardAnimation, bounce: 0.12)

    init(minBet: Int) { self.minBet = minBet }

    var activeHand: Hand? {
        phase == .player && hands.indices.contains(active) ? hands[active] : nil
    }
    var canDeal: Bool { phase == .betting && !isAnimating && bet >= minBet }
    var canDouble: Bool {
        guard let hand = activeHand else { return false }
        return hand.cards.count == 2 && !hand.splitAces
    }
    var canSplit: Bool {
        guard let hand = activeHand, hands.count < Rules.maxHands, hand.cards.count == 2 else { return false }
        return hand.cards[0].points == hand.cards[1].points
    }
    /// Zusätzlicher Einsatz für Double/Split der aktiven Hand.
    var extraCost: Int { activeHand?.bet ?? 0 }
    var stake: Int { hands.isEmpty ? bet : hands.reduce(0) { $0 + $1.bet } }

    // MARK: Einsatz

    func addChip(_ value: Int, limit: Int) {
        guard value > 0, phase == .betting, !isAnimating, bet + value <= limit else { return }
        bet += value
    }

    func setBet(_ value: Int) {
        guard phase == .betting, !isAnimating else { return }
        bet = max(0, value)
    }

    func clearBet() {
        guard phase == .betting, !isAnimating else { return }
        bet = 0
    }

    func prepareNextRound(keepBet: Bool, limit: Int) {
        guard phase == .finished, !isAnimating else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            hands = []
            dealer = []
            outcome = nil
            holeHidden = true
            phase = .betting
        }
        bet = keepBet ? min(lastBet, limit) : 0
    }

    // MARK: Ablauf

    func deal() async -> Settlement? {
        guard canDeal else { return nil }
        isAnimating = true
        defer { isAnimating = false }
        phase = .dealing
        lastBet = bet
        withAnimation(.easeOut(duration: 0.2)) {
            hands = []
            dealer = []
            outcome = nil
            holeHidden = true
            active = 0
        }
        if shoe.count < Rules.reshuffleBelow { shoe = Array(0..<52).shuffled() }

        await pause(Pacing.opening)
        hands = [Hand(id: newID(), cards: [], bet: bet)]
        for i in 0..<4 {                          // Spieler, Dealer, Spieler, Dealer (verdeckt)
            withAnimation(dealSpring) {
                if i % 2 == 0 { hands[0].cards.append(draw()) } else { dealer.append(draw()) }
            }
            await pause(Pacing.card)
        }

        if hands[0].isNatural || isNatural(dealer) { return await finish() }
        phase = .player
        return nil
    }

    func hit() async -> Settlement? {
        guard phase == .player, !isAnimating, hands.indices.contains(active) else { return nil }
        isAnimating = true
        defer { isAnimating = false }
        withAnimation(dealSpring) { hands[active].cards.append(draw()) }
        await pause(Pacing.card)
        let score = hands[active].score
        if score.isBust || (standOn21 && score.total == 21) { return await advance() }
        return nil
    }

    func stand() async -> Settlement? {
        guard phase == .player, !isAnimating else { return nil }
        isAnimating = true
        defer { isAnimating = false }
        await pause(Pacing.handSwitch)
        return await advance()
    }

    func doubleDown() async -> Settlement? {
        guard canDouble, !isAnimating else { return nil }
        isAnimating = true
        defer { isAnimating = false }
        hands[active].bet *= 2
        hands[active].doubled = true
        withAnimation(dealSpring) { hands[active].cards.append(draw()) }
        await pause(Pacing.card)
        return await advance()
    }

    func split() async -> Settlement? {
        guard canSplit, !isAnimating else { return nil }
        isAnimating = true
        defer { isAnimating = false }
        phase = .dealing
        let original = hands[active]
        let aces = original.cards[0].rank == 1
        var left = original
        left.cards = [original.cards[0]]
        left.fromSplit = true
        left.splitAces = aces
        let right = Hand(id: newID(), cards: [original.cards[1]], bet: original.bet,
                         fromSplit: true, splitAces: aces)
        withAnimation(dealSpring) {
            hands[active] = left
            hands.insert(right, at: active + 1)
        }
        await pause(Pacing.handSwitch)
        withAnimation(dealSpring) { hands[active].cards.append(draw()) }
        await pause(Pacing.card)
        phase = .player
        if aces || (standOn21 && hands[active].score.total == 21) { return await advance() }
        return nil
    }

    // MARK: Intern

    private func newID() -> Int {
        nextID += 1
        return nextID
    }

    private func draw(counting: Bool = true, alsoInPlay: [Card] = []) -> Card {
        if shoe.isEmpty {                         // Notnagel: nie ohne Karten dastehen
            let inPlay = Set((hands.flatMap(\.cards) + dealer + alsoInPlay).map(\.id))
            shoe = (0..<52).filter { !inPlay.contains($0) }.shuffled()
        }
        if counting { dealtCount &+= 1 }
        return Card(id: shoe.removeLast())
    }

    /// Schließt die aktive Hand ab und springt zur nächsten offenen Hand bzw. zum Dealer.
    private func advance() async -> Settlement? {
        hands[active].done = true
        guard let next = hands.indices.first(where: { !hands[$0].done }) else {
            return await dealerTurn()
        }
        withAnimation(.snappy) { active = next }
        await pause(Pacing.handSwitch)
        if hands[next].cards.count < 2 {          // zweite Karte nach Split
            phase = .dealing
            await pause(Pacing.handSwitch)
            withAnimation(dealSpring) { hands[next].cards.append(draw()) }
            await pause(Pacing.card)
            phase = .player
            if hands[next].splitAces || (standOn21 && hands[next].score.total == 21) {
                return await advance()
            }
        }
        return nil
    }

    /// Zieht die Dealerhand vorab und schreibt das Ergebnis über `onSettle` sofort gut;
    /// die Animation danach ist reine Anzeige. Ein App-Abbruch kostet so keinen Gewinn.
    private func dealerTurn() async -> Settlement? {
        phase = .dealer
        var final = dealer
        if hands.contains(where: { !$0.score.isBust }) {
            while Score(final).total < 17 {       // Dealer zieht bis 16, steht ab 17
                final.append(draw(counting: false, alsoInPlay: final))
            }
        }
        let (settlement, resolved, outcome) = resolve(final)
        let early = onSettle
        early?(settlement)

        await pause(Pacing.dealerOpening)
        withAnimation(.easeInOut(duration: 0.65)) { holeHidden = false }
        await pause(Pacing.dealerFlip)
        for card in final.dropFirst(dealer.count) {
            withAnimation(dealSpring) { dealer.append(card) }
            dealtCount &+= 1
            await pause(Pacing.dealerCard)
        }
        show(resolved, outcome)
        await pause(Pacing.result)
        return early == nil ? settlement : nil
    }

    private func finish() async -> Settlement? {
        let (settlement, resolved, outcome) = resolve(dealer)
        let early = onSettle
        early?(settlement)
        await pause(Pacing.dealerOpening)
        withAnimation(.easeInOut(duration: 0.65)) { holeHidden = false }
        await pause(Pacing.dealerFlip)
        show(resolved, outcome)
        await pause(Pacing.result)
        return early == nil ? settlement : nil
    }

    private func show(_ resolved: [Hand], _ outcome: Outcome) {
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
            hands = resolved
            holeHidden = false
            self.outcome = outcome
            phase = .finished
        }
    }

    /// Wertet alle Hände gegen die (endgültige) Dealerhand aus – ohne UI-Änderung.
    private func resolve(_ dealer: [Card]) -> (Settlement, [Hand], Outcome) {
        let d = Score(dealer)
        let dealerNatural = isNatural(dealer)
        var credit = 0
        var wins = 0, losses = 0, pushes = 0, blackjacks = 0
        var resolved = hands

        for i in resolved.indices {
            let hand = resolved[i]
            let p = hand.score
            let verdict: Verdict
            if hand.isNatural && dealerNatural { verdict = .push }
            else if hand.isNatural { verdict = .blackjack }
            else if dealerNatural { verdict = .lose }
            else if p.isBust { verdict = .lose }
            else if d.isBust || p.total > d.total { verdict = .win }
            else if p.total == d.total { verdict = .push }
            else { verdict = .lose }
            resolved[i].verdict = verdict

            switch verdict {
            case .blackjack:                      // 3:2, nur halbe Cent aufrunden
                credit += hand.bet + (hand.bet * 3 + 1) / 2
                blackjacks += 1
                wins += 1
            case .win:                            // 1:1
                credit += hand.bet * 2
                wins += 1
            case .push:                           // Einsatz zurück
                credit += hand.bet
                pushes += 1
            case .lose:
                losses += 1
            }
        }

        let stake = resolved.reduce(0) { $0 + $1.bet }
        let net = credit - stake
        let busted = resolved.count == 1 && resolved[0].score.isBust
        let headline: String
        let summary: Verdict
        if resolved.count == 1, let only = resolved[0].verdict {
            summary = only
            switch only {
            case .blackjack: headline = "BLACKJACK!"
            case .win: headline = d.isBust ? "DEALER BUST" : "YOU WIN"
            case .push: headline = dealerNatural ? "PUSH · BOTH BLACKJACK" : "PUSH"
            case .lose: headline = busted ? "BUST" : (dealerNatural ? "DEALER BLACKJACK" : "YOU LOSE")
            }
        } else {
            summary = net > 0 ? .win : (net < 0 ? .lose : .push)
            headline = "\(wins) WON · \(losses) LOST"
        }

        let settlement = Settlement(credit: credit, net: net, wins: wins, losses: losses, pushes: pushes,
                                    blackjacks: blackjacks, busted: busted)
        return (settlement, resolved, Outcome(verdict: summary, headline: headline, net: net))
    }
}

// MARK: - Jeton-Werte (dynamisch zum Guthaben)

/// Vier übliche Casino-Werte in einer passenden Größenordnung statt Prozent-Einsätzen.
/// Die Auswahl bleibt während des Setzens konstant; bezahlbare Chips werden separat aktiviert.
private func chipValues(for balance: Int, minBet: Int) -> [Int] {
    guard minBet > 0, balance >= minBet else { return [] }
    var denominations = [minBet]
    var scale = 100 // Cent pro Euro
    while scale <= balance {
        for value in [1, 2, 5, 10, 25, 50] {
            guard scale <= Int.max / value else { continue }
            let amount = scale * value
            if amount >= minBet && amount <= balance { denominations.append(amount) }
        }
        guard scale <= Int.max / 100 else { break }
        scale *= 100
    }
    let values = Array(Set(denominations)).sorted()
    let target = max(minBet, balance / 4)
    let upper = min(values.count, max(4, values.prefix { $0 <= target }.count))
    return Array(values.prefix(upper).suffix(4))
}

// MARK: - Tische & Bar-Ladys

enum HairStyle { case waves, bob, updo, straight, curls }
enum PlateIcon { case crown, eiffel, palace, tower, spade }

struct Lady {
    let name: String
    let skin: Color
    let hair: Color
    let style: HairStyle
    let eyes: Color
    let lips: Color
    let outfit: Color
}

struct Venue: Identifiable {
    let id: Int
    let city: String
    let tagline: String
    let level: Int
    let minBet: Int
    let entry: Int
    let felt: [Color]
    let accent: Color
    let room: Color
    let lady: Lady

    /// Porträtfoto im Bundle, z. B. "lady-las-vegas.heic" (Fallback: Vektor-Porträt).
    var photo: String { "lady-" + city.lowercased().replacingOccurrences(of: " ", with: "-") }

    /// Trinkgeld pro Tipp auf die Bar-Lady – steigt mit der Exklusivität des Tisches.
    var tip: Int { [5_000, 10_000, 25_000, 100_000, 500_000][id] }

    /// Symbol auf dem Namensschild der Bar-Lady.
    var plateIcon: PlateIcon { [.crown, .eiffel, .palace, .tower, .spade][id] }

    static let all: [Venue] = [
        Venue(
            id: 0, city: "LONDON", tagline: "The Velvet Club", level: 1, minBet: 100, entry: 0,
            felt: [Color(red: 0.07, green: 0.50, blue: 0.27), Color(red: 0.02, green: 0.25, blue: 0.13)],
            accent: Color(red: 0.25, green: 0.80, blue: 0.48), room: Color(red: 0.30, green: 0.18, blue: 0.10),
            lady: Lady(
                name: "Emily",
                skin: Color(red: 0.98, green: 0.84, blue: 0.74), hair: Color(red: 0.62, green: 0.26, blue: 0.12),
                style: .waves, eyes: Color(red: 0.25, green: 0.50, blue: 0.35),
                lips: Color(red: 0.78, green: 0.16, blue: 0.22), outfit: Color(red: 0.12, green: 0.20, blue: 0.48)
            )
        ),
        Venue(
            id: 1, city: "PARIS", tagline: "Salon Lumière", level: 3, minBet: 1_000, entry: 100_000,
            felt: [Color(red: 0.36, green: 0.16, blue: 0.48), Color(red: 0.15, green: 0.05, blue: 0.22)],
            accent: Color(red: 0.74, green: 0.42, blue: 0.95), room: Color(red: 0.24, green: 0.10, blue: 0.24),
            lady: Lady(
                name: "Céline",
                skin: Color(red: 0.96, green: 0.80, blue: 0.70), hair: Color(red: 0.12, green: 0.08, blue: 0.07),
                style: .bob, eyes: Color(red: 0.36, green: 0.24, blue: 0.14),
                lips: Color(red: 0.70, green: 0.05, blue: 0.16), outfit: Color(red: 0.45, green: 0.06, blue: 0.20)
            )
        ),
        Venue(
            id: 2, city: "MONACO", tagline: "Riviera Royale", level: 6, minBet: 5_000, entry: 500_000,
            felt: [Color(red: 0.06, green: 0.24, blue: 0.48), Color(red: 0.02, green: 0.09, blue: 0.22)],
            accent: Color(red: 1.00, green: 0.62, blue: 0.22), room: Color(red: 0.36, green: 0.20, blue: 0.08),
            lady: Lady(
                name: "Isabella",
                skin: Color(red: 0.88, green: 0.68, blue: 0.52), hair: Color(red: 0.93, green: 0.78, blue: 0.48),
                style: .updo, eyes: Color(red: 0.30, green: 0.45, blue: 0.62),
                lips: Color(red: 0.80, green: 0.28, blue: 0.32), outfit: Color(red: 0.80, green: 0.62, blue: 0.24)
            )
        ),
        Venue(
            id: 3, city: "DUBAI", tagline: "Desert Pearl", level: 10, minBet: 25_000, entry: 2_500_000,
            felt: [Color(red: 0.17, green: 0.14, blue: 0.08), Color(red: 0.05, green: 0.04, blue: 0.02)],
            accent: Color(red: 1.00, green: 0.76, blue: 0.28), room: Color(red: 0.32, green: 0.22, blue: 0.08),
            lady: Lady(
                name: "Layla",
                skin: Color(red: 0.86, green: 0.66, blue: 0.50), hair: Color(red: 0.06, green: 0.05, blue: 0.06),
                style: .straight, eyes: Color(red: 0.30, green: 0.18, blue: 0.10),
                lips: Color(red: 0.70, green: 0.30, blue: 0.32), outfit: Color(red: 0.10, green: 0.08, blue: 0.06)
            )
        ),
        Venue(
            id: 4, city: "LAS VEGAS", tagline: "Neon Palace", level: 15, minBet: 100_000, entry: 10_000_000,
            felt: [Color(red: 0.10, green: 0.10, blue: 0.30), Color(red: 0.03, green: 0.03, blue: 0.12)],
            accent: Color(red: 1.00, green: 0.32, blue: 0.70), room: Color(red: 0.22, green: 0.06, blue: 0.26),
            lady: Lady(
                name: "Jade",
                skin: Color(red: 0.55, green: 0.36, blue: 0.24), hair: Color(red: 0.10, green: 0.07, blue: 0.06),
                style: .curls, eyes: Color(red: 0.42, green: 0.28, blue: 0.12),
                lips: Color(red: 0.62, green: 0.14, blue: 0.30), outfit: Color(red: 0.12, green: 0.58, blue: 0.48)
            )
        ),
    ]
}

// MARK: - Bar-Lady-Sprüche

private enum Lines {
    static let tips = [
        "Thank you for the tip.",
        "Much appreciated. Enjoy the table.",
        "Thank you. Your remaining chips are available to play.",
        "Cheers. Take your time with the next hand.",
        "Thank you. The table is ready when you are.",
        "Tip received. Good evening.",
        "Many thanks. Enjoy your game.",
        "Thank you. Drinks service is open.",
        "Appreciated. Watch the dealer’s upcard.",
        "Thank you for your generosity.",
        "Cheers. Your tip has been collected.",
        "Thank you. Set your chips when you are ready.",
    ]
    static let greet = [
        "Welcome to the table.",
        "Good evening. Place your chips when ready.",
        "Welcome. Blackjack pays three to two.",
        "The table is open. Take your time.",
    ]
    static let luck = [
        "Bets placed. Here come the cards.",
        "The next hand is starting.",
        "Your cards are on their way.",
        "Let’s see the opening hand.",
    ]
    static let win = [
        "Winning hand. Your payout includes your stake.",
        "You win. Payout credited.",
        "The hand is yours.",
        "A win for the player.",
    ]
    static let blackjack = [
        "Blackjack. Three-to-two payout.",
        "A natural twenty-one.",
        "Blackjack. Your stake and winnings are credited.",
    ]
    static let lose = [
        "The dealer wins this hand.",
        "This hand goes to the house.",
        "Hand complete. Take your time before the next bet.",
    ]
    static let bust = [
        "Over twenty-one. This hand is bust.",
        "Bust. The stake goes to the house.",
    ]
    static let push = [
        "Push. Your stake is returned.",
        "Equal totals. No gain or loss.",
    ]
    static let broke = [
        "Out of chips. The refill details are in your profile.",
        "Your bankroll is empty. Time for a break.",
    ]
    static let greedy = [
        "Five consecutive tips. The remaining bankroll has been collected.",
        "That was the fifth consecutive tip. Your remaining chips went to the bar.",
    ]
    static let emptyPockets = [
        "Not enough available chips for this tip.",
        "Your remaining chips are reserved for the table.",
    ]

    /// Gebündelter Spruch-Satz; lokale Builds können ihn über Private/ überschreiben.
    /// Bei fehlenden oder unlesbaren Daten bleibt der Normalmodus verfügbar.
    struct Night: Decodable {
        let tips, greet, luck, win, blackjack, lose, bust, push, broke, emptyPockets: [String]
        let signatures: [String: [String]]
        /// Optional: pro Figur und Ereignis; alte lokale Dateien bleiben kompatibel.
        let characters: [String: [String: [String]]]?

        func pool(event: String, character: String, repeatedTips: Bool = false) -> [String] {
            let personal = characters?[character]
            let key = event == "tips" && repeatedTips && personal?["repeatTips"]?.isEmpty == false
                ? "repeatTips" : event
            let fallback: [String]
            switch event {
            case "tips": fallback = tips + (signatures[character] ?? [])
            case "greet": fallback = greet
            case "luck": fallback = luck
            case "win": fallback = win
            case "blackjack": fallback = blackjack
            case "lose": fallback = lose
            case "bust": fallback = bust
            case "push": fallback = push
            case "broke": fallback = broke
            default: fallback = emptyPockets
            }
            let selected = personal?[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            return selected.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    static let night: Night? = {
        guard let url = Bundle.main.url(forResource: "AfterDark", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Night.self, from: data)
    }()
}

/// Liefert jeden Spruch erst wieder, wenn alle anderen dran waren.
private struct LineBag {
    private var pool: [String] = []
    private var order: [Int] = []
    private var previous: String?

    mutating func next(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        if pool != lines { pool = lines; order = [] }
        if order.isEmpty {
            order = Array(lines.indices).shuffled()
            if order.count > 1, lines[order.last!] == previous { order.swapAt(0, order.count - 1) }
        }
        let line = lines[order.removeLast()]
        previous = line
        return line
    }
}

// MARK: - Erfolge

private struct Stats {
    let games, wins, blackjacks, splits, doubles, tips, bestStreak, highest, venues: Int
}

private struct Achievement: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let icon: String
    let reward: Int
    let target: Int
    let value: @Sendable (Stats) -> Int

    static let all: [Achievement] = [
        Achievement(id: 0, title: "The Beginning", detail: "Win your first game", icon: "star.fill",
                    reward: 10_000, target: 1) { $0.wins },
        Achievement(id: 1, title: "My First Blackjack", detail: "Get your first blackjack",
                    icon: "suit.spade.fill", reward: 25_000, target: 1) { $0.blackjacks },
        Achievement(id: 2, title: "The More the Merrier", detail: "Split a hand",
                    icon: "arrow.triangle.branch", reward: 5_000, target: 1) { $0.splits },
        Achievement(id: 3, title: "Double Trouble", detail: "Double down 10 times", icon: "plus.circle.fill",
                    reward: 15_000, target: 10) { $0.doubles },
        Achievement(id: 4, title: "Charmer", detail: "Tip the bar lady 10 times", icon: "wineglass.fill",
                    reward: 15_000, target: 10) { $0.tips },
        Achievement(id: 5, title: "Regular", detail: "Play 50 rounds", icon: "clock.fill",
                    reward: 30_000, target: 50) { $0.games },
        Achievement(id: 6, title: "Hot Streak", detail: "Win 5 rounds in a row", icon: "flame.fill",
                    reward: 40_000, target: 5) { $0.bestStreak },
        Achievement(id: 7, title: "Globetrotter", detail: "Play at 3 tables",
                    icon: "globe.europe.africa.fill", reward: 50_000, target: 3) { $0.venues },
        Achievement(id: 8, title: "High Roller", detail: "Reach a balance of €5,000", icon: "crown.fill",
                    reward: 100_000, target: 500_000) { $0.highest },
        Achievement(id: 9, title: "Blackjack Pro", detail: "Get 25 blackjacks", icon: "trophy.fill",
                    reward: 250_000, target: 25) { $0.blackjacks },
        Achievement(id: 10, title: "Veteran", detail: "Play 500 rounds", icon: "medal.fill",
                    reward: 200_000, target: 500) { $0.games },
    ]
}

// MARK: - Decks

/// Drei komplette Decks (Vorder- + Rückseite):
/// Classic = weiß/Bordeaux, Blue = weiß/Blau, Pro = Zebra-Vorderseite + Medaillon-Rückseite.
private enum Deck {
    static let names = ["Classic", "Blue", "Pro"]
    static let classic = 0
    static let blue = 1
    static let pro = 2
    static let standard = blue

    static func valid(_ value: Int) -> Int { names.indices.contains(value) ? value : standard }
    static func selected(_ value: Int, proUnlocked: Bool) -> Int {
        let index = valid(value)
        return index == pro && !proUnlocked ? blue : index
    }
}

// MARK: - Pleiteschutz

/// Reine Rechenlogik – kein Timer, kein Speicher.
struct Protection {
    let brokeSince: Double                        // Unix-Zeit bei 0 € (0 = nicht pleite)
    let lastRefillDay: String                     // Kalendertag der letzten Nutzung

    var cooldownEnd: Date? {
        brokeSince > 0 ? Date(timeIntervalSince1970: brokeSince + Rules.cooldown) : nil
    }

    func usedToday(at now: Date) -> Bool { lastRefillDay == dayKey(now) }

    func canRefill(at now: Date) -> Bool {
        guard let end = cooldownEnd, now >= end else { return false }
        return !usedToday(at: now)
    }

    /// Zeitpunkte, an denen sich die Anzeige ändert (Cooldown-Ende, Mitternacht).
    func changeDates(after now: Date) -> [Date] {
        var dates: [Date] = []
        if let end = cooldownEnd, end > now { dates.append(end) }
        if usedToday(at: now),
           let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            dates.append(next)
        }
        return dates
    }
}

/// TimelineView-Zeitplan ohne Dauer-Tick: nur jetzt + die angegebenen Zeitpunkte.
nonisolated struct DatesSchedule: TimelineSchedule {
    let dates: [Date]

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        [startDate] + dates.filter { $0 > startDate }.sorted()
    }
}

/// Rendert nur neu, wenn ein relevanter Zeitpunkt erreicht ist. Die Sekundenanzeige
/// übernimmt `Text(timerInterval:)` systemseitig; im Hintergrund pausiert alles.
private struct Live<Content: View>: View {
    let dates: [Date]
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if dates.isEmpty {
            content(.now)
        } else {
            TimelineView(DatesSchedule(dates: dates)) { context in
                content(context.date)
            }
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @AppStorage(Key.balance) private var balance = Rules.startBalance
    @AppStorage(Key.brokeSince) private var brokeSince = 0.0
    @AppStorage(Key.afterDark) private var afterDark = false
    @AppStorage(Key.ladyMode) private var ladyMode = 1
    @State private var table: Int?
    @State private var prepared = false

    var body: some View {
        ZStack {
            if let table, Venue.all.indices.contains(table) {
                TableScreen(venue: Venue.all[table]) {
                    withAnimation(.smooth(duration: 0.4)) { self.table = nil }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else {
                LobbyScreen { index in
                    withAnimation(.smooth(duration: 0.4)) { table = index }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if !prepared {
                prepared = true
                if ProcessInfo.processInfo.arguments.contains("--reset-progress") {
                    ProgressStore.reset()
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
                    afterDark = false
                    UserDefaults.standard.removeObject(forKey: Key.deck)
                    UserDefaults.standard.removeObject(forKey: Key.lastNightRecharge)
                }
                #endif
                MoneyStore.prepare()
                WagerReservation.recover()
                ladyMode = LadyPreference.normalized(ladyMode)
            }
            syncBroke(&balance, &brokeSince)
            if Lines.night == nil { afterDark = false }   // ohne Datei kein alternativer Modus
            #if DEBUG
            if let demo = UserDefaults.standard.string(forKey: "demoTable").flatMap(Int.init) { table = demo }
            #endif
        }
    }
}

// MARK: - Lobby

private struct LobbyScreen: View {
    @AppStorage(Key.proUnlocked) private var proUnlocked = false
    let play: (Int) -> Void

    @AppStorage(Key.balance) private var balance = Rules.startBalance
    @AppStorage(Key.xp) private var xp = 0
    @AppStorage(Key.name) private var name = "Guest"
    @AppStorage(Key.venue) private var savedVenue = 0
    @AppStorage(Key.afterDark) private var afterDark = false
    @State private var focused: Int?
    @State private var showProfile = false
    @State private var showOptions = false
    @State private var spadeTaps: [Date] = []
    @State private var proReward = false
    @State private var modeToast: Bool?             // true = „After Dark Unlocked“, false = „Back to Business“

    private var level: Int { Progression.level(xp: xp) }

    private func playable(_ venue: Venue) -> Bool {
        level >= venue.level && balance >= venue.entry
    }

    var body: some View {
        ZStack {
            LobbyBackground()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button { showProfile = true } label: {
                        PlayerBadge(name: name, xp: xp, size: 74)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("openProfile")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        BalancePill(balance: balance)
                        ProtectionPill()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Button(action: tapSpade) {
                    HStack(spacing: 8) {
                        Image(systemName: "suit.spade.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(afterDark ? Palette.afterDark : Palette.gold)
                            .shadow(color: (afterDark ? Palette.afterDark : Palette.gold).opacity(0.6), radius: 8)
                        Text("BLACKJACK")
                            .font(Typo.display(24))
                            .tracking(4)
                            .foregroundStyle(.white)
                        if afterDark {
                            Text("AFTER DARK")
                                .font(Typo.ui(10, .heavy))
                                .tracking(1.5)
                                .foregroundStyle(Palette.afterDark)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(Palette.afterDark.opacity(0.7), lineWidth: 1))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .accessibilityLabel("Blackjack").accessibilityIdentifier("modeSwitch")

                Spacer(minLength: 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(Venue.all) { venue in
                            VenueCard(venue: venue, unlocked: level >= venue.level,
                                      affordable: balance >= venue.entry) {
                                savedVenue = venue.id
                                play(venue.id)
                            }
                            .frame(width: 268, height: 430)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .rotation3DEffect(.degrees(phase.value * -22), axis: (x: 0, y: 1, z: 0),
                                                      perspective: 0.55)
                                    .scaleEffect(1 - abs(phase.value) * 0.1)
                                    .opacity(1 - abs(phase.value) * 0.35)
                            }
                            .id(venue.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 67, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focused)
                .frame(height: 450)

                Spacer(minLength: 12)

                HStack(spacing: 16) {
                    RoundIconButton(icon: "trophy.fill", tint: Palette.gold, ink: .black.opacity(0.75)) {
                        showProfile = true
                    }
                    Button {
                        playFocused()
                    } label: {
                        Text("PLAY NOW")
                            .font(Typo.ui(22, .heavy))
                            .tracking(0.5)
                            .foregroundStyle(.black.opacity(0.82))
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(
                                LinearGradient(colors: [Palette.gold, Color(red: 0.98, green: 0.68, blue: 0.10)],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .shadow(color: Palette.gold.opacity(0.45), radius: 14, y: 4)
                    }
                    .buttonStyle(PressStyle())
                    RoundIconButton(icon: "gearshape.fill", tint: Color(white: 0.92), ink: .black.opacity(0.7)) {
                        showOptions = true
                    }
                    .accessibilityIdentifier("openOptions")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            if focused == nil { focused = savedVenue }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "demoTab") != nil { showProfile = true }
            if let demo = UserDefaults.standard.string(forKey: "demoToast") { modeToast = demo == "on" }
            #endif
        }
        .onChange(of: focused) { _, new in if let new { savedVenue = new } }
        .overlay {
            if let modeToast {
                ModeToast(unlocked: modeToast, proReward: proReward) {
                    withAnimation(.easeOut(duration: 0.35)) { self.modeToast = nil }
                }
                .transition(.opacity)
            }
        }
        .sensoryFeedback(trigger: modeToast) { _, new in new == nil ? nil : .success }
        .sheet(isPresented: $showProfile) { ProfileSheet() }
        .sheet(isPresented: $showOptions) { OptionsSheet() }
    }

    /// Verstecktes Umschalten des alternativen Modus (nur wenn dessen Datei vorhanden ist).
    private func tapSpade() {
        guard Lines.night != nil else { return }
        let now = Date.now
        spadeTaps = spadeTaps.filter { now.timeIntervalSince($0) < 3 } + [now]
        guard spadeTaps.count >= 5 else { return }
        spadeTaps = []
        withAnimation(.spring(duration: 0.4)) {
            afterDark.toggle()
            proReward = afterDark && !proUnlocked
            if afterDark { proUnlocked = true }
            modeToast = afterDark
        }
    }

    private func playFocused() {
        let wanted = Venue.all.first { $0.id == (focused ?? savedVenue) }
        if let wanted, playable(wanted) {
            play(wanted.id)
        } else if let best = Venue.all.last(where: playable) {
            focused = best.id
            play(best.id)
        } else {
            play(0)
        }
    }
}

private struct LobbyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.13, blue: 0.06),
                                    Color(red: 0.10, green: 0.05, blue: 0.03),
                                    Color(red: 0.04, green: 0.02, blue: 0.02)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.52).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.5, y: 0.22), startRadius: 4, endRadius: 260)
            RadialGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.25), .clear],
                           center: UnitPoint(x: 0.12, y: 0.55), startRadius: 4, endRadius: 220)
            RadialGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.22), .clear],
                           center: UnitPoint(x: 0.9, y: 0.5), startRadius: 4, endRadius: 220)
            Canvas { context, size in                     // Kassettendecke & Kronleuchter-Lichter
                let w = size.width
                var beams = Path()
                for i in 0...6 {
                    let x = w * CGFloat(i) / 6
                    beams.move(to: CGPoint(x: x, y: 0))
                    beams.addLine(to: CGPoint(x: w / 2 + (x - w / 2) * 0.35, y: size.height * 0.3))
                }
                context.stroke(beams, with: .color(Palette.gold.opacity(0.07)), lineWidth: 6)
                for i in 0..<9 {
                    let angle = Double(i) / 9 * .pi * 2
                    let x = w / 2 + cos(angle) * 70
                    let y = size.height * 0.22 + sin(angle) * 16
                    context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)),
                                 with: .color(Color(red: 1, green: 0.92, blue: 0.75).opacity(0.5)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct VenueCard: View {
    let venue: Venue
    let unlocked: Bool
    let affordable: Bool
    let play: () -> Void

    #if DEBUG
    private static let hideLady = UserDefaults.standard.bool(forKey: "noLady")
    #else
    private static let hideLady = false
    #endif

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        ZStack(alignment: .topLeading) {
            VenueArt(venue: venue)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                Text(venue.city)
                    .font(Typo.display(44))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                Text(venue.tagline.uppercased())
                    .font(Typo.ui(12, .bold))
                    .tracking(2)
                    .foregroundStyle(venue.accent)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.hideLady ? "Level \(venue.level) · \(venue.tagline)" : "Level \(venue.level) · Bar lady \(venue.lady.name)")
                        .font(Typo.ui(.subheadline, .bold))
                        .foregroundStyle(.white)
                    Text("Min. bet \(eur(venue.minBet))")
                        .font(Typo.ui(.headline, .heavy))
                        .foregroundStyle(Palette.gold)
                    if venue.entry > 0 {
                        Text("Requires \(eur(venue.entry))")
                            .font(Typo.ui(.caption, .semibold))
                            .foregroundStyle(affordable ? .white.opacity(0.7) : Palette.lose)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(action: play) {
                    Label(unlocked ? (affordable ? "Play" : "Not enough chips") : "Unlocks at level \(venue.level)",
                          systemImage: unlocked ? (affordable ? "play.fill" : "eurosign.circle") : "lock.fill")
                        .font(Typo.ui(.title3, .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            LinearGradient(colors: unlocked && affordable
                                           ? [Palette.play, Palette.playDeep]
                                           : [Color(white: 0.35), Color(white: 0.2)],
                                           startPoint: .top, endPoint: .bottom),
                            in: Capsule()
                        )
                }
                .buttonStyle(PressStyle())
                .disabled(!(unlocked && affordable))
                .padding(.top, 10)
            }
            .padding(18)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(venue.accent.opacity(0.9), lineWidth: 2))
        .shadow(color: venue.accent.opacity(0.35), radius: 16, y: 6)
    }
}

/// Vektor-Raum: Bögen, Kronleuchter und Spieltisch in der Farbe des Standorts.
private struct VenueArt: View {
    let venue: Venue

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [venue.room.opacity(0.9), venue.room, .black]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // Fensterbögen mit warmem Licht
            for i in 0..<3 {
                let x = w * (0.12 + CGFloat(i) * 0.3)
                let rect = CGRect(x: x, y: h * 0.26, width: w * 0.16, height: h * 0.3)
                var arch = Path()
                arch.addRoundedRect(in: rect, cornerSize: CGSize(width: w * 0.08, height: w * 0.08))
                context.fill(arch, with: .linearGradient(
                    Gradient(colors: [venue.accent.opacity(0.55), venue.accent.opacity(0.05)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                context.stroke(arch, with: .color(Palette.gold.opacity(0.35)), lineWidth: 1.5)
            }
            // Kronleuchter
            let center = CGPoint(x: w / 2, y: h * 0.2)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 90, y: center.y - 50, width: 180, height: 100)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.7).opacity(0.55), .clear]),
                                               center: center, startRadius: 2, endRadius: 90))
            var chain = Path()
            chain.move(to: CGPoint(x: center.x, y: 0))
            chain.addLine(to: CGPoint(x: center.x, y: center.y - 12))
            context.stroke(chain, with: .color(Palette.gold.opacity(0.6)), lineWidth: 1.5)
            for i in 0..<7 {
                let t = CGFloat(i) / 6
                let x = center.x - 42 + t * 84
                let y = center.y + sin(t * .pi) * 12
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                             with: .color(Color(red: 1, green: 0.95, blue: 0.82)))
            }
            // Tisch
            let table = CGRect(x: -w * 0.1, y: h * 0.66, width: w * 1.2, height: h * 0.42)
            context.fill(Path(ellipseIn: table.insetBy(dx: -8, dy: -8)),
                         with: .color(Color(red: 0.25, green: 0.12, blue: 0.05)))
            context.fill(Path(ellipseIn: table),
                         with: .radialGradient(Gradient(colors: venue.felt), center: CGPoint(x: w / 2, y: h * 0.8),
                                               startRadius: 4, endRadius: w * 0.7))
            context.stroke(Path(ellipseIn: table.insetBy(dx: w * 0.15, dy: h * 0.06)),
                           with: .color(Palette.gold.opacity(0.35)), lineWidth: 1.2)
        }
    }
}

// MARK: - Spieltisch

private struct TableScreen: View {
    @AppStorage(Key.proUnlocked) private var proUnlocked = false
    let venue: Venue
    let leave: () -> Void

    @AppStorage(Key.balance) private var balance = Rules.startBalance
    @AppStorage(Key.brokeSince) private var brokeSince = 0.0
    @AppStorage(Key.games) private var games = 0
    @AppStorage(Key.wins) private var wins = 0
    @AppStorage(Key.losses) private var losses = 0
    @AppStorage(Key.pushes) private var pushes = 0
    @AppStorage(Key.blackjacks) private var blackjacks = 0
    @AppStorage(Key.splits) private var splits = 0
    @AppStorage(Key.doubles) private var doubles = 0
    @AppStorage(Key.tips) private var tips = 0
    @AppStorage(Key.tipTotal) private var tipTotal = 0
    @AppStorage(Key.streak) private var streak = 0
    @AppStorage(Key.bestStreak) private var bestStreak = 0
    @AppStorage(Key.highest) private var highest = Rules.startBalance
    @AppStorage(Key.xp) private var xp = 0
    @AppStorage(Key.venuesPlayed) private var venuesPlayed = 0
    @AppStorage(Key.deck) private var deck = Deck.standard
    @AppStorage(Key.name) private var name = "Guest"
    @AppStorage(Key.standOn21) private var standOn21 = true
    @AppStorage(Key.showValues) private var showValues = true
    @AppStorage(Key.sounds) private var sounds = true
    @AppStorage(Key.haptics) private var haptics = true
    @AppStorage(Key.ladyMode) private var ladyMode = 1
    @AppStorage(Key.afterDark) private var afterDark = false

    @State private var game: Game
    @State private var bubble: String?
    @State private var bubbleTask: Task<Void, Never>?
    @State private var tipBag = LineBag()
    @State private var tipStreak = 0                // Trinkgelder in Folge ohne Runde dazwischen
    @State private var greed: Int?                  // „Alles weg“-Betrag für die Animation
    @State private var heldCredit = 0
    @State private var pendingLine: String?
    @State private var queuedLine: String?
    @State private var isPerformingAction = false
    @State private var showRecharge = false
    @AppStorage(Key.reservedBet) private var reservedBet = 0

    init(venue: Venue, leave: @escaping () -> Void) {
        self.venue = venue
        self.leave = leave
        _game = State(initialValue: Game(minBet: venue.minBet))
    }

    var body: some View {
        ZStack {
            TableBackground(venue: venue)
            VStack(spacing: 8) {
                topBar
                if showLady {
                    LadyStage(venue: venue, game: game, haptics: haptics,
                              bubble: ladyMode == 0 ? nil : bubble, action: tapLady)
                        .disabled(isPerformingAction || game.isAnimating || bubble != nil)
                } else {
                    CenterStage(game: game, haptics: haptics)
                }
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 12) {
                            DealerRow(game: game, showValue: showValues).id("dealerHand")
                            PlayerHands(game: game, showValue: showValues).id("playerHand")
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: game.phase) { _, phase in
                        withAnimation(.easeInOut(duration: 0.4)) {
                            if phase == .player { proxy.scrollTo("playerHand", anchor: .bottom) }
                            if phase == .dealer { proxy.scrollTo("dealerHand", anchor: .top) }
                            if phase == .finished { proxy.scrollTo("dealerHand", anchor: .top) }
                        }
                    }
                }
                controls
                    .disabled(isPerformingAction || game.isAnimating)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AVAILABLE").font(Typo.ui(10, .bold)).foregroundStyle(.white.opacity(0.7))
                        BalancePill(balance: balance - heldCredit)
                    }
                    Spacer()
                    if game.phase != .finished {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("CHIPS IN POT").font(Typo.ui(10, .bold)).foregroundStyle(Palette.gold)
                            Text(eur(game.stake))
                                .font(Typo.ui(.headline, .bold)).monospacedDigit()
                                .foregroundStyle(Palette.gold)
                                .contentTransition(.numericText())
                                .animation(.snappy(duration: 0.2), value: game.stake)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Chips in pot \(eur(game.stake))")
                        .accessibilityIdentifier("pot")
                    }
                }
                .padding(.horizontal, 16)
                if game.phase == .betting && balance + game.bet >= venue.minBet {
                    ChipTray(game: game, balance: balance, haptics: haptics, sounds: sounds, addChip: addChip)
                        .disabled(isPerformingAction || game.isAnimating)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 4)
            SoundTicker(game: game, enabled: sounds)
            if let greed {
                GreedOverlay(venue: venue, amount: greed) {
                    withAnimation(.easeOut(duration: 0.3)) { self.greed = nil }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .sheet(isPresented: $showRecharge) { ProfileSheet(initialTab: 3) }
        .environment(\.deckStyle, Deck.selected(deck, proUnlocked: proUnlocked))
        .sensoryFeedback(trigger: greed) { _, new in haptics && new != nil ? .error : nil }
        .onAppear {
            game.standOn21 = standOn21
            game.onSettle = { settle($0) }
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .finished && (heldCredit != 0 || pendingLine != nil) { revealSettlement() }
        }
        .onAppear {
            say(lines(Lines.greet, event: "greet").randomElement() ?? "")
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demoRound") { demoRound() }
            if UserDefaults.standard.bool(forKey: "demoGreed") {
                Task {
                    for _ in 0..<5 {
                        try? await Task.sleep(for: .milliseconds(700))
                        tapLady()
                    }
                }
            }
            #endif
        }
        .onDisappear {
            game.onSettle = nil
            bubbleTask?.cancel()
            queuedLine = nil
        }
        .onChange(of: ladyMode) { _, mode in
            if mode == 0 {
                bubbleTask?.cancel()
                bubble = nil
                queuedLine = nil
            }
        }
    }

    private var available: Int { balance - heldCredit }
    private var bettingFunds: Int { available + (game.phase == .betting ? game.bet : 0) }

    /// Nur für Screenshots im Debug-Build ausblendbar (Startargument `-noLady YES`).
    private var showLady: Bool {
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "noLady")
        #else
        return true
        #endif
    }

    // MARK: Kopfzeile

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: leaveTable) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color(white: 0.93), in: Circle())
            }
            .buttonStyle(PressStyle())
            .disabled(!game.phase.isIdle || isPerformingAction || game.isAnimating)
            .opacity(game.phase.isIdle && !isPerformingAction && !game.isAnimating ? 1 : 0.4)
            .accessibilityLabel("Back to lobby")

            PlayerBadge(name: name, xp: xp, size: 46, subtitle: venue.city.capitalized)
            Spacer()
            ShoeView()
                .frame(width: 150, height: 92)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Steuerung

    @ViewBuilder
    private var controls: some View {
        let phase = game.phase
        Group {
            if bettingFunds < 100 && phase.isIdle {
                if afterDark {
                    Button("Recharge in Profile") { showRecharge = true }
                        .buttonStyle(CapsuleStyle(colors: [Palette.afterDark, Palette.purple], ink: .white))
                        .padding(.horizontal, 16)
                } else {
                    RefillCard().padding(.horizontal, 16)
                }
            } else if phase.isIdle && bettingFunds < venue.minBet {
                VStack(spacing: 10) {
                    Text("Your balance is below this table's minimum bet of \(eur(venue.minBet)).")
                        .font(Typo.ui(.subheadline, .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                    Button("Choose another table", action: leaveTable)
                        .buttonStyle(CapsuleStyle(colors: [Palette.gold, Palette.goldDeep], ink: .black))
                }
                .padding(.horizontal, 24)
            } else {
                switch phase {
                case .betting:
                    HStack(alignment: .top, spacing: 30) {
                        RoundAction(icon: "xmark", label: "Reset", colors: [Palette.lose, Color(red: 0.7, green: 0.18, blue: 0.16)]) {
                            setBet(0)
                        }
                        .disabled(game.bet == 0)
                        RoundAction(icon: "flame.fill", label: "All In", colors: [Palette.purple, Color(red: 0.45, green: 0.15, blue: 0.62)]) {
                            setBet(balance + game.bet)
                        }
                        RoundAction(icon: "rectangle.portrait.on.rectangle.portrait.fill", label: "Deal",
                                    colors: [Palette.play, Palette.playDeep], ring: true) {
                            deal()
                        }
                        .disabled(!game.canDeal)
                    }
                case .dealing, .player, .dealer:
                    HStack(alignment: .top, spacing: 16) {
                        RoundAction(icon: "plus", label: "Hit", colors: [Palette.play, Palette.playDeep]) { run { await game.hit() } }
                        RoundAction(icon: "hand.raised.fill", label: "Stand", colors: [Palette.lose, Color(red: 0.7, green: 0.18, blue: 0.16)]) {
                            run { await game.stand() }
                        }
                        // Double und Split erscheinen nur, wenn sie gerade erlaubt und bezahlbar sind.
                        if game.canDouble && balance >= game.extraCost {
                            RoundAction(glyph: "×2", label: "Double", colors: [Palette.gold, Palette.goldDeep]) { doubleDown() }
                                .transition(.scale.combined(with: .opacity))
                        }
                        if game.canSplit && balance >= game.extraCost {
                            RoundAction(icon: "arrow.triangle.branch", label: "Split", colors: [Color(red: 0.25, green: 0.6, blue: 0.95), Color(red: 0.1, green: 0.32, blue: 0.7)]) {
                                split()
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.25), value: game.canDouble)
                    .animation(.snappy(duration: 0.25), value: game.canSplit)
                    .disabled(phase != .player)
                case .finished:
                    HStack(spacing: 12) {
                        Button("New Bet") { game.prepareNextRound(keepBet: false, limit: balance) }
                            .buttonStyle(CapsuleStyle(colors: [Color(white: 0.32), Color(white: 0.16)], ink: .white))
                        Button("Rebet \(eur(max(venue.minBet, min(game.lastBet, balance))))") { again() }
                            .buttonStyle(CapsuleStyle(colors: [Palette.gold, Palette.goldDeep], ink: .black))
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(minHeight: 80)
    }

    // MARK: Aktionen

    private func run(_ operation: @escaping @MainActor () async -> Settlement?, prepare: () -> Void = {}) {
        guard !isPerformingAction, !game.isAnimating else { return }
        isPerformingAction = true
        prepare()
        Task {
            defer { isPerformingAction = false }
            if let settlement = await operation() { settle(settlement) }
        }
    }

    private func setBet(_ amount: Int) {
        guard game.phase == .betting, !isPerformingAction, !game.isAnimating,
              let next = WagerReservation(available: balance, chips: game.bet).setting(amount) else { return }
        game.setBet(next.chips)
        balance = next.available
        reservedBet = next.chips
    }

    private func addChip(_ amount: Int) {
        guard amount > 0 else { return }
        setBet(game.bet + amount)
    }

    private func leaveTable() {
        if game.phase == .betting { setBet(0) }
        syncBroke(&balance, &brokeSince)
        leave()
    }

    private func deal() {
        guard game.canDeal else { return }
        run({ await game.deal() }, prepare: {
            reservedBet = 0 // bereits beim Setzen abgebucht; ab jetzt im Spiel
            tipStreak = 0
            if bubble == nil && Int.random(in: 0..<3) == 0 {
                say(lines(Lines.luck, event: "luck").randomElement() ?? "")
            }
        })
    }

    private func doubleDown() {
        guard game.canDouble, balance >= game.extraCost else { return }
        run({ await game.doubleDown() }, prepare: {
            balance -= game.extraCost
            doubles += 1
        })
    }

    private func split() {
        guard game.canSplit, balance >= game.extraCost else { return }
        run({ await game.split() }, prepare: {
            balance -= game.extraCost
            splits += 1
        })
    }

    private func again() {
        guard game.phase == .finished, !isPerformingAction, !game.isAnimating else { return }
        game.prepareNextRound(keepBet: false, limit: balance)
        setBet(max(venue.minBet, min(game.lastBet, balance)))
        deal()
    }

    private func settle(_ s: Settlement) {
        balance += s.credit
        games += 1
        wins += s.wins
        losses += s.losses
        pushes += s.pushes
        blackjacks += s.blackjacks
        xp += 10 + s.wins * 15 + s.blackjacks * 25
        if s.net > 0 {
            streak += 1
            bestStreak = max(bestStreak, streak)
        } else if s.net < 0 {
            streak = 0
        }
        highest = max(highest, balance)
        venuesPlayed |= 1 << venue.id
        syncBroke(&balance, &brokeSince)

        let pool: [String]
        if s.blackjacks > 0 { pool = lines(Lines.blackjack, event: "blackjack") }
        else if s.net > 0 { pool = lines(Lines.win, event: "win") }
        else if s.busted { pool = lines(Lines.bust, event: "bust") }
        else if s.net < 0 { pool = balance < 100 ? lines(Lines.broke, event: "broke") : lines(Lines.lose, event: "lose") }
        else { pool = lines(Lines.push, event: "push") }
        // Gebucht ist sofort; Anzeige und Kommentar erst, wenn der Dealer aufgedeckt hat.
        heldCredit = s.credit
        pendingLine = pool.randomElement()
        if game.phase == .finished { revealSettlement() }
    }

    private func revealSettlement() {
        heldCredit = 0
        if let line = pendingLine { say(line) }
        pendingLine = nil
    }

    /// Spruch-Pool: Standard oder – falls aktiv und vorhanden – der alternative Satz.
    private func lines(_ normal: [String], event: String) -> [String] {
        guard afterDark, let set = Lines.night else { return normal }
        let pool = set.pool(event: event, character: venue.lady.name, repeatedTips: tipStreak >= 3)
        return pool.isEmpty ? normal : pool
    }

    /// Ein Tipp auf die Lady = Trinkgeld in Höhe des Tisch-Betrags. Im normalen Modus nimmt
    /// der fünfte Tipp in Folge (ohne gespielte Runde dazwischen) alles – inkl. gesetztem Einsatz.
    private func tapLady() {
        guard !isPerformingAction, !game.isAnimating, bubble == nil else { return }
        if !afterDark && tipStreak >= 4 {
            if game.phase == .betting { setBet(0) }
            let all = available
            guard all > 0 else { return say(lines(Lines.emptyPockets, event: "emptyPockets").randomElement() ?? "") }
            tipStreak = 0
            pay(all)
            withAnimation(.easeOut(duration: 0.25)) { greed = all }
            say(Lines.greedy.randomElement() ?? "")
            return
        }
        guard venue.tip <= available else { return say(lines(Lines.emptyPockets, event: "emptyPockets").randomElement() ?? "") }
        tipStreak += 1
        pay(venue.tip)
        say(tipBag.next(lines(Lines.tips, event: "tips")))
    }

    private func pay(_ amount: Int) {
        balance -= amount
        tips += 1
        tipTotal += amount
        if game.phase.isIdle && (game.phase != .betting || game.bet == 0) { syncBroke(&balance, &brokeSince) }
    }

    #if DEBUG
    /// Nur für Tests im Simulator (Startargumente `-demoTable 0 -demoRound YES`):
    /// setzt einen Einsatz, gibt, gibt Trinkgeld und steht nach kurzer Pause.
    private func demoRound() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            addChip(chipValues(for: balance, minBet: venue.minBet).last ?? venue.minBet)
            try? await Task.sleep(for: .seconds(1))
            deal()
            try? await Task.sleep(for: .seconds(2.5))
            tapLady()
            if game.canSplit && balance >= game.extraCost { split() } else { run { await game.stand() } }
        }
    }
    #endif

    private func say(_ text: String) {
        guard ladyMode != 0, !text.isEmpty else { return }
        if bubble != nil {
            queuedLine = text
            return
        }
        bubbleTask?.cancel()
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) { bubble = text }
        bubbleTask = Task {
            try? await Task.sleep(for: Pacing.readingTime(for: text))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { bubble = nil }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if let next = queuedLine {
                queuedLine = nil
                say(next)
            }
        }
    }
}

/// Unsichtbarer Mini-View: spielt pro gezogener Karte einen Systemklick,
/// ohne dass der ganze Tisch neu ausgewertet wird.
private struct SoundTicker: View {
    let game: Game
    let enabled: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: game.dealtCount) {
                if enabled { AudioServicesPlaySystemSound(1104) }
            }
            .allowsHitTesting(false)
    }
}

private struct TableBackground: View {
    let venue: Venue

    var body: some View {
        GeometryReader { g in
            let rim = FeltShape(bottomInset: 150)
            ZStack {
                LinearGradient(colors: [Palette.wood, Palette.woodDeep], startPoint: .top, endPoint: .bottom)
                rim.fill(
                    RadialGradient(colors: venue.felt, center: UnitPoint(x: 0.5, y: 0.42),
                                   startRadius: 10, endRadius: g.size.height * 0.75)
                )
                rim.stroke(Palette.woodDeep, lineWidth: 10)
                rim.stroke(Palette.gold.opacity(0.55), lineWidth: 1.5)
                VStack(spacing: 4) {
                    Text("BLACKJACK PAYS 3 TO 2")
                        .font(Typo.display(13))
                        .tracking(3)
                    Text("DEALER STANDS ON 17 · MIN. \(eur(venue.minBet))")
                        .font(Typo.display(10))
                        .tracking(2)
                }
                .foregroundStyle(Palette.gold.opacity(0.22))
                .position(x: g.size.width / 2, y: g.size.height * 0.47)
            }
        }
        .ignoresSafeArea()
    }
}

nonisolated private struct FeltShape: Shape {
    let bottomInset: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let side = rect.maxY - bottomInset - 70
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: side))
        p.addQuadCurve(to: CGPoint(x: 0, y: side), control: CGPoint(x: rect.midX, y: rect.maxY - bottomInset + 70))
        p.closeSubpath()
        return p
    }
}

private struct ShoeView: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                CardBack()
                    .frame(width: 86, height: 120)
                    .rotationEffect(.degrees(-58))
                    .offset(x: CGFloat(i) * 6, y: CGFloat(-i) * 3)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
        .accessibilityHidden(true)
    }
}

private struct LadyStage: View {
    let venue: Venue
    let game: Game
    let haptics: Bool
    let bubble: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 8) {
                CenterStage(game: game, haptics: haptics)
                if let bubble {
                    Text(bubble)
                        .font(Typo.ui(.footnote, .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.gold.opacity(0.45), lineWidth: 1))
                        .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
                        .id(bubble)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Button(action: action) {
                LadyAvatar(lady: venue.lady, photo: venue.photo, accent: venue.accent)
                    .frame(width: 86, height: 86)
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom),
                        lineWidth: 3))
                    .shadow(color: venue.accent.opacity(0.45), radius: 12)
                    .overlay(alignment: .topTrailing) {
                        Text("+\(eur(venue.tip))")
                            .font(Typo.ui(11, .heavy))
                            .foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Palette.gold, in: Capsule())
                            .offset(x: 10, y: -2)
                    }
                    .overlay(alignment: .bottom) {
                        NamePlate(name: venue.lady.name, icon: venue.plateIcon, height: 26)
                            .fixedSize()
                            .offset(y: 13)
                    }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(venue.lady.name), bar lady. Tap to tip \(eur(venue.tip))")

        }
        .frame(minHeight: 112)
        .padding(.horizontal, 12)
    }
}

/// Namensschild der Bar-Lady: schwarz, doppelter Goldrahmen, Location-Symbol und Name in Gold.
private struct NamePlate: View {
    let name: String
    let icon: PlateIcon
    var height: CGFloat = 28

    private static let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.9, blue: 0.62), Palette.gold, Palette.goldDeep],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
        HStack(spacing: height * 0.22) {
            PlateSymbol(icon: icon)
                .frame(width: height * 0.6, height: height * 0.72)
            Text(name)
                .font(Typo.display(height * 0.56))
                .lineLimit(1)
        }
        .foregroundStyle(Self.gold)
        .padding(.horizontal, height * 0.42)
        .frame(height: height)
        .background(shape.fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.04)],
                                              startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(Self.gold, lineWidth: max(1.2, height * 0.07)))
        .overlay(shape.inset(by: height * 0.12).strokeBorder(Palette.gold.opacity(0.45), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}

/// Location-Symbol fürs Namensschild: SF Symbols bzw. kleine Vektor-Silhouetten.
private struct PlateSymbol: View {
    let icon: PlateIcon

    var body: some View {
        switch icon {
        case .crown: Image(systemName: "crown.fill").resizable().scaledToFit()
        case .palace: Image(systemName: "building.columns.fill").resizable().scaledToFit()
        case .spade: Image(systemName: "suit.spade.fill").resizable().scaledToFit()
        case .eiffel: Silhouette(points: Self.eiffel, arch: true)
        case .tower: Silhouette(points: Self.burj, arch: false)
        }
    }

    // Umrisse im Einheitsquadrat (x, y), oben = 0.
    private static let eiffel: [CGPoint] = [
        .init(x: 0.5, y: 0), .init(x: 0.54, y: 0.3), .init(x: 0.6, y: 0.55), .init(x: 0.72, y: 0.62),
        .init(x: 0.68, y: 0.66), .init(x: 0.92, y: 1), .init(x: 0.08, y: 1), .init(x: 0.32, y: 0.66),
        .init(x: 0.28, y: 0.62), .init(x: 0.4, y: 0.55), .init(x: 0.46, y: 0.3),
    ]
    private static let burj: [CGPoint] = [
        .init(x: 0.5, y: 0), .init(x: 0.53, y: 0.18), .init(x: 0.56, y: 0.18), .init(x: 0.58, y: 0.42),
        .init(x: 0.62, y: 0.42), .init(x: 0.65, y: 0.7), .init(x: 0.7, y: 0.7), .init(x: 0.72, y: 1),
        .init(x: 0.28, y: 1), .init(x: 0.3, y: 0.7), .init(x: 0.35, y: 0.7), .init(x: 0.38, y: 0.42),
        .init(x: 0.42, y: 0.42), .init(x: 0.44, y: 0.18), .init(x: 0.47, y: 0.18),
    ]
}

private struct Silhouette: Shape {
    let points: [CGPoint]
    let arch: Bool

    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        p.closeSubpath()
        if arch {                                 // Bogen zwischen den Beinen ausschneiden
            var hole = Path()
            hole.move(to: CGPoint(x: rect.minX + 0.3 * rect.width, y: rect.maxY))
            hole.addQuadCurve(to: CGPoint(x: rect.minX + 0.7 * rect.width, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: rect.minY + 0.62 * rect.height))
            hole.closeSubpath()
            p = p.subtracting(hole)
        }
        return p
    }
}

/// Animation beim fünften Trinkgeld in Folge: Jetons fliegen zur Lady, alles ist weg.
private struct GreedOverlay: View {
    let venue: Venue
    let amount: Int
    let done: () -> Void
    @State private var go = false

    var body: some View {
        ZStack {
            ZStack {
                Color.black.opacity(0.85)
                RadialGradient(colors: [venue.accent.opacity(0.35), .clear],
                               center: .init(x: 0.5, y: 0.38), startRadius: 10, endRadius: 460)
            }
            .ignoresSafeArea()
            .opacity(go ? 1 : 0)
            ForEach(0..<18, id: \.self) { i in
                ChipView(value: venue.tip, tier: i % 4, size: 46)
                    .rotationEffect(.degrees(go ? Double(i * 53 % 360) : 0))
                    .scaleEffect(go ? 0.3 : 1)
                    .offset(x: go ? 0 : CGFloat(i * 47 % 320) - 160,
                            y: go ? -150 : 420 + CGFloat(i % 5) * 26)
                    .opacity(go ? 0 : 1)
                    .animation(.easeIn(duration: 1.1).delay(Double(i) * 0.055), value: go)
            }
            VStack(spacing: 12) {
                LadyAvatar(lady: venue.lady, photo: venue.photo, accent: venue.accent)
                    .frame(width: 150, height: 150)
                    .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 4))
                    .shadow(color: venue.accent.opacity(0.7), radius: 24)
                    .overlay(alignment: .bottom) {
                        NamePlate(name: venue.lady.name, icon: venue.plateIcon, height: 34).fixedSize().offset(y: 16)
                    }
                    .padding(.bottom, 26)
                Text("ALL IN ON \(venue.lady.name.uppercased())")
                    .font(Typo.display(30))
                    .foregroundStyle(Palette.gold)
                    .multilineTextAlignment(.center)
                Text("Five tips in a row – greedy for lines, not for blackjack.\nShe took everything.")
                    .font(Typo.ui(15, .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                Text("−\(eur(amount))")
                    .font(Typo.ui(34, .heavy))
                    .foregroundStyle(Palette.lose)
                    .contentTransition(.numericText(value: Double(amount)))
                Text("Tap to continue")
                    .font(Typo.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .scaleEffect(go ? 1 : 0.7)
            .opacity(go ? 1 : 0)
            .animation(.spring(duration: 0.6, bounce: 0.35).delay(0.5), value: go)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .onAppear { go = true }
        .task {
            try? await Task.sleep(for: .seconds(5))
            done()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Zeigt ein optionales Porträtfoto aus dem Bundle (AVIF/WebP/HEIC/JPEG), sonst das Vektor-Porträt.
/// Das Foto wird erst beim Betreten des Tisches im Hintergrund geladen und auf Anzeigegröße
/// heruntergerechnet – im Speicher liegen dann nur ~240×240 Pixel.
private struct LadyAvatar: View {
    let lady: Lady
    let photo: String
    let accent: Color
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                LadyPortrait(lady: lady, accent: accent)
            }
        }
        .clipShape(Circle())
        .task(id: photo) {
            let loaded = await ArtCache.image(photo, maxPixel: 240)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

private enum PortraitLoader {
    nonisolated static func load(_ name: String, maxPixel: Int) async -> CGImage? {
        await Task.detached(priority: .utility) {
            for ext in ["avif", "webp", "heic", "jpg", "png"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
            return nil
        }.value
    }
}

/// Vektor-Porträt (Headshot) einer Bar-Lady, gezeichnet in einem 100×100-Raster.
private struct LadyPortrait: View {
    let lady: Lady
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 100
            context.scaleBy(x: s, y: s)
            let disc = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100))
            context.fill(disc, with: .radialGradient(Gradient(colors: [accent.opacity(0.85), accent.opacity(0.25), .black]),
                                                     center: CGPoint(x: 50, y: 30), startRadius: 2, endRadius: 80))
            context.clip(to: disc)

            let hairShade = lady.hair.opacity(0.9)
            context.fill(hairBack, with: .color(lady.hair))

            // Hals, Schultern, Kleid
            context.fill(Path(roundedRect: CGRect(x: 42.5, y: 56, width: 15, height: 24), cornerRadius: 6),
                         with: .color(lady.skin))
            context.fill(Path(ellipseIn: CGRect(x: 42, y: 58, width: 16, height: 8)), with: .color(.black.opacity(0.16)))
            var shoulders = Path()
            shoulders.move(to: CGPoint(x: 6, y: 104))
            shoulders.addCurve(to: CGPoint(x: 34, y: 76), control1: CGPoint(x: 8, y: 86), control2: CGPoint(x: 20, y: 78))
            shoulders.addLine(to: CGPoint(x: 66, y: 76))
            shoulders.addCurve(to: CGPoint(x: 94, y: 104), control1: CGPoint(x: 80, y: 78), control2: CGPoint(x: 92, y: 86))
            shoulders.closeSubpath()
            context.fill(shoulders, with: .color(lady.skin))
            var dress = Path()
            dress.move(to: CGPoint(x: 6, y: 104))
            dress.addCurve(to: CGPoint(x: 26, y: 82), control1: CGPoint(x: 9, y: 92), control2: CGPoint(x: 16, y: 84))
            dress.addLine(to: CGPoint(x: 38, y: 83))
            dress.addQuadCurve(to: CGPoint(x: 62, y: 83), control: CGPoint(x: 50, y: 102))
            dress.addLine(to: CGPoint(x: 74, y: 82))
            dress.addCurve(to: CGPoint(x: 94, y: 104), control1: CGPoint(x: 84, y: 84), control2: CGPoint(x: 91, y: 92))
            dress.closeSubpath()
            context.fill(dress, with: .linearGradient(Gradient(colors: [lady.outfit, lady.outfit.opacity(0.6)]),
                                                      startPoint: CGPoint(x: 50, y: 80), endPoint: CGPoint(x: 50, y: 104)))
            var necklace = Path()
            necklace.addArc(center: CGPoint(x: 50, y: 70), radius: 11, startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            context.stroke(necklace, with: .color(Palette.gold), lineWidth: 0.9)
            context.fill(Path(ellipseIn: CGRect(x: 48.4, y: 79.5, width: 3.2, height: 3.8)), with: .color(Palette.gold))

            // Ohren & Ohrringe
            for x in [33.5, 66.5] {
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: 42, width: 6, height: 9)), with: .color(lady.skin))
                context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: 51.5, width: 3.2, height: 3.2)), with: .color(Palette.gold))
            }

            // Gesicht
            let face = Path(ellipseIn: CGRect(x: 35, y: 24, width: 30, height: 38))
            context.fill(face, with: .color(lady.skin))
            context.fill(face, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.12)]),
                                                     center: CGPoint(x: 48, y: 40), startRadius: 8, endRadius: 22))
            for x in [41.0, 59.0] {               // Rouge
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: 48, width: 8, height: 4.5)),
                             with: .color(Color(red: 1, green: 0.45, blue: 0.5).opacity(0.22)))
            }

            // Augen
            for x in [43.0, 57.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 3.6, y: 41.6, width: 7.2, height: 4)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: x - 1.9, y: 41.6, width: 3.8, height: 3.8)), with: .color(lady.eyes))
                context.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: 42.6, width: 1.8, height: 1.8)), with: .color(.black))
                context.fill(Path(ellipseIn: CGRect(x: x - 0.2, y: 42.3, width: 0.9, height: 0.9)), with: .color(.white))
                var lid = Path()
                lid.move(to: CGPoint(x: x - 4.2, y: 43.8))
                lid.addQuadCurve(to: CGPoint(x: x + 4.4, y: 42.6), control: CGPoint(x: x, y: 39.4))
                context.stroke(lid, with: .color(Palette.cardInk), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                var lash = Path()
                let outer = x < 50 ? x - 4.2 : x + 4.4
                let dir: CGFloat = x < 50 ? -1 : 1
                lash.move(to: CGPoint(x: outer, y: x < 50 ? 43.8 : 42.6))
                lash.addLine(to: CGPoint(x: outer + dir * 1.6, y: (x < 50 ? 43.8 : 42.6) - 1.4))
                context.stroke(lash, with: .color(Palette.cardInk), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                var brow = Path()
                brow.move(to: CGPoint(x: x - 4, y: 38.2))
                brow.addQuadCurve(to: CGPoint(x: x + 4, y: 37.6), control: CGPoint(x: x + (x < 50 ? 1 : -1), y: 35.4))
                context.stroke(brow, with: .color(hairShade), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }

            // Nase & Lippen
            var nose = Path()
            nose.move(to: CGPoint(x: 50.5, y: 45))
            nose.addQuadCurve(to: CGPoint(x: 49, y: 51), control: CGPoint(x: 52, y: 49.5))
            context.stroke(nose, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            var upper = Path()
            upper.move(to: CGPoint(x: 45, y: 55.4))
            upper.addQuadCurve(to: CGPoint(x: 50, y: 54.2), control: CGPoint(x: 47.5, y: 53.2))
            upper.addQuadCurve(to: CGPoint(x: 55, y: 55.4), control: CGPoint(x: 52.5, y: 53.2))
            upper.addQuadCurve(to: CGPoint(x: 45, y: 55.4), control: CGPoint(x: 50, y: 56.2))
            context.fill(upper, with: .color(lady.lips))
            var lower = Path()
            lower.move(to: CGPoint(x: 45.4, y: 55.6))
            lower.addQuadCurve(to: CGPoint(x: 54.6, y: 55.6), control: CGPoint(x: 50, y: 60.2))
            lower.closeSubpath()
            context.fill(lower, with: .color(lady.lips.opacity(0.92)))
            context.fill(Path(ellipseIn: CGRect(x: 48, y: 56.6, width: 3.4, height: 1.2)), with: .color(.white.opacity(0.35)))

            context.fill(hairFront, with: .color(lady.hair))
            context.stroke(hairFront, with: .color(.white.opacity(0.12)), lineWidth: 0.6)
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var hairBack: Path {
        var p = Path()
        switch lady.style {
        case .waves:
            p.addEllipse(in: CGRect(x: 27, y: 14, width: 46, height: 52))
            p.move(to: CGPoint(x: 29, y: 40))
            p.addCurve(to: CGPoint(x: 26, y: 90), control1: CGPoint(x: 20, y: 60), control2: CGPoint(x: 32, y: 74))
            p.addCurve(to: CGPoint(x: 40, y: 88), control1: CGPoint(x: 30, y: 96), control2: CGPoint(x: 38, y: 94))
            p.addLine(to: CGPoint(x: 60, y: 88))
            p.addCurve(to: CGPoint(x: 74, y: 90), control1: CGPoint(x: 62, y: 94), control2: CGPoint(x: 70, y: 96))
            p.addCurve(to: CGPoint(x: 71, y: 40), control1: CGPoint(x: 68, y: 74), control2: CGPoint(x: 80, y: 60))
            p.closeSubpath()
        case .bob:
            p.addEllipse(in: CGRect(x: 28, y: 15, width: 44, height: 46))
            p.addRoundedRect(in: CGRect(x: 29, y: 36, width: 42, height: 27), cornerSize: CGSize(width: 9, height: 9))
        case .updo:
            p.addEllipse(in: CGRect(x: 32, y: 17, width: 36, height: 32))
            p.addEllipse(in: CGRect(x: 40, y: 6, width: 20, height: 17))
        case .straight:
            p.addEllipse(in: CGRect(x: 28, y: 15, width: 44, height: 44))
            p.addRoundedRect(in: CGRect(x: 28, y: 36, width: 44, height: 62), cornerSize: CGSize(width: 4, height: 4))
        case .curls:
            for i in 0..<16 {
                let a = Double(i) / 16 * .pi * 2
                let cx = 50 + cos(a) * 21
                let cy = 46 + sin(a) * 25
                p.addEllipse(in: CGRect(x: cx - 10, y: cy - 10, width: 20, height: 20))
            }
            p.addEllipse(in: CGRect(x: 30, y: 22, width: 40, height: 48))
        }
        return p
    }

    private var hairFront: Path {
        var p = Path()
        switch lady.style {
        case .waves:                              // Seitenscheitel mit Schwung
            p.move(to: CGPoint(x: 34, y: 46))
            p.addCurve(to: CGPoint(x: 50, y: 19), control1: CGPoint(x: 31, y: 30), control2: CGPoint(x: 39, y: 19))
            p.addCurve(to: CGPoint(x: 67, y: 46), control1: CGPoint(x: 62, y: 19), control2: CGPoint(x: 69, y: 30))
            p.addCurve(to: CGPoint(x: 55, y: 29), control1: CGPoint(x: 64, y: 36), control2: CGPoint(x: 61, y: 30))
            p.addCurve(to: CGPoint(x: 34, y: 46), control1: CGPoint(x: 45, y: 30), control2: CGPoint(x: 37, y: 36))
            p.closeSubpath()
        case .bob:                                // gerader Pony
            p.move(to: CGPoint(x: 33.5, y: 47))
            p.addCurve(to: CGPoint(x: 50, y: 17), control1: CGPoint(x: 31, y: 28), control2: CGPoint(x: 39, y: 17))
            p.addCurve(to: CGPoint(x: 66.5, y: 47), control1: CGPoint(x: 61, y: 17), control2: CGPoint(x: 69, y: 28))
            p.addLine(to: CGPoint(x: 64.5, y: 35.5))
            p.addLine(to: CGPoint(x: 35.5, y: 35.5))
            p.closeSubpath()
        case .updo:                               // hoher Haaransatz, zurückgesteckt
            p.move(to: CGPoint(x: 35, y: 40))
            p.addCurve(to: CGPoint(x: 50, y: 18.5), control1: CGPoint(x: 34, y: 27), control2: CGPoint(x: 41, y: 18.5))
            p.addCurve(to: CGPoint(x: 65, y: 40), control1: CGPoint(x: 59, y: 18.5), control2: CGPoint(x: 66, y: 27))
            p.addQuadCurve(to: CGPoint(x: 35, y: 40), control: CGPoint(x: 50, y: 25))
            p.closeSubpath()
        case .straight:                           // Mittelscheitel
            p.move(to: CGPoint(x: 33.5, y: 50))
            p.addCurve(to: CGPoint(x: 50, y: 17), control1: CGPoint(x: 31, y: 28), control2: CGPoint(x: 39, y: 17))
            p.addCurve(to: CGPoint(x: 66.5, y: 50), control1: CGPoint(x: 61, y: 17), control2: CGPoint(x: 69, y: 28))
            p.addCurve(to: CGPoint(x: 50, y: 26), control1: CGPoint(x: 64, y: 34), control2: CGPoint(x: 56, y: 27))
            p.addCurve(to: CGPoint(x: 33.5, y: 50), control1: CGPoint(x: 44, y: 27), control2: CGPoint(x: 36, y: 34))
            p.closeSubpath()
        case .curls:
            p.move(to: CGPoint(x: 35, y: 42))
            p.addCurve(to: CGPoint(x: 50, y: 18), control1: CGPoint(x: 33, y: 27), control2: CGPoint(x: 40, y: 18))
            p.addCurve(to: CGPoint(x: 65, y: 42), control1: CGPoint(x: 60, y: 18), control2: CGPoint(x: 67, y: 27))
            p.addQuadCurve(to: CGPoint(x: 35, y: 42), control: CGPoint(x: 50, y: 26))
            for x in stride(from: 38.0, through: 62.0, by: 6) {
                p.addEllipse(in: CGRect(x: x - 4, y: 26 + abs(x - 50) * 0.35, width: 8, height: 8))
            }
        }
        return p
    }
}

private struct DealerRow: View {
    let game: Game
    let showValue: Bool

    var body: some View {
        let hidden = game.holeHidden && game.dealer.count > 1
        let visible = hidden ? Array(game.dealer.prefix(1)) : game.dealer
        VStack(spacing: 4) {
            HandView(cards: game.dealer, hideSecond: game.holeHidden, cardWidth: 104,
                     dealFrom: CGSize(width: 150, height: -60))
            ScoreTag(text: visible.isEmpty || !showValue ? nil : Score(visible).text + (hidden ? " + ?" : ""),
                     bust: Score(visible).isBust)
        }
        .padding(.horizontal, 16)
    }
}

private struct CenterStage: View {
    let game: Game
    let haptics: Bool

    var body: some View {
        ZStack {
            if let outcome = game.outcome {
                VStack(spacing: 1) {
                    Text(outcome.headline)
                        .font(Typo.display(26))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(tint(outcome.verdict))
                    Text(detail(outcome))
                        .font(Typo.ui(.headline, .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(.black.opacity(0.7), in: Capsule())
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if game.stake > 0 {
                HStack(spacing: 12) {
                    ChipStack(amount: game.stake)
                    Text(eur(game.stake))
                        .font(Typo.ui(.title3, .heavy))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(game.stake)))
                        .animation(.snappy, value: game.stake)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 64)
        .sensoryFeedback(trigger: game.outcome?.verdict) { _, new in
            guard haptics else { return nil }
            switch new {
            case .blackjack, .win: return .success
            case .lose: return .error
            case .push: return .warning
            case nil: return nil
            }
        }
    }

    private func tint(_ verdict: Verdict) -> Color {
        switch verdict {
        case .blackjack: Palette.gold
        case .win: Palette.win
        case .lose: Palette.lose
        case .push: .white
        }
    }

    private func detail(_ outcome: Outcome) -> String {
        if outcome.net > 0 { return "+\(eur(outcome.net))" }
        if outcome.net < 0 { return "−\(eur(-outcome.net))" }
        return "Bet returned"
    }
}

private struct PlayerHands: View {
    let game: Game
    let showValue: Bool

    var body: some View {
        let cardWidth: CGFloat = 120
        GeometryReader { geo in
            let hands = game.hands
            let column = hands.count > 1 ? max(240, min(320, geo.size.width * 0.72)) : geo.size.width
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        if hands.isEmpty {
                            HandView(cards: [], hideSecond: false, cardWidth: cardWidth, dealFrom: .zero)
                                .frame(width: geo.size.width)
                        } else {
                            ForEach(Array(hands.enumerated()), id: \.element.id) { index, hand in
                                let isActive = game.phase == .player && index == game.active && hands.count > 1
                                VStack(spacing: 6) {
                                    HandView(cards: hand.cards, hideSecond: false, cardWidth: cardWidth,
                                             dealFrom: CGSize(width: 160, height: -330))
                                    HStack(spacing: 6) {
                                        ScoreTag(text: showValue ? hand.score.text : nil, bust: hand.score.isBust)
                                        if hands.count > 1 || hand.doubled {
                                            Text(eur(hand.bet))
                                                .font(Typo.ui(11, .bold))
                                                .foregroundStyle(Palette.gold)
                                        }
                                        if let verdict = hand.verdict, hands.count > 1 {
                                            VerdictIcon(verdict: verdict)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(width: column)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Palette.gold.opacity(isActive ? 0.9 : 0), lineWidth: 2)
                                        .shadow(color: Palette.gold.opacity(isActive ? 0.6 : 0), radius: 8)
                                )
                                .id(hand.id)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(hands.count > 1 ? .visible : .hidden)
                .onChange(of: game.active) { _, index in
                    guard hands.indices.contains(index) else { return }
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(hands[index].id, anchor: .center) }
                }
                .onChange(of: game.hands.count) { _, _ in
                    guard hands.indices.contains(game.active) else { return }
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(hands[game.active].id, anchor: .center) }
                }
            }
        }
        .frame(height: cardWidth * 1.4 + 44)
        .padding(.horizontal, 12)
    }
}

private struct VerdictIcon: View {
    let verdict: Verdict

    var body: some View {
        let (icon, color): (String, Color) = switch verdict {
        case .blackjack: ("crown.fill", Palette.gold)
        case .win: ("checkmark.circle.fill", Palette.win)
        case .lose: ("xmark.circle.fill", Palette.lose)
        case .push: ("equal.circle.fill", .white)
        }
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
    }
}

private struct ScoreTag: View {
    let text: String?
    let bust: Bool

    var body: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(Typo.ui(.subheadline, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(bust ? .white : .black.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(bust ? Palette.lose : Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(height: 26)
    }
}

// MARK: - Karten-Views

private struct HandView: View {
    let cards: [Card]
    let hideSecond: Bool
    let cardWidth: CGFloat
    let dealFrom: CGSize

    var body: some View {
        let height = cardWidth * 1.4
        GeometryReader { geo in
            let count = cards.count
            let step = count > 1 ? min(cardWidth * 0.6, (geo.size.width - cardWidth) / CGFloat(count - 1)) : 0
            let total = cardWidth + step * CGFloat(max(count - 1, 0))
            let origin = (geo.size.width - total) / 2

            ZStack(alignment: .leading) {
                if cards.isEmpty {
                    RoundedRectangle(cornerRadius: cardWidth * 0.11, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .frame(width: cardWidth, height: height)
                        .offset(x: (geo.size.width - cardWidth) / 2)
                }
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    CardView(card: card, faceUp: !(hideSecond && index == 1))
                        .frame(width: cardWidth, height: height)
                        .rotationEffect(.degrees(Double(index - count / 2) * 2.5), anchor: .bottom)
                        .offset(x: origin + step * CGFloat(index))
                        .zIndex(Double(index))
                        .transition(
                            .offset(x: dealFrom.width, y: dealFrom.height)
                                .combined(with: .scale(scale: 0.55))
                                .combined(with: .opacity)
                        )
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
    }
}

private struct CardView: View {
    let card: Card
    let faceUp: Bool

    var body: some View {
        ZStack {
            CardFace(card: card).opacity(faceUp ? 1 : 0)
            CardBack()
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(faceUp ? 0 : 1)
        }
        .rotation3DEffect(.degrees(faceUp ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceUp ? card.spoken : "Face-down card")
    }
}

private struct CardFace: View {
    let card: Card
    @Environment(\.deckStyle) private var deck

    var body: some View {
        if deck == Deck.pro {
            ZebraFace(card: card)
        } else {
            classic
        }
    }

    private var classic: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let ink = card.isRed ? Palette.cardRed : Palette.cardInk
            let corner = RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)

            ZStack {
                corner.fill(Color(white: 0.985))
                corner.strokeBorder(.black.opacity(0.2), lineWidth: 0.8)
                center(w: w, h: h, ink: ink)
                index(w: w, ink: ink)
                    .position(x: w * 0.16, y: h * 0.15)
                index(w: w, ink: ink)
                    .rotationEffect(.degrees(180))
                    .position(x: w * 0.84, y: h * 0.85)
            }
        }
    }

    private func index(w: CGFloat, ink: Color) -> some View {
        VStack(spacing: 0) {
            Text(card.label)
                .font(Typo.ui(w * 0.25, .bold))
                .minimumScaleFactor(0.7)
            Image(systemName: card.symbol)
                .font(.system(size: w * 0.16))
        }
        .foregroundStyle(ink)
    }

    @ViewBuilder
    private func center(w: CGFloat, h: CGFloat, ink: Color) -> some View {
        switch card.rank {
        case 1:
            Image(systemName: card.symbol)
                .font(.system(size: w * 0.5))
                .foregroundStyle(ink)
        case 11...13:
            let frame = RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
            ZStack {
                frame.fill(LinearGradient(colors: [Palette.gold.opacity(0.4), Palette.goldDeep.opacity(0.15)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                frame.strokeBorder(Palette.goldDeep.opacity(0.7), lineWidth: 1)
                VStack(spacing: w * 0.01) {
                    Image(systemName: "crown.fill").font(.system(size: w * 0.12))
                    Text(card.label).font(Typo.display(w * 0.38))
                    Image(systemName: card.symbol).font(.system(size: w * 0.14))
                }
                .foregroundStyle(ink)
            }
            .frame(width: w * 0.44, height: h * 0.64)
        default:
            let area = CGSize(width: w * 0.3, height: h * 0.64)
            ForEach(Array(Self.pips(for: card.rank).enumerated()), id: \.offset) { _, pip in
                Image(systemName: card.symbol)
                    .font(.system(size: w * 0.19))
                    .foregroundStyle(ink)
                    .rotationEffect(.degrees(pip.y > 0.5 ? 180 : 0))
                    .position(x: w * 0.5 + (pip.x - 0.5) * area.width,
                              y: h * 0.18 + pip.y * area.height)
            }
        }
    }

    /// Pip-Positionen (x: links 0 / Mitte 0.5 / rechts 1, y: oben 0 … unten 1).
    private static func pips(for rank: Int) -> [CGPoint] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let corners = [p(0, 0), p(1, 0), p(0, 1), p(1, 1)]
        let sides6 = [p(0, 0), p(1, 0), p(0, 0.5), p(1, 0.5), p(0, 1), p(1, 1)]
        let sides8 = [p(0, 0), p(1, 0), p(0, 1.0 / 3), p(1, 1.0 / 3),
                      p(0, 2.0 / 3), p(1, 2.0 / 3), p(0, 1), p(1, 1)]
        switch rank {
        case 2: return [p(0.5, 0), p(0.5, 1)]
        case 3: return [p(0.5, 0), p(0.5, 0.5), p(0.5, 1)]
        case 4: return corners
        case 5: return corners + [p(0.5, 0.5)]
        case 6: return sides6
        case 7: return sides6 + [p(0.5, 0.25)]
        case 8: return sides6 + [p(0.5, 0.25), p(0.5, 0.75)]
        case 9: return sides8 + [p(0.5, 0.5)]
        case 10: return sides8 + [p(0.5, 1.0 / 6), p(0.5, 5.0 / 6)]
        default: return []
        }
    }
}

/// Eigene Vorderseite: Zebra-Hintergrund, Embleme oben rechts und unten links
/// (Rang im Silber-Achteck, Farbsymbol in den vier Sternen), Name und Symbol in der Mitte.
private struct ZebraFace: View {
    let card: Card

    private static let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.93, blue: 0.70), Color(red: 0.98, green: 0.78, blue: 0.36)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let corner = RoundedRectangle(cornerRadius: w * 0.09, style: .continuous)
            ZStack {
                BundledArt(name: "zebra")
                // Name und Symbol auf dunkler Plakette – gut lesbar auf den Zebra-Streifen.
                let plate = RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                VStack(spacing: w * 0.01) {
                    Text(card.name.uppercased())
                        .font(Typo.ui(w * 0.13, .heavy))
                        .tracking(w * 0.006)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: card.symbol)
                        .font(.system(size: w * 0.24, weight: .bold))
                }
                .foregroundStyle(Self.gold)
                .padding(.vertical, w * 0.045)
                .padding(.horizontal, w * 0.06)
                .background(plate.fill(.black.opacity(0.75)))
                .overlay(plate.strokeBorder(Palette.gold.opacity(0.75), lineWidth: max(0.6, w * 0.01)))
                .frame(maxWidth: w * 0.78)
                CornerEmblem(card: card)
                    .frame(width: w * 0.48, height: w * 0.48)
                    .position(x: w * 0.74, y: w * 0.25)
                CornerEmblem(card: card)
                    .frame(width: w * 0.48, height: w * 0.48)
                    .position(x: w * 0.26, y: h - w * 0.25)
            }
            .clipShape(corner)
            .overlay(corner.strokeBorder(Palette.gold.opacity(0.6), lineWidth: max(0.8, w * 0.012)))
        }
    }
}

/// Emblem aus `Artwork/emblem.png` mit Rang im Achteck und Farbsymbolen in den Sternen.
private struct CornerEmblem: View {
    let card: Card

    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let ink = Palette.cardInk                 // Pro-Design: einheitlich dunkel, kein Rot
            ZStack {
                BundledArt(name: "emblem", placeholder: .clear)
                Text(card.label)
                    .font(Typo.ui(s * 0.27, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: s * 0.33)
                    .offset(y: -s * 0.015)
                ForEach(Array([(0.0, -0.4), (0.41, -0.015), (0.0, 0.375), (-0.4, -0.015)].enumerated()), id: \.offset) { _, p in
                    Image(systemName: card.symbol)
                        .font(.system(size: s * 0.095, weight: .black))
                        .offset(x: s * p.0, y: s * p.1)
                }
            }
            .foregroundStyle(ink)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Kartenrücken im gewählten Deck-Stil (Environment `deckStyle`).
private struct CardBack: View {
    @Environment(\.deckStyle) private var style
    var styleOverride: Int?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                    .fill(Color(white: 0.97))
                Group {
                    if (styleOverride ?? style) == Deck.pro {
                        MedallionBack()
                    } else {
                        DeckPattern(blue: (styleOverride ?? style) == Deck.blue)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: w * 0.07, style: .continuous))
                .padding(w * 0.05)
            }
        }
    }
}

/// Bild aus dem Bundle – einmal im Hintergrund dekodiert und danach von allen Karten geteilt.
private struct BundledArt: View {
    let name: String
    var placeholder = Color(red: 0.55, green: 0.07, blue: 0.09)
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            placeholder
            if let image = image ?? ArtCache.cached(name) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: name) { image = await ArtCache.image(name) }
    }
}

/// Teilt dekodierte Bundle-Bilder zwischen allen Karten (je Datei nur einmal im RAM).
@MainActor
private enum ArtCache {
    private static var images: [String: CGImage] = [:]
    private static var loading: [String: Task<CGImage?, Never>] = [:]

    static func cached(_ name: String) -> CGImage? { images[name] }

    /// Gleichzeitige Anfragen für dasselbe Bild warten auf denselben Ladevorgang.
    static func image(_ name: String, maxPixel: Int = 600) async -> CGImage? {
        if let hit = images[name] { return hit }
        if let running = loading[name] { return await running.value }
        let task = Task { await PortraitLoader.load(name, maxPixel: maxPixel) }
        loading[name] = task
        let loaded = await task.value
        images[name] = loaded
        loading[name] = nil
        return loaded
    }
}

/// Pro-Rückseite: Ornament-Hintergrund (`Artwork/back-ornament.heic`, goldene Gitterecken oben
/// links und unten rechts) mit Medaillons aus `Artwork/medallion.png` als versetztem Muster,
/// das die Ornamente freilässt, plus großem Mittelmedaillon.
private struct MedallionBack: View {
    @State private var tile: CGImage? = ArtCache.cached("medallion")
    @State private var ornament: CGImage? = ArtCache.cached("back-ornament")

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let rect = CGRect(origin: .zero, size: size)
            let mid = CGPoint(x: w / 2, y: h / 2)
            if let ornament {
                context.draw(context.resolve(Image(decorative: ornament, scale: 1)), in: rect)
            } else {
                context.fill(Path(rect), with: .color(Color(red: 0.55, green: 0.08, blue: 0.09)))
            }

            if let tile {
                let image = context.resolve(Image(decorative: tile, scale: 1))
                let small = w * 0.19
                // Ornament-Ecken (oben links, unten rechts) als Dreiecke – dort keine Medaillons.
                func inOrnament(_ p: CGPoint) -> Bool {
                    let pad = small * 0.55
                    let topLeft = (p.x - pad) / (w * 0.5) + (p.y - pad) / (h * 0.33) < 1
                    let bottomRight = (w - p.x - pad) / (w * 0.5) + (h - p.y - pad) / (h * 0.33) < 1
                    return topLeft || bottomRight
                }
                // Versetzte Reihen kleiner Medaillons
                let dx = w * 0.3, dy = h * 0.135
                var row = 0
                var y = dy * 0.6
                while y < h - dy * 0.4 {
                    let shift = row.isMultiple(of: 2) ? 0 : dx / 2
                    var cx = w * 0.2 + shift - dx
                    while cx < w {
                        let p = CGPoint(x: cx, y: y)
                        if cx > small * 0.45, cx < w - small * 0.45,
                           hypot(cx - mid.x, (y - mid.y) * 0.8) > w * 0.46, !inOrnament(p) {
                            context.opacity = 0.9
                            context.draw(image, in: CGRect(x: cx - small / 2, y: y - small / 2, width: small, height: small))
                        }
                        cx += dx
                    }
                    y += dy
                    row += 1
                }
                // Mittelmedaillon mit dunklem Hof
                context.opacity = 1
                let big = w * 0.8                         // groß genug, dass „GSS“ lesbar bleibt
                context.fill(Path(ellipseIn: CGRect(x: mid.x - big * 0.5, y: mid.y - big * 0.5, width: big, height: big)),
                             with: .radialGradient(Gradient(colors: [.black.opacity(0.55), .clear]),
                                                   center: mid, startRadius: big * 0.2, endRadius: big * 0.5))
                context.draw(image, in: CGRect(x: mid.x - big / 2, y: mid.y - big / 2, width: big, height: big))
            }

            // Feiner Goldrahmen
            context.stroke(Path(roundedRect: rect.insetBy(dx: w * 0.035, dy: w * 0.035), cornerRadius: w * 0.04),
                           with: .linearGradient(Gradient(colors: [Palette.gold, Palette.goldDeep, Palette.gold]),
                                                 startPoint: .zero, endPoint: CGPoint(x: w, y: h)),
                           lineWidth: max(0.8, w * 0.012))
        }
        .task {
            if ornament == nil { ornament = await ArtCache.image("back-ornament") }
            if tile == nil { tile = await ArtCache.image("medallion") }
        }
    }
}

/// Rückseiten der Decks „Classic“ (Bordeaux) und „Blue“: Rautenmuster mit Rahmen und Mittelraute.
private struct DeckPattern: View {
    let blue: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let rect = CGRect(origin: .zero, size: size)
            let mid = CGPoint(x: w / 2, y: h / 2)
            let colors = blue
                ? [Color(red: 0.14, green: 0.30, blue: 0.70), Color(red: 0.04, green: 0.10, blue: 0.34)]
                : [Color(red: 0.66, green: 0.09, blue: 0.14), Color(red: 0.33, green: 0.03, blue: 0.07)]
            let line = blue ? Color.white : Palette.gold
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: colors), startPoint: .zero,
                                                           endPoint: CGPoint(x: w, y: h)))
            var hatch = Path()
            var x = -h
            while x < w {
                hatch.move(to: CGPoint(x: x, y: 0)); hatch.addLine(to: CGPoint(x: x + h, y: h))
                hatch.move(to: CGPoint(x: x + h, y: 0)); hatch.addLine(to: CGPoint(x: x, y: h))
                x += w * 0.15
            }
            context.stroke(hatch, with: .color(.white.opacity(0.13)), lineWidth: max(0.5, w * 0.008))
            let frame = rect.insetBy(dx: w * 0.07, dy: w * 0.07)
            context.stroke(Path(roundedRect: frame, cornerRadius: w * 0.05), with: .color(line.opacity(0.85)),
                           lineWidth: max(1, w * 0.014))
            var diamond = Path()
            let r = w * 0.2
            diamond.move(to: CGPoint(x: mid.x, y: mid.y - r * 1.3))
            diamond.addLine(to: CGPoint(x: mid.x + r, y: mid.y))
            diamond.addLine(to: CGPoint(x: mid.x, y: mid.y + r * 1.3))
            diamond.addLine(to: CGPoint(x: mid.x - r, y: mid.y))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(colors[1]))
            context.stroke(diamond, with: .color(line.opacity(0.9)), lineWidth: max(1, w * 0.014))
            let inner = diamond.applying(CGAffineTransform(translationX: -mid.x, y: -mid.y)
                .concatenating(CGAffineTransform(scaleX: 0.55, y: 0.55))
                .concatenating(CGAffineTransform(translationX: mid.x, y: mid.y)))
            context.fill(inner, with: .color(line.opacity(0.85)))
        }
    }
}

// MARK: - Jetons

private struct ChipView: View {
    let value: Int
    let tier: Int
    var size: CGFloat = 64

    private var colors: (Color, Color) {
        switch tier {
        case 0: (Color(white: 0.92), Color(white: 0.6))
        case 1: (Color(red: 0.15, green: 0.62, blue: 0.95), Color(red: 0.05, green: 0.35, blue: 0.7))
        case 2: (Color(red: 0.95, green: 0.42, blue: 0.15), Color(red: 0.62, green: 0.22, blue: 0.06))
        default: (Color(white: 0.25), Color(white: 0.08))
        }
    }

    var body: some View {
        let (light, deep) = colors
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [light, deep], startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(.white.opacity(0.95), style: StrokeStyle(lineWidth: size * 0.1, dash: [size * 0.13, size * 0.115]))
                .padding(size * 0.02)
            Circle()
                .fill(Color(white: 0.97))
                .padding(size * 0.2)
            Circle()
                .strokeBorder(deep, lineWidth: size * 0.025)
                .padding(size * 0.24)
            VStack(spacing: -size * 0.02) {
                Text((Double(value) / 100).formatted(euroFormat))
                    .font(Typo.ui(size * 0.24, .heavy))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text("EURO")
                    .font(Typo.ui(size * 0.08, .heavy))
                    .tracking(1)
                    .foregroundStyle(deep)
            }
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, size * 0.27)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
    }
}

private struct ChipStack: View {
    let amount: Int

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                ChipView(value: amount, tier: 3 - i, size: 52)
                    .offset(y: CGFloat(2 - i) * 4)
            }
        }
        .frame(width: 52, height: 62)
    }
}

private struct ChipTray: View {
    let game: Game
    let balance: Int
    let haptics: Bool
    let sounds: Bool
    let addChip: (Int) -> Void
    @State private var denominations: [Int] = []

    var body: some View {
        let free = balance
        HStack(spacing: 10) {
            ForEach(Array(denominations.enumerated()), id: \.offset) { index, value in
                Button {
                    addChip(value)
                    if sounds { AudioServicesPlaySystemSound(1105) }
                } label: {
                    ChipView(value: value, tier: index, size: 72)
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .disabled(value > free)
                .opacity(value > free ? 0.35 : 1)
                .accessibilityLabel("\(eur(value)) chip").accessibilityIdentifier("chip_\(value)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.black.opacity(0.25)).padding(5))
        )
        .padding(.horizontal, 10)
        .onAppear { denominations = chipValues(for: balance + game.bet, minBet: game.minBet) }
        .sensoryFeedback(.impact(weight: .light), trigger: game.bet) { _, _ in haptics }
    }
}

// MARK: - Spieler, Guthaben, Pleiteschutz

private struct PlayerBadge: View {
    let name: String
    let xp: Int
    var size: CGFloat = 70
    var subtitle: String?

    var body: some View {
        let level = Progression.level(xp: xp)
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.black.opacity(0.5))
                Circle()
                    .trim(from: 0, to: Progression.progress(xp: xp))
                    .stroke(Palette.gold, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.03)
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.2, blue: 0.5), Color(red: 0.1, green: 0.05, blue: 0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(size * 0.1)
                Text(String(name.prefix(1)).uppercased())
                    .font(Typo.display(size * 0.38))
                    .foregroundStyle(Palette.gold)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomLeading) {
                Text("\(level)")
                    .font(Typo.ui(max(11, size * 0.2), .heavy))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Palette.gold, in: Capsule())
                    .offset(x: -4, y: 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(Typo.ui(max(15, size * 0.3), .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.ui(13, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BalancePill: View {
    let balance: Int

    var body: some View {
        HStack(spacing: 8) {
            ChipIcon()
            Text(eur(balance))
                .font(Typo.ui(.headline, .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(balance)))
                .animation(.snappy, value: balance)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance \(eur(balance))").accessibilityIdentifier("bankroll")
    }
}

private struct ChipIcon: View {
    var body: some View {
        ZStack {
            Circle().fill(Palette.lose)
            Circle().strokeBorder(.white, style: StrokeStyle(lineWidth: 4, dash: [4, 3.6])).padding(1)
            Circle().fill(.white).padding(7)
            Circle().fill(Palette.lose).padding(10)
        }
        .frame(width: 28, height: 28)
    }
}

/// Kompakter Status: laufender Cooldown oder Tages-Status des Pleiteschutzes.
private struct ProtectionPill: View {
    @AppStorage(Key.afterDark) private var afterDark = false
    @AppStorage(Key.brokeSince) private var brokeSince = 0.0
    @AppStorage(Key.lastRefillDay) private var lastRefillDay = ""

    var body: some View {
        let protection = Protection(brokeSince: brokeSince, lastRefillDay: lastRefillDay)
        if !afterDark {
            Live(dates: protection.changeDates(after: .now)) { now in
                HStack(spacing: 6) {
                    if let end = protection.cooldownEnd, now < end {
                        Image(systemName: "timer").foregroundStyle(Palette.gold)
                        Text(timerInterval: now...end, countsDown: true, showsHours: false)
                            .monospacedDigit()
                    } else if protection.usedToday(at: now) {
                        Image(systemName: "shield.slash.fill").foregroundStyle(Palette.lose)
                        Text("Refill used today")
                    } else if protection.cooldownEnd != nil {
                        Image(systemName: "shield.checkered").foregroundStyle(Palette.win)
                        Text("Refill ready")
                    }
                }
                .font(Typo.ui(.subheadline, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
                // Nur sichtbar, wenn der Pleiteschutz gerade eine Rolle spielt (Countdown, bereit, heute genutzt).
                .opacity(protection.cooldownEnd != nil || protection.usedToday(at: now) ? 1 : 0)
            }
        }
    }
}

/// Aufladen-Karte des Pleiteschutzes (Countdown, Tageslimit, +500 €).
private struct RefillCard: View {
    @AppStorage(Key.afterDark) private var afterDark = false
    @AppStorage(Key.balance) private var balance = Rules.startBalance
    @AppStorage(Key.brokeSince) private var brokeSince = 0.0
    @AppStorage(Key.lastRefillDay) private var lastRefillDay = ""

    var body: some View {
        let protection = Protection(brokeSince: brokeSince, lastRefillDay: lastRefillDay)
        Live(dates: protection.changeDates(after: .now)) { now in
            let used = protection.usedToday(at: now)
            let end = protection.cooldownEnd
            let waiting = end.map { now < $0 } ?? false

            VStack(spacing: 10) {
                Label(balance < 100 ? "Out of chips" : "Bankroll Rescue", systemImage: "shield.lefthalf.filled")
                    .font(Typo.ui(.headline, .bold))
                    .foregroundStyle(balance < 100 ? Palette.lose : Palette.gold)
                Group {
                    if balance >= 100 {
                        Text(used ? "Already used today – available again tomorrow."
                                  : "Below €1 a 30-minute timer starts. Then refill +\(eur(Rules.refillAmount)) once per day.")
                    } else if used {
                        Text("Already used today. You can refill again tomorrow.")
                    } else if waiting, let end {
                        HStack(spacing: 6) {
                            Text("Refill available in")
                            Text(timerInterval: now...end, countsDown: true, showsHours: false)
                                .monospacedDigit()
                                .fontWeight(.bold)
                                .foregroundStyle(Palette.gold)
                        }
                    } else {
                        Text("Your rescue refill is ready.")
                    }
                }
                .font(Typo.ui(.subheadline, .regular))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

                if balance < 100 {
                    Button(used ? "Back tomorrow" : (waiting ? "Locked" : "Refill  +\(eur(Rules.refillAmount))")) {
                        refill()
                    }
                    .buttonStyle(CapsuleStyle(colors: [Palette.gold, Palette.goldDeep], ink: .black))
                    .disabled(used || waiting)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder((balance < 100 ? Palette.lose : Palette.gold).opacity(0.35), lineWidth: 1))
        }
    }

    private func refill() {
        let now = Date.now
        let protection = Protection(brokeSince: brokeSince, lastRefillDay: lastRefillDay)
        guard !afterDark, balance < 100, protection.canRefill(at: now) else { return }
        balance += Rules.refillAmount
        lastRefillDay = dayKey(now)
        brokeSince = 0
    }
}

/// After-Dark-Recharge ausschließlich in Profil und Einstellungen.
private struct NightRechargeCard: View {
    @AppStorage(Key.afterDark) private var afterDark = false
    @AppStorage(Key.balance) private var balance = Rules.startBalance
    @AppStorage(Key.lastNightRecharge) private var lastClaim = 0.0
    @AppStorage(Key.brokeSince) private var brokeSince = 0.0
    @AppStorage(Key.highest) private var highest = Rules.startBalance
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = Date.now

    var body: some View {
        if afterDark {
            let recharge = NightRecharge(lastClaim: lastClaim)
            let dates = recharge.cooldownEnd.map { [$0] } ?? []
            Live(dates: dates) { now in
                let waiting = recharge.remaining(at: now) > 0
                VStack(spacing: 12) {
                    Label("After Dark Recharge", systemImage: "bolt.fill")
                        .font(Typo.ui(.headline, .bold)).foregroundStyle(Palette.afterDark)
                    Text("Manually add +\(eur(Rules.nightRechargeAmount)) in play money every 10 minutes, at any balance. Unused recharges do not accumulate.")
                        .font(Typo.ui(.subheadline, .regular))
                        .foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                    if waiting, let end = recharge.cooldownEnd {
                        HStack(spacing: 6) {
                            Text("Ready in")
                            Text(timerInterval: now...end, countsDown: true, showsHours: false)
                                .monospacedDigit().fontWeight(.bold)
                        }
                        .foregroundStyle(Palette.afterDark)
                    } else {
                        Text("Ready to recharge").foregroundStyle(Palette.win)
                    }
                    Button("Recharge +\(eur(Rules.nightRechargeAmount))") { claim() }
                        .buttonStyle(CapsuleStyle(colors: [Palette.afterDark, Palette.purple], ink: .white))
                        .disabled(waiting)
                }
                .padding(16).frame(maxWidth: .infinity)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.afterDark.opacity(0.4)))
            }
            .id(refresh)
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh = .now } }
        }
    }

    private func claim() {
        guard NightRecharge.claim(balance: &balance, lastClaim: &lastClaim, afterDark: afterDark, at: .now) else { return }
        highest = max(highest, balance)
        syncBroke(&balance, &brokeSince)
    }
}

// MARK: - Profil

private struct ProfileSheet: View {
    @AppStorage(Key.proUnlocked) private var proUnlocked = false
    @AppStorage(Key.afterDark) private var afterDark = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Key.balance) private var balance = Rules.startBalance
    @AppStorage(Key.brokeSince) private var brokeSince = 0.0
    @AppStorage(Key.name) private var name = "Guest"
    @AppStorage(Key.xp) private var xp = 0
    @AppStorage(Key.games) private var games = 0
    @AppStorage(Key.wins) private var wins = 0
    @AppStorage(Key.losses) private var losses = 0
    @AppStorage(Key.pushes) private var pushes = 0
    @AppStorage(Key.blackjacks) private var blackjacks = 0
    @AppStorage(Key.splits) private var splits = 0
    @AppStorage(Key.doubles) private var doubles = 0
    @AppStorage(Key.tips) private var tips = 0
    @AppStorage(Key.tipTotal) private var tipTotal = 0
    @AppStorage(Key.bestStreak) private var bestStreak = 0
    @AppStorage(Key.highest) private var highest = Rules.startBalance
    @AppStorage(Key.venuesPlayed) private var venuesPlayed = 0
    @AppStorage(Key.claimed) private var claimed = 0
    @AppStorage(Key.deck) private var deck = Deck.standard
    @State private var tab = 0
    @Namespace private var tabSpace

    init(initialTab: Int = 0) { _tab = State(initialValue: initialTab) }

    private var stats: Stats {
        Stats(games: games, wins: wins, blackjacks: blackjacks, splits: splits, doubles: doubles, tips: tips,
              bestStreak: bestStreak, highest: highest, venues: venuesPlayed.nonzeroBitCount)
    }

    var body: some View {
        ZStack {
            StripedBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SheetHeader(title: "Profile") { dismiss() }
                    HStack(alignment: .center) {
                        PlayerBadge(name: name, xp: xp, size: 92)
                        Spacer()
                        BalancePill(balance: balance)
                    }
                    TextField("Name", text: $name)
                        .font(Typo.ui(.body, .semibold))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: name) { _, new in
                            if new.count > 16 { name = String(new.prefix(16)) }
                        }

                    HStack(spacing: 0) {
                        ForEach(Array(["Stats", "Challenges", "Decks", afterDark ? "Recharge" : "Bonus"].enumerated()), id: \.offset) { index, title in
                            Button {
                                withAnimation(.snappy(duration: 0.3)) { tab = index }
                            } label: {
                                Text(title)
                                    .font(Typo.ui(14, tab == index ? .bold : .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(tab == index ? Color.black.opacity(0.85) : .white.opacity(0.65))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background {
                                        if tab == index {
                                            Capsule()
                                                .fill(LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                                                     startPoint: .top, endPoint: .bottom))
                                                .matchedGeometryEffect(id: "tab", in: tabSpace)
                                        }
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(.black.opacity(0.4), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))

                    switch tab {
                    case 0: statsTab
                    case 1: achievementsTab
                    case 2: decksTab
                    default:
                        if afterDark { NightRechargeCard() } else { RefillCard() }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDragIndicator(.visible)
        #if DEBUG
        .onAppear { if let demo = UserDefaults.standard.string(forKey: "demoTab").flatMap(Int.init) { tab = demo } }
        #endif
    }

    private var statsTab: some View {
        let items: [(String, String, Int)] = [
            ("Games", "suit.diamond.fill", games), ("Blackjacks", "21.circle.fill", blackjacks),
            ("Wins", "hand.thumbsup.fill", wins), ("Losses", "hand.thumbsdown.fill", losses),
            ("Push", "equal.circle.fill", pushes), ("Splits", "arrow.triangle.branch", splits),
            ("Doubles", "plus.circle.fill", doubles), ("Best Streak", "flame.fill", bestStreak),
            ("Tips", "wineglass.fill", tipTotal),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
            ForEach(items, id: \.0) { title, icon, value in
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(icon.contains("thumbsup") ? Palette.win : .white)
                    Text(title)
                        .font(Typo.ui(.subheadline, .bold))
                        .foregroundStyle(Palette.gold)
                    Text(title == "Tips" ? eur(value) : value.formatted(.number))
                        .font(Typo.ui(.body, .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var achievementsTab: some View {
        let list = Achievement.all
        let done = list.filter { claimed & (1 << $0.id) != 0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Completed \(done * 100 / list.count) %")
                .font(Typo.ui(.headline, .bold))
                .foregroundStyle(Palette.gold)
            ForEach(list) { item in
                let value = item.value(stats)
                let isClaimed = claimed & (1 << item.id) != 0
                let ready = value >= item.target && !isClaimed
                HStack(spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 48, height: 62)
                        .background(Palette.gold, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .rotationEffect(.degrees(-4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(Typo.ui(.headline, .bold))
                        Text(item.detail).font(Typo.ui(.subheadline, .regular)).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ChipIcon().scaleEffect(0.7).frame(width: 20, height: 20)
                            Text(eur(item.reward)).font(Typo.ui(.subheadline, .bold))
                                .foregroundStyle(Palette.lose)
                        }
                    }
                    .foregroundStyle(.black.opacity(0.85))
                    Spacer(minLength: 4)
                    Button {
                        claim(item)
                    } label: {
                        Text(isClaimed ? "✓" : (ready ? "Claim" : "\(min(100, value * 100 / max(item.target, 1))) %"))
                            .font(Typo.ui(.headline, .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 44)
                            .background(ready ? Palette.play : (isClaimed ? Palette.playDeep : Color(white: 0.4)),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!ready)
                }
                .padding(14)
                .background(Color(white: 0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var decksTab: some View {
        HStack(spacing: 12) {
            ForEach(Deck.names.indices, id: \.self) { index in
                let active = Deck.selected(deck, proUnlocked: proUnlocked) == index
                let locked = index == Deck.pro && !proUnlocked
                Button {
                    withAnimation(.snappy) { deck = index }
                } label: {
                    VStack(spacing: 10) {
                        ZStack {
                            CardBack(styleOverride: index)
                                .frame(width: 66, height: 92)
                                .rotationEffect(.degrees(-9))
                                .offset(x: -14, y: 4)
                            CardFace(card: Card(id: index == Deck.pro ? 0 : 25))
                                .environment(\.deckStyle, index)
                                .frame(width: 66, height: 92)
                                .rotationEffect(.degrees(8))
                                .offset(x: 14)
                        }
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                        .frame(height: 118)
                        Text(Deck.names[index])
                            .font(Typo.display(19))
                            .foregroundStyle(.white)
                        Text(locked ? "Locked" : (active ? "Active" : "Select"))
                            .font(Typo.ui(13, .bold))
                            .foregroundStyle(active ? .white : .black.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(active ? Palette.play : Color.white.opacity(0.9), in: Capsule())
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(active ? 0.45 : 0.25), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(active ? Palette.gold : .white.opacity(0.08), lineWidth: active ? 2 : 1))
                }
                .buttonStyle(PressStyle())
                .disabled(locked)
                .accessibilityHint(locked ? "Discover After Dark to unlock the Pro deck." : "Select this deck.")
                .accessibilityLabel("\(Deck.names[index]) deck\(active ? ", active" : "")")
                .accessibilityIdentifier("deck_\(index)")
            }
        }
    }

    private func claim(_ item: Achievement) {
        guard item.value(stats) >= item.target, claimed & (1 << item.id) == 0 else { return }
        claimed |= 1 << item.id
        balance += item.reward
        highest = max(highest, balance)
        syncBroke(&balance, &brokeSince)
    }
}

// MARK: - Optionen

private struct OptionsSheet: View {
    @AppStorage(Key.afterDark) private var afterDark = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Key.standOn21) private var standOn21 = true
    @AppStorage(Key.showValues) private var showValues = true
    @AppStorage(Key.sounds) private var sounds = true
    @AppStorage(Key.haptics) private var haptics = true
    @AppStorage(Key.ladyMode) private var ladyMode = 1
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            StripedBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(title: "Options") { dismiss() }
                    VStack(spacing: 0) {
                        row("Stand on 21") { Toggle("", isOn: $standOn21).labelsHidden() }
                        Divider().overlay(.white.opacity(0.1))
                        row("Show Hand Value") { Toggle("", isOn: $showValues).labelsHidden() }
                        Divider().overlay(.white.opacity(0.1))
                        row("Sounds") { Toggle("", isOn: $sounds).labelsHidden() }
                        Divider().overlay(.white.opacity(0.1))
                        row("Haptics") { Toggle("", isOn: $haptics).labelsHidden() }
                        Divider().overlay(.white.opacity(0.1))
                        row("Bar Lady") {
                            Picker("Bar Lady", selection: $ladyMode) {
                                Text("Off").tag(0)
                                Text("Text").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    }
                    .tint(Palette.gold)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if afterDark { NightRechargeCard() }

                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                            .font(Typo.ui(.headline, .bold))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                    }

                    ShareLink(item: "Ad-free Blackjack – just cards, chips and charming bar ladies. 🃏") {
                        Label("Share with Friends", systemImage: "square.and.arrow.up")
                            .font(Typo.ui(.headline, .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(LinearGradient(colors: [Palette.play, Palette.playDeep], startPoint: .top, endPoint: .bottom),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("100% ad-free · no purchases · no tracking", systemImage: "checkmark.seal.fill")
                        Label("Featherweight: vector graphics & tiny images", systemImage: "leaf.fill")
                        Label("Play money only – no real-money value", systemImage: "info.circle.fill")
                    }
                    .font(Typo.ui(.footnote, .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 6)
                }
                .padding(20)
            }
        }
        .presentationDragIndicator(.visible)
        .confirmationDialog("Reset progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to €500", role: .destructive) {
                ProgressStore.reset()
                dismiss()
            }
        } message: {
            Text("Reset your balance, level, statistics and achievements. Your name and options are kept.")
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .font(Typo.ui(.body, .semibold))
                .foregroundStyle(.white)
            Spacer()
            control()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }
}

/// Kurze Einblendung beim Umschalten des alternativen Modus.
private struct ModeToast: View {
    let unlocked: Bool
    var proReward = false
    let done: () -> Void
    @State private var go = false

    var body: some View {
        let tint = unlocked ? Palette.afterDark : Palette.gold
        ZStack {
            ZStack {
                Color.black.opacity(0.82)
                RadialGradient(colors: [tint.opacity(unlocked ? 0.4 : 0.22), .clear],
                               center: .center, startRadius: 10, endRadius: 420)
            }
            .ignoresSafeArea()
            .opacity(go ? 1 : 0)
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(tint.opacity(0.6), lineWidth: 2)
                        .frame(width: 150, height: 150)
                        .scaleEffect(go ? 1.25 : 0.6)
                        .opacity(go ? 0 : 1)
                        .animation(.easeOut(duration: 1.1), value: go)
                    Image(systemName: unlocked ? "suit.spade.fill" : "briefcase.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(tint)
                        .shadow(color: tint.opacity(0.8), radius: 22)
                        .scaleEffect(go ? 1 : 0.3)
                        .rotationEffect(.degrees(go ? 0 : -25))
                }
                Text(unlocked ? "AFTER DARK" : "BACK TO")
                    .font(Typo.display(38))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text(unlocked ? "UNLOCKED" : "BUSINESS")
                    .font(Typo.ui(16, .heavy))
                    .tracking(8)
                    .foregroundStyle(tint)
                if unlocked && proReward {
                    Text("PRO DECK UNLOCKED")
                        .font(Typo.ui(14, .heavy)).tracking(2).foregroundStyle(Palette.gold)
                    Text("Choose it in Profile → Decks")
                        .font(Typo.ui(.subheadline, .regular)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .scaleEffect(go ? 1 : 0.85)
            .opacity(go ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .onAppear { withAnimation(.spring(duration: 0.55, bounce: 0.35)) { go = true } }
        .task {
            try? await Task.sleep(for: .seconds(2.8))
            done()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modeToast")
    }
}

// MARK: - Gemeinsame Bausteine

private struct SheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(Typo.display(40))
                .foregroundStyle(.white)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close")
        }
    }
}

private struct StripedBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.14, blue: 0.08), Color(red: 0.08, green: 0.06, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var p = Path()
                for i in 0..<14 {
                    let y = CGFloat(i) * 46 - 120
                    p.move(to: CGPoint(x: size.width * 0.15, y: y))
                    p.addLine(to: CGPoint(x: size.width * 1.1, y: y + size.width * 0.55))
                }
                context.stroke(p, with: .color(Color(red: 0.3, green: 0.5, blue: 0.25).opacity(0.35)),
                               style: StrokeStyle(lineWidth: 20, lineCap: .round, dash: [80, 34]))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

private struct RoundIconButton: View {
    let icon: String
    let tint: Color
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 58, height: 58)
                .background(tint, in: Circle())
                .shadow(color: tint.opacity(0.4), radius: 8)
        }
        .buttonStyle(PressStyle())
    }
}

private struct RoundAction: View {
    var icon: String?
    var glyph: String?
    let label: String
    let colors: [Color]
    var ring = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    if ring { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3) }
                    if let icon {
                        Image(systemName: icon).font(.system(size: 24, weight: .heavy))
                    } else if let glyph {
                        Text(glyph).font(Typo.ui(22, .heavy))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .shadow(color: colors[0].opacity(0.45), radius: 8, y: 3)
                Text(label)
                    .font(Typo.ui(.subheadline, .heavy))
                    .foregroundStyle(.white)
            }
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
    }
}

private struct CapsuleStyle: ButtonStyle {
    let colors: [Color]
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, colors: colors, ink: ink)
    }
}

private struct CapsuleBody: View {
    let configuration: ButtonStyleConfiguration
    let colors: [Color]
    let ink: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Typo.ui(.headline, .heavy))
            .foregroundStyle(ink.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
