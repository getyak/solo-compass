# ADR: 中国大陆 POI 数据源接入高德地图（混合模式）

- **Status**: Proposed
- **Date**: 2026-06-13
- **Context owner**: Explore / Enrichment pipeline
- **Related**: `EnrichmentAgent`, `OverpassService`, `MapViewModel.exploreNearby*`, `docs/architecture/data-source-quality.md`, `docs/PLAN_living_experience_data.md`

---

## 1. 问题（Why）

用户在深圳 explore 时数据极少。已实测根因：

| 城市 | 同查询 3km 内 OSM/Overpass POI 数 |
| --- | --- |
| 深圳福田 CBD | **260** |
| 清迈古城 | **2244**（8.6×） |

- AI 链路（DeepSeek）正常、API key 就位、**没有走 skeleton**——证明这不是 key 问题。
- 瓶颈在**数据源头**：OSM 在中国大陆覆盖稀疏（大陆主流是高德/腾讯，OSM 几乎无人维护）。
- `AIService.synthesisLimit = 60`，深圳连 60 个原料都凑不满，AI 巧妇难为无米之炊。

**结论：必须为中国大陆坐标引入高德 POI 数据源。**

## 2. 决策（What）

采用**混合模式**，而非整体替换 Overpass：

```
explore 坐标
  ├─ 在中国大陆境内  → AmapPOIService（权威源）+ MapKit（尽力）
  └─ 境外            → OverpassService（权威源，维持现状）+ MapKit + Foursquare
```

理由：
1. **合规隔离**：高德禁止数据落库（见 §3.2），只有中国坐标才需要承担这个约束；海外维持 OSM（ODbL，可自由落库）不受影响。
2. **复用现有抽象**：项目已有多源 POI 管线——`OverpassService` / `MapKitPOIService` / `FoursquareService` 都返回同构的 `OverpassService.POI`，由 `EnrichmentAgent`（`Services/Agents/EnrichmentAgent.swift:83`）用 `FoursquareService.enrichMerge(base:enrichment:)` 按坐标格子合并。**高德只需新增一个同构 Service，插进同一个合并器**，不动管线骨架。
3. **零成本起步**：高德个人实名认证即可用「周边搜索 v5/place/around」，**搜索类免费 5000 次/月**，超额接口报错不自动扣费。

## 3. 三个硬约束

### 3.1 坐标系：GCJ-02 ↔ WGS84（boundary 转换）

- app 内部坐标体系 = **WGS84** GeoJSON `[lon, lat]`（见 CLAUDE.md）。
- 高德进出**都是 GCJ-02（火星坐标系）**，不转换深圳的点会偏 ~100–300m。
- 先例：`Services/NavigationLauncher.swift:79` 已用 `dev=0` 让高德导航 URL 内部转换。
- **入参** WGS84→GCJ-02：用内置算法（不依赖网络，避免每次 explore 多一次 RTT）。
- **返回** GCJ-02→WGS84：高德**不提供官方反向接口**（测绘法规），用开源迭代逆变换（亚米~米级精度，对"附近找咖啡"足够）。
- 转换在 **`AmapPOIService` 边界内完成**：进 Service 是 WGS84，出 Service 也是 WGS84。`EnrichmentAgent` / 合并器 / 落库**全程只见 WGS84**，与现有管线零摩擦。

### 3.2 合规：高德数据**不落库**（红线）

高德服务协议 3.5 / 4.12.2 条**明文禁止存储、缓存、构建衍生数据库**。这与现有 `OverpassService` → `ExperienceRepository.writeExploreCache`（`Services/ExperienceRepository.swift:459`）的落库缓存设计**直接冲突**。

应对（分层处理）：

| 数据 | 能否落库 | 处理 |
| --- | --- | --- |
| 高德原始 POI 字段（名称/坐标/营业时间/评分） | ❌ 禁止 | 仅**会话级内存缓存**（`AmapPOIService` 内部 NSCache，进程退出即清），绝不写 SwiftData |
| AI 合成后的 `Experience`（你的衍生文案 + soloScore） | ✅ 允许 | 这是 SoloCompass 自己生成的内容，可正常落库。**但 sources attribution 必须标注 © AutoNavi/高德**，且不得回填高德原始结构化字段（如原始营业时间表）作为可分发数据 |
| 高德 POI ID | ✅ 允许（仅 ID） | 落库只存 ID + 你的衍生内容，需要刷新时实时回查 |

