# Contributing to Sharedee Tools

Thanks for helping improve the app. You can report bugs, suggest changes, or open a pull request.

## Before opening a pull request

1. Describe the user-facing change and why it is needed.
2. Build the `SharedeCapture` scheme in Xcode. If you changed `project.yml`, run `xcodegen generate` first and include the updated `SharedeCapture.xcodeproj`.
3. Run the existing tests with `xcodebuild -project SharedeCapture.xcodeproj -scheme SharedeCapture -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`.
4. For capture or menu bar changes, check the flow manually on macOS. If possible, check an Intel Mac and an Apple Silicon Mac. Debug builds run as **Sharedee Tools Dev** (`com.sharedecapture.app.dev`), so granting them permissions doesn't affect an installed release.
5. For Cleanup and Uninstall, anything that decides which files are removed needs a test against a throwaway folder (see `CleanupScannerTests` and `AppUninstallerTests`); never test deletion against your real home folder.
6. New tools implement `MenuBarTool` for their menu bar submenu and add a `HomePage` case for their window page.
7. Do not commit screenshots containing private information, local build outputs, signing certificates, or secrets.

## Commit messages and versions

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org), because the app version is computed from them (see `scripts/version.sh`):

| Commit | Example | Version change |
| --- | --- | --- |
| New feature | `feat: create Drive folders from Settings` | 1.2.3 → 1.3.0 |
| Bug fix | `fix(drive): send client secret on token refresh` | 1.2.3 → 1.2.4 |
| Breaking change | `feat!: require macOS 13` or a `BREAKING CHANGE:` line | 1.2.3 → 2.0.0 |
| Anything else | `docs:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:` | 1.2.3 → 1.2.4 |

Enable the message check once per clone with `git config core.hooksPath .githooks`. Maintainers cut a release with `scripts/release.sh`, which updates `CHANGELOG.md` and tags `vX.Y.Z`; then push with `git push origin main --follow-tags`.

By submitting a contribution, you agree that it will be licensed under the project's Apache License 2.0 license. The project may ask for clarification of ownership when a contribution includes third-party code or assets.
