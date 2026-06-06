# 路线地图分享卡片 — 设计文档

> 让「分享路线」的卡片把地图上那条连线本身作为视觉主体分享出去,
> 对标 Strava / Komoot / AllTrails / 小红书旅行博主的顶级路线分享卡。

- **作者**: Claude (设计交付)
- **日期**: 2026-06-06
- **分支**: `fix/preview-card-unified-flow`(实现时另开 `feat/route-map-share-card`)
- **状态**: 待实现

---

## 1. 问题陈述

### 现状

`RouteShareSheet.swift` 已有完整的分享管线(`ImageRenderer` → `UIImage`/PNG →
`UIActivityViewController` + 剪贴板),并支持 `.card` / `.text` 两种模式。但
`.card` 模式的 `RouteShareCardView` 用的是 **分类渐变背景 + emoji + 统计芯片**,
**完全没有展示路线在地图上的实际形状**。

```
当前 RouteShareCardView(540×960 → 1080×1920):
┌─────────────────────┐
│ 🍵            ROUTE  │   ← emoji + kicker
│                     │
│                     │   ← 一大片纯渐变,信息密度低
│ 📍 Bangkok          │
│ 黄昏河岸慢走         │   ← 标题
│ 从老城咖啡馆出发…    │   ← 摘要
│ [⏱2h][📏2.4km][👣4] │   ← 统计芯片
│ 37 位旅人走过        │
│ #sunset #riverside  │
│ solocompass.app     │
└─────────────────────┘
```

### 痛点

顶级路线分享卡的**视觉核心永远是那条线本身** —— 用户一眼就能看出
「这是一条沿河的环线 / 这是一段穿城的直线」。当前卡片把最有辨识度、最值得
炫耀的资产(路线形状)丢掉了,退化成一张「带统计数字的渐变海报」,和任何
一张普通体验卡没有区别。

### 已有可复用资产

| 资产 | 位置 | 复用方式 |
| --- | --- | --- |
| 分享管线 (renderImage/renderTempPNG) | `RouteShareSheet.swift:224` | 几乎不动,只替换被渲染的 View |
| 风格切换 UI (modePicker) | `RouteShareSheet.swift:318` | 扩成三档:地图卡 / 极简线 / 文本 |
| polyline 坐标解析 | `RouteDetailView.swift:66` 的 `service.getExperience(id:)` | 抽成 payload 构建逻辑 |
| 地图 polyline 绘制约定 | `CompassMapView.swift:1190` (MapPolyline + 编号 badge) | 视觉语言对齐(accentColor 4pt 线 + 编号停靠点) |
| 分类渐变/emoji | `CategoryVisual` | 作为 fallback / 极简风格背景 |
| Experience 坐标 | `Experience.coordinate: CLLocationCoordinate2D?` | `[lon,lat]` 约定,直接取 |

---

## 2. 设计目标

1. **路线形状是主角**:连线占据卡片视觉中心 ≥50% 面积。
2. **两种风格可切换**(用户已确认):
   - **地图底图风(Map)**:`MKMapSnapshotter` 截取真实街道底图,polyline + 编号
     停靠点叠加其上 —— Strava/Komoot 质感。
   - **极简线条风(Trace)**:无底图,把 polyline 归一化后画成纯矢量描边线 +
     编号停靠点,配品牌渐变背景 —— 小红书/极简卡片质感。
3. **复用现有分享管线**:产物仍是 `UIImage` / 临时 PNG,经
   `UIActivityViewController` 分享或复制到剪贴板。不碰系统分享桥接层。
4. **健壮降级**:坐标 <2 点、快照失败、深色模式 → 优雅回退到极简风,再不行
   回退到旧的渐变卡,绝不空白或崩溃。
5. **不阻塞 UI**:`MKMapSnapshotter` 是异步的,预览区显示 `ProgressView`,渲染
   完成后填充;失败有明确状态提示。

### 非目标

