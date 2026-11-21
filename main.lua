--[[--
fastpage.koplugin — 极速翻页（FAST 瞬时刷新）。

把快速刷新降级为最快的 FAST 波形：无黑闪、无动画、残影累积（手动全刷
清除）。Swipe_Animation issue #34 极速模式的独立版。

作用范围：
  翻页极速（默认）：只降级翻页周期内的 partial/ui/full——
      ReaderView.onPageUpdate 标记、UIManager._repaint 释放；
  全局（可选）：界面与文件管理器的所有 partial/ui 一并降级；
      显式 full（手动全刷/旋转/开关书）保留，天然定期清残影。

生效方式：纯运行时包裹（磁盘零改动，不打补丁、不改系统文件）——
  ReaderView.onPageUpdate → 标记翻页到来的绘制周期（paging/rolling 通用锚点）
  UIManager._refresh      → 入队时降级（partial→full 周期性提升自然被绕过）
  UIManager._repaint      → 绘制周期结束释放翻页标记

开关实时读取设置，改动即时生效，无需重启。删除插件目录即完全卸载。
版本护栏：pcall(require) + 方法存在性检查，任一不符则静默失效、回退原生。
]]

local logger = require("logger")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local ENABLED_KEY = "fastpage_enabled"
local GLOBAL_KEY = "fastpage_global"
local AUTOCLEAN_KEY = "fastpage_autoclean"

-- 双语文案：按界面语言取中文或英文（插件不依赖 .po 翻译）。
local function isZhUi()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    return tostring(lang or ""):find("^zh") ~= nil
end

local function L(zh, en)
    if isZhUi() then return zh end
    return en
end

local function isEnabled()
    return G_reader_settings ~= nil and G_reader_settings:isTrue(ENABLED_KEY)
end

-- 全局模式：界面/文件管理器的所有 partial/ui 也降级；显式 full 保留。
local function isGlobal()
    return G_reader_settings ~= nil and G_reader_settings:isTrue(GLOBAL_KEY)
end

-- 自动清残影：FAST 限定于局刷，每 N 页放行一次整页全刷（N=原生全刷频率，需≥2）。
local function isAutoclean()
    return G_reader_settings ~= nil and G_reader_settings:isTrue(AUTOCLEAN_KEY)
end

-- 翻页标记：onPageUpdate 置位，_repaint 结束清位。
local pending = false
local hooks_installed = false

local function installHooks()
    if hooks_installed then return end
    hooks_installed = true

    local UIManager = require("ui/uimanager")
    local Device = require("device")
    local Screen = Device and Device.screen
    if not Screen or type(Screen.refreshFast) ~= "function" then
        logger.warn("fastpage: Screen:refreshFast unavailable, stay idle")
        return
    end

    -- 1) 翻页锚点：paging/rolling 翻页都走 ReaderView:onPageUpdate，
    --    标记本次绘制周期的刷新应走 FAST（类级包裹，跨书籍复用）。
    local ok_rv, ReaderView = pcall(require, "apps/reader/modules/readerview")
    if ok_rv and ReaderView and ReaderView.onPageUpdate
        and not ReaderView._fastpage_orig_onPageUpdate then
        ReaderView._fastpage_orig_onPageUpdate = ReaderView.onPageUpdate
        ReaderView.onPageUpdate = function(view, ...)
            pending = true
            return ReaderView._fastpage_orig_onPageUpdate(view, ...)
        end
    end

    -- 2) 入队时降级：赶在 _refresh 内 partial→full 周期性提升之前，
    --    所以 full_refresh_count=1 也不会在翻页时闪屏。
    --    翻页极速（启用+pending）：partial/ui/full 全降级；
    --    全局模式（独立开关）：partial/ui 全降级，显式 full 保留
    --    （旋转/手动全刷/开关书清残影）。
    --    自动清残影（可选）：partial 改走自管计数，每 N 页放行一次整页
    --    full（该页会闪，其余页保持无闪 FAST）；计数语义与原生一致，
    --    置 refresh_counted 防原生计数器重复计数。
    if not UIManager._fastpage_orig_refresh then
        UIManager._fastpage_orig_refresh = UIManager._refresh
        UIManager._refresh = function(self, mode, region, dither)
            if isEnabled() or isGlobal() then
                if pending or isGlobal() then
                    if mode == "partial" then
                        local n = self.FULL_REFRESH_COUNT or 0
                        if isAutoclean() and n > 1 and not self.refresh_counted then
                            self.refresh_count = ((self.refresh_count or 0) + 1) % n
                            self.refresh_counted = true
                            if self.refresh_count == n - 1 then
                                -- 周期性整页清残影：放行原生 full
                                return UIManager._fastpage_orig_refresh(self, "full", region, dither)
                            end
                        end
                        mode = "fast"
                    elseif mode == "ui" or mode == "flashui" or mode == "flashpartial" then
                        -- 菜单关闭（TouchMenu:onCloseWidget）排的是 flashui，一并降级
                        mode = "fast"
                    elseif mode == "full" and pending and isEnabled() then
                        mode = "fast"
                    end
                end
            end
            return UIManager._fastpage_orig_refresh(self, mode, region, dither)
        end
    end

    -- 3) 绘制周期结束释放标记：菜单、高亮等非翻页刷新保持原波形。
    if not UIManager._fastpage_orig_repaint then
        UIManager._fastpage_orig_repaint = UIManager._repaint
        UIManager._repaint = function(self, ...)
            local ret = UIManager._fastpage_orig_repaint(self, ...)
            pending = false
            return ret
        end
    end
