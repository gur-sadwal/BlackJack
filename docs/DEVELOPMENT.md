# Development

Open `BlackJack.xcodeproj` with Xcode. The app uses Apple frameworks and has no external runtime packages.

## Checks and builds

```sh
./scripts/test-game.sh
BLACKJACK_DIALOGUE_PATH=Private/AfterDark.json ./scripts/test-game.sh # optional override
xcodebuild test -project BlackJack.xcodeproj -scheme BlackJack -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
./scripts/build-ipa.sh --public
```

The checks compile the original game-model section and exercise fixed hands, concurrent-action guards, result timing, payouts, splits and explicit progress reset. They run on macOS with Xcode installed. The XCTest UI target covers visible chip debits, all-in, reset, table exit, restart recovery, a played hand and rebet, first discovery, permanent Pro selection, and recharge persistence across mode switches. UI tests reset only their simulator app state.

The IPA build stops on an Xcode error, uses a temporary build directory and replaces `build/BlackJack.ipa` only after successful packaging.

## Dialogue and After Dark

`BlackJack/AfterDark.json` contains the bundled, non-explicit English dialogue. Five taps within three seconds on the lobby spade/title toggle After Dark. First discovery permanently unlocks the Pro deck; Blue is the default. There is no speech output. Normal dialogue remains factual casino commentary.

Each event has a base string array: `tips`, `greet`, `luck`, `win`, `blackjack`, `lose`, `bust`, `push`, `broke`, `emptyPockets`. `signatures` is a legacy per-name tip pool. Optional `characters` maps each character name to event arrays; `repeatTips` changes only the commentary after three consecutive paid tips. Missing character pools fall back to the base array; empty text falls back to normal dialogue. The shuffled tip bag handles pool changes safely.

For personal overrides, put an `AfterDark.json` with this schema under ignored `Private/` and run `./scripts/build-ipa.sh`. `--public` uses only the bundled dialogue and never copies `Private/`. Keep personal overrides out of commits and public assets.

## Bankroll and recharge

All money is stored as integer cents. On first launch after upgrading, existing Euro values for balance, reserved chips, highest balance and total tips are converted once. Blackjack pays 3:2, rounding a half-cent upward only when a stake contains an odd number of cents.

Placing chips immediately reserves money from the available bankroll. Reset and leaving the table return undealt chips; a restart returns a saved undealt reservation once. Deal commits that reservation without debiting again. Double and Split reserve their extra stake once; payout includes returned stakes. The existing engine books settlement before the presentation, then reveals it after the dealer animation. Active unfinished hands are not resumable across force-quitting.

The four familiar chip denominations are selected from a standard ladder for the bankroll/table minimum and stay fixed throughout one betting phase. Unaffordable chips are disabled rather than resized after each tap.

Normal-mode rescue is manual +€500 once per calendar day after 30 minutes below the smallest playable bankroll (€1). A fractional remainder is preserved. After Dark has a separate manual +€1,000 recharge at any balance every 10 minutes. Unused intervals do not stack. It is available only in Profile → Recharge and Options, never through tipping. The last claim is stored locally, survives restarts and mode switches, and is not cleared by Reset Progress. Both timers use the device wall clock; there is no server authority, cross-device cooldown, or guarantee against clock/storage manipulation.

## Saved progress

Balance, level, statistics, deck discovery and achievements stay in the app's own preferences. Updating the existing app with the same app identifier and signing account preserves those preferences.

`Options → Reset Progress` resets progress only after confirmation; name and options stay unchanged; Pro must be discovered again. The recharge cooldown stays in place. An explicit `--reset-progress` launch argument also performs a reset for device maintenance. A normal launch or update never requests this reset.

Deleting the app removes its own local data. Installer files exported to another app or kept on a Mac are separate files.
