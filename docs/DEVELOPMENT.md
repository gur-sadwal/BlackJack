# Development

Open `BlackJack.xcodeproj` with Xcode. The app uses Apple frameworks and has no external runtime packages.

## Checks and builds

```sh
./scripts/test-game.sh
./scripts/build-ipa.sh --public
```

The checks compile the original game-model section and exercise fixed hands, concurrent-action guards, result timing, payouts, splits and explicit progress reset. They run on macOS with Xcode installed.

The IPA build stops on an Xcode error, uses a temporary build directory and replaces `build/BlackJack.ipa` only after successful packaging.

## Optional local dialogue

The optional dialogue loader and five-tap switch are available for extensions. Create `Private/AfterDark.json` locally and build without `--public` to include it. `Private/` is ignored by Git; keep personal content out of commits and public release assets.

Minimal example:

```json
{
  "tips": ["Thank you for the tip."],
  "greet": ["Welcome back."],
  "luck": ["Good luck."],
  "win": ["Well played."],
  "blackjack": ["Blackjack!"],
  "lose": ["Another hand?"],
  "bust": ["A little too much."],
  "push": ["An even hand."],
  "broke": ["Time for a break."],
  "emptyPockets": ["Keep your remaining chips."],
  "signatures": {}
}
```

Use non-empty string arrays. `signatures` can map a character's name to additional strings. When the file is present, five taps within three seconds on the lobby's spade/title toggle the extra dialogue. A public build omits the file, so the switch has no effect.

## Saved progress

Balance, level, statistics and achievements stay in the app's own preferences. Updating the existing app with the same app identifier and signing account preserves those preferences.

`Options → Reset Progress` resets progress only after confirmation; name and options stay unchanged. An explicit `--reset-progress` launch argument also performs a reset for device maintenance. A normal launch or update never requests this reset.

Deleting the app removes its own local data. Installer files exported to another app or kept on a Mac are separate files.