end

local FastPage = WidgetContainer:extend{
    name = "fastpage",
}

function FastPage:init()
    installHooks()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function FastPage:addToMainMenu(menu_items)
    menu_items.fastpage = {
        text = L("极速翻页（FAST 瞬时刷新）", "Instant page turn (FAST refresh)"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = L("启用（翻页极速）", "Enabled (page turns)"),
                checked_func = isEnabled,
                callback = function()
                    G_reader_settings:saveSetting(ENABLED_KEY, not isEnabled())
                end,
                help_text = L(
                    "翻页时用最快的 FAST 波形刷新：无黑闪、无动画，但残影会累积，可用菜单全刷清除。",
                    "Uses the fastest FAST waveform for page turns: no flash, no animation. Ghosting accumulates; clear it with a manual full refresh."),
            },
            {
                text = L("全局（界面也极速）", "Global (all UI, not just reading)"),
                checked_func = isGlobal,
                callback = function()
                    G_reader_settings:saveSetting(GLOBAL_KEY, not isGlobal())
                end,
                help_text = L(
                    "文件管理器、菜单等所有界面刷新也走 FAST。手动全刷、旋转屏幕、开关书等显式全刷仍保留，会顺带清残影。界面图标灰阶会随残影累积而变淡，定期手动全刷恢复。",
                    "Also applies FAST to file manager, menus and all UI. Explicit full refreshes (manual, rotation, book open/close) are kept and clear ghosting. UI grays may fade from ghosting; a manual full refresh restores them."),
            },
            {
                text = L("自动清残影（每 N 页全刷）", "Auto ghosting cleanup (full refresh every N pages)"),
                checked_func = isAutoclean,
                callback = function()
                    G_reader_settings:saveSetting(AUTOCLEAN_KEY, not isAutoclean())
                end,
                help_text = L(
                    "FAST 限定于局刷：每 N 页放行一次整页全刷清残影（N=设置→屏幕→刷新频率里的全刷页数，需 2 以上）。那一页会闪一次，其余保持无闪 FAST。全刷频率为 0/-1/1 时无效。",
                    "Keeps FAST for partial refreshes only: one full refresh every N pages clears ghosting (N = full refresh rate in Settings→Screen, must be ≥2). That page flashes once; all others stay flashless FAST. No effect if the rate is 0/-1/1."),
            },
        },
    }
end

local ok, err = pcall(installHooks)
if not ok then
    hooks_installed = false
    logger.warn("fastpage: install failed, native refresh stays: ", tostring(err))
else
    pcall(function() require("ui/plugin/insert_menu").add("fastpage") end)
end

return FastPage
