# Contributing to Sharedee Tools

Thanks for helping improve the app. You can report bugs, suggest changes, or open a pull request.

## Before opening a pull request

1. Describe the user-facing change and why it is needed.
2. Build the `SharedeCapture` scheme in Xcode. If you changed `project.yml`, run `xcodegen generate` first and include the updated `SharedeCapture.xcodeproj`.
3. Run the existing tests with `xcodebuild -project SharedeCapture.xcodeproj -scheme SharedeCapture -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`.
4. For capture or menu bar changes, check the flow manually on macOS. If possible, check an Intel Mac and an Apple Silicon Mac.
5. Do not commit screenshots containing private information, local build outputs, signing certificates, or secrets.

By submitting a contribution, you agree that it will be licensed under the project's Apache License 2.0 license. The project may ask for clarification of ownership when a contribution includes third-party code or assets.