**关键改动**：`EnrichmentAgent` 在中国分支必须**跳过 explore 落库缓存**（`OverpassService` 的 geohash 缓存路径），改走"实时查 + 内存缓存"。

### 3.3 认证 / 费用

- 个人身份证实名认证即可商用（免费额度内）。无需营业执照。
- 搜索类 **5000 次/月**（≈166/天）。早期足够；规模化需企业认证付费扩容（30 元/万次）。
- key 走现有 `Secrets` / `GeneratedSecrets` 机制（同 DeepSeek/Foursquare），新增 `resolvedAmapKey`。空 key → 中国分支降级回 Overpass（不崩）。

## 4. 实现蓝图（文件级）

| 文件 | 改动 | 说明 |
| --- | --- | --- |
| `Services/AmapPOIService.swift` | **新建** | 同构 `fetchPOIs(near:radiusMeters:category:) async throws -> [OverpassService.POI]`；内部做 WGS84↔GCJ-02 转换；NSCache 会话缓存；ExperienceCategory → 高德 POI typecode 映射；范本参考 `Services/MapKitPOIService.swift:81`（`poi(from:)` 把外部源塞回 `OverpassService.POI`） |
| `Services/Geo/CoordinateConverter.swift` | **新建** | `wgs84ToGcj02` / `gcj02ToWgs84`（开源算法）；纯函数易测；附 `isInsideChinaMainland(_:)` 判定（国测局通用的国界粗包围盒，境外直接跳过转换） |
| `Models/Secrets.swift` + `Config/GeneratedSecrets.swift` | 加字段 | `resolvedAmapKey`（UserDefaults > Generated > env `AMAP_API_KEY`） |
| `Services/Agents/EnrichmentAgent.swift` | 改 `enrich(at:)`（L83） | 开头按 `CoordinateConverter.isInsideChinaMainland(coordinate)` 分流：中国 → `amapService.fetchPOIs` 作 base + 跳过落库；境外 → 维持 `overpassService` |
| `ViewModels/MapViewModel.swift` | 注入 | 构造 `AmapPOIService` 并传入 `EnrichmentAgent`；`exploreNearby*`（L1713 / L2186）的旧路径同样加中国分流 |
| `Resources/*.lproj/Localizable.strings` | 加键 | 高德 attribution、错误文案 |
| `Tests/AmapPOIServiceTests.swift`、`CoordinateConverterTests.swift` | 新建 | 转换往返误差 < 1m；深圳坐标判定为境内；境外坐标不转换；category 映射；空 key 降级 |

**新建 .swift 后必须 `cd apps/ios && xcodegen`**（项目惯例：新测试文件不跑 xcodegen 会静默执行 0 用例假绿）。

## 5. 风险与权衡

| 风险 | 缓解 |
| --- | --- |
| 高德条款禁止落库，与现有缓存架构冲突 | 中国分支强制走内存缓存；落库的只有自生成 `Experience` + POI ID（见 §3.2） |
| GCJ-02→WGS84 无官方反向接口，有精度损失 | 用成熟开源逆变换，米级精度对 explore 足够；坐标转换全封装在 Service 边界 |
| 5000 次/月 免费额度可能被真实用户量打爆 | 会话内存缓存 + 同 geohash 去重；接近额度时降级 Overpass；规模化再上企业认证 |
| 香港/澳门/台湾坐标系边界（港澳台用 WGS84，不偏移） | `isInsideChinaMainland` 只圈**大陆**，港澳台走境外 Overpass 分支 |
| 双向坐标转换累积误差 | 同一 explore 内只转一轮（进 WGS84→GCJ 查，出 GCJ→WGS84 存），不反复转换 |

## 6. 验收

- 深圳福田 explore 出 ≥ 30 条体验（对齐清迈量级），sources 标 © 高德。
- 深圳 POI marker 落点与真实位置偏差 < 50m（坐标转换生效）。
- 高德原始 POI 字段**不出现在 SwiftData**（合规校验：查 explore 后的持久化记录）。
- 空 `AMAP_API_KEY` 时深圳 explore 不崩，降级回 Overpass。
- 海外（清迈）explore 行为**完全不变**（回归）。

## 7. 暂不做（YAGNI）

- 腾讯位置服务（个人 200 次/天，比高德差，不纳入）。
- 高德企业数据授权 / 大规模 POI 落库（需商务谈判，等有规模再说）。
- 把 OSM 完全替换（海外 OSM 仍是合规、免费、可落库的最优选）。