- 不做实时可拖拽编辑路线(那是 RouteDetailView 的事)。
- 不做服务端渲染 / 短链分享落地页(未来工作,留扩展点)。
- 不改 Route 数据模型。

---

## 3. 视觉规格

### 3.1 画布

沿用现有 `renderSize = 540×960` (pt),`renderScale = 2.0` → **1080×1920 px**
(竖版 9:16,适配 IG Story / 小红书 / 微信)。

### 3.2 地图底图风(Map style)

```
┌───────────────────────────────┐  1080×1920
│ 🧭 SOLO COMPASS      Bangkok   │  ← 顶部品牌条(56pt 高,半透明黑底)
├───────────────────────────────┤
│░░░░░░ MKMapSnapshotter ░░░░░░░│
│░░░░░  真实街道底图(深色)  ░░░░│
│░░░   ②───────③             ░░│  ← polyline: accentColor 主线 8pt
│░░   ╱           ╲           ░░│     + 白色外描边 12pt(描边halo,保证任何
│░░  ①             ④──────⑤  ░░│       底图上都清晰)
│░░░  编号停靠点圆徽(白底accent数字)│
│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│        (地图占 ~62% 高度)      │
├───────────────────────────────┤
│ 黄昏河岸慢走                   │  ← 标题区(渐变 scrim 压底)
│ 从老城咖啡馆出发,沿河散步…     │
│ ┌────┐┌──────┐┌────┐         │
│ │⏱2h ││📏2.4km││👣5站│        │  ← 统计芯片(玻璃)
│ └────┘└──────┘└────┘         │
│ 37 位旅人走过 · #sunset        │
│ solocompass.app               │
└───────────────────────────────┘
```

要点:
- **底图**:`MKMapSnapshotter`,`MKMapConfiguration` 用 `.standard`,
  `traitCollection` 强制 `.dark`(深色街道更出片,且白色 polyline 对比强)。
- **mapRect**:由所有停靠点坐标算外接 `MKMapRect`,四周加 ~25% padding,
  保证线不贴边。单城内通常 1~3km 跨度。
- **polyline 双层描边**:先画白色 12pt(halo),再画 accentColor 8pt(主线),
  圆角 lineCap/lineJoin —— 这是 Strava/Komoot 在任意底图上保持可读的标准做法。
- **停靠点徽章**:白底圆 + accentColor 数字,直径 ~34pt,起点/终点可用
  旗标(`flag.fill`)区分(可选 v2)。
- **scrim**:底部 40% 高度的 `clear→black(0.55)` 线性渐变,保证文字在任何
  底图上可读。

### 3.3 极简线条风(Trace style)

```
┌───────────────────────────────┐
│ 🧭 SOLO COMPASS      Bangkok   │
│                               │
│      品牌分类渐变背景          │
│        ②╲                     │  ← polyline 归一化到中心安全区,
│          ╲___③                │     纯矢量描边(白 10pt + 投影)
│   ①          ╲                │     无真实底图
│                ╲___④___⑤      │
│      编号停靠点(白圈accent字)  │
│                               │
│ 黄昏河岸慢走                   │
│ 从老城咖啡馆出发…              │
│ [⏱2h][📏2.4km][👣5站]         │
│ 37 位旅人走过                  │
│ solocompass.app               │
└───────────────────────────────┘
```

要点:
- 复用 `CategoryVisual.gradient(for:)` 作背景(与 RouteDetailView hero 一致)。
- polyline 用 SwiftUI `Path` 绘制:把坐标 **等比归一化** 到一个居中安全区
  (保持经纬度宽高比,避免拉伸变形)。
- 同步渲染、无网络、最快最稳 → 作为 Map 风格失败时的**降级目标**。

### 3.4 颜色 / 字体

沿用现有卡片 token:`accentColor` 主线,`SpaceGrotesk-Bold`(若已注册,标题)
或 `.system(.heavy)`;统计芯片复用现有 `statChip` 玻璃样式。

