# Changelog

## 1.2.0

- A welcome window installs everything a build needs, without the Terminal: Homebrew and the .NET 10 SDK from their
  signed installer packages (Gatekeeper-checked for notarization and the expected Apple developer team, and .NET
  against Microsoft's SHA-512), zstd, glslang and uv, Xcode's Metal toolchain, nxnative and the Python environment.
  The Mac's password is asked once, in macOS's own dialog. Xcode comes from the App Store: NX Builder opens its page,
  waits for it, then selects it, accepts its licence and runs its first launch.
- Setup has an **Install everything …** button whenever something is missing.

## 1.1.0

- Six more languages: German, French, Spanish, Brazilian Portuguese, Japanese and Simplified Chinese. The app
  follows the Mac's language, or the one chosen in Setup.
- The texts live in `Localizations/<code>.json`, one file per language, so anyone can add or correct a
  translation; `Tools/check_localizations.py` checks a file against the app's texts.

## 1.0.0

First public version.

- Builds a game into a Mac app with nxnative's `build_ipa_from_nsp.py --platform mac-app`, with live steps,
  progress, time left and log. Stop stops the script and every tool it started.
- Setup page: checks Xcode, the Metal toolchain, Homebrew tools, .NET 10, nxnative, Python and keys; downloads
  nxnative, sets up its own Python environment (uv, Python 3.14, Capstone 5, fontTools, lz4) and installs the Metal
  toolchain with one click; copyable commands for the rest.
- Recipes: the list of games nxnative supports and the version each needs; a warning before and during a build
  when the files are another version.
- Asks before building with an untested Metal compiler, and offers one-click fixes for known stops.
- Library: play, build again, logs and save folders, and deleting build folders to free space.
- nxnative update check and one-click update, with the `Front-ends:` notes of each update.
- Loose XCI and NSP files in shared folders can be moved into a folder of their own.
- Keyboard and controller overview.
- English and Norwegian.
