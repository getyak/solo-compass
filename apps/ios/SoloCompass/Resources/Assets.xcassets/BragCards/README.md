# Brag Card Templates (#320)

Owner: external designer

## Design constraints

Five templates. Album-cover level. Absolutely no emoji, no cartoon,
no drop shadows for fake depth.

- **Template A — Sun on paper.** Warm off-white background, one
  serif line, small `CT.sunGold` accent bar bottom-left.
- **Template B — Late window.** Dark navy background,
  `CT.capsuleGlow` glow behind the text, single roman numeral for the
  day count.
- **Template C — Field notes.** Cream background, hand-plotted
  compass rose in `CT.omenGold`, day count in the center.
- **Template D — Cinema.** Full-bleed photo (user's most-visited
  Experience hero), letterbox bars, city code in small caps bottom.
- **Template E — Almanac.** Grid of tiny place-title pills, each
  with a `CT.borderSubtle` outline, city code at top in mono.

## Delivery spec

- 4 sizes per template: 1080×1350 (IG portrait) · 1080×1920 (Story) ·
  1200×630 (Twitter card) · 3840×2160 (wallpaper).
- All must respect Dynamic Type via the trailing SwiftUI overlay
  (`BragCardView` composes on top of these templates).
- File format: PNG @2x + @3x plus SVG source for compass rose in
  template C.

## Delivery destination

Drop the finished set into this folder (`BragCards/`). Each template
becomes one `.imageset/` following Xcode asset catalog conventions:

```
BragCards/
  README.md                (this file)
  templateA_sun.imageset/
    Contents.json
    templateA_sun.png
    templateA_sun@2x.png
    templateA_sun@3x.png
  templateB_lateWindow.imageset/
  templateC_fieldNotes.imageset/
  templateD_cinema.imageset/
  templateE_almanac.imageset/
```

`BragCardView` will reference each by `Image("templateA_sun")` etc.

## Handoff status

- [ ] Designer signed statement of work with unit price.
- [ ] Round 1 delivered.
- [ ] Round 1 review + revisions requested.
- [ ] Final assets in this folder.
- [ ] `BragCardView` updated to reference the templates instead of
  the current numeric layout.