---

## 4. 架构与数据流

### 4.1 新增 / 改动文件

```
Views/Companion/Share/                    ← 新建子目录(从 RouteShareSheet.swift 拆分)
  RouteSharePayload.swift        [改]  payload 加 coordinates: [CLLocationCoordinate2D]
  RouteShareStyle.swift          [新]  enum: map / trace / text
  RouteMapSnapshotter.swift      [新]  MKMapSnapshotter 封装(async, 错误处理, mapRect 计算)
  RoutePolylineShape.swift       [新]  SwiftUI Shape: 坐标归一化 → Path(给 trace 风格 & 叠加层共用)
  RouteShareCardView.swift       [改]  按 style 分派:RouteMapCard / RouteTraceCard
  RouteShareRenderer.swift       [改]  renderImage 改 async(因 snapshotter 异步)
  RouteShareSheet.swift          [改]  modePicker 三档;预览异步加载;降级逻辑
Views/Companion/RouteDetailView.swift  [改]  sharePayload 解析 stop 坐标传入
Resources/en.lproj/Localizable.strings [改]  新增风格名 / 状态文案 key
Tests/RouteShareCardTests.swift        [新]  payload 构建 / 归一化 / 降级 单测
```

> 注:为遵守「文件 200–400 行」约定,把当前 517 行的 `RouteShareSheet.swift`
> 拆成上述多个文件。

### 4.2 数据流

```
RouteDetailView
  │  liveRoute.experienceIds
  ▼
service.getExperience(id:) → [Experience]
  │  .compactMap { $0.coordinate }   // [lon,lat] → CLLocationCoordinate2D
  ▼
RouteSharePayload(route:, category:, stopCount:, coordinates:)   // 新增 coordinates
  │
  ▼
RouteShareSheet  ──(style)──►  RouteShareCardView
                                 ├─ .map   → RouteMapCard
                                 │            └─ RouteMapSnapshotter.snapshot(coordinates:) async
                                 │                 └─ 叠加 RoutePolylineShape + 编号 badge
                                 ├─ .trace → RouteTraceCard
                                 │            └─ RoutePolylineShape(归一化) 直接画
                                 └─ .text  → 现有 shareText
  │
  ▼
RouteShareRenderer.renderImage(payload:, style:) async → UIImage → PNG → 系统分享
```

### 4.3 坐标 → mapRect(地图风)

```swift
// 所有停靠点的外接矩形 + 25% padding
func boundingMapRect(_ coords: [CLLocationCoordinate2D], padding: Double = 0.25) -> MKMapRect {
    let rects = coords.map { MKMapRect(origin: MKMapPoint($0), size: .init(width: 0, height: 0)) }
    var union = rects.reduce(MKMapRect.null) { $0.union($1) }
    let dx = union.size.width * padding
    let dy = union.size.height * padding
    union = union.insetBy(dx: -max(dx, 1_000), dy: -max(dy, 1_000)) // 至少 ~1km 视野,避免单点贴脸
    return union
}
```

### 4.4 坐标 → 归一化 Path(极简风 & 叠加层)

把 `[CLLocationCoordinate2D]` 投影到单位坐标系再映射到绘制 `rect`:
- 经度→x,纬度→y(y 翻转,北在上)。
- **等比缩放**:取 lon/lat 跨度的较大者作统一比例,letterbox 居中,避免变形。
- 输出 `Path`,供 `RoutePolylineShape: Shape` 使用。

> ⚠️ 坐标约定:项目用 `[lon, lat]`(GeoJSON)。`Experience.coordinate` 已转成
> `CLLocationCoordinate2D(latitude:longitude:)`,在归一化时 **x=longitude, y=latitude**。

---

## 5. 降级策略(关键)

