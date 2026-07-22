# Changelog

## [3.2.3](https://github.com/dryvist/nix-ai/compare/v3.2.2...v3.2.3) (2026-07-22)


### Bug Fixes

* **mlx:** preserve productive watchdog work ([e202689](https://github.com/dryvist/nix-ai/commit/e202689ebc653702825739f26cbb3bcee8c42c71))
* **mlx:** preserve productive watchdog work ([c9ff3ee](https://github.com/dryvist/nix-ai/commit/c9ff3ee98c9f9ff5a605079df8e647fa71d06e32))

## [3.2.2](https://github.com/dryvist/nix-ai/compare/v3.2.1...v3.2.2) (2026-07-21)


### Bug Fixes

* keep Splunk MCP auth placeholder ShellCheck-clean ([f8a0a8c](https://github.com/dryvist/nix-ai/commit/f8a0a8cf530cdec8f75f1764ad18b1b93f020a52))
* **mcp:** preserve literal auth placeholder under shellcheck ([f8a0a8c](https://github.com/dryvist/nix-ai/commit/f8a0a8cf530cdec8f75f1764ad18b1b93f020a52))
* **mcp:** preserve literal auth placeholder under shellcheck ([1157ef1](https://github.com/dryvist/nix-ai/commit/1157ef1f878270cb166a585b403d393ad025e8df))

## [3.2.1](https://github.com/dryvist/nix-ai/compare/v3.2.0...v3.2.1) (2026-07-21)


### Bug Fixes

* **mcp:** redact Splunk authorization header ([210ee4a](https://github.com/dryvist/nix-ai/commit/210ee4a29d70b70fd78089c92fb093ac258e6d2f))
* **mcp:** redact Splunk authorization header ([c08d28f](https://github.com/dryvist/nix-ai/commit/c08d28f34cbf9979a4e9d8a977d7f1a6f9cdab41))
* prevent Splunk MCP bearer token disclosure ([210ee4a](https://github.com/dryvist/nix-ai/commit/210ee4a29d70b70fd78089c92fb093ac258e6d2f))

## [3.2.0](https://github.com/dryvist/nix-ai/compare/v3.1.1...v3.2.0) (2026-07-21)


### Features

* **mlx:** KV-arch metadata + disable paged cache on qwen3-next 80B ([db813c3](https://github.com/dryvist/nix-ai/commit/db813c31abc87833ee3471cd660446ff80b83923))
* single-slot serving for all 40B+ MLX models ([ffb98d2](https://github.com/dryvist/nix-ai/commit/ffb98d2c24f3a3453e0bfa45e8516b0ae3a3348f))

## [3.1.1](https://github.com/dryvist/nix-ai/compare/v3.1.0...v3.1.1) (2026-07-21)


### Bug Fixes

* **mlx-cluster:** anchor rank pgrep to the venv script path ([#1333](https://github.com/dryvist/nix-ai/issues/1333)) ([08a7ccb](https://github.com/dryvist/nix-ai/commit/08a7ccbd9bfb53c8a53a02f643ceb35b5dc6caa1))

## [3.1.0](https://github.com/dryvist/nix-ai/compare/v3.0.2...v3.1.0) (2026-07-21)


### Features

* **mlx:** ping external deadman on healthy watchdog probe ([#1328](https://github.com/dryvist/nix-ai/issues/1328)) ([2319ae1](https://github.com/dryvist/nix-ai/commit/2319ae14995bac99c8163b18b3fe9b3ddb892882))

## [3.0.2](https://github.com/dryvist/nix-ai/compare/v3.0.1...v3.0.2) (2026-07-21)


### Bug Fixes

* **mlx:** watchdog probe discrimination — stop kickstarting on busy ([#1324](https://github.com/dryvist/nix-ai/issues/1324)) ([a79ff67](https://github.com/dryvist/nix-ai/commit/a79ff67ecb6d1244b917a896077a280cf796c8d0))

## [3.0.1](https://github.com/dryvist/nix-ai/compare/v3.0.0...v3.0.1) (2026-07-21)


### Bug Fixes

* **mlx:** make gpu-memory-utilization apply on the lifecycle engine path ([#1317](https://github.com/dryvist/nix-ai/issues/1317)) ([d04be98](https://github.com/dryvist/nix-ai/commit/d04be98524cffc04807acff795bf870ba7cbd128))
* **mlx:** serialize qwen3-next-80b requests (concurrency 1) ([9235f59](https://github.com/dryvist/nix-ai/commit/9235f59cb629558f531cca190f68208b3a411dad))
* **mlx:** watchdog escalation ladder — bootout+bootstrap on repeated failure ([e2935c4](https://github.com/dryvist/nix-ai/commit/e2935c43f788fa92a777815c49429596e7a47f47))

## [3.0.0](https://github.com/dryvist/nix-ai/compare/v2.4.0...v3.0.0) (2026-07-20)


### ⚠ BREAKING CHANGES

* **mlx:** rename cluster standalone-ceiling identifiers, trim option docs ([#1313](https://github.com/dryvist/nix-ai/issues/1313))

### Features

* **mlx:** default llama-swap proxy logging to debug ([#1310](https://github.com/dryvist/nix-ai/issues/1310)) ([a51fd9e](https://github.com/dryvist/nix-ai/commit/a51fd9e076024992ff4e59364211225bf4a96f83))
* **mlx:** patch vllm-mlx to honor VLLM_MLX_LOG_LEVEL, default debug ([#1312](https://github.com/dryvist/nix-ai/issues/1312)) ([a81a5c5](https://github.com/dryvist/nix-ai/commit/a81a5c5116d755235708891172305ca229c38a38))


### Refactoring

* **mlx:** rename cluster standalone-ceiling identifiers, trim option docs ([#1313](https://github.com/dryvist/nix-ai/issues/1313)) ([931cfcd](https://github.com/dryvist/nix-ai/commit/931cfcd9c0deebc69e3ad65a5aad16b8d4674932))

## [2.4.0](https://github.com/dryvist/nix-ai/compare/v2.3.0...v2.4.0) (2026-07-20)


### Features

* **mlx:** generation-parity preflight with auto-heal in cluster-join ([#1298](https://github.com/dryvist/nix-ai/issues/1298)) ([21bb181](https://github.com/dryvist/nix-ai/commit/21bb181f3f47ab5358191f5642f1b899bf3b81a9))


### Bug Fixes

* **mlx:** drop reasoning parser from 80B-Instruct catalog entry ([#1297](https://github.com/dryvist/nix-ai/issues/1297)) ([8d19e34](https://github.com/dryvist/nix-ai/commit/8d19e34d3564143b663f5d87bb0bae7b64c20c6b))
* **mlx:** generation auto-heal rebuilds from the remote flake ref ([#1299](https://github.com/dryvist/nix-ai/issues/1299)) ([b2b29ab](https://github.com/dryvist/nix-ai/commit/b2b29abbdf2f8ff2310ddc6dd105caf4213af007))

## [2.3.0](https://github.com/dryvist/nix-ai/compare/v2.2.0...v2.3.0) (2026-07-20)


### Features

* **mlx:** clusterMode.keepResidentBackends — spare a standalone engine from cluster quiesce ([#1291](https://github.com/dryvist/nix-ai/issues/1291)) ([200d107](https://github.com/dryvist/nix-ai/commit/200d10770ac4cd1bd42521818cd3d7e149d2de39))

## [2.2.0](https://github.com/dryvist/nix-ai/compare/v2.1.0...v2.2.0) (2026-07-19)


### Features

* **mlx:** cluster-join/cluster-detach lifecycle commands ([#1285](https://github.com/dryvist/nix-ai/issues/1285)) ([0eb0294](https://github.com/dryvist/nix-ai/commit/0eb0294f422648aa353e0107d68eb43ab3982553))


### Bug Fixes

* **mlx:** grep absolute paths + orchestrator robustness nits ([#1288](https://github.com/dryvist/nix-ai/issues/1288)) ([b7f3484](https://github.com/dryvist/nix-ai/commit/b7f34841f447dffb2c7fce2caafa4555c1168423))

## [2.1.0](https://github.com/dryvist/nix-ai/compare/v2.0.4...v2.1.0) (2026-07-18)


### Features

* **automode:** homelab-gated allow rules for the classifier ([002e627](https://github.com/dryvist/nix-ai/commit/002e6278ce288de5159be949b7b8543b68dcb1b3))
* **mcp:** add Zammad MCP catalog entry (basher83/Zammad-MCP) ([#1254](https://github.com/dryvist/nix-ai/issues/1254)) ([a0bd3ec](https://github.com/dryvist/nix-ai/commit/a0bd3ec824f87b1db6b65200b0f67e406f012cde))
* **mcp:** enable zammad MCP server in catalog ([ac308ae](https://github.com/dryvist/nix-ai/commit/ac308ae60b7afb4e8ea219f481342d57d1450aff))
* **mcp:** inject Vikunja credentials via doppler-mcp ([#1241](https://github.com/dryvist/nix-ai/issues/1241)) ([a998434](https://github.com/dryvist/nix-ai/commit/a998434d9905e278e3b370dfb4c1b312842cacb3))
* **mcp:** source Splunk credentials from OpenBao ([#1230](https://github.com/dryvist/nix-ai/issues/1230)) ([0a6a610](https://github.com/dryvist/nix-ai/commit/0a6a610e9dff2740662b70e1e6f1e3b0b66a4eed))
* **mlx:** add defaultRepetitionPenalty to keep batches uniform ([#1262](https://github.com/dryvist/nix-ai/issues/1262)) ([fb2afdb](https://github.com/dryvist/nix-ai/commit/fb2afdb5c054d3cb45e4234fdff35411fc7f25ff))
* **mlx:** add Qwen3-Next-80B-A3B-Instruct catalog entry (new fleet brain) ([#1272](https://github.com/dryvist/nix-ai/issues/1272)) ([e9e0569](https://github.com/dryvist/nix-ai/commit/e9e0569dd49aea8c253956ff9383af601c51eb88))
* **opencode:** render shared MCP servers via new shared mcp client helper ([#1235](https://github.com/dryvist/nix-ai/issues/1235)) ([71722ff](https://github.com/dryvist/nix-ai/commit/71722ff6e6d9afa84efaf4163be7515667a365ff))
* **qwen-code:** wire shared permissions and AGENTS.md context ([#1237](https://github.com/dryvist/nix-ai/issues/1237)) ([b0c1db9](https://github.com/dryvist/nix-ai/commit/b0c1db9302cf4269d0635c75d708eef5ea67e1c3))


### Bug Fixes

* **cluster:** pin mlx on the rank, readiness-probe the endpoint, quiesce on every kickstart ([#1245](https://github.com/dryvist/nix-ai/issues/1245)) ([8344def](https://github.com/dryvist/nix-ai/commit/8344def0e916247e823c0835a06b4af347eae8bf))
* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#1238](https://github.com/dryvist/nix-ai/issues/1238)) ([3f9afa8](https://github.com/dryvist/nix-ai/commit/3f9afa82e1877d917ae131e59c3af50ee8c4105d))
* discover-models.py: activation-time run registers nothing (env quoting); manual run with identical inputs registers 27 ([#1270](https://github.com/dryvist/nix-ai/issues/1270)) ([ad0de9f](https://github.com/dryvist/nix-ai/commit/ad0de9fa3170eb92823ce17518c3efde886231f7))
* discover-models.py: activation-time run registers nothing (env quoting); manual run with identical inputs registers 27 ([#1270](https://github.com/dryvist/nix-ai/issues/1270)) ([260c8d5](https://github.com/dryvist/nix-ai/commit/260c8d5821bb8dcb0126a56e31b9b801bc86e179))
* **docs:** drop internal secrets topology, parametrize Doppler/OpenBao identifiers ([826539e](https://github.com/dryvist/nix-ai/commit/826539ed38f6eec4dc9fa71c93eb360dea01d1b9))
* **mcp:** inline the single-use version aliases in the catalog ([#1261](https://github.com/dryvist/nix-ai/issues/1261)) ([ecdbe9e](https://github.com/dryvist/nix-ai/commit/ecdbe9e277c764546fb401dabdf488bce217f9c0))
* **mcp:** make splunk-mcp-connect pass shellcheck SC2016 ([#1243](https://github.com/dryvist/nix-ai/issues/1243)) ([c7208cb](https://github.com/dryvist/nix-ai/commit/c7208cb5f7b011c2fc1bd3a49e19416c21050255))
* **mcp:** stop disabling TLS verification in splunk-mcp-connect ([#1263](https://github.com/dryvist/nix-ai/issues/1263)) ([7e6f811](https://github.com/dryvist/nix-ai/commit/7e6f811d6494dd3ac835498292a63a0791144372))
* **mlx:** guard readiness age calculation ([6791b68](https://github.com/dryvist/nix-ai/commit/6791b6859915a1605568312d4afe5ffdcc751895))
* **mlx:** reap orphaned workers on proxy start, probe serving not liveness ([#1260](https://github.com/dryvist/nix-ai/issues/1260)) ([fcf4562](https://github.com/dryvist/nix-ai/commit/fcf4562e31eae14dab4b78caec048ce74b0eb849))


### Performance

* warm the pipeline rank after readiness (first request pays the full cold load) ([#1247](https://github.com/dryvist/nix-ai/issues/1247)) ([#1250](https://github.com/dryvist/nix-ai/issues/1250)) ([ae3cf60](https://github.com/dryvist/nix-ai/commit/ae3cf600a50517e110f392b32e430de321bcb4f4))

## [2.0.4](https://github.com/dryvist/nix-ai/compare/v2.0.3...v2.0.4) (2026-07-15)


### Bug Fixes

* **skills:** source Codex skills directly ([0733be2](https://github.com/dryvist/nix-ai/commit/0733be2639383c8d60997889c2c1baa539d93b11))

## [2.0.3](https://github.com/dryvist/nix-ai/compare/v2.0.2...v2.0.3) (2026-07-14)


### Bug Fixes

* **mlx:** add shebang to mlx-watchdog.sh (shellcheck SC2148) ([#1224](https://github.com/dryvist/nix-ai/issues/1224)) ([61f5cb2](https://github.com/dryvist/nix-ai/commit/61f5cb2aad300e7b87e505519c4f2db3d93e4f1b))
* **mlx:** make the zombie watchdog CI-clean ([#1223](https://github.com/dryvist/nix-ai/issues/1223)) ([260202a](https://github.com/dryvist/nix-ai/commit/260202a77b233c3cc91c9a7e90469de938bf0c5a))
* **mlx:** self-heal the listening-but-dead llama-swap zombie ([#1221](https://github.com/dryvist/nix-ai/issues/1221)) ([1607680](https://github.com/dryvist/nix-ai/commit/1607680a510aa47a43a37190f22957405aaaff38))

## [2.0.2](https://github.com/dryvist/nix-ai/compare/v2.0.1...v2.0.2) (2026-07-14)


### Bug Fixes

* **mlx:** give stock 35B the agent timeout + a resident profile ([#1218](https://github.com/dryvist/nix-ai/issues/1218)) ([7a04dce](https://github.com/dryvist/nix-ai/commit/7a04dceb0712647c28bf4c4b0d30226911df0169))

## [2.0.1](https://github.com/dryvist/nix-ai/compare/v2.0.0...v2.0.1) (2026-07-13)


### Bug Fixes

* **claude:** loosen auto-mode classifier and disable autoresearch guard hooks ([#1202](https://github.com/dryvist/nix-ai/issues/1202)) ([a311bca](https://github.com/dryvist/nix-ai/commit/a311bca42b89889ca4ea6a46b09cba7f980d5e6e))
* update nix-claude-code flake input to current develop tip ([7381651](https://github.com/dryvist/nix-ai/commit/73816510bf89b72f386ee9926ed4ce6b63300450))

## [2.0.0](https://github.com/dryvist/nix-ai/compare/v1.87.0...v2.0.0) (2026-07-12)


### ⚠ BREAKING CHANGES

* **mlx:** programs.mlx.nightCluster is now programs.mlx.clusterMode; launchd labels dev.mlx-night.* are now dev.mlx-cluster.*; the watcher/launcher env contract is CLUSTER_* (was NIGHT_*); log/state/config dirs move from mlx-night to mlx-cluster. Consumers (nix-darwin hosts) must rename in the same flake bump.

### Features

* integrate autoresearch across all harnesses via a generalized skill fan-out ([#1189](https://github.com/dryvist/nix-ai/issues/1189)) ([ff0f11f](https://github.com/dryvist/nix-ai/commit/ff0f11fe7f0733c12fa7a6af6544ccbbb76d807e))
* **mlx:** night-cluster link-local rework — zero written IP, runtime discovery ([#1192](https://github.com/dryvist/nix-ai/issues/1192)) ([df917f3](https://github.com/dryvist/nix-ai/commit/df917f3b19c946e7d4d55aa84571bcec3aaa6e1c))
* **mlx:** PD-guard — cap night-rank kickstarts and page on halt ([#1195](https://github.com/dryvist/nix-ai/issues/1195)) ([03b9301](https://github.com/dryvist/nix-ai/commit/03b9301bb17d71d13405fc0efb7f190cc6e4c1a9))
* **mlx:** raise proxy concurrencyLimit 2-&gt;4 to feed continuous batching ([#1190](https://github.com/dryvist/nix-ai/issues/1190)) ([477e747](https://github.com/dryvist/nix-ai/commit/477e74797acc865eead18a803aa4e3c019e6b6ad))


### Bug Fixes

* **ci:** recompile ci-doctor lock to trigger on develop ([#1187](https://github.com/dryvist/nix-ai/issues/1187)) ([69f944d](https://github.com/dryvist/nix-ai/commit/69f944d837f698b3c811dcfeaae06b5db036463a))
* **mcp:** assign catalog in config so per-server overrides merge ([#1184](https://github.com/dryvist/nix-ai/issues/1184)) ([9cd0e3f](https://github.com/dryvist/nix-ai/commit/9cd0e3f6d478690cbade0a7bcf37cc7bc50ef150))
* mlx-default kickstart -k orphans vllm-mlx workers (port conflict blocks resident reload) ([#1182](https://github.com/dryvist/nix-ai/issues/1182)) ([144cb06](https://github.com/dryvist/nix-ai/commit/144cb062aec21dfb3ad0fa4b8c067808a9be061a))
* **mlx:** default night-link discovery to static — JACCL rendezvous is IPv4-only ([#1194](https://github.com/dryvist/nix-ai/issues/1194)) ([6ebe93e](https://github.com/dryvist/nix-ai/commit/6ebe93eb6111754e17a47fb7106baed26cec2e29))


### Refactoring

* **mlx:** rename night/day naming to clustered/normal mode ([#1199](https://github.com/dryvist/nix-ai/issues/1199)) ([ab29b05](https://github.com/dryvist/nix-ai/commit/ab29b05f3f27c4d87ee5bd193bb39e3d3b9b6dc6))

## [1.87.0](https://github.com/dryvist/nix-ai/compare/v1.86.4...v1.87.0) (2026-07-10)


### Features

* add AI PR care caller (dep review + release highlights) ([#1093](https://github.com/dryvist/nix-ai/issues/1093)) ([43fd4ee](https://github.com/dryvist/nix-ai/commit/43fd4eedd0e6f13c39eda6bad3e98da314b4330e))
* add review-thread-resolver caller for instant bot-thread resolution ([#1103](https://github.com/dryvist/nix-ai/issues/1103)) ([9aec395](https://github.com/dryvist/nix-ai/commit/9aec395523b4fdf1ac57fe5730cedc8dd6ae4e66))
* **ai-stack:** select LLM endpoint (local llama-swap or cluster router) ([#1113](https://github.com/dryvist/nix-ai/issues/1113)) ([6e6b654](https://github.com/dryvist/nix-ai/commit/6e6b6540cb380a0bf7d8364dedeaf5ef3f97a0e2))
* **claude:** set advisorModel to fable-5 ([#1149](https://github.com/dryvist/nix-ai/issues/1149)) ([27f917d](https://github.com/dryvist/nix-ai/commit/27f917d7cd4e71fc538d116f29d3960dde342c9b))
* enable elements-of-style writing skill plugin ([#1132](https://github.com/dryvist/nix-ai/issues/1132)) ([987c1bd](https://github.com/dryvist/nix-ai/commit/987c1bd3770f6c1a899544d7c449f699c9a09daa)), closes [#1131](https://github.com/dryvist/nix-ai/issues/1131)
* **mlx:** add modelFlagOverrides for per-model serve-option overrides ([#1090](https://github.com/dryvist/nix-ai/issues/1090)) ([6180f2b](https://github.com/dryvist/nix-ai/commit/6180f2be2ae7e3007efe20f5b081f0731b53a301))
* **mlx:** cap per-worker MLX retained-buffer cache (MLX_BUFFER_CACHE_LIMIT) ([#1160](https://github.com/dryvist/nix-ai/issues/1160)) ([9a9a698](https://github.com/dryvist/nix-ai/commit/9a9a6986bef736e469ce3ba1dcc70d5715564968))
* **mlx:** programs.mlx.catalog — validated model catalog with typed host tweaks ([#1158](https://github.com/dryvist/nix-ai/issues/1158)) ([ba85cbe](https://github.com/dryvist/nix-ai/commit/ba85cbe76d146a5ceddd1361d794bbba4736c899))
* multi-resident model serving prereqs + Open WebUI service ([#1082](https://github.com/dryvist/nix-ai/issues/1082)) ([999b874](https://github.com/dryvist/nix-ai/commit/999b87402dd6478745e23b3d8be52c936aa08ecc))
* vllm-mlx 0.4.0 + mlx 0.31.2/mlx-lm 0.31.3, per-model registry args ([#1083](https://github.com/dryvist/nix-ai/issues/1083)) ([05a728a](https://github.com/dryvist/nix-ai/commit/05a728a7a340d4f9a2fe581ccb54d5f5155e3f27))
* warm MLX preload models and split swap tier ([#1127](https://github.com/dryvist/nix-ai/issues/1127)) ([14c98bf](https://github.com/dryvist/nix-ai/commit/14c98bfb5d878efe2ef0a5f2b9634d0ac06a7a18))


### Bug Fixes

* **agent-skills:** prune orphaned skill symlinks on activation ([#1111](https://github.com/dryvist/nix-ai/issues/1111)) ([cbe914d](https://github.com/dryvist/nix-ai/commit/cbe914d6b36cb988428486ecdfdde5db563ebe0e))
* **codex:** rename custom-instructions -&gt; context (upstream rename) ([#1117](https://github.com/dryvist/nix-ai/issues/1117)) ([0da468f](https://github.com/dryvist/nix-ai/commit/0da468fa398b044810b5c998e27ad2c96cdbc49d))
* **deps:** ignore new alias PYSEC-2026-597 for nltk ([#1152](https://github.com/dryvist/nix-ai/issues/1152)) ([c760dea](https://github.com/dryvist/nix-ai/commit/c760dea13ca232515d5b6af4011c0dc7d87d7e08))
* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#1125](https://github.com/dryvist/nix-ai/issues/1125)) ([e03ec0c](https://github.com/dryvist/nix-ai/commit/e03ec0c2affee0b59b5c1f23b6d7978a4783f135))
* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#1148](https://github.com/dryvist/nix-ai/issues/1148)) ([1fedb0a](https://github.com/dryvist/nix-ai/commit/1fedb0a83f5e2c60f72cd9a9515b374c4a3210a8))
* **deps:** update mlx-core ([#1143](https://github.com/dryvist/nix-ai/issues/1143)) ([4522766](https://github.com/dryvist/nix-ai/commit/4522766ca69171ca8073c1091700584865e08bd2))
* drop the mlx 0.31.2/0.31.3 renovate hard-block (nix-ai[#751](https://github.com/dryvist/nix-ai/issues/751) resolved) ([#1086](https://github.com/dryvist/nix-ai/issues/1086)) ([49f3675](https://github.com/dryvist/nix-ai/commit/49f3675cc9c0eff080977d64acab1cde472cd75e)), closes [#762](https://github.com/dryvist/nix-ai/issues/762)
* **fabric:** build fabric-ai via proxyVendor to fix inconsistent vendoring ([#1156](https://github.com/dryvist/nix-ai/issues/1156)) ([d6a6665](https://github.com/dryvist/nix-ai/commit/d6a6665b9a07c7d12249f2337c52e361468eb3ba))
* **fabric:** pin nix-claude-code's fabric-src to ours to stop version skew ([#1159](https://github.com/dryvist/nix-ai/issues/1159)) ([a9ed4ee](https://github.com/dryvist/nix-ai/commit/a9ed4ee9394307f9dee0c907089eb61d1e5dc7c9))
* **mlx:** keep resident group when swap tier is non-empty ([#1140](https://github.com/dryvist/nix-ai/issues/1140)) ([a25e85c](https://github.com/dryvist/nix-ai/commit/a25e85c77754ec74eb296ef0357935983864f188))
* **mlx:** pin transformers 5.12.0 — 5.13.0 breaks mlx-lm import, fleet-wide outage ([d923607](https://github.com/dryvist/nix-ai/commit/d923607393b62db6afb92cfb5f934c0694078e14))
* **mlx:** raise gpuMemoryUtilization default 0.5 → 0.80 to stop KV-cache death loop ([#1130](https://github.com/dryvist/nix-ai/issues/1130)) ([f6fa41f](https://github.com/dryvist/nix-ai/commit/f6fa41f5443ec5eb8db9ebecfef2f0f4071a9ab3))
* **open-webui:** pin WorkingDirectory and secret-key file into dataDir ([#1088](https://github.com/dryvist/nix-ai/issues/1088)) ([9bc7828](https://github.com/dryvist/nix-ai/commit/9bc7828abb682ef93fdbf867d9d9a7897d20254a))
* stop backlog-sweep caller startup-failing on schedule runs ([c8caecc](https://github.com/dryvist/nix-ai/commit/c8caecc78fea2e510ec74b3629e07cbf787d95c4))
* **versions:** block transformers 5.13.0 regression, bump mlx 0.32.0 ([#1157](https://github.com/dryvist/nix-ai/issues/1157)) ([e7558f6](https://github.com/dryvist/nix-ai/commit/e7558f69f49a9edd4f0c85f362c117370a6962ad))
* **versions:** bump huggingface-hub 1.15.0 -&gt; 1.21.0 to restore hf CLI ([#1081](https://github.com/dryvist/nix-ai/issues/1081)) ([56f1678](https://github.com/dryvist/nix-ai/commit/56f16781ffd1dd64d3ab148952082aca7fc1a74a))

## [1.86.4](https://github.com/dryvist/nix-ai/compare/v1.86.3...v1.86.4) (2026-07-02)


### Bug Fixes

* drop caller concurrency that collided with reusable ([8ef38a4](https://github.com/dryvist/nix-ai/commit/8ef38a4bb4764efb2274cf6e8f317e52109ecdcf))

## [1.86.3](https://github.com/dryvist/nix-ai/compare/v1.86.2...v1.86.3) (2026-07-02)


### Bug Fixes

* drop actions:read from backlog-sweep caller ([c10156c](https://github.com/dryvist/nix-ai/commit/c10156c942ad2710bed40b5ef3468a9586aeb91d))

## [1.86.2](https://github.com/dryvist/nix-ai/compare/v1.86.1...v1.86.2) (2026-07-02)


### Bug Fixes

* pass backlog-sweep secrets via inherit (org secrets can't be mapped) ([3f89484](https://github.com/dryvist/nix-ai/commit/3f894843a19f566c9f571985e3bc9e5ac165287e))

## [1.86.1](https://github.com/dryvist/nix-ai/compare/v1.86.0...v1.86.1) (2026-07-02)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#1069](https://github.com/dryvist/nix-ai/issues/1069)) ([b5991c0](https://github.com/dryvist/nix-ai/commit/b5991c07210020cf75727a101c8956e647cefecb))

## [1.86.0](https://github.com/dryvist/nix-ai/compare/v1.85.7...v1.86.0) (2026-07-02)


### Features

* add throttled issue-backlog-sweep to drain the backlog ([b2048ed](https://github.com/dryvist/nix-ai/commit/b2048ed20f566e2a553d9f35227484875c199452))

## [1.85.7](https://github.com/dryvist/nix-ai/compare/v1.85.6...v1.85.7) (2026-07-02)


### Bug Fixes

* point callers at renamed cc- reusable workflows ([3fa18fa](https://github.com/dryvist/nix-ai/commit/3fa18fa8b67112320b0343b6a9aa6073eb31241b))

## [1.85.6](https://github.com/dryvist/nix-ai/compare/v1.85.5...v1.85.6) (2026-06-29)


### Bug Fixes

* **ci:** clear OSV-flagged uv.lock CVEs; rely on native Renovate lockFileMaintenance ([#1033](https://github.com/dryvist/nix-ai/issues/1033)) ([7c0e211](https://github.com/dryvist/nix-ai/commit/7c0e2115b1c505762043d6ec37aa2089f4d8fe8c))

## [1.85.5](https://github.com/dryvist/nix-ai/compare/v1.85.4...v1.85.5) (2026-06-29)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#1048](https://github.com/dryvist/nix-ai/issues/1048)) ([1a60c9b](https://github.com/dryvist/nix-ai/commit/1a60c9b76ba3375d8c5be3823c1265d49d5db96e))

## [1.85.4](https://github.com/dryvist/nix-ai/compare/v1.85.3...v1.85.4) (2026-06-29)


### Bug Fixes

* **ci:** repin code-simplifier caller to [@main](https://github.com/main) (pre-[#274](https://github.com/dryvist/nix-ai/issues/274) v0 silently discards work) ([#1041](https://github.com/dryvist/nix-ai/issues/1041)) ([d12d1cd](https://github.com/dryvist/nix-ai/commit/d12d1cd5a890c841540bf20b251fc37ab29173b6))

## [1.85.3](https://github.com/dryvist/nix-ai/compare/v1.85.2...v1.85.3) (2026-06-28)


### Bug Fixes

* **ci:** point code-simplifier caller at renamed reusable workflow ([#1036](https://github.com/dryvist/nix-ai/issues/1036)) ([d95b474](https://github.com/dryvist/nix-ai/commit/d95b47468c0215b6c4687784c87364c3505c0df0))

## [1.85.2](https://github.com/dryvist/nix-ai/compare/v1.85.1...v1.85.2) (2026-06-26)


### Bug Fixes

* drop invalid attribution.sessionUrl and conflicting antigravity-cli cask ([#1027](https://github.com/dryvist/nix-ai/issues/1027)) ([3649ddf](https://github.com/dryvist/nix-ai/commit/3649ddf8704fdf1dad30868936df7c3c8c3a15ea))

## [1.85.1](https://github.com/dryvist/nix-ai/compare/v1.85.0...v1.85.1) (2026-06-25)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#1020](https://github.com/dryvist/nix-ai/issues/1020)) ([27ad337](https://github.com/dryvist/nix-ai/commit/27ad337b2a38b764bc4e44002a0acc6299b128be))

## [1.85.0](https://github.com/dryvist/nix-ai/compare/v1.84.0...v1.85.0) (2026-06-21)


### Features

* **profile:** centralize maintainer-specific values into one overridable profile ([#987](https://github.com/dryvist/nix-ai/issues/987)) ([b599e99](https://github.com/dryvist/nix-ai/commit/b599e99cd0fddc6d80c69c478c112d1fd515fa59))

## [1.84.0](https://github.com/dryvist/nix-ai/compare/v1.83.0...v1.84.0) (2026-06-21)


### Features

* **secrets:** add .env.example + direnv dotenv; relocate inline secret docs ([#986](https://github.com/dryvist/nix-ai/issues/986)) ([adf0e2e](https://github.com/dryvist/nix-ai/commit/adf0e2e6d38e5a5143bcfe8ed74737aa5ec8d21a))

## [1.83.0](https://github.com/dryvist/nix-ai/compare/v1.82.0...v1.83.0) (2026-06-20)


### Features

* evaluate homeManagerModules.default with zero consumer config ([#979](https://github.com/dryvist/nix-ai/issues/979)) ([cacc266](https://github.com/dryvist/nix-ai/commit/cacc2669c855b20102c0c9ade7710be425a3f82e))

## [1.82.0](https://github.com/dryvist/nix-ai/compare/v1.81.0...v1.82.0) (2026-06-20)


### Features

* remove the PAL MCP server and its model-discovery sync ([#974](https://github.com/dryvist/nix-ai/issues/974)) ([87d6f5a](https://github.com/dryvist/nix-ai/commit/87d6f5a422a08a464bdbc60ce915a7c584778796))

## [1.81.0](https://github.com/dryvist/nix-ai/compare/v1.80.0...v1.81.0) (2026-06-20)


### Features

* **claude:** importable skill packs; disable unused plugins and MCP servers ([#962](https://github.com/dryvist/nix-ai/issues/962)) ([be94eff](https://github.com/dryvist/nix-ai/commit/be94eff467bd69e40e924936bdd0ae63baddba75))

## [1.80.0](https://github.com/dryvist/nix-ai/compare/v1.79.0...v1.80.0) (2026-06-20)


### Features

* **mcp:** add UniFi Network and Monarch Money MCP servers ([#966](https://github.com/dryvist/nix-ai/issues/966)) ([13b162f](https://github.com/dryvist/nix-ai/commit/13b162fd598bde5e43be142f9c1dcf28673d675f))

## [1.79.0](https://github.com/dryvist/nix-ai/compare/v1.78.3...v1.79.0) (2026-06-20)


### Features

* add last30days-skill cross-tool agent skill ([#965](https://github.com/dryvist/nix-ai/issues/965)) ([9f8500d](https://github.com/dryvist/nix-ai/commit/9f8500d7866ffded40082706ab1573fc579d76c8))

## [1.78.3](https://github.com/dryvist/nix-ai/compare/v1.78.2...v1.78.3) (2026-06-20)


### Bug Fixes

* **orchestrator:** bump langsmith to 0.8.18 (GHSA-f4xh-w4cj-qxq8) ([#967](https://github.com/dryvist/nix-ai/issues/967)) ([5d4a44b](https://github.com/dryvist/nix-ai/commit/5d4a44b456a43f9f2176ad07a41d5c22802e2038))

## [1.78.2](https://github.com/dryvist/nix-ai/compare/v1.78.1...v1.78.2) (2026-06-18)


### Bug Fixes

* **agent-skills:** align codex and agy skill loading and fix CI ([#953](https://github.com/dryvist/nix-ai/issues/953)) ([724f3a2](https://github.com/dryvist/nix-ai/commit/724f3a20494e2eb1220f7d8d92700e3c31ece508))

## [1.78.1](https://github.com/dryvist/nix-ai/compare/v1.78.0...v1.78.1) (2026-06-13)


### Bug Fixes

* **ci:** pin untrusted re-actors/alls-green action to commit SHA ([#944](https://github.com/dryvist/nix-ai/issues/944)) ([aa2f97d](https://github.com/dryvist/nix-ai/commit/aa2f97d7ceaa0a4fee612daed24c38c879743a89))

## [1.78.0](https://github.com/dryvist/nix-ai/compare/v1.77.1...v1.78.0) (2026-06-13)


### Features

* **claude:** auto-load ponytail skill everywhere + fix worktree placement ([#946](https://github.com/dryvist/nix-ai/issues/946)) ([eef66b0](https://github.com/dryvist/nix-ai/commit/eef66b01c04f50fa5c04ccb47b3e32771c96381e))

## [1.77.1](https://github.com/dryvist/nix-ai/compare/v1.77.0...v1.77.1) (2026-06-13)


### Bug Fixes

* **mlx:** tighten seeded runtime config to owner-only perms (0o600) ([#942](https://github.com/dryvist/nix-ai/issues/942)) ([d7580b7](https://github.com/dryvist/nix-ai/commit/d7580b75a227e4956f32dfff83d2c44211a62c9c))

## [1.77.0](https://github.com/dryvist/nix-ai/compare/v1.76.2...v1.77.0) (2026-06-13)


### Features

* **profiles:** autonomy profiles + container-image config renderers ([#939](https://github.com/dryvist/nix-ai/issues/939)) ([4d9eaec](https://github.com/dryvist/nix-ai/commit/4d9eaec4cc47745018184f55b6eda40c8f7c29ba))

## [1.76.2](https://github.com/dryvist/nix-ai/compare/v1.76.1...v1.76.2) (2026-06-12)


### Bug Fixes

* **ci:** grant actions read to retrigger-pr-checks caller ([#940](https://github.com/dryvist/nix-ai/issues/940)) ([d8414e4](https://github.com/dryvist/nix-ai/commit/d8414e489c84feaad78a8399ffb130e1e40e57d5))

## [1.76.1](https://github.com/dryvist/nix-ai/compare/v1.76.0...v1.76.1) (2026-06-12)


### Bug Fixes

* **ci:** repoint reusable workflows from JacobPEvans-personal to dryvist hub ([#936](https://github.com/dryvist/nix-ai/issues/936)) ([3fb20c3](https://github.com/dryvist/nix-ai/commit/3fb20c3916199ba53c3e1d78e4223f7c673580f9))

## [1.76.0](https://github.com/dryvist/nix-ai/compare/v1.75.0...v1.76.0) (2026-06-12)


### Features

* **agent-skills:** integrate dashmotion animated diagram skill ([#932](https://github.com/dryvist/nix-ai/issues/932)) ([b204ebc](https://github.com/dryvist/nix-ai/commit/b204ebc1e7493da2971b8203624a27370f15173d))
* **claude:** add auto-mode classifier allow/soft_deny so rm is governed by intent ([#927](https://github.com/dryvist/nix-ai/issues/927)) ([cff83a3](https://github.com/dryvist/nix-ai/commit/cff83a373d88e142a8c76be47477362792afa9cf))
* **mlx:** native per-worker memory bounds via vllm-mlx flags ([#924](https://github.com/dryvist/nix-ai/issues/924)) ([3edd9e0](https://github.com/dryvist/nix-ai/commit/3edd9e08d4cc38e065690d0df60b67c02a1550f1))


### Bug Fixes

* **antigravity:** shadow home-manager's new antigravity-cli module ([#929](https://github.com/dryvist/nix-ai/issues/929)) ([4b1c297](https://github.com/dryvist/nix-ai/commit/4b1c2975191084a5079c3e165a8dace29a11d04e))
* **deps:** bump transitive jacobpevans-cc-plugins pin to v4.2.0 era ([#928](https://github.com/dryvist/nix-ai/issues/928)) ([5e0378d](https://github.com/dryvist/nix-ai/commit/5e0378d840ca4d9c6b9768762de848fb657c27b2))

## [1.75.0](https://github.com/dryvist/nix-ai/compare/v1.74.1...v1.75.0) (2026-06-11)


### Features

* **mlx:** tighten idleTtl default to 900s to cut idle-weight dwell ([#920](https://github.com/dryvist/nix-ai/issues/920)) ([f47fe18](https://github.com/dryvist/nix-ai/commit/f47fe18c1ea972904d5d7c6fd9ac137fc576a741))

## [1.74.1](https://github.com/dryvist/nix-ai/compare/v1.74.0...v1.74.1) (2026-06-10)


### Bug Fixes

* **mlx:** default launchd ProcessType to Interactive — Background QoS clamps Metal decode ~8x ([#916](https://github.com/dryvist/nix-ai/issues/916)) ([1218296](https://github.com/dryvist/nix-ai/commit/1218296db5a2f7587cf9735c6dc62c152168a574))

## [1.74.0](https://github.com/dryvist/nix-ai/compare/v1.73.2...v1.74.0) (2026-06-08)


### Features

* **homebrew:** expose programs.ai-homebrew.trustedTaps option ([#911](https://github.com/dryvist/nix-ai/issues/911)) ([a82ad48](https://github.com/dryvist/nix-ai/commit/a82ad4857ee1db469c83e6b23bf5199f2afe3487))

## [1.73.2](https://github.com/dryvist/nix-ai/compare/v1.73.1...v1.73.2) (2026-06-07)


### Bug Fixes

* **homebrew:** drop nonexistent google/antigravity tap ([#907](https://github.com/dryvist/nix-ai/issues/907)) ([7147101](https://github.com/dryvist/nix-ai/commit/71471011bd7a2513eee58423091fc7c07d2e6c61))

## [1.73.1](https://github.com/dryvist/nix-ai/compare/v1.73.0...v1.73.1) (2026-06-07)


### Bug Fixes

* **pal:** give the resident MLX model a proxy Elo so it lands in custom_models.json ([#904](https://github.com/dryvist/nix-ai/issues/904)) ([c8257b2](https://github.com/dryvist/nix-ai/commit/c8257b24a9d3dd8b57766939e28c582ae2f62ec5))

## [1.73.0](https://github.com/dryvist/nix-ai/compare/v1.72.0...v1.73.0) (2026-06-06)


### Features

* declare AI-tool Homebrew taps/casks and trust.json in nix-ai ([#897](https://github.com/dryvist/nix-ai/issues/897)) ([72fc391](https://github.com/dryvist/nix-ai/commit/72fc3912fe2c10f27849e90facfc3280c01f31c3))

## [1.72.0](https://github.com/dryvist/nix-ai/compare/v1.71.5...v1.72.0) (2026-06-05)


### Features

* **antigravity-cli:** replace gemini module ([#895](https://github.com/dryvist/nix-ai/issues/895)) ([c561636](https://github.com/dryvist/nix-ai/commit/c5616364bd7fd0dd50880480c7cbe000091fdcb0))

## [1.71.5](https://github.com/dryvist/nix-ai/compare/v1.71.4...v1.71.5) (2026-06-05)


### Bug Fixes

* **claude:** restore opusplan model, enable traces, clean up moot settings ([#893](https://github.com/dryvist/nix-ai/issues/893)) ([f6c3d08](https://github.com/dryvist/nix-ai/commit/f6c3d083fef75185562d479b58ea1063ede924e2))

## [1.71.4](https://github.com/dryvist/nix-ai/compare/v1.71.3...v1.71.4) (2026-06-04)


### Bug Fixes

* **claude:** leave model and effort unset for account/upstream defaults ([c6575eb](https://github.com/dryvist/nix-ai/commit/c6575ebd74986ee7d976679075740d8b0f0ab855))

## [1.71.3](https://github.com/dryvist/nix-ai/compare/v1.71.2...v1.71.3) (2026-06-04)


### Bug Fixes

* **ci:** repair ai-stack & mlx regression checks after [#878](https://github.com/dryvist/nix-ai/issues/878) ([#887](https://github.com/dryvist/nix-ai/issues/887)) ([d062552](https://github.com/dryvist/nix-ai/commit/d0625526209a6d3c669a76b91f9b9e6f10c947e0))

## [1.71.2](https://github.com/dryvist/nix-ai/compare/v1.71.1...v1.71.2) (2026-06-04)


### Bug Fixes

* **mcp:** remove PAL custom health checks entirely ([#884](https://github.com/dryvist/nix-ai/issues/884)) ([1f61165](https://github.com/dryvist/nix-ai/commit/1f6116580308805df9c10a20727e6cc532e83ae4))

## [1.71.1](https://github.com/dryvist/nix-ai/compare/v1.71.0...v1.71.1) (2026-06-04)


### Bug Fixes

* **ci:** drop stale claude.autoUpdates options + bump aiohttp past CVEs ([#882](https://github.com/dryvist/nix-ai/issues/882)) ([3b4d126](https://github.com/dryvist/nix-ai/commit/3b4d12682691cc574d97b365f4c58478afa05723))

## [1.71.0](https://github.com/dryvist/nix-ai/compare/v1.70.0...v1.71.0) (2026-06-04)


### Features

* **ai-stack:** parameterize default local model id; tighten mlx defaults ([#878](https://github.com/dryvist/nix-ai/issues/878)) ([67bd0d9](https://github.com/dryvist/nix-ai/commit/67bd0d900fa43060e1364467ef5399c7bdd533c4))

## [1.70.0](https://github.com/dryvist/nix-ai/compare/v1.69.0...v1.70.0) (2026-06-04)


### Features

* **ci:** event-driven flake input updates ([#869](https://github.com/dryvist/nix-ai/issues/869)) ([d99a51a](https://github.com/dryvist/nix-ai/commit/d99a51a6f6301dbdc806c0b88ed6e1ded3c50aaa))
* **mlx:** periodic watchdog kicks LaunchAgent under memory pressure (closes [#801](https://github.com/dryvist/nix-ai/issues/801) defensively) ([#873](https://github.com/dryvist/nix-ai/issues/873)) ([d43c1ce](https://github.com/dryvist/nix-ai/commit/d43c1cef39f5ae6d1b298d24858a303cec10242e))


### Bug Fixes

* **ci:** quote workflow_dispatch description to avoid YAML parse error ([#880](https://github.com/dryvist/nix-ai/issues/880)) ([f681e4f](https://github.com/dryvist/nix-ai/commit/f681e4f8f540ebf602e16a6f71aedbf072227f93))
* **claude-code:** install via brew, latest channel, no nix binary ([#871](https://github.com/dryvist/nix-ai/issues/871)) ([7b6ee59](https://github.com/dryvist/nix-ai/commit/7b6ee59ddef68fefe61b3177826958f95b0a581a))
* **claude:** restore ccstatusline statusline theme ([#875](https://github.com/dryvist/nix-ai/issues/875)) ([56e845c](https://github.com/dryvist/nix-ai/commit/56e845ce24fc24d620d61a704a75a6c667f25ee7))

## [1.69.0](https://github.com/dryvist/nix-ai/compare/v1.68.1...v1.69.0) (2026-06-01)


### Features

* **agent-skills:** add karpathy-skills + auto-discover all marketplaces ([#831](https://github.com/dryvist/nix-ai/issues/831)) ([ab45a6c](https://github.com/dryvist/nix-ai/commit/ab45a6cf9c0c5d612a886cd47fc0179d2fc81e52))
* **claude-config:** move host MCP overrides + playwright disable from nix-darwin ([#853](https://github.com/dryvist/nix-ai/issues/853)) ([110a4a6](https://github.com/dryvist/nix-ai/commit/110a4a6bcc925e19134dcdbf359ad28769a6b9f1))
* **claude:** expose programs.claude.settings.autoMode configuration ([#838](https://github.com/dryvist/nix-ai/issues/838)) ([54a0492](https://github.com/dryvist/nix-ai/commit/54a04924053a3c2f92e21c71849d11833fd7226f))


### Bug Fixes

* **ci:** repoint release-please caller to org-native reusable workflow ([#859](https://github.com/dryvist/nix-ai/issues/859)) ([1ed2fc8](https://github.com/dryvist/nix-ai/commit/1ed2fc83a14c08add79f32cb86d6e8209ca9d1e8))
* **claude:** rewire claude-latest to bunx @anthropic-ai/claude-code@latest ([#858](https://github.com/dryvist/nix-ai/issues/858)) ([63949ed](https://github.com/dryvist/nix-ai/commit/63949ed3722d862c0ac0b276de8409d28919cadf))
* **claude:** use kernel-spec commit trailer format ([#847](https://github.com/dryvist/nix-ai/issues/847)) ([aebe9c1](https://github.com/dryvist/nix-ai/commit/aebe9c1f3475e60f6b90d757bd3f996601055e34))
* **qwen-code:** drop the soft install-check script ([#863](https://github.com/dryvist/nix-ai/issues/863)) ([f35bdca](https://github.com/dryvist/nix-ai/commit/f35bdca64c713ae8ca33cf03dfc60a223961f7bb))

## [1.68.1](https://github.com/JacobPEvans/nix-ai/compare/v1.68.0...v1.68.1) (2026-05-25)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins [aw:gh-aw-pin-refresh] ([#844](https://github.com/JacobPEvans/nix-ai/issues/844)) ([68e5120](https://github.com/JacobPEvans/nix-ai/commit/68e51207883cae860c49336b60d4bcfed963efd1))

## [1.68.0](https://github.com/JacobPEvans/nix-ai/compare/v1.67.1...v1.68.0) (2026-05-24)


### Features

* **mcp:** add apple-events server for Reminders and Calendar ([#826](https://github.com/JacobPEvans/nix-ai/issues/826)) ([58a4d82](https://github.com/JacobPEvans/nix-ai/commit/58a4d8264bc0448f6744bb0fd5113f3744dcd54b))
* **mlx:** add Galileo observability scaffolding with fail-closed design ([#835](https://github.com/JacobPEvans/nix-ai/issues/835)) ([7b1a3a6](https://github.com/JacobPEvans/nix-ai/commit/7b1a3a627a19303fbe85a50d0b4cfad3a6f88445))


### Bug Fixes

* **ci-gate:** sync pip-audit ignore-vulns with osv-scanner.toml ([#832](https://github.com/JacobPEvans/nix-ai/issues/832)) ([9e3afbb](https://github.com/JacobPEvans/nix-ai/commit/9e3afbb652e8f786ef949eeabf20bce956aa1f6c))

## [1.67.1](https://github.com/JacobPEvans/nix-ai/compare/v1.67.0...v1.67.1) (2026-05-21)


### Bug Fixes

* **deps:** refresh gh-aw action SHA pins ([#822](https://github.com/JacobPEvans/nix-ai/issues/822)) ([f0e6293](https://github.com/JacobPEvans/nix-ai/commit/f0e6293ec276ee6c0447f0e506aa854d7b0f04d2))

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
* change MLX port from 11435 to 11436 (port conflict) ([#230](https://github.com/JacobPEvans/nix-ai/issues/230)) ([8a8dde9](https://github.com/JacobPEvans/nix-ai/commit/8a8dde9e90ef09491089115fbb19ecaa7856e605))
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
