# Changelog

All notable changes to Sharedee Tools are documented here. The project follows
[Semantic Versioning](https://semver.org) and [Conventional Commits](https://www.conventionalcommits.org);
new sections are added by `scripts/release.sh`.

## 1.2.0 - 2026-09-30

### Features

- force quit with ⌥, pinned apps, and quit all but current
- find installers, stale node_modules and device backups
- warn about running apps and show disk usage
- add an app uninstaller that also removes leftovers
- group the menu by tool and add Quit Apps and Cleanup

### Other changes

- describe the Quit Apps, Cleanup and Uninstall tools
- give Debug builds their own bundle ID
- cover what the cleanup scanner picks up

## 1.1.0 - 2026-09-30

### Features

- English UI, Drive setup, Live Text, and interactive scrolling capture
- new app icon and menu bar template icon

### Fixes

- set the version after Info.plist is processed

### Other changes

- add a notarized DMG release script
- derive the version from git tags and Conventional Commits

## 1.0.0 - 2026-09-29

- First open-source release under the Apache License 2.0.
