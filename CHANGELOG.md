# Changelog

## [1.67.0](https://github.com/JacobPEvans/nix-ai/compare/v1.66.1...v1.67.0) (2026-05-21)


### Features

* **claude:** enable Anthropic frontend / design skill plugins ([#815](https://github.com/JacobPEvans/nix-ai/issues/815)) ([e2239bb](https://github.com/JacobPEvans/nix-ai/commit/e2239bb05cef0bfed7de9efea0db5f4a8085dee4))

## [1.66.1](https://github.com/JacobPEvans/nix-ai/compare/v1.66.0...v1.66.1) (2026-05-20)


### Bug Fixes

* **security:** add osv-scanner.toml with tracked unfixable-vuln ignores ([#813](https://github.com/JacobPEvans/nix-ai/issues/813)) ([ee9cef9](https://github.com/JacobPEvans/nix-ai/commit/ee9cef989e2f04e8694fcdab3012c276e518a4f0))

## [1.66.0](https://github.com/JacobPEvans/nix-ai/compare/v1.65.4...v1.66.0) (2026-05-19)


### Features

* **mlx:** pull llama-swap from nixpkgs-unstable ([#809](https://github.com/JacobPEvans/nix-ai/issues/809)) ([6161fa0](https://github.com/JacobPEvans/nix-ai/commit/6161fa0a658876cfbfd34f053d180ce26ab2e9eb)), closes [#801](https://github.com/JacobPEvans/nix-ai/issues/801)


### Bug Fixes

* **automation:** restore Mon+Thu lockFileMaintenance, fix renovate branch listener, drop dead palMcpServer pin ([#802](https://github.com/JacobPEvans/nix-ai/issues/802)) ([33380ea](https://github.com/JacobPEvans/nix-ai/commit/33380ea81a4de705f693ff90b417cedcf73753c2))

## [1.65.4](https://github.com/JacobPEvans/nix-ai/compare/v1.65.3...v1.65.4) (2026-05-19)


### Bug Fixes

* **mlx:** enforce loop-prevention penalties via llama-swap setParams ([#797](https://github.com/JacobPEvans/nix-ai/issues/797)) ([222ad24](https://github.com/JacobPEvans/nix-ai/commit/222ad2444091c28012fd73e9827bc276762b7303))

## [1.65.3](https://github.com/JacobPEvans/nix-ai/compare/v1.65.2...v1.65.3) (2026-05-19)


### Bug Fixes

* **cecli:** refresh cecli_dev 0.99.12 source hash after upstream republish ([b78addc](https://github.com/JacobPEvans/nix-ai/commit/b78addc61ecc019de18cb32c7c1eb9cba0945722))

## [1.65.2](https://github.com/JacobPEvans/nix-ai/compare/v1.65.1...v1.65.2) (2026-05-19)


### Bug Fixes

* **mlx:** add proxy.concurrencyLimit option (default 4) to bound runaway clients ([6e68d48](https://github.com/JacobPEvans/nix-ai/commit/6e68d486a047bc4a42959d7a7ea8d94a8beecccf))

## [1.65.1](https://github.com/JacobPEvans/nix-ai/compare/v1.65.0...v1.65.1) (2026-05-18)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#792](https://github.com/JacobPEvans/nix-ai/issues/792)) ([5b2200b](https://github.com/JacobPEvans/nix-ai/commit/5b2200bf23f87027e1044ec8ada9c5b3817e5f19))

## [1.65.0](https://github.com/JacobPEvans/nix-ai/compare/v1.64.12...v1.65.0) (2026-05-15)


### Features

* **ci:** migrate Linux CI to self-hosted RunsOn runners ([#783](https://github.com/JacobPEvans/nix-ai/issues/783)) ([8858a94](https://github.com/JacobPEvans/nix-ai/commit/8858a94adcfd7c06a08ddd84a3dee4db8b68161f))

## [1.64.12](https://github.com/JacobPEvans/nix-ai/compare/v1.64.11...v1.64.12) (2026-05-15)


### Bug Fixes

* **fabric:** update vendorHash for nixpkgs-25.11 Go toolchain ([#780](https://github.com/JacobPEvans/nix-ai/issues/780)) ([31bfd7f](https://github.com/JacobPEvans/nix-ai/commit/31bfd7f733084edee6c80addd0e2790657a311e1))

## [1.64.11](https://github.com/JacobPEvans/nix-ai/compare/v1.64.10...v1.64.11) (2026-05-15)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#781](https://github.com/JacobPEvans/nix-ai/issues/781)) ([b21b766](https://github.com/JacobPEvans/nix-ai/commit/b21b7663d914e41571a495c6148c1ceec45d2136))

## [1.64.10](https://github.com/JacobPEvans/nix-ai/compare/v1.64.9...v1.64.10) (2026-05-15)


### Bug Fixes

* **cecli:** correct hashes and automate nix-update on Renovate pushes ([#778](https://github.com/JacobPEvans/nix-ai/issues/778)) ([e805936](https://github.com/JacobPEvans/nix-ai/commit/e80593664b8c4436a13b50b47839063b1ef03637))

## [1.64.9](https://github.com/JacobPEvans/nix-ai/compare/v1.64.8...v1.64.9) (2026-05-14)


### Bug Fixes

* **flake:** scope checks to x86_64-linux; restore --all-systems default ([#774](https://github.com/JacobPEvans/nix-ai/issues/774)) ([18b1229](https://github.com/JacobPEvans/nix-ai/commit/18b12299407bab7b817470bf6fc8255c8651e56e))

## [1.64.8](https://github.com/JacobPEvans/nix-ai/compare/v1.64.7...v1.64.8) (2026-05-14)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#765](https://github.com/JacobPEvans/nix-ai/issues/765)) ([3a77581](https://github.com/JacobPEvans/nix-ai/commit/3a77581f46c70de2947cd21c7011e9b726e2ce11))

## [1.64.7](https://github.com/JacobPEvans/nix-ai/compare/v1.64.6...v1.64.7) (2026-05-12)


### Bug Fixes

* **mlx:** pin mlx==0.31.1 + mlx-lm==0.31.2 to restore inference ([#756](https://github.com/JacobPEvans/nix-ai/issues/756)) ([2934e52](https://github.com/JacobPEvans/nix-ai/commit/2934e52e2eae5b7f8c4d281ae0c58ba4d1d289c1))

## [1.64.6](https://github.com/JacobPEvans/nix-ai/compare/v1.64.5...v1.64.6) (2026-05-12)


### Bug Fixes

* **mlx:** query /running for load state, not /v1/models[0] ([#752](https://github.com/JacobPEvans/nix-ai/issues/752)) ([0c4236d](https://github.com/JacobPEvans/nix-ai/commit/0c4236dca8bbe7fed82d32abb8509e81a2d50b34))

## [1.64.5](https://github.com/JacobPEvans/nix-ai/compare/v1.64.4...v1.64.5) (2026-05-11)


### Bug Fixes

* **ci:** opt out of --all-systems for nix-validate ([#754](https://github.com/JacobPEvans/nix-ai/issues/754)) ([8a6493c](https://github.com/JacobPEvans/nix-ai/commit/8a6493cdb9ee4614fdb6af95270e25632904067b))

## [1.64.4](https://github.com/JacobPEvans/nix-ai/compare/v1.64.3...v1.64.4) (2026-05-11)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#745](https://github.com/JacobPEvans/nix-ai/issues/745)) ([2cb4fa6](https://github.com/JacobPEvans/nix-ai/commit/2cb4fa6507263a7dda477d5e8c114b5e7c70c514))

## [1.64.3](https://github.com/JacobPEvans/nix-ai/compare/v1.64.2...v1.64.3) (2026-05-07)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#732](https://github.com/JacobPEvans/nix-ai/issues/732)) ([06be494](https://github.com/JacobPEvans/nix-ai/commit/06be4945c1b223c8d229e782c8e9480399e5dfb9))

## [1.64.2](https://github.com/JacobPEvans/nix-ai/compare/v1.64.1...v1.64.2) (2026-05-07)


### Bug Fixes

* **claude,cecli:** eliminate Python env conflicts in home-manager buildEnv ([#729](https://github.com/JacobPEvans/nix-ai/issues/729)) ([9703230](https://github.com/JacobPEvans/nix-ai/commit/97032307320d1e3b051948e495bb67bd60489e67))

## [1.64.1](https://github.com/JacobPEvans/nix-ai/compare/v1.64.0...v1.64.1) (2026-05-07)


### Bug Fixes

* **flake:** replace prev.system with prev.stdenv.hostPlatform.system ([#728](https://github.com/JacobPEvans/nix-ai/issues/728)) ([a186a52](https://github.com/JacobPEvans/nix-ai/commit/a186a5263f033a399c1dd1bc1d5f873130c41f0a))

## [1.64.0](https://github.com/JacobPEvans/nix-ai/compare/v1.63.0...v1.64.0) (2026-05-07)


### Features

* **flake:** export overlays.default for downstream consumers ([#726](https://github.com/JacobPEvans/nix-ai/issues/726)) ([ba9b464](https://github.com/JacobPEvans/nix-ai/commit/ba9b4644f38191474bf17a9491572ed760919c0c))

## [1.63.0](https://github.com/JacobPEvans/nix-ai/compare/v1.62.2...v1.63.0) (2026-05-06)


### Features

* **ai-stack:** central registry, cecli, and Qwen Code module ([#719](https://github.com/JacobPEvans/nix-ai/issues/719)) ([542c262](https://github.com/JacobPEvans/nix-ai/commit/542c262ed8d4999e6118ff89d3960f3e515db2b3))

## [1.62.2](https://github.com/JacobPEvans/nix-ai/compare/v1.62.1...v1.62.2) (2026-05-06)


### Bug Fixes

* **claude:** scope project plugins per-repo + raise skill listing budget ([#721](https://github.com/JacobPEvans/nix-ai/issues/721)) ([e020c0c](https://github.com/JacobPEvans/nix-ai/commit/e020c0c43e87c5eb40bb297de7f4ec0fc968053b))

## [1.62.1](https://github.com/JacobPEvans/nix-ai/compare/v1.62.0...v1.62.1) (2026-05-04)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#711](https://github.com/JacobPEvans/nix-ai/issues/711)) ([67c91df](https://github.com/JacobPEvans/nix-ai/commit/67c91dfbe256acae7940af0a79069de69735667a))

## [1.62.0](https://github.com/JacobPEvans/nix-ai/compare/v1.61.0...v1.62.0) (2026-05-03)


### Features

* **ai-stack:** export aiStackModels as flake output ([#698](https://github.com/JacobPEvans/nix-ai/issues/698)) ([7121d7d](https://github.com/JacobPEvans/nix-ai/commit/7121d7d8a6c131f784d66b74eaa22107f35a6039))
* **aider:** add home-manager module with MLX routing ([#699](https://github.com/JacobPEvans/nix-ai/issues/699)) ([670b29d](https://github.com/JacobPEvans/nix-ai/commit/670b29df6a07351f41097fc0ab4d33ed8f04f5c0))

## [1.61.0](https://github.com/JacobPEvans/nix-ai/compare/v1.60.1...v1.61.0) (2026-05-03)


### Features

* **gemini:** add defaultModel and gemmaModelRouter options ([#700](https://github.com/JacobPEvans/nix-ai/issues/700)) ([9eaff06](https://github.com/JacobPEvans/nix-ai/commit/9eaff06b4e82eb255d4c088baf2d08a4190b4d78))

## [1.60.1](https://github.com/JacobPEvans/nix-ai/compare/v1.60.0...v1.60.1) (2026-05-03)


### Bug Fixes

* **claude:** remove auto-claude orchestrator ([#697](https://github.com/JacobPEvans/nix-ai/issues/697)) ([6fb3d00](https://github.com/JacobPEvans/nix-ai/commit/6fb3d00fd2d6616bcce5803e7979e958e31e4f34))

## [1.60.0](https://github.com/JacobPEvans/nix-ai/compare/v1.59.0...v1.60.0) (2026-05-03)


### Features

* **claude:** migrate statusline from daniel3303 fork to ccstatusline ([#690](https://github.com/JacobPEvans/nix-ai/issues/690)) ([9a392d7](https://github.com/JacobPEvans/nix-ai/commit/9a392d70362dcfaa60951cefee6b5aae8fdccda3))

## [1.59.0](https://github.com/JacobPEvans/nix-ai/compare/v1.58.6...v1.59.0) (2026-05-03)


### Features

* **mlx:** rewrite alias→physical via llama-swap useModelName ([#686](https://github.com/JacobPEvans/nix-ai/issues/686)) ([6b42fd2](https://github.com/JacobPEvans/nix-ai/commit/6b42fd202652c669a7b252899b2432f4f08e2751))

## [1.58.6](https://github.com/JacobPEvans/nix-ai/compare/v1.58.5...v1.58.6) (2026-05-03)


### Bug Fixes

* **mlx:** write seed-config target with user-writable mode ([#685](https://github.com/JacobPEvans/nix-ai/issues/685)) ([163bd17](https://github.com/JacobPEvans/nix-ai/commit/163bd173354b0ca5e9585fea0e63707037e197d0))

## [1.58.5](https://github.com/JacobPEvans/nix-ai/compare/v1.58.4...v1.58.5) (2026-05-03)


### Bug Fixes

* **mlx:** correct vllm-mlx 0.2.9 prefix-cache flag names ([#683](https://github.com/JacobPEvans/nix-ai/issues/683)) ([dbd0ae8](https://github.com/JacobPEvans/nix-ai/commit/dbd0ae820244c94d0ec48a149b1345ed8d1efb11))
* **mlx:** fix discover-models memory query, sysctl path, and vllm-mlx 0.2.9 flag names ([#684](https://github.com/JacobPEvans/nix-ai/issues/684)) ([db66230](https://github.com/JacobPEvans/nix-ai/commit/db662308c7016e1c640a6f711472d5b55c89c043))

## [1.58.4](https://github.com/JacobPEvans/nix-ai/compare/v1.58.3...v1.58.4) (2026-05-02)


### Bug Fixes

* **claude:** :fire: remove runtimeCleanup activation hook ([#681](https://github.com/JacobPEvans/nix-ai/issues/681)) ([745f9e3](https://github.com/JacobPEvans/nix-ai/commit/745f9e3ae723415ed88b3113f823f5ab2d276ab1))
* **mlx:** resolve role aliases in discover-models preload lookup ([#682](https://github.com/JacobPEvans/nix-ai/issues/682)) ([c0fe4cf](https://github.com/JacobPEvans/nix-ai/commit/c0fe4cffd38c501e92c926df0dd0094eb4c3154c))

## [1.58.3](https://github.com/JacobPEvans/nix-ai/compare/v1.58.2...v1.58.3) (2026-05-02)


### Bug Fixes

* centralize agent skills and MCP config ([#662](https://github.com/JacobPEvans/nix-ai/issues/662)) ([ca350e5](https://github.com/JacobPEvans/nix-ai/commit/ca350e5d7f0c85a616b31cae578192f15cfa623e))

## [1.58.2](https://github.com/JacobPEvans/nix-ai/compare/v1.58.1...v1.58.2) (2026-05-01)


### Bug Fixes

* switch Claude commit attribution to Linux Assisted-by format ([#585](https://github.com/JacobPEvans/nix-ai/issues/585)) [issue-solver-2026-04-29] ([#663](https://github.com/JacobPEvans/nix-ai/issues/663)) ([00fdd11](https://github.com/JacobPEvans/nix-ai/commit/00fdd11f301b8d879e2eaf2e14b675e3d4fd4ddb))

## [1.58.1](https://github.com/JacobPEvans/nix-ai/compare/v1.58.0...v1.58.1) (2026-05-01)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#675](https://github.com/JacobPEvans/nix-ai/issues/675)) ([fe00fa0](https://github.com/JacobPEvans/nix-ai/commit/fe00fa065c50e37ada1bc5e996efc5489ec712e4))

## [1.58.0](https://github.com/JacobPEvans/nix-ai/compare/v1.57.0...v1.58.0) (2026-04-29)


### Features

* **mlx:** :sparkles: bump vllm-mlx 0.2.6 → 0.2.9 with prefix caching ([#665](https://github.com/JacobPEvans/nix-ai/issues/665)) ([86245e0](https://github.com/JacobPEvans/nix-ai/commit/86245e06699310dd4e096ce5403d7b468ebc71cb))

## [1.57.0](https://github.com/JacobPEvans/nix-ai/compare/v1.56.1...v1.57.0) (2026-04-29)


### Features

* **mcp:** self-contained sub-flake + lib.aiCommon for cross-flake consumption ([#643](https://github.com/JacobPEvans/nix-ai/issues/643)) ([52aae1d](https://github.com/JacobPEvans/nix-ai/commit/52aae1d98505614bdea11daf0b7cd5818e9fde33))

## [1.56.1](https://github.com/JacobPEvans/nix-ai/compare/v1.56.0...v1.56.1) (2026-04-29)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#657](https://github.com/JacobPEvans/nix-ai/issues/657)) ([a0caa88](https://github.com/JacobPEvans/nix-ai/commit/a0caa8821000ac321739bb941193163441aa0b77))

## [1.56.0](https://github.com/JacobPEvans/nix-ai/compare/v1.55.0...v1.56.0) (2026-04-26)


### Features

* **plugins:** add huggingface/skills marketplace with hf-cli ([06c4d2b](https://github.com/JacobPEvans/nix-ai/commit/06c4d2b76ecbcdb3529049c4962dc36dc5ba1251))

## [1.55.0](https://github.com/JacobPEvans/nix-ai/compare/v1.54.4...v1.55.0) (2026-04-26)


### Features

* **mlx:** auto-discover HF models on every darwin-rebuild switch ([de6b51f](https://github.com/JacobPEvans/nix-ai/commit/de6b51f689c5ceecf6537c8f9304d1a9134fdc39))

## [1.54.4](https://github.com/JacobPEvans/nix-ai/compare/v1.54.3...v1.54.4) (2026-04-26)


### Bug Fixes

* **plugins:** remove ralph-loop plugin references ([#644](https://github.com/JacobPEvans/nix-ai/issues/644)) ([0370d5e](https://github.com/JacobPEvans/nix-ai/commit/0370d5e42e8a9e1b95b87437ef9a2b01cd6b4270))

## [1.54.3](https://github.com/JacobPEvans/nix-ai/compare/v1.54.2...v1.54.3) (2026-04-25)


### Bug Fixes

* **claude:** guarantee knownMarketplacesMerge runs before install activations ([d7890ef](https://github.com/JacobPEvans/nix-ai/commit/d7890eff7f636b1f009dba6726365a8c877769f3))

## [1.54.2](https://github.com/JacobPEvans/nix-ai/compare/v1.54.1...v1.54.2) (2026-04-25)


### Bug Fixes

* **ci:** app-id → client-id deprecation + renovate.json5 rename ([#634](https://github.com/JacobPEvans/nix-ai/issues/634)) ([58b75c6](https://github.com/JacobPEvans/nix-ai/commit/58b75c60488a5bfc1a4cb29d193c27d00285839b))

## [1.54.1](https://github.com/JacobPEvans/nix-ai/compare/v1.54.0...v1.54.1) (2026-04-25)


### Bug Fixes

* convert assignment to `inherit (cfg) worktrees`. ([b668877](https://github.com/JacobPEvans/nix-ai/commit/b66887797ac79d5839f5b09de7a6b8b6dc0d5360))
* **gemini:** document worktree location quirk, keep feature enabled ([b668877](https://github.com/JacobPEvans/nix-ai/commit/b66887797ac79d5839f5b09de7a6b8b6dc0d5360))

## [1.54.0](https://github.com/JacobPEvans/nix-ai/compare/v1.53.0...v1.54.0) (2026-04-25)


### Features

* **plugins:** add VisiCore cribl-pack-validator skill (Claude+Codex+Gemini) ([#630](https://github.com/JacobPEvans/nix-ai/issues/630)) ([466fd1d](https://github.com/JacobPEvans/nix-ai/commit/466fd1d9721d856c5d0fce27ae1eb94df8d3b763))

## [1.53.0](https://github.com/JacobPEvans/nix-ai/compare/v1.52.0...v1.53.0) (2026-04-25)


### Features

* **routines:** add routines module with permission-sync Gemini task ([#588](https://github.com/JacobPEvans/nix-ai/issues/588)) ([82388a1](https://github.com/JacobPEvans/nix-ai/commit/82388a1b1f6cb835e0ff1511beb832cd90367fb8))

## [1.52.0](https://github.com/JacobPEvans/nix-ai/compare/v1.51.0...v1.52.0) (2026-04-24)


### Features

* **gemini:** default sandboxAllowedPaths to ~/git ([#628](https://github.com/JacobPEvans/nix-ai/issues/628)) ([ae043cf](https://github.com/JacobPEvans/nix-ai/commit/ae043cfeaa586dfb72134478a85765541a5c2dd3))

## [1.51.0](https://github.com/JacobPEvans/nix-ai/compare/v1.50.1...v1.51.0) (2026-04-24)


### Features

* **claude:** bump effort to high, add claude-latest install, centralize AI aliases ([#619](https://github.com/JacobPEvans/nix-ai/issues/619)) ([d68bac6](https://github.com/JacobPEvans/nix-ai/commit/d68bac6970944471f735b2a543016906529ed2a5))

## [1.50.1](https://github.com/JacobPEvans/nix-ai/compare/v1.50.0...v1.50.1) (2026-04-24)


### Bug Fixes

* **codex:** tighten default approvalPolicy to untrusted ([#609](https://github.com/JacobPEvans/nix-ai/issues/609)) ([bd91928](https://github.com/JacobPEvans/nix-ai/commit/bd919284f9d1a7857f80ba51f08c352ce87e5d1d))

## [1.50.0](https://github.com/JacobPEvans/nix-ai/compare/v1.49.0...v1.50.0) (2026-04-24)


### Features

* **gemini:** support custom sandbox profile path ([#615](https://github.com/JacobPEvans/nix-ai/issues/615)) ([7b3a661](https://github.com/JacobPEvans/nix-ai/commit/7b3a661ab35fa6237882bde2448ac40b19dfcaf1))

## [1.49.0](https://github.com/JacobPEvans/nix-ai/compare/v1.48.6...v1.49.0) (2026-04-24)


### Features

* centralize shared skills in agent-skills module ([#612](https://github.com/JacobPEvans/nix-ai/issues/612)) ([955eda6](https://github.com/JacobPEvans/nix-ai/commit/955eda6a22722fdc17eb1154abcc527167cd8adb))

## [1.48.6](https://github.com/JacobPEvans/nix-ai/compare/v1.48.5...v1.48.6) (2026-04-24)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#618](https://github.com/JacobPEvans/nix-ai/issues/618)) ([d9e402f](https://github.com/JacobPEvans/nix-ai/commit/d9e402fb1d49bb19aae4f529547fc376cfe6b4a5))

## [1.48.5](https://github.com/JacobPEvans/nix-ai/compare/v1.48.4...v1.48.5) (2026-04-22)


### Bug Fixes

* **mlx:** cap uncapped local generations ([#596](https://github.com/JacobPEvans/nix-ai/issues/596)) ([33430f7](https://github.com/JacobPEvans/nix-ai/commit/33430f72b1de33e6f19fcc0c137e2db2a22cffd6))

## [1.48.4](https://github.com/JacobPEvans/nix-ai/compare/v1.48.3...v1.48.4) (2026-04-22)


### Bug Fixes

* **claude:** automate marketplace cache refresh after Nix rebuilds ([#611](https://github.com/JacobPEvans/nix-ai/issues/611)) ([472e886](https://github.com/JacobPEvans/nix-ai/commit/472e88660a1d0ecb479e4c34f4583589d3590701))

## [1.48.3](https://github.com/JacobPEvans/nix-ai/compare/v1.48.2...v1.48.3) (2026-04-21)


### Bug Fixes

* **mlx:** bump defaultModel to Qwen3.6-35B-A3B-mxfp4 ([#606](https://github.com/JacobPEvans/nix-ai/issues/606)) ([fed7bc0](https://github.com/JacobPEvans/nix-ai/commit/fed7bc005a1ca197a5bc4ae037baa13438160024))

## [1.48.2](https://github.com/JacobPEvans/nix-ai/compare/v1.48.1...v1.48.2) (2026-04-21)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([9f5e27a](https://github.com/JacobPEvans/nix-ai/commit/9f5e27a4363fe79573e9ad342fee4d79c9b334c5))

## [1.48.1](https://github.com/JacobPEvans/nix-ai/compare/v1.48.0...v1.48.1) (2026-04-21)


### Bug Fixes

* **ci:** add gh-aw-pin-refresh workflow and recompile lock files ([5515e5d](https://github.com/JacobPEvans/nix-ai/commit/5515e5d0dc60b9abb8e8129bdb90d647f7951325)), closes [#600](https://github.com/JacobPEvans/nix-ai/issues/600)

## [1.48.0](https://github.com/JacobPEvans/nix-ai/compare/v1.47.0...v1.48.0) (2026-04-21)


### Features

* **gemini:** add worktree, sandbox path, and auto-edit defaults ([#597](https://github.com/JacobPEvans/nix-ai/issues/597)) ([9e29a07](https://github.com/JacobPEvans/nix-ai/commit/9e29a07ecb19bd0cb400ea58d911bf4b933f8bd7))


### Bug Fixes

* add bot PR CI retrigger workflow ([#599](https://github.com/JacobPEvans/nix-ai/issues/599)) ([ce38b8b](https://github.com/JacobPEvans/nix-ai/commit/ce38b8b6b24d4e7d82fbc7c926796ff5bdfff7e0))

## [1.47.0](https://github.com/JacobPEvans/nix-ai/compare/v1.46.1...v1.47.0) (2026-04-19)


### Features

* **mlx:** expose llama-swap logLevel and logToStdout as configurable options ([#587](https://github.com/JacobPEvans/nix-ai/issues/587)) ([c1102df](https://github.com/JacobPEvans/nix-ai/commit/c1102df3776c271e4193c579fe4b01ffdca38e50))

## [1.46.1](https://github.com/JacobPEvans/nix-ai/compare/v1.46.0...v1.46.1) (2026-04-18)


### Bug Fixes

* **claude:** run conflicting-dir cleanup before checkLinkTargets ([#582](https://github.com/JacobPEvans/nix-ai/issues/582)) ([3fb42b4](https://github.com/JacobPEvans/nix-ai/commit/3fb42b45e5c18d2addffb5cf99fc8dec6810351f))

## [1.46.0](https://github.com/JacobPEvans/nix-ai/compare/v1.45.5...v1.46.0) (2026-04-18)


### Features

* **cross-tool:** wire shared skills to Codex and Gemini, fix stale MCP keys ([c63a358](https://github.com/JacobPEvans/nix-ai/commit/c63a358b6f8c843774001ad96ec673187ce6e7dd))

## [1.45.5](https://github.com/JacobPEvans/nix-ai/compare/v1.45.4...v1.45.5) (2026-04-18)


### Bug Fixes

* **permissions:** simplify deny rules for auto mode ([#576](https://github.com/JacobPEvans/nix-ai/issues/576)) ([6909691](https://github.com/JacobPEvans/nix-ai/commit/6909691cb484a227903226b23559dc4d9211afa7))

## [1.45.4](https://github.com/JacobPEvans/nix-ai/compare/v1.45.3...v1.45.4) (2026-04-18)


### Bug Fixes

* **pal:** correct custom_models.json field names and alias collisions ([#575](https://github.com/JacobPEvans/nix-ai/issues/575)) ([068f418](https://github.com/JacobPEvans/nix-ai/commit/068f418bcf26cced99242b25a6baaec45158f100))

## [1.45.3](https://github.com/JacobPEvans/nix-ai/compare/v1.45.2...v1.45.3) (2026-04-17)


### Bug Fixes

* **mcp:** env vars, wrappers, tool restoration ([#563](https://github.com/JacobPEvans/nix-ai/issues/563)) ([68ce7fc](https://github.com/JacobPEvans/nix-ai/commit/68ce7fc6f3173e775e0da92d8c801811a9277bda))

## [1.45.2](https://github.com/JacobPEvans/nix-ai/compare/v1.45.1...v1.45.2) (2026-04-17)


### Bug Fixes

* **claude:** add /tmp/ to additionalDirectories ([#571](https://github.com/JacobPEvans/nix-ai/issues/571)) ([bb6fef9](https://github.com/JacobPEvans/nix-ai/commit/bb6fef9ff1c1371b5539d61b946885dfbddba07c))

## [1.45.1](https://github.com/JacobPEvans/nix-ai/compare/v1.45.0...v1.45.1) (2026-04-17)


### Bug Fixes

* **claude:** narrow additionalDirectories, DRY the list, add retrospecting/reports ([#567](https://github.com/JacobPEvans/nix-ai/issues/567)) ([2d0dae7](https://github.com/JacobPEvans/nix-ai/commit/2d0dae78139903016272b25bc6eae63b16f1fbd1))

## [1.45.0](https://github.com/JacobPEvans/nix-ai/compare/v1.44.1...v1.45.0) (2026-04-17)


### Features

* **claude:** enable auto mode by default ([#564](https://github.com/JacobPEvans/nix-ai/issues/564)) ([f54be3d](https://github.com/JacobPEvans/nix-ai/commit/f54be3d8c5242cdce2adb13c9e864bbdbfe5fa05))

## [1.44.1](https://github.com/JacobPEvans/nix-ai/compare/v1.44.0...v1.44.1) (2026-04-17)


### Bug Fixes

* **pal-mcp:** use mlx-local/ provider prefix for Bifrost routing ([#565](https://github.com/JacobPEvans/nix-ai/issues/565)) ([f818d9a](https://github.com/JacobPEvans/nix-ai/commit/f818d9ac2a4ce0a612951b3c8615f000535e3024))

## [1.44.0](https://github.com/JacobPEvans/nix-ai/compare/v1.43.5...v1.44.0) (2026-04-17)


### Features

* **codex:** add config surface with 8 knobs ([#549](https://github.com/JacobPEvans/nix-ai/issues/549)) ([79070c5](https://github.com/JacobPEvans/nix-ai/commit/79070c53bb66aad08ee3dc5fde836df9a5896f17))

## [1.43.5](https://github.com/JacobPEvans/nix-ai/compare/v1.43.4...v1.43.5) (2026-04-17)


### Bug Fixes

* **pal-mcp:** env var injection and restore disabled tools ([#559](https://github.com/JacobPEvans/nix-ai/issues/559)) ([a1829f8](https://github.com/JacobPEvans/nix-ai/commit/a1829f8890c973ce44c1c702d6850a5ce2ca980f))

## [1.43.4](https://github.com/JacobPEvans/nix-ai/compare/v1.43.3...v1.43.4) (2026-04-16)


### Bug Fixes

* **claude:** update model references from Opus 4.6 to Opus 4.7 ([#556](https://github.com/JacobPEvans/nix-ai/issues/556)) ([d526bbb](https://github.com/JacobPEvans/nix-ai/commit/d526bbb0303453d93a788dfcb771a776ac50e8ff))

## [1.43.3](https://github.com/JacobPEvans/nix-ai/compare/v1.43.2...v1.43.3) (2026-04-14)


### Bug Fixes

* add automation bots to AI Moderator skip-bots ([#535](https://github.com/JacobPEvans/nix-ai/issues/535)) ([09cf37a](https://github.com/JacobPEvans/nix-ai/commit/09cf37aa40e5252f24c4437608aecffd03d3220b))

## [1.43.2](https://github.com/JacobPEvans/nix-ai/compare/v1.43.1...v1.43.2) (2026-04-13)


### Bug Fixes

* **gh-aw:** recompile workflows with v0.68.1, enable ai-ci auto-triggers ([786d881](https://github.com/JacobPEvans/nix-ai/commit/786d881252541b495724d4a9bcf445e79191b9c6)), closes [#508](https://github.com/JacobPEvans/nix-ai/issues/508)

## [1.43.1](https://github.com/JacobPEvans/nix-ai/compare/v1.43.0...v1.43.1) (2026-04-13)


### Bug Fixes

* relax codex default approvals ([#526](https://github.com/JacobPEvans/nix-ai/issues/526)) ([7fd2508](https://github.com/JacobPEvans/nix-ai/commit/7fd2508d703a98c287eec60a918d96e71660f92e))

## [1.43.0](https://github.com/JacobPEvans/nix-ai/compare/v1.42.2...v1.43.0) (2026-04-13)


### Features

* add AI merge gate ([#419](https://github.com/JacobPEvans/nix-ai/issues/419)) ([1791db9](https://github.com/JacobPEvans/nix-ai/commit/1791db99d7574dd7ee958507f12dad937c0a9d06))
* add browser-use skills via synthetic marketplace ([#319](https://github.com/JacobPEvans/nix-ai/issues/319)) ([c4315cb](https://github.com/JacobPEvans/nix-ai/commit/c4315cb05953f4380622e6d17db8a783f6bc1c44))
* add CI infrastructure ([#1](https://github.com/JacobPEvans/nix-ai/issues/1)) ([a251829](https://github.com/JacobPEvans/nix-ai/commit/a251829c405e1da283442cbebf2b0c19e8910b74))
* add daily repo health audit agentic workflow ([#137](https://github.com/JacobPEvans/nix-ai/issues/137)) ([daa4a0e](https://github.com/JacobPEvans/nix-ai/commit/daa4a0ea05d5a828034d24377f187273763aecf9))
* add devenv with ai-dev shell, convert mlx-server to devenv ([#158](https://github.com/JacobPEvans/nix-ai/issues/158)) ([0d1deb1](https://github.com/JacobPEvans/nix-ai/commit/0d1deb113464adb622186e08c4b95d3882db4c8f))
* add Google Workspace MCP server and gws CLI ([#269](https://github.com/JacobPEvans/nix-ai/issues/269)) ([e25cee2](https://github.com/JacobPEvans/nix-ai/commit/e25cee23ac306e9d9be82bab538cee3bb4add0da))
* add MIT license, workflows, renovate, and markdownlint standardization ([b592694](https://github.com/JacobPEvans/nix-ai/commit/b592694bd6bbfb8dba3d4cc67e4047053292fb00))
* add MLX inference server home-manager module ([#161](https://github.com/JacobPEvans/nix-ai/issues/161)) ([eb4e91f](https://github.com/JacobPEvans/nix-ai/commit/eb4e91ffa3a3a6113e59f57b4b4e5a9529943dc7))
* add orchestrator devShell with skill schema and semantic router ([de9826d](https://github.com/JacobPEvans/nix-ai/commit/de9826d463f7a950613c6470dbd21e85f9c26754))
* add release-please automation ([#96](https://github.com/JacobPEvans/nix-ai/issues/96)) ([06fa54a](https://github.com/JacobPEvans/nix-ai/commit/06fa54ae068b3b43df85755059080ece10a1d4fc))
* add scheduled AI workflow callers ([#113](https://github.com/JacobPEvans/nix-ai/issues/113)) ([475114a](https://github.com/JacobPEvans/nix-ai/commit/475114a1cbf0c52609e9a5199cc62154b334304a))
* add splunk-mcp-connect wrapper script ([#151](https://github.com/JacobPEvans/nix-ai/issues/151)) ([294abd1](https://github.com/JacobPEvans/nix-ai/commit/294abd13b211390518bd68a76166fbef1f78141f))
* add visual-explainer marketplace plugin ([#272](https://github.com/JacobPEvans/nix-ai/issues/272)) ([b7d5094](https://github.com/JacobPEvans/nix-ai/commit/b7d5094263702058059ed0a384ca5ea10335263b))
* **ai-tools:** add whisper-cpp and openai-whisper moved from nix-darwin ([#482](https://github.com/JacobPEvans/nix-ai/issues/482)) ([0077a28](https://github.com/JacobPEvans/nix-ai/commit/0077a287366daa7107e16cdfe2ca7280c023a8e7))
* auto-approve CLAUDE.md external imports via unified claude.json overlay ([#80](https://github.com/JacobPEvans/nix-ai/issues/80)) ([04d13e5](https://github.com/JacobPEvans/nix-ai/commit/04d13e5ab0ec1d449cfe1830cd41e0b5ca70a716))
* **benchmarks:** add MLX benchmark CI/CD system ([#306](https://github.com/JacobPEvans/nix-ai/issues/306)) ([46d5f7f](https://github.com/JacobPEvans/nix-ai/commit/46d5f7f579383c6e650f2a7ff43e6f1c8fab51c0))
* **ci:** add flake update workflow for upstream dispatch events ([#108](https://github.com/JacobPEvans/nix-ai/issues/108)) ([9e3e6d0](https://github.com/JacobPEvans/nix-ai/commit/9e3e6d00b83d802c60e5752294e8b2dd7e3022ca))
* **ci:** add trigger-nix-update workflow ([#82](https://github.com/JacobPEvans/nix-ai/issues/82)) ([b75ef8c](https://github.com/JacobPEvans/nix-ai/commit/b75ef8cff9517914ad521961f1ae2cf27f8f788b))
* **claude:** add overlayFiles option for marketplace plugins ([#388](https://github.com/JacobPEvans/nix-ai/issues/388)) ([ef96354](https://github.com/JacobPEvans/nix-ai/commit/ef963545391eac936e0b67b187c8883a11810a3e))
* **claude:** auto-discover global rules from flake inputs ([#413](https://github.com/JacobPEvans/nix-ai/issues/413)) ([3d6b324](https://github.com/JacobPEvans/nix-ai/commit/3d6b3243320cb7f12618a34cc42f7bf9ff89b8a5))
* **claude:** auto-generate marketplace.json for jacobpevans-cc-plugins ([#391](https://github.com/JacobPEvans/nix-ai/issues/391)) ([78b0e1d](https://github.com/JacobPEvans/nix-ai/commit/78b0e1d2bbba391b43c2c0e4f567655d9f83d1a5))
* **claude:** enable OTEL telemetry to OrbStack collector ([#496](https://github.com/JacobPEvans/nix-ai/issues/496)) ([b9129f2](https://github.com/JacobPEvans/nix-ai/commit/b9129f2d0c56d339dcd9c2152b50e203ef0931e4))
* **claude:** make effortLevel optional, add adaptive thinking env var ([#106](https://github.com/JacobPEvans/nix-ai/issues/106)) ([c26c599](https://github.com/JacobPEvans/nix-ai/commit/c26c599b19ef1d6a074689410e6cc33c4a893c8b))
* **claude:** make settings.json writable via activation-time merge ([#107](https://github.com/JacobPEvans/nix-ai/issues/107)) ([9af21f8](https://github.com/JacobPEvans/nix-ai/commit/9af21f8339078d0c69e3799bc0b32bf17ab596f9))
* **claude:** re-enable greptile plugin ([#81](https://github.com/JacobPEvans/nix-ai/issues/81)) ([8cb80c9](https://github.com/JacobPEvans/nix-ai/commit/8cb80c9895d582ff32cd3d026ef0e486bcca17ad))
* **codex,gemini:** expand modules to Claude-level feature parity ([72168b3](https://github.com/JacobPEvans/nix-ai/commit/72168b31b00836b196bbfd8a981caf633fb35097))
* **codex:** add native Codex configuration with writable config.toml ([8b4b088](https://github.com/JacobPEvans/nix-ai/commit/8b4b088076c1d7c6b730e8fe3a7c45899275658c))
* **codex:** add official OpenAI Codex plugin + MCP server ([#497](https://github.com/JacobPEvans/nix-ai/issues/497)) ([3ea8d5c](https://github.com/JacobPEvans/nix-ai/commit/3ea8d5c55cec87713ea754311df3935dcf63f8e6))
* **devenv:** add nixpkgs-python input and remove flake-level nixConfig ([#170](https://github.com/JacobPEvans/nix-ai/issues/170)) ([b80ceca](https://github.com/JacobPEvans/nix-ai/commit/b80ceca8a6a486877567a339bce8ab30fe57614b))
* disable automatic triggers on Claude-executing workflows ([ad7cef3](https://github.com/JacobPEvans/nix-ai/commit/ad7cef3bf6462486a2c2704697d5bd60fbfa0a59))
* enable 1M context window models in model picker ([#155](https://github.com/JacobPEvans/nix-ai/issues/155)) ([73ae890](https://github.com/JacobPEvans/nix-ai/commit/73ae890e1b872af01dedd7dcab38b24740dbb914))
* enable MLX inference server (vllm-mlx on port 11435) ([#229](https://github.com/JacobPEvans/nix-ai/issues/229)) ([b7b2a1b](https://github.com/JacobPEvans/nix-ai/commit/b7b2a1b7a977873d4557a6f7e9c8bfece61a213c))
* expose gh-aw package, fix PAL hash, add nix-update to flake workflow ([#131](https://github.com/JacobPEvans/nix-ai/issues/131)) ([f519f98](https://github.com/JacobPEvans/nix-ai/commit/f519f98f63061bf25921bdcf9bf9dc7d7db931e7))
* **fabric:** add zsh completions and AI tool decision tree ([28af185](https://github.com/JacobPEvans/nix-ai/commit/28af1856d02d23da1b33d090d5ebb681ab2cc8e4))
* **fabric:** integrate Daniel Miessler's Fabric framework ([d361940](https://github.com/JacobPEvans/nix-ai/commit/d361940c7a30ef2cc5ce03264d6a5005bea0059c))
* **gemini:** migrate to Policy Engine, drop deprecated tools.allowed/exclude ([#516](https://github.com/JacobPEvans/nix-ai/issues/516)) ([6df0934](https://github.com/JacobPEvans/nix-ai/commit/6df0934fd02d3643eed55abf153b9594bb6b23e8))
* initial nix-ai repository ([5a2273e](https://github.com/JacobPEvans/nix-ai/commit/5a2273efb075c03db1b9ec711e5d572c93139994))
* **mcp:** add Bifrost AI gateway MCP server and check-bifrost CLI ([#456](https://github.com/JacobPEvans/nix-ai/issues/456)) ([efc4501](https://github.com/JacobPEvans/nix-ai/commit/efc4501a39ffba2a78ea0f63e1f1744a4ffd811f))
* **mcp:** route PAL through Bifrost AI gateway ([#466](https://github.com/JacobPEvans/nix-ai/issues/466)) ([5b18711](https://github.com/JacobPEvans/nix-ai/commit/5b187116b4a177f2ba6abbd2b59a8e9302b62cee))
* migrate flake.lock updates to Renovate nix manager ([#169](https://github.com/JacobPEvans/nix-ai/issues/169)) ([5dbaf23](https://github.com/JacobPEvans/nix-ai/commit/5dbaf23e8bab84847e7ec64a0edf41b9178755ee))
* migrate to ai-workflows suite groupings (v0.8.0) ([#102](https://github.com/JacobPEvans/nix-ai/issues/102)) ([4b6b806](https://github.com/JacobPEvans/nix-ai/commit/4b6b8068e955afbde551cb0c67a50129c3d83376))
* **mlx:** concurrency options and mlx-bench benchmark script ([#260](https://github.com/JacobPEvans/nix-ai/issues/260)) ([e1cefde](https://github.com/JacobPEvans/nix-ai/commit/e1cefdeab9d0f4014eb01e990e401654c43f922e))
* **mlx:** dynamic model discovery and comprehensive benchmark suite ([b9a277f](https://github.com/JacobPEvans/nix-ai/commit/b9a277f9fa159d09ab2b4c62dd8b1f201042be20)), closes [#294](https://github.com/JacobPEvans/nix-ai/issues/294)
* **mlx:** enable server-side tool calling for vllm-mlx ([#280](https://github.com/JacobPEvans/nix-ai/issues/280)) ([7771757](https://github.com/JacobPEvans/nix-ai/commit/77717579cb52be012e4a8bba99f4af9b1a2583c4))
* **mlx:** establish ecosystem stack with parakeet-mlx and mlx-vlm ([#365](https://github.com/JacobPEvans/nix-ai/issues/365)) ([265cd12](https://github.com/JacobPEvans/nix-ai/commit/265cd128f514cb611ba34a6bb491c33dc555370c))
* **mlx:** replace model switching with llama-swap proxy ([#396](https://github.com/JacobPEvans/nix-ai/issues/396)) ([2bc75e7](https://github.com/JacobPEvans/nix-ai/commit/2bc75e7fae44ea4a37f46d9ac700495069f2b089))
* **mlx:** split module, add benchmarks & health check ([#263](https://github.com/JacobPEvans/nix-ai/issues/263)) ([cc4a95f](https://github.com/JacobPEvans/nix-ai/commit/cc4a95f9bc9a7481eee211cdd6738970854ab76b))
* **open-webui:** add LaunchAgent for auto-start on login ([#110](https://github.com/JacobPEvans/nix-ai/issues/110)) ([d3f8460](https://github.com/JacobPEvans/nix-ai/commit/d3f84604e3373e3f799b9ed2a88c414c3d36174b))
* orchestrator phase 2-3 — loaders, embeddings, workflows ([#208](https://github.com/JacobPEvans/nix-ai/issues/208)) ([585ed75](https://github.com/JacobPEvans/nix-ai/commit/585ed75059233d6a9dff6552efbd8de4b5c83c6e))
* **orchestrator:** add agent framework evaluation scripts ([7490ad0](https://github.com/JacobPEvans/nix-ai/commit/7490ad05b50b93da3df109eab374394a95464543))
* **pal:** 100% reliability via auto mode, Doppler fallback, and global rules ([#394](https://github.com/JacobPEvans/nix-ai/issues/394)) ([486173a](https://github.com/JacobPEvans/nix-ai/commit/486173a996f895403e30a9af2e0e3dc628023ba8))
* **pal:** Phase 5 — disable tools with native/Bifrost equivalents ([#481](https://github.com/JacobPEvans/nix-ai/issues/481)) ([64fc4c1](https://github.com/JacobPEvans/nix-ai/commit/64fc4c1bdd209866e532c5d39d0abfd8a0dc5642))
* **pal:** score models from real LMSYS Chatbot Arena Elo ratings ([#463](https://github.com/JacobPEvans/nix-ai/issues/463)) ([2e5f35a](https://github.com/JacobPEvans/nix-ai/commit/2e5f35ae966c7d6b5ad389b98e661d86a7707cd0))
* **pal:** set DEFAULT_MODEL to latest Gemini (gemini-3-pro-preview) ([#109](https://github.com/JacobPEvans/nix-ai/issues/109)) ([c540bda](https://github.com/JacobPEvans/nix-ai/commit/c540bda62de5712365e0638632e120ce3f506ae2))
* **plugins:** add Bitwarden ai-plugins marketplace ([#217](https://github.com/JacobPEvans/nix-ai/issues/217)) ([f1ddbc1](https://github.com/JacobPEvans/nix-ai/commit/f1ddbc1e639d14fda48546663d21a9eac2f9c5a5))
* re-enable issue auto-resolve gated by ai:ready label ([#127](https://github.com/JacobPEvans/nix-ai/issues/127)) ([3342d6f](https://github.com/JacobPEvans/nix-ai/commit/3342d6fb105e714384c717248cf70f9dda78c6ad))
* remove Ollama, unify local inference on MLX port 11434 ([#242](https://github.com/JacobPEvans/nix-ai/issues/242)) ([8d3503d](https://github.com/JacobPEvans/nix-ai/commit/8d3503d566fac8b5e47d9598a0c3c26902e15171))
* show repo/worktree in statusline cwd instead of basename ([#129](https://github.com/JacobPEvans/nix-ai/issues/129)) ([5f4feb9](https://github.com/JacobPEvans/nix-ai/commit/5f4feb94b1cffa22fdec2316588d7e824f217443))
* simplify statusline to 2-line layout and remove legacy dead code ([#79](https://github.com/JacobPEvans/nix-ai/issues/79)) ([629b8a3](https://github.com/JacobPEvans/nix-ai/commit/629b8a374c030828f93e04e3dfcd4cca70f8ec5c))
* **statusline:** expand to 3-line layout ([#86](https://github.com/JacobPEvans/nix-ai/issues/86)) ([e3926d1](https://github.com/JacobPEvans/nix-ai/commit/e3926d1d3926147fe5946e8ed1d3910e80d8434e))
* **statusline:** reorder line 1 segments to git-first layout ([#83](https://github.com/JacobPEvans/nix-ai/issues/83)) ([48e8848](https://github.com/JacobPEvans/nix-ai/commit/48e8848e7e4a885ad4560bc82caa604185e5a984))
* switch to ClaudeCodeStatusLine (daniel3303) 2-line statusline ([#126](https://github.com/JacobPEvans/nix-ai/issues/126)) ([805b240](https://github.com/JacobPEvans/nix-ai/commit/805b240bf23815421f123b38d6f6d6093769b051)), closes [#103](https://github.com/JacobPEvans/nix-ai/issues/103)
* upgrade to Python 3.14 and add MLX inference server ([#142](https://github.com/JacobPEvans/nix-ai/issues/142)) ([60695d9](https://github.com/JacobPEvans/nix-ai/commit/60695d9dd1fc759541f806170099b3f42886c950))
* WakaTime Doppler injection, PAL flake pinning, GitHub MCP disabled ([#122](https://github.com/JacobPEvans/nix-ai/issues/122)) ([448417c](https://github.com/JacobPEvans/nix-ai/commit/448417cbbd6458b103a92fe1d0a7945a44a06928))


### Bug Fixes

* add concurrency groups to prevent duplicate PR creation ([#114](https://github.com/JacobPEvans/nix-ai/issues/114)) ([8c6a543](https://github.com/JacobPEvans/nix-ai/commit/8c6a54382db529bdb843bd00d6742ada92489f30))
* add diagnostic logging to doppler-mcp and check-pal-mcp health script ([#130](https://github.com/JacobPEvans/nix-ai/issues/130)) ([a88b266](https://github.com/JacobPEvans/nix-ai/commit/a88b26611db1deb81aa725d829253403df3d5410))
* add MLX perf tuning flags and remove Ollama from stack ([#243](https://github.com/JacobPEvans/nix-ai/issues/243)) ([f375d87](https://github.com/JacobPEvans/nix-ai/commit/f375d8758903d7e1909514237ec36349c5d158bb))
* add MLX performance tuning flags for vllm-mlx LaunchAgent ([f375d87](https://github.com/JacobPEvans/nix-ai/commit/f375d8758903d7e1909514237ec36349c5d158bb))
* add port allocation docs and negative regression tests ([#262](https://github.com/JacobPEvans/nix-ai/issues/262)) ([f3e192d](https://github.com/JacobPEvans/nix-ai/commit/f3e192dff69f09a8ba76c99a88e555b1f8572132))
* add release-please config for manifest mode ([5c1d9eb](https://github.com/JacobPEvans/nix-ai/commit/5c1d9ebbab3ec1ef87813e837a188945b74f0e48))
* address PR [#188](https://github.com/JacobPEvans/nix-ai/issues/188) review feedback ([a7f4782](https://github.com/JacobPEvans/nix-ai/commit/a7f4782b5e93eb4bc28ff49bf64caf051a90a88d))
* **ai-tools:** bump huggingface-hub pin 1.9.0 -&gt; 1.10.1 ([#486](https://github.com/JacobPEvans/nix-ai/issues/486)) ([0a193d3](https://github.com/JacobPEvans/nix-ai/commit/0a193d3ab981455ceeef9beb4d37865469c53def))
* auto-sync Claude Code plugin cache after nix rebuild ([#235](https://github.com/JacobPEvans/nix-ai/issues/235)) ([edba1ad](https://github.com/JacobPEvans/nix-ai/commit/edba1adb0d2ade246e7c7ce51a60762d8fb770ae))
* build pal-mcp-server as Nix derivation ([#157](https://github.com/JacobPEvans/nix-ai/issues/157)) ([7e5ab79](https://github.com/JacobPEvans/nix-ai/commit/7e5ab799c0ae56d7af12cfe2769988f780c61373))
* cap Ollama memory at 20G, switch MLX default to Qwen3.5-122B MoE ([#234](https://github.com/JacobPEvans/nix-ai/issues/234)) ([9d82a86](https://github.com/JacobPEvans/nix-ai/commit/9d82a86d8a17b88eeb670e490a6401ff7f92e73f))
* change MLX port from 11435 to 11436 (screenpipe conflict) ([#230](https://github.com/JacobPEvans/nix-ai/issues/230)) ([8a8dde9](https://github.com/JacobPEvans/nix-ai/commit/8a8dde9e90ef09491089115fbb19ecaa7856e605))
* **checks:** bump test stateVersion to 25.11 ([#244](https://github.com/JacobPEvans/nix-ai/issues/244)) ([616d251](https://github.com/JacobPEvans/nix-ai/commit/616d251f0968ddb28521403e0c6d3f4c7dc58429))
* **ci:** add pull-requests:write for release-please auto-approve ([007d630](https://github.com/JacobPEvans/nix-ai/commit/007d630d28ee4b59e2ce11d7926f3f0a0aac2e58))
* **ci:** exclude CHANGELOG.md from markdownlint ([#171](https://github.com/JacobPEvans/nix-ai/issues/171)) ([f974ead](https://github.com/JacobPEvans/nix-ai/commit/f974eada87f0c10a29fe6897b5543ebb289b86fd))
* **ci:** migrate copilot-setup-steps to determinate-nix-action@v3 ([#175](https://github.com/JacobPEvans/nix-ai/issues/175)) ([47eef4b](https://github.com/JacobPEvans/nix-ai/commit/47eef4b714e6b31e2fdf002d678e824ee247bc72))
* **ci:** replace stub benchmark PR comments with benchmark-action ([#333](https://github.com/JacobPEvans/nix-ai/issues/333)) ([64c56a7](https://github.com/JacobPEvans/nix-ai/commit/64c56a7f5a820e0b30f3b79f23306b0b9f50feb2))
* **ci:** skip benchmark-action when no results to post ([#363](https://github.com/JacobPEvans/nix-ai/issues/363)) ([d454020](https://github.com/JacobPEvans/nix-ai/commit/d4540204b78858460a938c3375fa5ef6251b78f9))
* **ci:** upgrade ci-gate.yml to Merge Gatekeeper pattern ([#162](https://github.com/JacobPEvans/nix-ai/issues/162)) ([10a5a47](https://github.com/JacobPEvans/nix-ai/commit/10a5a478b9e57fc870df527838ba686a2315576b))
* **ci:** use [@v0](https://github.com/v0) floating tag for ai-workflows references ([#104](https://github.com/JacobPEvans/nix-ai/issues/104)) ([31d1d61](https://github.com/JacobPEvans/nix-ai/commit/31d1d61ceabde91c2cfe408605b5c70df478f64e))
* **ci:** use drvPath in module-eval to avoid full activation build ([#90](https://github.com/JacobPEvans/nix-ai/issues/90)) ([155e117](https://github.com/JacobPEvans/nix-ai/commit/155e117bcf900c62869594eec32300cee69845e9))
* **ci:** use GitHub App token for release-please to trigger CI Gate ([#147](https://github.com/JacobPEvans/nix-ai/issues/147)) ([d5837bb](https://github.com/JacobPEvans/nix-ai/commit/d5837bb2aaa4e510212ab1691a5314dd344de7dd))
* clarify MLX port description as default choice ([#232](https://github.com/JacobPEvans/nix-ai/issues/232)) ([d9125dc](https://github.com/JacobPEvans/nix-ai/commit/d9125dcba9630944fc2258b52aded1e8bf7e5e38))
* **claude:** clean up config defaults, set model/effort explicitly ([#495](https://github.com/JacobPEvans/nix-ai/issues/495)) ([b99e227](https://github.com/JacobPEvans/nix-ai/commit/b99e227eb489ef9cfe6fadb8067282465f4c80b2))
* **claude:** deploy retrospective report override as global rule ([#405](https://github.com/JacobPEvans/nix-ai/issues/405)) ([fd819b9](https://github.com/JacobPEvans/nix-ai/commit/fd819b966bc455c0897d5faa44d6678cbb920414))
* **claude:** set writes_only=false in wakatime config ([#318](https://github.com/JacobPEvans/nix-ai/issues/318)) ([0969bce](https://github.com/JacobPEvans/nix-ai/commit/0969bcecfb27a25afb37cab78cd7b1ff6982f169))
* **claude:** switch auto-update channel from stable to latest ([#414](https://github.com/JacobPEvans/nix-ai/issues/414)) ([a76ae00](https://github.com/JacobPEvans/nix-ai/commit/a76ae0050631f48a2230c87eb5d5cb96636e64fa))
* correct best-practices permissions and add ref-scoped concurrency ([#115](https://github.com/JacobPEvans/nix-ai/issues/115)) ([197d1aa](https://github.com/JacobPEvans/nix-ai/commit/197d1aaea84a95a36b1173c7b7d734d7b1e66854))
* cross-repo cleanup after unstable overlay removal ([#249](https://github.com/JacobPEvans/nix-ai/issues/249)) ([9093bd9](https://github.com/JacobPEvans/nix-ai/commit/9093bd9424a70ea870c226a6d7855eb38238e2c9))
* defer cache purge when Claude Code sessions are active ([#268](https://github.com/JacobPEvans/nix-ai/issues/268)) ([8b63780](https://github.com/JacobPEvans/nix-ai/commit/8b6378041feb499f5cc087c9d6b6657fc36ee5e3))
* **deps:** centralize Python version and Renovate pep621 policy ([#373](https://github.com/JacobPEvans/nix-ai/issues/373)) ([4fce2a9](https://github.com/JacobPEvans/nix-ai/commit/4fce2a962be645260e58cdddbcb80c6387975c33))
* **deps:** close Renovate automation gaps for all version-pinned packages ([#321](https://github.com/JacobPEvans/nix-ai/issues/321)) ([3d7e2a7](https://github.com/JacobPEvans/nix-ai/commit/3d7e2a767f8edbc70b9ea4f6981042ec53098e0b))
* **deps:** correct gh-aw v0.65.0 source hash ([#386](https://github.com/JacobPEvans/nix-ai/issues/386)) ([8fd8952](https://github.com/JacobPEvans/nix-ai/commit/8fd8952afd95d3546d081a97f8cab51a3f6e504b))
* **deps:** drop llama-index meta-package, remove 9 unused transitive deps ([#274](https://github.com/JacobPEvans/nix-ai/issues/274)) ([92ce757](https://github.com/JacobPEvans/nix-ai/commit/92ce75716aeab79bd5a6cad019edad79edae54eb))
* **deps:** fix Renovate regex for uv tool install packages ([#402](https://github.com/JacobPEvans/nix-ai/issues/402)) ([0d5d8b7](https://github.com/JacobPEvans/nix-ai/commit/0d5d8b767fbf5fe66e562914611674a69c4e9a68))
* **deps:** pin all packages for Renovate auto-update coverage ([#435](https://github.com/JacobPEvans/nix-ai/issues/435)) ([016f5ab](https://github.com/JacobPEvans/nix-ai/commit/016f5abe52ac3b0c6a5c53ce7439af7bbec3710d))
* **deps:** remove manual input list from flake update workflow ([#118](https://github.com/JacobPEvans/nix-ai/issues/118)) ([cd7946d](https://github.com/JacobPEvans/nix-ai/commit/cd7946d0a2be24da35254abb0811be16a11ac30c))
* **deps:** update all flake inputs ([#384](https://github.com/JacobPEvans/nix-ai/issues/384)) ([b997f2d](https://github.com/JacobPEvans/nix-ai/commit/b997f2dd7ada5e5712f0d0aa1cdca04b28c60cb6))
* **deps:** update gh-aw hashes, switch to daily nix-update ([#401](https://github.com/JacobPEvans/nix-ai/issues/401)) ([e7ae532](https://github.com/JacobPEvans/nix-ai/commit/e7ae532cbc8af50da55c8d881e93fd0cfad491ac))
* **deps:** update jacobpevans-cc-plugins for /ship command ([#184](https://github.com/JacobPEvans/nix-ai/issues/184)) ([f4983a9](https://github.com/JacobPEvans/nix-ai/commit/f4983a9102065acb942fda376d49f3142ae4b034))
* **devenv:** use impure eval for runtime DEVENV_ROOT resolution ([#172](https://github.com/JacobPEvans/nix-ai/issues/172)) ([d0247dc](https://github.com/JacobPEvans/nix-ai/commit/d0247dc20ea3a62511e9ea7cbf2c847f2f3778b7))
* **devenv:** use python package attr instead of version string ([#187](https://github.com/JacobPEvans/nix-ai/issues/187)) ([daca68a](https://github.com/JacobPEvans/nix-ai/commit/daca68afbf7dc2055853f3fc1c9b19d9b467068b))
* **devshell:** use python package attr instead of version in orchestrator shell ([#218](https://github.com/JacobPEvans/nix-ai/issues/218)) ([ae9fe44](https://github.com/JacobPEvans/nix-ai/commit/ae9fe44ff157c664b6f79eb9d3d4b2126d2ef1aa))
* disable greptile plugin (cost) ([#264](https://github.com/JacobPEvans/nix-ai/issues/264)) ([6c780a1](https://github.com/JacobPEvans/nix-ai/commit/6c780a1933934b60153e48d7171f01a2ea41fecd))
* disable hash pinning for trusted actions, use version tags ([#116](https://github.com/JacobPEvans/nix-ai/issues/116)) ([29510d5](https://github.com/JacobPEvans/nix-ai/commit/29510d59c56d0333580797af6a210c92ea1c16b6))
* **docs:** correct PAL model script references in MCP README ([#211](https://github.com/JacobPEvans/nix-ai/issues/211)) ([c880929](https://github.com/JacobPEvans/nix-ai/commit/c880929eff3b5cffca4cb6d32e8c9250e4c591ca))
* **docs:** distinguish static vs runtime validation; fix OSV scan ([#353](https://github.com/JacobPEvans/nix-ai/issues/353)) ([759c613](https://github.com/JacobPEvans/nix-ai/commit/759c613ab5f7da61dba02bd84b6c314e19d4fe1e))
* **docs:** drop "quartet" and numeric group words from CLAUDE.md ([#488](https://github.com/JacobPEvans/nix-ai/issues/488)) ([a48d8f3](https://github.com/JacobPEvans/nix-ai/commit/a48d8f3d80e132e890c72976e6ac19bc1fc38611))
* **docs:** remove inline keychain password from testing docs ([#240](https://github.com/JacobPEvans/nix-ai/issues/240)) ([5dee71e](https://github.com/JacobPEvans/nix-ai/commit/5dee71e72721ec579045384a18b95eb7ed7a9179))
* dual-backend MLX module with CLI flag validation ([#248](https://github.com/JacobPEvans/nix-ai/issues/248)) ([1152927](https://github.com/JacobPEvans/nix-ai/commit/11529279aed497c8e2aad82640565ef5c830d5a3))
* **gemini:** replace shell grep validation with pure Nix assertions ([#518](https://github.com/JacobPEvans/nix-ai/issues/518)) ([78672a5](https://github.com/JacobPEvans/nix-ai/commit/78672a506f3cd8e77c2e4a6c1b15ae73400ae937))
* golden standard — bugs, cross-platform, dead code, style ([#174](https://github.com/JacobPEvans/nix-ai/issues/174)) ([4954bd1](https://github.com/JacobPEvans/nix-ai/commit/4954bd1e6a7c6e388dbb26c85736f3cecf8e1ee7))
* **mcp:** document Obsidian CLI integration, remove REST API port ([#493](https://github.com/JacobPEvans/nix-ai/issues/493)) ([171d946](https://github.com/JacobPEvans/nix-ai/commit/171d9469d94c27b1f4df6979f0c051c393d06d59))
* migrate Bash permission format from colon to space separator ([#177](https://github.com/JacobPEvans/nix-ai/issues/177)) ([62658c1](https://github.com/JacobPEvans/nix-ai/commit/62658c1ade1cf96e5b735dd0c47c942a3a3dc423))
* **mlx:** cap KV cache at 16GB to prevent OOM ([#271](https://github.com/JacobPEvans/nix-ai/issues/271)) ([630f9a3](https://github.com/JacobPEvans/nix-ai/commit/630f9a365083c6ba2a3ea50de3772a224a8fb808))
* **mlx:** correct mlx-eval base_url for lm-eval local-chat-completions ([#431](https://github.com/JacobPEvans/nix-ai/issues/431)) ([869948b](https://github.com/JacobPEvans/nix-ai/commit/869948b04d5342313349f818e245f8db99507327))
* **mlx:** correct mlx-preflight path construction ([#360](https://github.com/JacobPEvans/nix-ai/issues/360)) ([02ca479](https://github.com/JacobPEvans/nix-ai/commit/02ca4794ff2d88c5c4ca5f5ec5b14062cf9eebf4))
* **mlx:** disable reasoning parser to fix streaming tool calls ([cb18f84](https://github.com/JacobPEvans/nix-ai/commit/cb18f846c8ba334a57155e15ff5634bb19bcde94))
* **mlx:** restore Qwen3.5-35B-A3B-4bit as defaultModel — fabricated incident ([#489](https://github.com/JacobPEvans/nix-ai/issues/489)) ([e6ccc03](https://github.com/JacobPEvans/nix-ai/commit/e6ccc032db50a6e0d5dbff0d1328cf7d5fc8c36c))
* **mlx:** simplify OOM prevention to minimal 3-layer defense ([54208d2](https://github.com/JacobPEvans/nix-ai/commit/54208d28147db1fb7cfeccfe76dacd7a1dd3aa4c))
* **mlx:** switch default model to Qwen3.5-27B to prevent memory freezes ([#328](https://github.com/JacobPEvans/nix-ai/issues/328)) ([3945679](https://github.com/JacobPEvans/nix-ai/commit/39456794a507a617c6c4f9a2fbd4f76f4312fa91))
* **mlx:** update LaunchAgent flags for vllm-mlx 0.2.6 CLI, split checks.nix ([#250](https://github.com/JacobPEvans/nix-ai/issues/250)) ([b9c7165](https://github.com/JacobPEvans/nix-ai/commit/b9c716564687a92dae39f4ea03ff650da6895ecb))
* **mlx:** use footprint for memory reporting in mlx-status ([#332](https://github.com/JacobPEvans/nix-ai/issues/332)) ([a7b57f7](https://github.com/JacobPEvans/nix-ai/commit/a7b57f73e1b31c756948ebe245375318e5e26332))
* **models:** replace hardcoded model names with env var references (DRY) ([#423](https://github.com/JacobPEvans/nix-ai/issues/423)) ([16d3610](https://github.com/JacobPEvans/nix-ai/commit/16d3610e5d56d8d1a12f338e8eb3c7415c3d6973))
* move git policy to nix-home, add separation guidelines ([#293](https://github.com/JacobPEvans/nix-ai/issues/293)) ([c927776](https://github.com/JacobPEvans/nix-ai/commit/c9277768fcb697b9b2724c33794278181def8518))
* move sync-ollama-models to pal-models.nix for MLX model append ([#226](https://github.com/JacobPEvans/nix-ai/issues/226)) ([d66fca5](https://github.com/JacobPEvans/nix-ai/commit/d66fca59ee907056e53a23f12ca7853ddfb9b902))
* PAL MCP model routing — fix JSON nesting, MLX-first default, add MLX models ([#225](https://github.com/JacobPEvans/nix-ai/issues/225)) ([15b297a](https://github.com/JacobPEvans/nix-ai/commit/15b297adc5208e54e67056f4382fa3396b525d77))
* **pal:** bulletproof MCP diagnostics, logs, and activation ([#266](https://github.com/JacobPEvans/nix-ai/issues/266)) ([6836fe9](https://github.com/JacobPEvans/nix-ai/commit/6836fe97271c991a57a17c6110336e879574dbd5))
* **pal:** dynamic model discovery via OpenRouter, kill stale defaults ([#434](https://github.com/JacobPEvans/nix-ai/issues/434)) ([3e8dea9](https://github.com/JacobPEvans/nix-ai/commit/3e8dea9ebb909043a7da6aeca805ebf9a39c0f5c))
* **pal:** radically simplify cloud model discovery ([37f7afe](https://github.com/JacobPEvans/nix-ai/commit/37f7afeed9983ef69cbcddcc5292320c8aaffae9))
* **plugins:** add synthetic marketplace support for browser-use ([#331](https://github.com/JacobPEvans/nix-ai/issues/331)) ([c255fef](https://github.com/JacobPEvans/nix-ai/commit/c255fef1fb9fbb3248d66fdf77b89d7e66bfcd64))
* **plugins:** replace per-file symlinks with directory symlinks ([#186](https://github.com/JacobPEvans/nix-ai/issues/186)) ([cff42d5](https://github.com/JacobPEvans/nix-ai/commit/cff42d58f776b58e75faf8f3a9e45dfa0810b966))
* **plugins:** update stale plugin count comment in development.nix ([#222](https://github.com/JacobPEvans/nix-ai/issues/222)) ([5ffd43d](https://github.com/JacobPEvans/nix-ai/commit/5ffd43db73206590cda7797aa37a642dc94521c9))
* quote flake URL in orchestrator .envrc ([10c57ba](https://github.com/JacobPEvans/nix-ai/commit/10c57badb8bfa8b7ccfd610346ea16a5bf417a95))
* raise issue hard limit from 50 to 150 per repo ([25ccf92](https://github.com/JacobPEvans/nix-ai/commit/25ccf9294a4fc51118acf9de3cb0214e34c5e77f))
* remove blanket auto-merge workflow ([#117](https://github.com/JacobPEvans/nix-ai/issues/117)) ([cc0315b](https://github.com/JacobPEvans/nix-ai/commit/cc0315b19ef3bddd62fae25c6252d010e0cda0eb))
* remove doppler-mcp preflight check causing MCP startup race ([#343](https://github.com/JacobPEvans/nix-ai/issues/343)) ([6451d27](https://github.com/JacobPEvans/nix-ai/commit/6451d27ff69d4e18c4eb2abb6539439bd78e72ce))
* remove plugin cache mutation from activation scripts ([#258](https://github.com/JacobPEvans/nix-ai/issues/258)) ([4df8af5](https://github.com/JacobPEvans/nix-ai/commit/4df8af59171a49405b3eb42e91938dfca5ca4db2))
* remove redundant .markdownlint-cli2.yaml ([#91](https://github.com/JacobPEvans/nix-ai/issues/91)) ([6de3e82](https://github.com/JacobPEvans/nix-ai/commit/6de3e8291525ec9f77c79829f48776a2d0aa5e2f))
* remove stale manual plugin list from development.nix comment ([#292](https://github.com/JacobPEvans/nix-ai/issues/292)) ([d2e7dc3](https://github.com/JacobPEvans/nix-ai/commit/d2e7dc3e2f5cf50703b0efcd4809b64ce2db5c04))
* remove stale versions from wrapper package comments ([#368](https://github.com/JacobPEvans/nix-ai/issues/368)) ([5ac0e31](https://github.com/JacobPEvans/nix-ai/commit/5ac0e31f43779aa701ef94b27e42588732dff0ac))
* remove unnecessary comments from python centralization ([#374](https://github.com/JacobPEvans/nix-ai/issues/374)) ([b287dce](https://github.com/JacobPEvans/nix-ai/commit/b287dceedd17e0496d856d889ffde39b6719368a))
* rename GH_APP_ID secret to GH_ACTION_JACOBPEVANS_APP_ID ([#132](https://github.com/JacobPEvans/nix-ai/issues/132)) ([ed48910](https://github.com/JacobPEvans/nix-ai/commit/ed4891083564906a6b0fbd87e5302cfbc7e5b5d6))
* replace deleted /init-worktree references with /refresh-repo ([#421](https://github.com/JacobPEvans/nix-ai/issues/421)) ([cb73b7f](https://github.com/JacobPEvans/nix-ai/commit/cb73b7f267b12ac175fd61057816ff7688357bca))
* resolve 13 Claude Code plugin startup errors ([#2](https://github.com/JacobPEvans/nix-ai/issues/2)) ([89f4be6](https://github.com/JacobPEvans/nix-ai/commit/89f4be62d187518517008b56f50c7b6f21f1471b))
* resolve claude binary path during sudo activation ([#238](https://github.com/JacobPEvans/nix-ai/issues/238)) ([a0d6d1a](https://github.com/JacobPEvans/nix-ai/commit/a0d6d1a9e77a77982593c228aa18119a97d0006a))
* resolve MCP server issues and add HuggingFace + MLX tools ([#144](https://github.com/JacobPEvans/nix-ai/issues/144)) ([fe5f2ce](https://github.com/JacobPEvans/nix-ai/commit/fe5f2ce01cbc4859ea4c01f74eeb1c26e81d46c2))
* **security:** add Python security scanning and OSV scanner to CI ([#341](https://github.com/JacobPEvans/nix-ai/issues/341)) ([e4645d5](https://github.com/JacobPEvans/nix-ai/commit/e4645d5cf7e3837a3afde8eb278aced0d235c551))
* **security:** path traversal, branch injection, pgrep regex injection ([#88](https://github.com/JacobPEvans/nix-ai/issues/88)) ([c61de8c](https://github.com/JacobPEvans/nix-ai/commit/c61de8c0480d781c0ae93a72cf3cdbb163172448))
* **security:** pin uv tool installs and block compromised LiteLLM ([#324](https://github.com/JacobPEvans/nix-ai/issues/324)) ([9279aa4](https://github.com/JacobPEvans/nix-ai/commit/9279aa418a85d03e2debb933a2adaad1bd6873ad))
* **security:** redact sensitive data in logging calls (CodeQL py/clear-text-logging-sensitive-data) ([#89](https://github.com/JacobPEvans/nix-ai/issues/89)) ([76b5a0b](https://github.com/JacobPEvans/nix-ai/commit/76b5a0bb11919b0afa42a736166a0a69093a7950))
* **security:** upgrade pygments and remove all CVE ignores ([#369](https://github.com/JacobPEvans/nix-ai/issues/369)) ([1cac3ad](https://github.com/JacobPEvans/nix-ai/commit/1cac3ad60a1a6f22f845e19dd6eaed5435114cfa))
* set cleanupPeriodDays to 30 (upstream default) ([#139](https://github.com/JacobPEvans/nix-ai/issues/139)) ([8c641b6](https://github.com/JacobPEvans/nix-ai/commit/8c641b6d2406b650058a569674d4864d598666ea))
* sync release-please permissions and VERSION ([df6938a](https://github.com/JacobPEvans/nix-ai/commit/df6938a57a3944d5d24bdfdddcfaf2ba5f6d0278))
* **tests:** use MagicMock instance for SimpleDocumentStore in pipeline tests ([#215](https://github.com/JacobPEvans/nix-ai/issues/215)) ([e788030](https://github.com/JacobPEvans/nix-ai/commit/e788030048a5af2c2ee361250a345cb107da90ad))
* update Copilot setup source to ai-workflows ([#426](https://github.com/JacobPEvans/nix-ai/issues/426)) ([c385804](https://github.com/JacobPEvans/nix-ai/commit/c3858046251c76da4affea92095401484f50aea3))
* update gh-aw to v0.57.2 and remove silent failure in workflow ([#135](https://github.com/JacobPEvans/nix-ai/issues/135)) ([c34008d](https://github.com/JacobPEvans/nix-ai/commit/c34008d7cbbe64f22211ab8f17becf89fdc4f944))
* update stale nix-config references to nix-darwin ([#112](https://github.com/JacobPEvans/nix-ai/issues/112)) ([4f09511](https://github.com/JacobPEvans/nix-ai/commit/4f09511c8920851294c76151cc58861caa128363))
* use absolute path for shasum in verify-cache-integrity.sh ([#128](https://github.com/JacobPEvans/nix-ai/issues/128)) ([c8fabcc](https://github.com/JacobPEvans/nix-ai/commit/c8fabcc930dbf5aef22fe16dc9478c82d8c0753d))
* wire is-deps-only detection and narrow CI triggers ([#432](https://github.com/JacobPEvans/nix-ai/issues/432)) ([db82c5c](https://github.com/JacobPEvans/nix-ai/commit/db82c5ca7da0571944692a10e0f8678e864b3a13))

## [1.42.2](https://github.com/JacobPEvans/nix-ai/compare/v1.42.1...v1.42.2) (2026-04-13)


### Bug Fixes

* **gemini:** replace shell grep validation with pure Nix assertions ([#518](https://github.com/JacobPEvans/nix-ai/issues/518)) ([78672a5](https://github.com/JacobPEvans/nix-ai/commit/78672a506f3cd8e77c2e4a6c1b15ae73400ae937))

## [1.42.1](https://github.com/JacobPEvans/nix-ai/compare/v1.42.0...v1.42.1) (2026-04-12)


### Bug Fixes

* **claude:** clean up config defaults, set model/effort explicitly ([#495](https://github.com/JacobPEvans/nix-ai/issues/495)) ([b99e227](https://github.com/JacobPEvans/nix-ai/commit/b99e227eb489ef9cfe6fadb8067282465f4c80b2))

## [1.42.0](https://github.com/JacobPEvans/nix-ai/compare/v1.41.0...v1.42.0) (2026-04-12)


### Features

* **gemini:** migrate to Policy Engine, drop deprecated tools.allowed/exclude ([#516](https://github.com/JacobPEvans/nix-ai/issues/516)) ([6df0934](https://github.com/JacobPEvans/nix-ai/commit/6df0934fd02d3643eed55abf153b9594bb6b23e8))

## [1.41.0](https://github.com/JacobPEvans/nix-ai/compare/v1.40.0...v1.41.0) (2026-04-12)


### Features

* **codex,gemini:** expand modules to Claude-level feature parity ([72168b3](https://github.com/JacobPEvans/nix-ai/commit/72168b31b00836b196bbfd8a981caf633fb35097))

## [1.40.0](https://github.com/JacobPEvans/nix-ai/compare/v1.39.0...v1.40.0) (2026-04-12)


### Features

* **codex:** add native Codex configuration with writable config.toml ([8b4b088](https://github.com/JacobPEvans/nix-ai/commit/8b4b088076c1d7c6b730e8fe3a7c45899275658c))

## [1.39.0](https://github.com/JacobPEvans/nix-ai/compare/v1.38.1...v1.39.0) (2026-04-12)


### Features

* **fabric:** add zsh completions and AI tool decision tree ([28af185](https://github.com/JacobPEvans/nix-ai/commit/28af1856d02d23da1b33d090d5ebb681ab2cc8e4))

## [1.38.0](https://github.com/JacobPEvans/nix-ai/compare/v1.37.1...v1.38.0) (2026-04-12)


### Features

* **claude:** enable OTEL telemetry to OrbStack collector ([#496](https://github.com/JacobPEvans/nix-ai/issues/496)) ([b9129f2](https://github.com/JacobPEvans/nix-ai/commit/b9129f2d0c56d339dcd9c2152b50e203ef0931e4))
* **codex:** add official OpenAI Codex plugin + MCP server ([#497](https://github.com/JacobPEvans/nix-ai/issues/497)) ([3ea8d5c](https://github.com/JacobPEvans/nix-ai/commit/3ea8d5c55cec87713ea754311df3935dcf63f8e6))
* **fabric:** integrate Daniel Miessler's Fabric framework ([d361940](https://github.com/JacobPEvans/nix-ai/commit/d361940c7a30ef2cc5ce03264d6a5005bea0059c))

## [1.37.1](https://github.com/JacobPEvans/nix-ai/compare/v1.37.0...v1.37.1) (2026-04-12)


### Bug Fixes

* **docs:** drop "quartet" and numeric group words from CLAUDE.md ([#488](https://github.com/JacobPEvans/nix-ai/issues/488)) ([a48d8f3](https://github.com/JacobPEvans/nix-ai/commit/a48d8f3d80e132e890c72976e6ac19bc1fc38611))
* **mcp:** document Obsidian CLI integration, remove REST API port ([#493](https://github.com/JacobPEvans/nix-ai/issues/493)) ([171d946](https://github.com/JacobPEvans/nix-ai/commit/171d9469d94c27b1f4df6979f0c051c393d06d59))
* **mlx:** restore Qwen3.5-35B-A3B-4bit as defaultModel — fabricated incident ([#489](https://github.com/JacobPEvans/nix-ai/issues/489)) ([e6ccc03](https://github.com/JacobPEvans/nix-ai/commit/e6ccc032db50a6e0d5dbff0d1328cf7d5fc8c36c))

## [1.37.0](https://github.com/JacobPEvans/nix-ai/compare/v1.36.0...v1.37.0) (2026-04-11)


### Features

* **ai-tools:** add whisper-cpp and openai-whisper moved from nix-darwin ([#482](https://github.com/JacobPEvans/nix-ai/issues/482)) ([0077a28](https://github.com/JacobPEvans/nix-ai/commit/0077a287366daa7107e16cdfe2ca7280c023a8e7))


### Bug Fixes

* **ai-tools:** bump huggingface-hub pin 1.9.0 -&gt; 1.10.1 ([#486](https://github.com/JacobPEvans/nix-ai/issues/486)) ([0a193d3](https://github.com/JacobPEvans/nix-ai/commit/0a193d3ab981455ceeef9beb4d37865469c53def))

## [1.36.0](https://github.com/JacobPEvans/nix-ai/compare/v1.35.0...v1.36.0) (2026-04-11)


### Features

* **pal:** Phase 5 — disable tools with native/Bifrost equivalents ([#481](https://github.com/JacobPEvans/nix-ai/issues/481)) ([64fc4c1](https://github.com/JacobPEvans/nix-ai/commit/64fc4c1bdd209866e532c5d39d0abfd8a0dc5642))

## [1.35.0](https://github.com/JacobPEvans/nix-ai/compare/v1.34.0...v1.35.0) (2026-04-11)


### Features

* **mcp:** route PAL through Bifrost AI gateway ([#466](https://github.com/JacobPEvans/nix-ai/issues/466)) ([5b18711](https://github.com/JacobPEvans/nix-ai/commit/5b187116b4a177f2ba6abbd2b59a8e9302b62cee))

## [1.34.0](https://github.com/JacobPEvans/nix-ai/compare/v1.33.1...v1.34.0) (2026-04-10)


### Features

* **pal:** score models from real LMSYS Chatbot Arena Elo ratings ([#463](https://github.com/JacobPEvans/nix-ai/issues/463)) ([2e5f35a](https://github.com/JacobPEvans/nix-ai/commit/2e5f35ae966c7d6b5ad389b98e661d86a7707cd0))

## [1.33.1](https://github.com/JacobPEvans/nix-ai/compare/v1.33.0...v1.33.1) (2026-04-10)


### Bug Fixes

* **pal:** radically simplify cloud model discovery ([37f7afe](https://github.com/JacobPEvans/nix-ai/commit/37f7afeed9983ef69cbcddcc5292320c8aaffae9))

## [1.33.0](https://github.com/JacobPEvans/nix-ai/compare/v1.32.5...v1.33.0) (2026-04-10)


### Features

* **mcp:** add Bifrost AI gateway MCP server and check-bifrost CLI ([#456](https://github.com/JacobPEvans/nix-ai/issues/456)) ([efc4501](https://github.com/JacobPEvans/nix-ai/commit/efc4501a39ffba2a78ea0f63e1f1744a4ffd811f))

## [1.32.4](https://github.com/JacobPEvans/nix-ai/compare/v1.32.3...v1.32.4) (2026-04-10)


### Bug Fixes

* **deps:** pin all packages for Renovate auto-update coverage ([#435](https://github.com/JacobPEvans/nix-ai/issues/435)) ([016f5ab](https://github.com/JacobPEvans/nix-ai/commit/016f5abe52ac3b0c6a5c53ce7439af7bbec3710d))

## [1.32.3](https://github.com/JacobPEvans/nix-ai/compare/v1.32.2...v1.32.3) (2026-04-09)


### Bug Fixes

* **mlx:** correct mlx-eval base_url for lm-eval local-chat-completions ([#431](https://github.com/JacobPEvans/nix-ai/issues/431)) ([869948b](https://github.com/JacobPEvans/nix-ai/commit/869948b04d5342313349f818e245f8db99507327))
* **pal:** dynamic model discovery via OpenRouter, kill stale defaults ([#434](https://github.com/JacobPEvans/nix-ai/issues/434)) ([3e8dea9](https://github.com/JacobPEvans/nix-ai/commit/3e8dea9ebb909043a7da6aeca805ebf9a39c0f5c))

## [1.32.2](https://github.com/JacobPEvans/nix-ai/compare/v1.32.1...v1.32.2) (2026-04-09)


### Bug Fixes

* wire is-deps-only detection and narrow CI triggers ([#432](https://github.com/JacobPEvans/nix-ai/issues/432)) ([db82c5c](https://github.com/JacobPEvans/nix-ai/commit/db82c5ca7da0571944692a10e0f8678e864b3a13))

## [1.32.1](https://github.com/JacobPEvans/nix-ai/compare/v1.32.0...v1.32.1) (2026-04-08)


### Bug Fixes

* update Copilot setup source to ai-workflows ([#426](https://github.com/JacobPEvans/nix-ai/issues/426)) ([c385804](https://github.com/JacobPEvans/nix-ai/commit/c3858046251c76da4affea92095401484f50aea3))

## [1.32.0](https://github.com/JacobPEvans/nix-ai/compare/v1.31.1...v1.32.0) (2026-04-07)


### Features

* **mlx:** dynamic model discovery and comprehensive benchmark suite ([b9a277f](https://github.com/JacobPEvans/nix-ai/commit/b9a277f9fa159d09ab2b4c62dd8b1f201042be20)), closes [#294](https://github.com/JacobPEvans/nix-ai/issues/294)

## [1.31.1](https://github.com/JacobPEvans/nix-ai/compare/v1.31.0...v1.31.1) (2026-04-07)


### Bug Fixes

* **models:** replace hardcoded model names with env var references (DRY) ([#423](https://github.com/JacobPEvans/nix-ai/issues/423)) ([16d3610](https://github.com/JacobPEvans/nix-ai/commit/16d3610e5d56d8d1a12f338e8eb3c7415c3d6973))

## [1.31.0](https://github.com/JacobPEvans/nix-ai/compare/v1.30.0...v1.31.0) (2026-04-07)


### Features

* add AI merge gate ([#419](https://github.com/JacobPEvans/nix-ai/issues/419)) ([1791db9](https://github.com/JacobPEvans/nix-ai/commit/1791db99d7574dd7ee958507f12dad937c0a9d06))


### Bug Fixes

* replace deleted /init-worktree references with /refresh-repo ([#421](https://github.com/JacobPEvans/nix-ai/issues/421)) ([cb73b7f](https://github.com/JacobPEvans/nix-ai/commit/cb73b7f267b12ac175fd61057816ff7688357bca))

## [1.30.0](https://github.com/JacobPEvans/nix-ai/compare/v1.29.3...v1.30.0) (2026-04-07)


### Features

* **claude:** auto-discover global rules from flake inputs ([#413](https://github.com/JacobPEvans/nix-ai/issues/413)) ([3d6b324](https://github.com/JacobPEvans/nix-ai/commit/3d6b3243320cb7f12618a34cc42f7bf9ff89b8a5))

## [1.29.3](https://github.com/JacobPEvans/nix-ai/compare/v1.29.2...v1.29.3) (2026-04-07)


### Bug Fixes

* **claude:** switch auto-update channel from stable to latest ([#414](https://github.com/JacobPEvans/nix-ai/issues/414)) ([a76ae00](https://github.com/JacobPEvans/nix-ai/commit/a76ae0050631f48a2230c87eb5d5cb96636e64fa))

## [1.29.2](https://github.com/JacobPEvans/nix-ai/compare/v1.29.1...v1.29.2) (2026-04-06)


### Bug Fixes

* **claude:** deploy retrospective report override as global rule ([#405](https://github.com/JacobPEvans/nix-ai/issues/405)) ([fd819b9](https://github.com/JacobPEvans/nix-ai/commit/fd819b966bc455c0897d5faa44d6678cbb920414))

## [1.29.1](https://github.com/JacobPEvans/nix-ai/compare/v1.29.0...v1.29.1) (2026-04-04)


### Bug Fixes

* **deps:** fix Renovate regex for uv tool install packages ([#402](https://github.com/JacobPEvans/nix-ai/issues/402)) ([0d5d8b7](https://github.com/JacobPEvans/nix-ai/commit/0d5d8b767fbf5fe66e562914611674a69c4e9a68))

## [1.29.0](https://github.com/JacobPEvans/nix-ai/compare/v1.28.0...v1.29.0) (2026-04-03)


### Features

* **mlx:** replace model switching with llama-swap proxy ([#396](https://github.com/JacobPEvans/nix-ai/issues/396)) ([2bc75e7](https://github.com/JacobPEvans/nix-ai/commit/2bc75e7fae44ea4a37f46d9ac700495069f2b089))


### Bug Fixes

* **deps:** update gh-aw hashes, switch to daily nix-update ([#401](https://github.com/JacobPEvans/nix-ai/issues/401)) ([e7ae532](https://github.com/JacobPEvans/nix-ai/commit/e7ae532cbc8af50da55c8d881e93fd0cfad491ac))

## [1.28.0](https://github.com/JacobPEvans/nix-ai/compare/v1.27.0...v1.28.0) (2026-04-02)


### Features

* **pal:** 100% reliability via auto mode, Doppler fallback, and global rules ([#394](https://github.com/JacobPEvans/nix-ai/issues/394)) ([486173a](https://github.com/JacobPEvans/nix-ai/commit/486173a996f895403e30a9af2e0e3dc628023ba8))

## [1.27.0](https://github.com/JacobPEvans/nix-ai/compare/v1.26.0...v1.27.0) (2026-04-01)


### Features

* **claude:** auto-generate marketplace.json for jacobpevans-cc-plugins ([#391](https://github.com/JacobPEvans/nix-ai/issues/391)) ([78b0e1d](https://github.com/JacobPEvans/nix-ai/commit/78b0e1d2bbba391b43c2c0e4f567655d9f83d1a5))

## [1.26.0](https://github.com/JacobPEvans/nix-ai/compare/v1.25.4...v1.26.0) (2026-04-01)


### Features

* **claude:** add overlayFiles option for marketplace plugins ([#388](https://github.com/JacobPEvans/nix-ai/issues/388)) ([ef96354](https://github.com/JacobPEvans/nix-ai/commit/ef963545391eac936e0b67b187c8883a11810a3e))

## [1.25.4](https://github.com/JacobPEvans/nix-ai/compare/v1.25.3...v1.25.4) (2026-04-01)


### Bug Fixes

* **mlx:** disable reasoning parser to fix streaming tool calls ([cb18f84](https://github.com/JacobPEvans/nix-ai/commit/cb18f846c8ba334a57155e15ff5634bb19bcde94))

## [1.25.3](https://github.com/JacobPEvans/nix-ai/compare/v1.25.2...v1.25.3) (2026-03-31)


### Bug Fixes

* **deps:** correct gh-aw v0.65.0 source hash ([#386](https://github.com/JacobPEvans/nix-ai/issues/386)) ([8fd8952](https://github.com/JacobPEvans/nix-ai/commit/8fd8952afd95d3546d081a97f8cab51a3f6e504b))

## [1.25.2](https://github.com/JacobPEvans/nix-ai/compare/v1.25.1...v1.25.2) (2026-03-31)


### Bug Fixes

* **deps:** update all flake inputs ([#384](https://github.com/JacobPEvans/nix-ai/issues/384)) ([b997f2d](https://github.com/JacobPEvans/nix-ai/commit/b997f2dd7ada5e5712f0d0aa1cdca04b28c60cb6))

## [1.25.1](https://github.com/JacobPEvans/nix-ai/compare/v1.25.0...v1.25.1) (2026-03-29)


### Bug Fixes

* remove unnecessary comments from python centralization ([#374](https://github.com/JacobPEvans/nix-ai/issues/374)) ([b287dce](https://github.com/JacobPEvans/nix-ai/commit/b287dceedd17e0496d856d889ffde39b6719368a))

## [1.25.0](https://github.com/JacobPEvans/nix-ai/compare/v1.24.8...v1.25.0) (2026-03-29)


### Features

* **mlx:** establish ecosystem stack with parakeet-mlx and mlx-vlm ([#365](https://github.com/JacobPEvans/nix-ai/issues/365)) ([265cd12](https://github.com/JacobPEvans/nix-ai/commit/265cd128f514cb611ba34a6bb491c33dc555370c))


### Bug Fixes

* **ci:** skip benchmark-action when no results to post ([#363](https://github.com/JacobPEvans/nix-ai/issues/363)) ([d454020](https://github.com/JacobPEvans/nix-ai/commit/d4540204b78858460a938c3375fa5ef6251b78f9))
* **deps:** centralize Python version and Renovate pep621 policy ([#373](https://github.com/JacobPEvans/nix-ai/issues/373)) ([4fce2a9](https://github.com/JacobPEvans/nix-ai/commit/4fce2a962be645260e58cdddbcb80c6387975c33))
* **mlx:** correct mlx-preflight path construction ([#360](https://github.com/JacobPEvans/nix-ai/issues/360)) ([02ca479](https://github.com/JacobPEvans/nix-ai/commit/02ca4794ff2d88c5c4ca5f5ec5b14062cf9eebf4))

## [1.24.8](https://github.com/JacobPEvans/nix-ai/compare/v1.24.7...v1.24.8) (2026-03-29)


### Bug Fixes

* remove stale versions from wrapper package comments ([#368](https://github.com/JacobPEvans/nix-ai/issues/368)) ([5ac0e31](https://github.com/JacobPEvans/nix-ai/commit/5ac0e31f43779aa701ef94b27e42588732dff0ac))
* **security:** upgrade pygments and remove all CVE ignores ([#369](https://github.com/JacobPEvans/nix-ai/issues/369)) ([1cac3ad](https://github.com/JacobPEvans/nix-ai/commit/1cac3ad60a1a6f22f845e19dd6eaed5435114cfa))

## [1.24.7](https://github.com/JacobPEvans/nix-ai/compare/v1.24.6...v1.24.7) (2026-03-29)


### Bug Fixes

* **docs:** distinguish static vs runtime validation; fix OSV scan ([#353](https://github.com/JacobPEvans/nix-ai/issues/353)) ([759c613](https://github.com/JacobPEvans/nix-ai/commit/759c613ab5f7da61dba02bd84b6c314e19d4fe1e))

## [1.24.6](https://github.com/JacobPEvans/nix-ai/compare/v1.24.5...v1.24.6) (2026-03-27)


### Bug Fixes

* remove doppler-mcp preflight check causing MCP startup race ([#343](https://github.com/JacobPEvans/nix-ai/issues/343)) ([6451d27](https://github.com/JacobPEvans/nix-ai/commit/6451d27ff69d4e18c4eb2abb6539439bd78e72ce))

## [1.24.5](https://github.com/JacobPEvans/nix-ai/compare/v1.24.4...v1.24.5) (2026-03-26)


### Bug Fixes

* **security:** add Python security scanning and OSV scanner to CI ([#341](https://github.com/JacobPEvans/nix-ai/issues/341)) ([e4645d5](https://github.com/JacobPEvans/nix-ai/commit/e4645d5cf7e3837a3afde8eb278aced0d235c551))

## [1.24.4](https://github.com/JacobPEvans/nix-ai/compare/v1.24.3...v1.24.4) (2026-03-26)


### Bug Fixes

* **ci:** replace stub benchmark PR comments with benchmark-action ([#333](https://github.com/JacobPEvans/nix-ai/issues/333)) ([64c56a7](https://github.com/JacobPEvans/nix-ai/commit/64c56a7f5a820e0b30f3b79f23306b0b9f50feb2))
* **mlx:** use footprint for memory reporting in mlx-status ([#332](https://github.com/JacobPEvans/nix-ai/issues/332)) ([a7b57f7](https://github.com/JacobPEvans/nix-ai/commit/a7b57f73e1b31c756948ebe245375318e5e26332))

## [1.24.3](https://github.com/JacobPEvans/nix-ai/compare/v1.24.2...v1.24.3) (2026-03-25)


### Bug Fixes

* **mlx:** switch default model to Qwen3.5-27B to prevent memory freezes ([#328](https://github.com/JacobPEvans/nix-ai/issues/328)) ([3945679](https://github.com/JacobPEvans/nix-ai/commit/39456794a507a617c6c4f9a2fbd4f76f4312fa91))

## [1.24.2](https://github.com/JacobPEvans/nix-ai/compare/v1.24.1...v1.24.2) (2026-03-25)


### Bug Fixes

* **security:** pin uv tool installs and block compromised LiteLLM ([#324](https://github.com/JacobPEvans/nix-ai/issues/324)) ([9279aa4](https://github.com/JacobPEvans/nix-ai/commit/9279aa418a85d03e2debb933a2adaad1bd6873ad))

## [1.24.1](https://github.com/JacobPEvans/nix-ai/compare/v1.24.0...v1.24.1) (2026-03-24)


### Bug Fixes

* **deps:** close Renovate automation gaps for all version-pinned packages ([#321](https://github.com/JacobPEvans/nix-ai/issues/321)) ([3d7e2a7](https://github.com/JacobPEvans/nix-ai/commit/3d7e2a767f8edbc70b9ea4f6981042ec53098e0b))

## [1.24.0](https://github.com/JacobPEvans/nix-ai/compare/v1.23.0...v1.24.0) (2026-03-24)


### Features

* add browser-use skills via synthetic marketplace ([#319](https://github.com/JacobPEvans/nix-ai/issues/319)) ([c4315cb](https://github.com/JacobPEvans/nix-ai/commit/c4315cb05953f4380622e6d17db8a783f6bc1c44))


### Bug Fixes

* **claude:** set writes_only=false in wakatime config ([#318](https://github.com/JacobPEvans/nix-ai/issues/318)) ([0969bce](https://github.com/JacobPEvans/nix-ai/commit/0969bcecfb27a25afb37cab78cd7b1ff6982f169))

## [1.23.0](https://github.com/JacobPEvans/nix-ai/compare/v1.22.1...v1.23.0) (2026-03-22)


### Features

* **benchmarks:** add MLX benchmark CI/CD system ([#306](https://github.com/JacobPEvans/nix-ai/issues/306)) ([46d5f7f](https://github.com/JacobPEvans/nix-ai/commit/46d5f7f579383c6e650f2a7ff43e6f1c8fab51c0))

## [1.22.1](https://github.com/JacobPEvans/nix-ai/compare/v1.22.0...v1.22.1) (2026-03-22)


### Bug Fixes

* move git policy to nix-home, add separation guidelines ([#293](https://github.com/JacobPEvans/nix-ai/issues/293)) ([c927776](https://github.com/JacobPEvans/nix-ai/commit/c9277768fcb697b9b2724c33794278181def8518))
* remove stale manual plugin list from development.nix comment ([#292](https://github.com/JacobPEvans/nix-ai/issues/292)) ([d2e7dc3](https://github.com/JacobPEvans/nix-ai/commit/d2e7dc3e2f5cf50703b0efcd4809b64ce2db5c04))

## [1.22.0](https://github.com/JacobPEvans/nix-ai/compare/v1.21.0...v1.22.0) (2026-03-22)


### Features

* **orchestrator:** add agent framework evaluation scripts ([7490ad0](https://github.com/JacobPEvans/nix-ai/commit/7490ad05b50b93da3df109eab374394a95464543))

## [1.21.0](https://github.com/JacobPEvans/nix-ai/compare/v1.20.1...v1.21.0) (2026-03-22)


### Features

* **mlx:** enable server-side tool calling for vllm-mlx ([#280](https://github.com/JacobPEvans/nix-ai/issues/280)) ([7771757](https://github.com/JacobPEvans/nix-ai/commit/77717579cb52be012e4a8bba99f4af9b1a2583c4))

## [1.20.1](https://github.com/JacobPEvans/nix-ai/compare/v1.20.0...v1.20.1) (2026-03-22)


### Bug Fixes

* **mlx:** simplify OOM prevention to minimal 3-layer defense ([54208d2](https://github.com/JacobPEvans/nix-ai/commit/54208d28147db1fb7cfeccfe76dacd7a1dd3aa4c))
* quote flake URL in orchestrator .envrc ([10c57ba](https://github.com/JacobPEvans/nix-ai/commit/10c57badb8bfa8b7ccfd610346ea16a5bf417a95))

## [1.20.0](https://github.com/JacobPEvans/nix-ai/compare/v1.19.1...v1.20.0) (2026-03-21)


### Features

* add Google Workspace MCP server and gws CLI ([#269](https://github.com/JacobPEvans/nix-ai/issues/269)) ([e25cee2](https://github.com/JacobPEvans/nix-ai/commit/e25cee23ac306e9d9be82bab538cee3bb4add0da))
* add visual-explainer marketplace plugin ([#272](https://github.com/JacobPEvans/nix-ai/issues/272)) ([b7d5094](https://github.com/JacobPEvans/nix-ai/commit/b7d5094263702058059ed0a384ca5ea10335263b))


### Bug Fixes

* add port allocation docs and negative regression tests ([#262](https://github.com/JacobPEvans/nix-ai/issues/262)) ([f3e192d](https://github.com/JacobPEvans/nix-ai/commit/f3e192dff69f09a8ba76c99a88e555b1f8572132))
* **deps:** drop llama-index meta-package, remove 9 unused transitive deps ([#274](https://github.com/JacobPEvans/nix-ai/issues/274)) ([92ce757](https://github.com/JacobPEvans/nix-ai/commit/92ce75716aeab79bd5a6cad019edad79edae54eb))
* **mlx:** cap KV cache at 16GB to prevent OOM ([#271](https://github.com/JacobPEvans/nix-ai/issues/271)) ([630f9a3](https://github.com/JacobPEvans/nix-ai/commit/630f9a365083c6ba2a3ea50de3772a224a8fb808))
* **pal:** bulletproof MCP diagnostics, logs, and activation ([#266](https://github.com/JacobPEvans/nix-ai/issues/266)) ([6836fe9](https://github.com/JacobPEvans/nix-ai/commit/6836fe97271c991a57a17c6110336e879574dbd5))

## [1.19.1](https://github.com/JacobPEvans/nix-ai/compare/v1.19.0...v1.19.1) (2026-03-21)


### Bug Fixes

* defer cache purge when Claude Code sessions are active ([#268](https://github.com/JacobPEvans/nix-ai/issues/268)) ([8b63780](https://github.com/JacobPEvans/nix-ai/commit/8b6378041feb499f5cc087c9d6b6657fc36ee5e3))
* disable greptile plugin (cost) ([#264](https://github.com/JacobPEvans/nix-ai/issues/264)) ([6c780a1](https://github.com/JacobPEvans/nix-ai/commit/6c780a1933934b60153e48d7171f01a2ea41fecd))

## [1.19.0](https://github.com/JacobPEvans/nix-ai/compare/v1.18.0...v1.19.0) (2026-03-21)


### Features

* **mlx:** split module, add benchmarks & health check ([#263](https://github.com/JacobPEvans/nix-ai/issues/263)) ([cc4a95f](https://github.com/JacobPEvans/nix-ai/commit/cc4a95f9bc9a7481eee211cdd6738970854ab76b))

## [1.18.0](https://github.com/JacobPEvans/nix-ai/compare/v1.17.6...v1.18.0) (2026-03-21)


### Features

* **mlx:** concurrency options and mlx-bench benchmark script ([#260](https://github.com/JacobPEvans/nix-ai/issues/260)) ([e1cefde](https://github.com/JacobPEvans/nix-ai/commit/e1cefdeab9d0f4014eb01e990e401654c43f922e))

## [1.17.6](https://github.com/JacobPEvans/nix-ai/compare/v1.17.5...v1.17.6) (2026-03-21)


### Bug Fixes

* remove plugin cache mutation from activation scripts ([#258](https://github.com/JacobPEvans/nix-ai/issues/258)) ([4df8af5](https://github.com/JacobPEvans/nix-ai/commit/4df8af59171a49405b3eb42e91938dfca5ca4db2))

## [1.17.5](https://github.com/JacobPEvans/nix-ai/compare/v1.17.4...v1.17.5) (2026-03-20)


### Bug Fixes

* **mlx:** update LaunchAgent flags for vllm-mlx 0.2.6 CLI, split checks.nix ([#250](https://github.com/JacobPEvans/nix-ai/issues/250)) ([b9c7165](https://github.com/JacobPEvans/nix-ai/commit/b9c716564687a92dae39f4ea03ff650da6895ecb))

## [1.17.4](https://github.com/JacobPEvans/nix-ai/compare/v1.17.3...v1.17.4) (2026-03-20)


### Bug Fixes

* dual-backend MLX module with CLI flag validation ([#248](https://github.com/JacobPEvans/nix-ai/issues/248)) ([1152927](https://github.com/JacobPEvans/nix-ai/commit/11529279aed497c8e2aad82640565ef5c830d5a3))

## [1.17.3](https://github.com/JacobPEvans/nix-ai/compare/v1.17.2...v1.17.3) (2026-03-20)


### Bug Fixes

* cross-repo cleanup after unstable overlay removal ([#249](https://github.com/JacobPEvans/nix-ai/issues/249)) ([9093bd9](https://github.com/JacobPEvans/nix-ai/commit/9093bd9424a70ea870c226a6d7855eb38238e2c9))

## [1.17.2](https://github.com/JacobPEvans/nix-ai/compare/v1.17.1...v1.17.2) (2026-03-20)


### Bug Fixes

* add MLX perf tuning flags and remove Ollama from stack ([#243](https://github.com/JacobPEvans/nix-ai/issues/243)) ([f375d87](https://github.com/JacobPEvans/nix-ai/commit/f375d8758903d7e1909514237ec36349c5d158bb))
* add MLX performance tuning flags for vllm-mlx LaunchAgent ([f375d87](https://github.com/JacobPEvans/nix-ai/commit/f375d8758903d7e1909514237ec36349c5d158bb))

## [1.17.1](https://github.com/JacobPEvans/nix-ai/compare/v1.17.0...v1.17.1) (2026-03-20)


### Bug Fixes

* **checks:** bump test stateVersion to 25.11 ([#244](https://github.com/JacobPEvans/nix-ai/issues/244)) ([616d251](https://github.com/JacobPEvans/nix-ai/commit/616d251f0968ddb28521403e0c6d3f4c7dc58429))

## [1.17.0](https://github.com/JacobPEvans/nix-ai/compare/v1.16.5...v1.17.0) (2026-03-20)


### Features

* remove Ollama, unify local inference on MLX port 11434 ([#242](https://github.com/JacobPEvans/nix-ai/issues/242)) ([8d3503d](https://github.com/JacobPEvans/nix-ai/commit/8d3503d566fac8b5e47d9598a0c3c26902e15171))

## [1.16.5](https://github.com/JacobPEvans/nix-ai/compare/v1.16.4...v1.16.5) (2026-03-20)


### Bug Fixes

* **docs:** remove inline keychain password from testing docs ([#240](https://github.com/JacobPEvans/nix-ai/issues/240)) ([5dee71e](https://github.com/JacobPEvans/nix-ai/commit/5dee71e72721ec579045384a18b95eb7ed7a9179))

## [1.16.4](https://github.com/JacobPEvans/nix-ai/compare/v1.16.3...v1.16.4) (2026-03-19)


### Bug Fixes

* resolve claude binary path during sudo activation ([#238](https://github.com/JacobPEvans/nix-ai/issues/238)) ([a0d6d1a](https://github.com/JacobPEvans/nix-ai/commit/a0d6d1a9e77a77982593c228aa18119a97d0006a))

## [1.16.3](https://github.com/JacobPEvans/nix-ai/compare/v1.16.2...v1.16.3) (2026-03-19)


### Bug Fixes

* auto-sync Claude Code plugin cache after nix rebuild ([#235](https://github.com/JacobPEvans/nix-ai/issues/235)) ([edba1ad](https://github.com/JacobPEvans/nix-ai/commit/edba1adb0d2ade246e7c7ce51a60762d8fb770ae))
* cap Ollama memory at 20G, switch MLX default to Qwen3.5-122B MoE ([#234](https://github.com/JacobPEvans/nix-ai/issues/234)) ([9d82a86](https://github.com/JacobPEvans/nix-ai/commit/9d82a86d8a17b88eeb670e490a6401ff7f92e73f))

## [1.16.2](https://github.com/JacobPEvans/nix-ai/compare/v1.16.1...v1.16.2) (2026-03-19)


### Bug Fixes

* clarify MLX port description as default choice ([#232](https://github.com/JacobPEvans/nix-ai/issues/232)) ([d9125dc](https://github.com/JacobPEvans/nix-ai/commit/d9125dcba9630944fc2258b52aded1e8bf7e5e38))

## [1.16.1](https://github.com/JacobPEvans/nix-ai/compare/v1.16.0...v1.16.1) (2026-03-19)


### Bug Fixes

* change MLX port from 11435 to 11436 (external port conflict) ([#230](https://github.com/JacobPEvans/nix-ai/issues/230)) ([8a8dde9](https://github.com/JacobPEvans/nix-ai/commit/8a8dde9e90ef09491089115fbb19ecaa7856e605))

## [1.16.0](https://github.com/JacobPEvans/nix-ai/compare/v1.15.0...v1.16.0) (2026-03-19)


### Features

* enable MLX inference server (vllm-mlx on port 11435) ([#229](https://github.com/JacobPEvans/nix-ai/issues/229)) ([b7b2a1b](https://github.com/JacobPEvans/nix-ai/commit/b7b2a1b7a977873d4557a6f7e9c8bfece61a213c))


### Bug Fixes

* add release-please config for manifest mode ([5c1d9eb](https://github.com/JacobPEvans/nix-ai/commit/5c1d9ebbab3ec1ef87813e837a188945b74f0e48))
* move sync-ollama-models to pal-models.nix for MLX model append ([#226](https://github.com/JacobPEvans/nix-ai/issues/226)) ([d66fca5](https://github.com/JacobPEvans/nix-ai/commit/d66fca59ee907056e53a23f12ca7853ddfb9b902))
* PAL MCP model routing — fix JSON nesting, MLX-first default, add MLX models ([#225](https://github.com/JacobPEvans/nix-ai/issues/225)) ([15b297a](https://github.com/JacobPEvans/nix-ai/commit/15b297adc5208e54e67056f4382fa3396b525d77))
* **plugins:** update stale plugin count comment in development.nix ([#222](https://github.com/JacobPEvans/nix-ai/issues/222)) ([5ffd43d](https://github.com/JacobPEvans/nix-ai/commit/5ffd43db73206590cda7797aa37a642dc94521c9))
* sync release-please permissions and VERSION ([df6938a](https://github.com/JacobPEvans/nix-ai/commit/df6938a57a3944d5d24bdfdddcfaf2ba5f6d0278))

## [1.15.0](https://github.com/JacobPEvans/nix-ai/compare/v1.14.0...v1.15.0) (2026-03-18)


### Features

* **plugins:** add Bitwarden ai-plugins marketplace ([#217](https://github.com/JacobPEvans/nix-ai/issues/217)) ([f1ddbc1](https://github.com/JacobPEvans/nix-ai/commit/f1ddbc1e639d14fda48546663d21a9eac2f9c5a5))


### Bug Fixes

* **devshell:** use python package attr instead of version in orchestrator shell ([#218](https://github.com/JacobPEvans/nix-ai/issues/218)) ([ae9fe44](https://github.com/JacobPEvans/nix-ai/commit/ae9fe44ff157c664b6f79eb9d3d4b2126d2ef1aa))

## [1.14.0](https://github.com/JacobPEvans/nix-ai/compare/v1.13.0...v1.14.0) (2026-03-18)


### Bug Fixes

* **tests:** use MagicMock instance for SimpleDocumentStore in pipeline tests ([#215](https://github.com/JacobPEvans/nix-ai/issues/215)) ([e788030](https://github.com/JacobPEvans/nix-ai/commit/e788030048a5af2c2ee361250a345cb107da90ad))

## [1.13.0](https://github.com/JacobPEvans/nix-ai/compare/v1.12.0...v1.13.0) (2026-03-17)


### Features

* orchestrator phase 2-3 — loaders, embeddings, workflows ([#208](https://github.com/JacobPEvans/nix-ai/issues/208)) ([585ed75](https://github.com/JacobPEvans/nix-ai/commit/585ed75059233d6a9dff6552efbd8de4b5c83c6e))

## [1.12.0](https://github.com/JacobPEvans/nix-ai/compare/v1.11.0...v1.12.0) (2026-03-17)


### Bug Fixes

* **docs:** correct PAL model script references in MCP README ([#211](https://github.com/JacobPEvans/nix-ai/issues/211)) ([c880929](https://github.com/JacobPEvans/nix-ai/commit/c880929eff3b5cffca4cb6d32e8c9250e4c591ca))

## [1.11.0](https://github.com/JacobPEvans/nix-ai/compare/v1.10.0...v1.11.0) (2026-03-17)


### Bug Fixes

* **plugins:** replace per-file symlinks with directory symlinks ([#186](https://github.com/JacobPEvans/nix-ai/issues/186)) ([cff42d5](https://github.com/JacobPEvans/nix-ai/commit/cff42d58f776b58e75faf8f3a9e45dfa0810b966))

## [1.10.0](https://github.com/JacobPEvans/nix-ai/compare/v1.9.0...v1.10.0) (2026-03-17)


### Features

* add orchestrator devShell with skill schema and semantic router ([de9826d](https://github.com/JacobPEvans/nix-ai/commit/de9826d463f7a950613c6470dbd21e85f9c26754))


### Bug Fixes

* address PR [#188](https://github.com/JacobPEvans/nix-ai/issues/188) review feedback ([a7f4782](https://github.com/JacobPEvans/nix-ai/commit/a7f4782b5e93eb4bc28ff49bf64caf051a90a88d))
* **deps:** update jacobpevans-cc-plugins for /ship command ([#184](https://github.com/JacobPEvans/nix-ai/issues/184)) ([f4983a9](https://github.com/JacobPEvans/nix-ai/commit/f4983a9102065acb942fda376d49f3142ae4b034))
* **devenv:** use python package attr instead of version string ([#187](https://github.com/JacobPEvans/nix-ai/issues/187)) ([daca68a](https://github.com/JacobPEvans/nix-ai/commit/daca68afbf7dc2055853f3fc1c9b19d9b467068b))
* raise issue hard limit from 50 to 150 per repo ([25ccf92](https://github.com/JacobPEvans/nix-ai/commit/25ccf9294a4fc51118acf9de3cb0214e34c5e77f))

## [1.9.0](https://github.com/JacobPEvans/nix-ai/compare/v1.8.0...v1.9.0) (2026-03-15)


### Bug Fixes

* **ci:** add pull-requests:write for release-please auto-approve ([007d630](https://github.com/JacobPEvans/nix-ai/commit/007d630d28ee4b59e2ce11d7926f3f0a0aac2e58))

## [1.8.0](https://github.com/JacobPEvans/nix-ai/compare/v1.7.0...v1.8.0) (2026-03-15)


### Bug Fixes

* **ci:** migrate copilot-setup-steps to determinate-nix-action@v3 ([#175](https://github.com/JacobPEvans/nix-ai/issues/175)) ([47eef4b](https://github.com/JacobPEvans/nix-ai/commit/47eef4b714e6b31e2fdf002d678e824ee247bc72))
* golden standard — bugs, cross-platform, dead code, style ([#174](https://github.com/JacobPEvans/nix-ai/issues/174)) ([4954bd1](https://github.com/JacobPEvans/nix-ai/commit/4954bd1e6a7c6e388dbb26c85736f3cecf8e1ee7))
* migrate Bash permission format from colon to space separator ([#177](https://github.com/JacobPEvans/nix-ai/issues/177)) ([62658c1](https://github.com/JacobPEvans/nix-ai/commit/62658c1ade1cf96e5b735dd0c47c942a3a3dc423))

## [1.7.0](https://github.com/JacobPEvans/nix-ai/compare/v1.6.0...v1.7.0) (2026-03-15)


### Bug Fixes

* **devenv:** use impure eval for runtime DEVENV_ROOT resolution ([#172](https://github.com/JacobPEvans/nix-ai/issues/172)) ([d0247dc](https://github.com/JacobPEvans/nix-ai/commit/d0247dc20ea3a62511e9ea7cbf2c847f2f3778b7))

## [1.6.0](https://github.com/JacobPEvans/nix-ai/compare/v1.5.0...v1.6.0) (2026-03-15)


### Features

* add MLX inference server home-manager module ([#161](https://github.com/JacobPEvans/nix-ai/issues/161)) ([eb4e91f](https://github.com/JacobPEvans/nix-ai/commit/eb4e91ffa3a3a6113e59f57b4b4e5a9529943dc7))
* **devenv:** add nixpkgs-python input and remove flake-level nixConfig ([#170](https://github.com/JacobPEvans/nix-ai/issues/170)) ([b80ceca](https://github.com/JacobPEvans/nix-ai/commit/b80ceca8a6a486877567a339bce8ab30fe57614b))
* migrate flake.lock updates to Renovate nix manager ([#169](https://github.com/JacobPEvans/nix-ai/issues/169)) ([5dbaf23](https://github.com/JacobPEvans/nix-ai/commit/5dbaf23e8bab84847e7ec64a0edf41b9178755ee))


### Bug Fixes

* **ci:** exclude CHANGELOG.md from markdownlint ([#171](https://github.com/JacobPEvans/nix-ai/issues/171)) ([f974ead](https://github.com/JacobPEvans/nix-ai/commit/f974eada87f0c10a29fe6897b5543ebb289b86fd))
* **ci:** upgrade ci-gate.yml to Merge Gatekeeper pattern ([#162](https://github.com/JacobPEvans/nix-ai/issues/162)) ([10a5a47](https://github.com/JacobPEvans/nix-ai/commit/10a5a478b9e57fc870df527838ba686a2315576b))

## [1.5.0](https://github.com/JacobPEvans/nix-ai/compare/v1.4.0...v1.5.0) (2026-03-14)


### Features

* add devenv with ai-dev shell, convert mlx-server to devenv ([#158](https://github.com/JacobPEvans/nix-ai/issues/158)) ([0d1deb1](https://github.com/JacobPEvans/nix-ai/commit/0d1deb113464adb622186e08c4b95d3882db4c8f))

## [1.4.0](https://github.com/JacobPEvans/nix-ai/compare/v1.3.0...v1.4.0) (2026-03-14)

### Bug Fixes

* build pal-mcp-server as Nix derivation ([#157](https://github.com/JacobPEvans/nix-ai/issues/157)) ([7e5ab79](https://github.com/JacobPEvans/nix-ai/commit/7e5ab799c0ae56d7af12cfe2769988f780c61373))

## [1.3.0](https://github.com/JacobPEvans/nix-ai/compare/v1.2.0...v1.3.0) (2026-03-14)

### Features

* enable 1M context window models in model picker ([#155](https://github.com/JacobPEvans/nix-ai/issues/155)) ([73ae890](https://github.com/JacobPEvans/nix-ai/commit/73ae890e1b872af01dedd7dcab38b24740dbb914))

## [1.2.0](https://github.com/JacobPEvans/nix-ai/compare/v1.1.0...v1.2.0) (2026-03-13)

### Features

* add splunk-mcp-connect wrapper script ([#151](https://github.com/JacobPEvans/nix-ai/issues/151)) ([294abd1](https://github.com/JacobPEvans/nix-ai/commit/294abd13b211390518bd68a76166fbef1f78141f))

## [1.1.0](https://github.com/JacobPEvans/nix-ai/compare/v1.0.0...v1.1.0) (2026-03-13)

### Features

* add daily repo health audit agentic workflow ([#137](https://github.com/JacobPEvans/nix-ai/issues/137)) ([daa4a0e](https://github.com/JacobPEvans/nix-ai/commit/daa4a0ea05d5a828034d24377f187273763aecf9))
* add release-please automation ([#96](https://github.com/JacobPEvans/nix-ai/issues/96)) ([06fa54a](https://github.com/JacobPEvans/nix-ai/commit/06fa54ae068b3b43df85755059080ece10a1d4fc))
* add scheduled AI workflow callers ([#113](https://github.com/JacobPEvans/nix-ai/issues/113)) ([475114a](https://github.com/JacobPEvans/nix-ai/commit/475114a1cbf0c52609e9a5199cc62154b334304a))
* **ci:** add flake update workflow for upstream dispatch events ([#108](https://github.com/JacobPEvans/nix-ai/issues/108)) ([9e3e6d0](https://github.com/JacobPEvans/nix-ai/commit/9e3e6d00b83d802c60e5752294e8b2dd7e3022ca))
* **claude:** make effortLevel optional, add adaptive thinking env var ([#106](https://github.com/JacobPEvans/nix-ai/issues/106)) ([c26c599](https://github.com/JacobPEvans/nix-ai/commit/c26c599b19ef1d6a074689410e6cc33c4a893c8b))
* **claude:** make settings.json writable via activation-time merge ([#107](https://github.com/JacobPEvans/nix-ai/issues/107)) ([9af21f8](https://github.com/JacobPEvans/nix-ai/commit/9af21f8339078d0c69e3799bc0b32bf17ab596f9))
* disable automatic triggers on Claude-executing workflows ([ad7cef3](https://github.com/JacobPEvans/nix-ai/commit/ad7cef3bf6462486a2c2704697d5bd60fbfa0a59))
* expose gh-aw package, fix PAL hash, add nix-update to flake workflow ([#131](https://github.com/JacobPEvans/nix-ai/issues/131)) ([f519f98](https://github.com/JacobPEvans/nix-ai/commit/f519f98f63061bf25921bdcf9bf9dc7d7db931e7))
* migrate to ai-workflows suite groupings (v0.8.0) ([#102](https://github.com/JacobPEvans/nix-ai/issues/102)) ([4b6b806](https://github.com/JacobPEvans/nix-ai/commit/4b6b8068e955afbde551cb0c67a50129c3d83376))
* **open-webui:** add LaunchAgent for auto-start on login ([#110](https://github.com/JacobPEvans/nix-ai/issues/110)) ([d3f8460](https://github.com/JacobPEvans/nix-ai/commit/d3f84604e3373e3f799b9ed2a88c414c3d36174b))
* **pal:** set DEFAULT_MODEL to latest Gemini (gemini-3-pro-preview) ([#109](https://github.com/JacobPEvans/nix-ai/issues/109)) ([c540bda](https://github.com/JacobPEvans/nix-ai/commit/c540bda62de5712365e0638632e120ce3f506ae2))
* re-enable issue auto-resolve gated by ai:ready label ([#127](https://github.com/JacobPEvans/nix-ai/issues/127)) ([3342d6f](https://github.com/JacobPEvans/nix-ai/commit/3342d6fb105e714384c717248cf70f9dda78c6ad))
* show repo/worktree in statusline cwd instead of basename ([#129](https://github.com/JacobPEvans/nix-ai/issues/129)) ([5f4feb9](https://github.com/JacobPEvans/nix-ai/commit/5f4feb94b1cffa22fdec2316588d7e824f217443))
* switch to ClaudeCodeStatusLine (daniel3303) 2-line statusline ([#126](https://github.com/JacobPEvans/nix-ai/issues/126)) ([805b240](https://github.com/JacobPEvans/nix-ai/commit/805b240bf23815421f123b38d6f6d6093769b051)), closes [#103](https://github.com/JacobPEvans/nix-ai/issues/103)
* upgrade to Python 3.14 and add MLX inference server ([#142](https://github.com/JacobPEvans/nix-ai/issues/142)) ([60695d9](https://github.com/JacobPEvans/nix-ai/commit/60695d9dd1fc759541f806170099b3f42886c950))
* WakaTime Doppler injection, PAL flake pinning, GitHub MCP disabled ([#122](https://github.com/JacobPEvans/nix-ai/issues/122)) ([448417c](https://github.com/JacobPEvans/nix-ai/commit/448417cbbd6458b103a92fe1d0a7945a44a06928))

### Bug Fixes

* add concurrency groups to prevent duplicate PR creation ([#114](https://github.com/JacobPEvans/nix-ai/issues/114)) ([8c6a543](https://github.com/JacobPEvans/nix-ai/commit/8c6a54382db529bdb843bd00d6742ada92489f30))
* add diagnostic logging to doppler-mcp and check-pal-mcp health script ([#130](https://github.com/JacobPEvans/nix-ai/issues/130)) ([a88b266](https://github.com/JacobPEvans/nix-ai/commit/a88b26611db1deb81aa725d829253403df3d5410))
* **ci:** use [@v0](https://github.com/v0) floating tag for ai-workflows references ([#104](https://github.com/JacobPEvans/nix-ai/issues/104)) ([31d1d61](https://github.com/JacobPEvans/nix-ai/commit/31d1d61ceabde91c2cfe408605b5c70df478f64e))
* **ci:** use GitHub App token for release-please to trigger CI Gate ([#147](https://github.com/JacobPEvans/nix-ai/issues/147)) ([d5837bb](https://github.com/JacobPEvans/nix-ai/commit/d5837bb2aaa4e510212ab1691a5314dd344de7dd))
* correct best-practices permissions and add ref-scoped concurrency ([#115](https://github.com/JacobPEvans/nix-ai/issues/115)) ([197d1aa](https://github.com/JacobPEvans/nix-ai/commit/197d1aaea84a95a36b1173c7b7d734d7b1e66854))
* **deps:** remove manual input list from flake update workflow ([#118](https://github.com/JacobPEvans/nix-ai/issues/118)) ([cd7946d](https://github.com/JacobPEvans/nix-ai/commit/cd7946d0a2be24da35254abb0811be16a11ac30c))
* disable hash pinning for trusted actions, use version tags ([#116](https://github.com/JacobPEvans/nix-ai/issues/116)) ([29510d5](https://github.com/JacobPEvans/nix-ai/commit/29510d59c56d0333580797af6a210c92ea1c16b6))
* remove blanket auto-merge workflow ([#117](https://github.com/JacobPEvans/nix-ai/issues/117)) ([cc0315b](https://github.com/JacobPEvans/nix-ai/commit/cc0315b19ef3bddd62fae25c6252d010e0cda0eb))
* remove redundant .markdownlint-cli2.yaml ([#91](https://github.com/JacobPEvans/nix-ai/issues/91)) ([6de3e82](https://github.com/JacobPEvans/nix-ai/commit/6de3e8291525ec9f77c79829f48776a2d0aa5e2f))
* rename GH_APP_ID secret to GH_ACTION_JACOBPEVANS_APP_ID ([#132](https://github.com/JacobPEvans/nix-ai/issues/132)) ([ed48910](https://github.com/JacobPEvans/nix-ai/commit/ed4891083564906a6b0fbd87e5302cfbc7e5b5d6))
* resolve MCP server issues and add HuggingFace + MLX tools ([#144](https://github.com/JacobPEvans/nix-ai/issues/144)) ([fe5f2ce](https://github.com/JacobPEvans/nix-ai/commit/fe5f2ce01cbc4859ea4c01f74eeb1c26e81d46c2))
* set cleanupPeriodDays to 30 (upstream default) ([#139](https://github.com/JacobPEvans/nix-ai/issues/139)) ([8c641b6](https://github.com/JacobPEvans/nix-ai/commit/8c641b6d2406b650058a569674d4864d598666ea))
* update gh-aw to v0.57.2 and remove silent failure in workflow ([#135](https://github.com/JacobPEvans/nix-ai/issues/135)) ([c34008d](https://github.com/JacobPEvans/nix-ai/commit/c34008d7cbbe64f22211ab8f17becf89fdc4f944))
* update stale nix-config references to nix-darwin ([#112](https://github.com/JacobPEvans/nix-ai/issues/112)) ([4f09511](https://github.com/JacobPEvans/nix-ai/commit/4f09511c8920851294c76151cc58861caa128363))
* use absolute path for shasum in verify-cache-integrity.sh ([#128](https://github.com/JacobPEvans/nix-ai/issues/128)) ([c8fabcc](https://github.com/JacobPEvans/nix-ai/commit/c8fabcc930dbf5aef22fe16dc9478c82d8c0753d))
