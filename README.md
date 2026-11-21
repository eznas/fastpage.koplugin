# 极速翻页 (fastpage.koplugin)

[![Version](https://img.shields.io/badge/version-0.4.1-green)](../../releases)
[![KOReader](https://img.shields.io/badge/KOReader-v2026.07-blue)](https://github.com/koreader/koreader)

翻页/界面刷新降级为最快的 **FAST** 波形：无黑闪、无翻页动画、响应最快。
提取自 [Swipe_Animation issue #34](https://github.com/koplugin-swipe-animation/Swipe_Animation.koplugin/issues/34) 的极速模式，独立成插件。

Instant page turns via the fastest **FAST** e-ink waveform: no flash, no animation, fastest response.
Extracted from the Swipe_Animation instant-refresh mode ([issue #34](https://github.com/koplugin-swipe-animation/Swipe_Animation.koplugin/issues/34)) into a standalone plugin.

[中文](#功能) | [English](#features-1)

## 功能

菜单路径：工具 → 更多工具 → 极速翻页（三个独立开关，实时生效，无需重启）。

| 开关 | 说明 |
|---|---|
| **启用（翻页极速）** | 翻页周期内的 partial / ui / flashui / flashpartial / full 全部降级 FAST：翻页零闪烁 |
| **全局（界面也极速）** | 文件管理器、菜单、弹窗等所有界面刷新也走 FAST（含关菜单的 flashui）；手动全刷、旋转屏幕、开关书等显式全刷保留，天然定期清残影 |
| **自动清残影** | FAST 限定局刷：每 N 页放行一次整页全刷清残影（N = KOReader「全刷频率」设置，需 ≥2；为 0/-1/1 时无效） |

残影说明：FAST 波形不做粒子归位校准，残影会累积——用菜单全刷或「自动清残影」清除即可，无硬件风险。

## Features

Menu: Tools → More tools → Instant page turn (three independent toggles, take effect instantly, no restart needed).

| Toggle | Description |
|---|---|
| **Enabled (page turns)** | Downgrades partial / ui / flashui / flashpartial / full to FAST within page-turn cycles: zero flash |
| **Global (all UI)** | Also applies FAST to file manager, menus, dialogs (including the flashui on menu close); explicit full refreshes (manual, rotation, book open/close) are kept and clear ghosting |
| **Auto ghosting cleanup** | Keeps FAST for partial refreshes only: one full refresh every N pages (N = KOReader "Full refresh rate", must be ≥2; no effect if 0/-1/1) |

Ghosting note: the FAST waveform skips particle calibration, so ghosting accumulates — clear it with a manual full refresh or the auto-cleanup toggle. No hardware risk.

## 安装 / Install

```
koreader/plugins/fastpage.koplugin/
├── _meta.lua
└── main.lua
```

复制到 KOReader 的 `plugins/` 目录后重启即可。
Copy to KOReader's `plugins/` directory and restart.

## 原理 / How it works

**纯运行时包裹，磁盘零改动，不打补丁，删除插件目录即完全卸载。**
Runtime wrapping only — touches no file outside the plugin dir; delete the dir to uninstall.

```
ReaderView.onPageUpdate  → 标记翻页到来的绘制周期（paging/rolling 通用锚点）
UIManager._refresh       → 入队时降级（赶在 partial→full 周期性提升之前，
                           所以 full_refresh_count=1 也不会闪屏）
UIManager._repaint       → 绘制周期结束释放标记
```

## 兼容 / Compatibility

- KOReader v2026.07 实测（Kindle PaperWhite 2 / PaperWhite 3）
- Tested on KOReader v2026.07 (Kindle PW2 / PW3)
- 与 Swipe_Animation 补丁体系可并存，但建议二选一（效果等同）
- Coexists with the Swipe_Animation patches, but running both is redundant — pick one