| 触发条件 | 行为 |
| --- | --- |
| `coordinates.count >= 2` 且快照成功 | **Map 风格**正常渲染 |
| `MKMapSnapshotter` 失败/超时(>4s) | 回退 **Trace 风格**,状态条提示「地图底图不可用,已用极简线条」 |
| `coordinates.count == 1` | 单点:Map 风格只放一个停靠点 pin(无线);Trace 风格画单点 |
| `coordinates.count == 0`(坐标全解析失败) | 回退到**旧渐变卡**(现有 `RouteShareCardView` 逻辑保留为 `RouteGradientCard`) |
| 用户手动选 Trace | 直接 Trace,不尝试快照 |

降级是**静默且有提示**的,绝不空白或崩溃(参照 memory 中「幽灵 SF Symbol /
死 FAB」的教训:渲染失败要可见)。

---

## 6. 实现步骤(TDD 顺序)

1. **抽 payload**:`RouteSharePayload` 加 `coordinates: [CLLocationCoordinate2D]`;
   `init(route:category:stopCount:coordinates:)`。`RouteDetailView.sharePayload`
   解析 stop 坐标传入。→ 单测:坐标解析 / 空降级。
2. **RoutePolylineShape**:归一化 + Path。→ 单测:已知坐标 → 预期归一化点(等比、
   不变形、y 翻转)。
3. **RouteTraceCard**:纯矢量风格(无异步,先做,易测)。`#Preview`。
4. **RouteMapSnapshotter**:async 封装 + boundingMapRect + 深色 trait。
   → 单测:mapRect 计算(纯函数部分);快照本身在 UI 验证。
5. **RouteMapCard**:快照底图 + polyline 叠加层 + 编号 badge + scrim + 文字块。`#Preview`。
6. **RouteShareCardView 分派** + **RouteShareRenderer async 化**。
7. **RouteShareSheet**:modePicker 三档、异步预览、降级提示。
8. **Localizable.strings** 新 key。
9. **构建 + 测试**:`xcodebuild build` & `test`(iPhone 17 Pro / iOS latest),
   再用临时 XCTest + `ImageRenderer` 把三种卡片写 PNG 到 `/tmp` **肉眼验证**
   (参照 memory「iOS 视觉验证路径」—— `MKMapSnapshotter` 产物也可直接存 PNG 看)。

---

## 7. 风险 & 注意

- **MKMapSnapshotter 是异步且可能慢/失败**(无网时只有缓存瓦片)。必须 async +
  超时 + 降级。预览区先 `ProgressView`。
- **ImageRenderer 不展开 LazyVStack/ScrollView**(memory 教训):卡片内用
  `VStack` 不要用 Lazy/Scroll。
- **深色 trait 注入**:`MKMapSnapshotter.Options.traitCollection =
  UITraitCollection(userInterfaceStyle: .dark)`,否则浅色底图上白 halo 不明显。
- **坐标系别搞反**:`[lon,lat]` vs `[lat,lng]`,归一化 x=lon、y=lat。
- **文件行数**:拆分到 ≤400 行/文件,符合项目约定。
- **新增测试文件需 `xcodegen`**(memory 教训):新建 `.swift` 测试后务必
  `cd apps/ios && xcodegen` 再跑,否则静默 0 用例假绿。
- **品牌一致性**:polyline 用 `accentColor`,与地图上 `CompassMapView` 的活动
  路线连线同色,分享出去和 App 内看到的是同一条线。

---

## 8. 验收标准

- [ ] RouteDetailView 分享 → 默认 Map 风格,卡片显示真实街道底图 + 那条路线连线 + 编号停靠点。
- [ ] 可切到 Trace(极简矢量线)和 Text(纯文本)。
- [ ] 无网/快照失败 → 自动降级 Trace,有提示,不崩溃不空白。
- [ ] 坐标 0 点 → 降级旧渐变卡。
- [ ] 产物经系统分享 / 复制图片 正常(沿用现有管线)。
- [ ] `xcodebuild build` + `test` 全绿(`Executed N>0`)。
- [ ] `/tmp` PNG 肉眼验证三种风格出片质量。
