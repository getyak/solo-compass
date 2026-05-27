# 实施方案:可生长、可重新编译的地点数据层

> 目标:把"一次性编码出来的快照"升级为"可持续生长、可重新编译、可基于旧信息验证补充的知识库"。
> 用户诉求:① 元数据表 + 编译后维基表分离;② 维基是用户看的信息;③ 可基于旧信息验证/补充/更新(增量编译);④ 起码有个"编译/深度探索"按钮。
>
> 已定决策:**统一到 packages/db(Drizzle 高级版)schema** + **编译按钮先做同步等待**。

---

## 0. 现状关键事实(经交叉验证)

### 三套并行后端
- **A. `infra/supabase` 简单版(活的)**:`osm_pois`(元数据)+ `synthesized_experiences`(编译维基,payload JSONB)。**覆盖式、无版本、无 job 入口。** iOS 实际连这套。
- **B. `packages/db` Drizzle 高级版(建好未接通)**:`experiences`(status 生命周期 candidate/active/stale/retired + `last_compiled_at`)、`experience_revisions`(版本史)、`compilation_jobs`(编译队列)、`editor_queue`、`sources`(多源溯源 + verified_at + weight)、`user_signals`、`audit_log`。**几乎是照用户蓝图设计的,但从没被写过/读过。**
- **C. `apps/api` Go 服务**:OSM reviews 抓取 + AI 提取,独立。

### 三条 AI 合成路径(重要)
1. **Edge Function 路径** `AIService.synthesizeViaEdge` (786-894) → `synthesize-experiences/index.ts`。**退化版**:只传 OSM tag;六维 breakdown 用同一个 overall 填充;无多源。
2. **本地直连 Anthropic 路径** `parseSynthesizedExperiences` (~1260-1316)。**完整版**:有 `hasHardSignals(poi)` 判断 Foursquare/Apple 信号、`soloBreakdown` 六维独立、attribution 区分 "+ Foursquare/Apple Maps + AI"。
3. **skeleton 降级** `skeletonExperience` (1321+):AI 不可用时的空壳,固定 7.0 分 + `explore.skeleton.why` 文案("We don't have a curated story for this place yet")。

> **核心洞察**:多源富化 + 细粒度评分**已经在 iOS 本地路径跑通**。工作的本质不是"从零造能力",而是"把本地路径的能力搬到 Edge Function,落到 B schema,并加版本化 + 增量编译 + 按钮"。

### 关键文件清单
| 关注点 | 文件 |
|---|---|
| Edge Function(待升级) | `infra/supabase/functions/synthesize-experiences/index.ts` |
| iOS 合成入口 | `apps/ios/SoloCompass/Services/AIService.swift` (717 起) |
| iOS Supabase 封装 | `apps/ios/SoloCompass/Services/SupabaseClient.swift` |
| B schema(目标) | `packages/db/src/schema/{experiences,revisions,jobs,sources}.ts` |
| B migrations | `packages/db/migrations/000{0,1,3}_*.sql` |
| skeleton 文案 | `apps/ios/SoloCompass/Resources/en.lproj/Localizable.strings` (`explore.skeleton.*`) |
| FeatureFlags | `routeAIThroughEdge` / `backendSync` |

---

## Phase 0 — Schema 收敛(决策已定:统一到 B)

**目标**:确立 B(`packages/db`)为唯一编译数据源,A 降级为兼容读。

1. 在 B 的 `experiences` 表补齐 A `synthesized_experiences` 缺的列:`city_code`、`source_cache_key`、`model_name`、`aggregated_solo_score`、`signal_count`(新 migration `0005_*.sql`)。
2. 写一次性迁移脚本:`synthesized_experiences.payload` → 拆进 `experiences` + 首版 `experience_revisions`(revision 1,created_by='migration')。
3. `osm_pois` 保留(它就是"元数据表"第一层),与 `experiences` 通过 `exp_osm_<osmId>` 约定关联;在 `sources` 表为每个 experience 落一行 osm 源。
4. **风险**:A 表上线数据量未知。迁移脚本须幂等 + 可重跑。**先在本地/staging 跑通再上 prod。**

**验收**:`experiences` 表能查到原 A 的全部地点;每个有 ≥1 条 revision 和 ≥1 条 sources。

---

## Phase 1 — 增量编译(诉求③,价值最高)

**目标**:编译从"覆盖式"改成"读旧故事 + 新证据 → 验证/补充/修正",每次产出新 revision。

