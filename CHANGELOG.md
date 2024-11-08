# Changelog

## [2.1.0](https://github.com/akinsho/git-conflict.nvim/compare/v2.0.0...v2.1.0) (2024-11-08)


### Features

* add visual mode mappings ([#78](https://github.com/akinsho/git-conflict.nvim/issues/78)) ([888bc31](https://github.com/akinsho/git-conflict.nvim/commit/888bc31a41abf511ab8611b25c72d971faf18cc7))


### Bug Fixes

* windows path separator ([#93](https://github.com/akinsho/git-conflict.nvim/issues/93)) ([40ab009](https://github.com/akinsho/git-conflict.nvim/commit/40ab0095dcce61435128b5f3905664382b1c7e32))

## [2.0.0](https://github.com/akinsho/git-conflict.nvim/compare/v1.3.0...v2.0.0) (2024-06-03)


### ⚠ BREAKING CHANGES

* **mapping:** swap prev and next mapping for conflicts ([#89](https://github.com/akinsho/git-conflict.nvim/issues/89))

### Features

* add support for git worktrees ([#81](https://github.com/akinsho/git-conflict.nvim/issues/81)) ([1371080](https://github.com/akinsho/git-conflict.nvim/commit/13710803346cfe468ce7be250d19c430866ba1bd))


### Bug Fixes

* extmarks missing from final line ([#87](https://github.com/akinsho/git-conflict.nvim/issues/87)) ([96458b8](https://github.com/akinsho/git-conflict.nvim/commit/96458b843795c6dd84f221188cccd3242328349e))
* **mapping:** swap prev and next mapping for conflicts ([#89](https://github.com/akinsho/git-conflict.nvim/issues/89)) ([c57bbf0](https://github.com/akinsho/git-conflict.nvim/commit/c57bbf09e36e967272d60899113ac308ee55d2cd))
* off-by-one error in find_position ([#86](https://github.com/akinsho/git-conflict.nvim/issues/86)) ([4ff00ae](https://github.com/akinsho/git-conflict.nvim/commit/4ff00aed1ef47d9b7ab16ca62563089c15723b14))

## [1.3.0](https://github.com/akinsho/git-conflict.nvim/compare/v1.2.2...v1.3.0) (2024-01-22)


### Features

* **api:** add conflict_count function ([#75](https://github.com/akinsho/git-conflict.nvim/issues/75)) ([599d380](https://github.com/akinsho/git-conflict.nvim/commit/599d3809ea3bf1ef26c8368bfc74c50c44f39913))

## [1.2.2](https://github.com/akinsho/git-conflict.nvim/compare/v1.2.1...v1.2.2) (2023-09-17)


### Bug Fixes

* **quickfix:** invoke callback once with all items ([#70](https://github.com/akinsho/git-conflict.nvim/issues/70)) ([a97a355](https://github.com/akinsho/git-conflict.nvim/commit/a97a35507a485d6bbdc3c67820a8ca459c9c3f49))

## [1.2.1](https://github.com/akinsho/git-conflict.nvim/compare/v1.2.0...v1.2.1) (2023-08-31)


### Bug Fixes

* **mappings:** set mappings if needed when parsing buffer ([#66](https://github.com/akinsho/git-conflict.nvim/issues/66)) ([b1c1274](https://github.com/akinsho/git-conflict.nvim/commit/b1c1274873f0b9a1b8da7eac62bb74c9266d4410))
* **quickfix cmd:** construct items from visited buffers ([#68](https://github.com/akinsho/git-conflict.nvim/issues/68)) ([cee519e](https://github.com/akinsho/git-conflict.nvim/commit/cee519ef0482b20e506ae1401f82f3c7b23a6c03))

## [1.2.0](https://github.com/akinsho/git-conflict.nvim/compare/v1.1.2...v1.2.0) (2023-08-21)


### Features

* Add a list_opener setting ([#63](https://github.com/akinsho/git-conflict.nvim/issues/63)) ([1e74b7d](https://github.com/akinsho/git-conflict.nvim/commit/1e74b7dd6c1b4c6750e6f917f91012c450aece86))


### Bug Fixes

* use a list for jobstart [#58](https://github.com/akinsho/git-conflict.nvim/issues/58) ([#59](https://github.com/akinsho/git-conflict.nvim/issues/59)) ([751d98b](https://github.com/akinsho/git-conflict.nvim/commit/751d98be83a9c7bdf0a136d05d8b7b1c25560368))

## [1.1.2](https://github.com/akinsho/git-conflict.nvim/compare/v1.1.1...v1.1.2) (2023-04-26)


### Bug Fixes

* highlights should be default ([75e9056](https://github.com/akinsho/git-conflict.nvim/commit/75e90560521e5e395452e9a9f36309ae8f6000a7))

## [1.1.1](https://github.com/akinsho/git-conflict.nvim/compare/v1.1.0...v1.1.1) (2023-04-26)


### Bug Fixes

* check buffer is valid before using it ([e41555b](https://github.com/akinsho/git-conflict.nvim/commit/e41555bf0be8a06589b5a7598220e33962333feb)), closes [#50](https://github.com/akinsho/git-conflict.nvim/issues/50)

## [1.1.0](https://github.com/akinsho/git-conflict.nvim/compare/v1.0.0...v1.1.0) (2023-04-18)


### Features

* add option to disable commands ([#35](https://github.com/akinsho/git-conflict.nvim/issues/35)) ([77faa75](https://github.com/akinsho/git-conflict.nvim/commit/77faa75c09a6af88e7b54d8d456327e06611f7ea))
* user mappings config ([#42](https://github.com/akinsho/git-conflict.nvim/issues/42)) ([c92604a](https://github.com/akinsho/git-conflict.nvim/commit/c92604a64a2cce15a6e6a753f4501bcee06fa00a))


### Bug Fixes

* **color:** reset the color after colorscheme was changed ([#39](https://github.com/akinsho/git-conflict.nvim/issues/39)) ([#40](https://github.com/akinsho/git-conflict.nvim/issues/40)) ([cbefa70](https://github.com/akinsho/git-conflict.nvim/commit/cbefa7075b67903ca27f6eefdc9c1bf0c4881017))
* ensure valid value is passed when opening QF ([2957f74](https://github.com/akinsho/git-conflict.nvim/commit/2957f747e1a34f1854e4e0efbfbfa59a1db04af5))
