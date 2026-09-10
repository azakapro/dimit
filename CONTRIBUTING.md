# Contributing to Dimit

Hardware testing and a fluent review of the Uzbek (Latin) and Russian strings
are especially useful contributions. See [the tester checklist](docs/TESTING_CHECKLIST.md)
and [hardware QA](docs/QA.md) for the gaps. Do not include serial numbers or
precise personal location coordinates in reports, fixtures, or screenshots.

To build, install Xcode 26 or newer and select it with `xcode-select`, then run:

```bash
scripts/bootstrap.sh
xcodebuild test -project Dimit.xcodeproj -scheme Dimit -destination 'platform=macOS'
scripts/build.sh
```

Bootstrap installs XcodeGen through Homebrew if it is missing. The project uses
the Swift 6 toolchain in Swift 5 language mode. Edit `project.yml`, then run
bootstrap again; the generated `Dimit.xcodeproj` is gitignored. Quit any running
copy of Dimit before `scripts/build.sh` performs its launch check.

Read [CLAUDE.md](CLAUDE.md), [the architecture](docs/ARCHITECTURE.md), and
[the PR requirements](docs/PLAN.md#3-pr-requirements-every-cycle) before changing
code. Use the PR template and report test counts and any hardware checks honestly.
Display-driver work is not a beginner task: gamma, backlight, and DDC changes
can leave a screen tinted or too bright. Preserve restoration on OFF, quit,
signals, and launch, and test the relevant pure functions and real hardware.

All app strings belong in `Localizable.xcstrings` with `en`, `uz`, and `ru`.
Provide English and flag unreviewed uz/ru with `state: needs_review`; only mark
them `translated` after a fluent review. Do not silently machine-translate.
Do not add dependencies, network calls, or permission prompts without discussion.

Contributions are made under the project's [MIT licence](LICENSE).