1. **Edge Function `synthesize-experiences/index.ts` 改造**:
   - 请求体新增可选 `previousPayload`(上一版 experience JSON)和 `mode: 'create' | 'recompile'`。
   - `buildPrompt`:recompile 模式下注入旧故事,prompt 语义改为「以下是该地点已有的描述,请用新的 OSM/源数据**验证它是否仍成立**:保留仍准确的内容,补充缺失信息,修正过时表述,并在置信度上反映验证结果。不要凭空发明 tag 里没有的事实。」
   - 写库:从 upsert `synthesized_experiences` 改为写 `experiences`(更新当前版本)+ `experience_revisions`(revision N+1, created_by='ai:recompile')+ 更新 `last_compiled_at`。
   - **把 Edge 的六维 breakdown 升级到和本地路径一致**(接收 `soloBreakdown`,而非用 overall 填充)。

2. **prompt 对齐**:Edge prompt 与本地 `synthesisPrompt` 字段对齐(补 `soloBreakdown`),消除两条路径产出差异。

**验收**:对同一地点连续编译两次,第二次 prompt 含旧 payload;`experience_revisions` 出现 revision 2;旧的人工/优质内容不被无脑覆盖。

---

## Phase 2 — iOS 编译按钮(诉求④,同步等待)

**目标**:详情页可手动触发编译;空壳文案旁放按钮,把"占位"变"可操作"。

1. **新 Edge Function `request-compilation`**(或复用 synthesize 加 `mode`):同步执行一次 recompile,返回新 payload。先不做队列 worker(决策:同步等待)。
   - 仍走 JWT + entitlement + 配额检查(复用现有逻辑)。
2. **iOS**:
   - `AIService` 加 `recompile(experienceId:) async throws -> Experience`,调新函数。
   - `ExperienceDetailView`:在 `whyItMatters` 区/skeleton 空状态加「深度探索 / 重新编译」按钮;点击 → 转圈 → 替换为新内容。
   - 新增本地化 key:`detail.recompile.button`、`detail.recompile.loading`、`detail.recompile.failed`。
   - 编译成功后更新本地 `ExperienceRecord` + 失效该地点的 `AISynthesisCacheRecord`。
3. **可发现性**:skeleton 文案 `explore.skeleton.why` 后追加引导,或直接在空状态主推该按钮。

**验收**:模拟器里点空壳地点的按钮 → 等待 → 出现真实编译故事;失败有 toast;Pro 配额/free 拦截生效。(CLAUDE.md 要求 iOS UI 改动必须模拟器实测,#Preview 不够。)

---

## Phase 3 — 多源富化接通(诉求①深化)

**目标**:Edge 编译时也吃 Foursquare/Apple 鲜度数据(本地路径已有,Edge 缺),并落 `sources` 表。

1. iOS 把已采集的 Foursquare/Apple 信号(`hasHardSignals` 用到的)随 Edge 请求一起上传,或 Edge 端补拉。
2. Edge 编译后,为每个源写 `sources` 表(type ∈ wikivoyage/osm/google_places,**需要扩 enum 加 foursquare/apple_poi**),带 `verified_at` + `weight`。
3. attribution / confidence level 按源数量分级(对齐本地路径 1294-1308 的逻辑)。

**验收**:有 Foursquare/Apple 信号的地点,`sources` 表出现对应行;confidence level=2;attribution 含 "+ Foursquare/Apple Maps"。

---

## Phase 4 — 可写 / 可订正(诉求③的"验证"闭环)

**目标**:人工/用户修正写入 revision,下次增量编译时作为"已验证事实"喂回。

1. `editor_queue` + `experience_revisions` 已支持;先用最小后台(Web 内部页)或 SQL 录入修正 → 新 revision(created_by='editor:...')。
2. 增量编译 prompt 把"最近一条人工修正"标为高可信、不得被 AI 覆盖。
3. `audit_log` 记录每次编辑/编译(actor/action/target)。

**验收**:人工改一条 → 下次 AI 编译保留该修正;audit_log 有记录。

---

## 跨阶段注意事项

- **每阶段可独立交付、独立验收**,不必一次做完。建议顺序 0 → 1 → 2 → (3/4 视价值)。
- **FeatureFlags**:全程用 `routeAIThroughEdge` / `backendSync` 控制灰度,可随时回退本地路径。
- **测试**:TS 侧 `pnpm typecheck` + 包测试;Edge Function 有 `test.sh`;iOS `xcodebuild build/test` + 模拟器实测;碰 `packages/core/experience.ts` 要 `pnpm parity:check`。
- **安全**:Edge 写库只走 service-role;RLS 边界不破(synthesized/experiences 仅 service-role 可写)。
- **待核实项**:A 表线上数据量(影响 Phase 0 迁移)、`request-compilation` 是否复用 synthesize(影响 Phase 2 工作量)。

---

## 一句话总结
你要的"两层 + 可重编译 + 可验证补充"在 `packages/db` 已建好骨架、在 iOS 本地路径已跑通能力——这套方案的本质是**接通 + 版本化 + 加触发入口**,而非从零搭建。
