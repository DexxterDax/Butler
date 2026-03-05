# Changelog

All notable changes to this project are documented in this file.

## [2.0.1] - 2026-03-05

### Fixed

- Resolved Luau `--!strict` diagnostics across the Butler API by tightening generic types and nullable connection handling (`Add`, `Set`, `Guard`, `Wrap`, `Construct`, `Once`, `Until`, and `ConnectMany`).
- Hardened cleanup behavior for threads and table-like objects by adding safe member access and a fallback close path when `task.cancel` cannot cancel a suspended thread.
- Improved teardown safety in `Remove` and `LinkToInstance` for edge cases where tracked entries or link connections may already be cleared.

### Changed

- Synced module and documentation version labels to `v2.0.1`.

## [2.0.0] - 2026-02-23

### Added

- Initial Butler release with core lifecycle tracking, scoped cleanup, async helpers, signal utilities, and comprehensive test and documentation coverage.
