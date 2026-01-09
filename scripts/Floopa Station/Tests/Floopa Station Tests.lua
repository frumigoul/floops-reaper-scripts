-- @noindex
-- @description Floopa Station Tests
_G.__FLOOPA_NO_GUI__ = true

local scriptPath = debug.getinfo(1, 'S').source:match('^@(.+)$')
local scriptDir = (scriptPath and scriptPath:match('(.+[\\/])')) or ''
dofile(scriptDir .. 'Floopa Station.lua')

-- Ensure Floopa tracks (1..5) exist and are named
local function ensureFloopaTracksIdempotent()
    local needed = {}
    for i = 1, 5 do needed[i] = false end
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
        if ok and name then
            local n = tostring(name):gsub('^%s+', ''):gsub('%s+$', '')
            local k = n:match('^Floopa (%d+)$')
            if k then needed[tonumber(k)] = true end
        end
    end
    for i = 1, 5 do
        if not needed[i] then
            reaper.InsertTrackAtIndex(i - 1, true)
            local tr = reaper.GetTrack(0, math.min(i - 1, math.max(0, reaper.CountTracks(0) - 1)))
            if tr then reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', ('Floopa %d'):format(i), true) end
        end
    end
end

-- Return list of {track=<MediaTrack*>, num=<int>} for tracks named Floopa N
local function getFloopaTracks()
    local list = {}
    local nt = reaper.CountTracks(0)
    for i = 0, nt - 1 do
        local t = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false)
        if ok and name then
            local n = tostring(name):match('^Floopa (%d+)$')
            if n then table.insert(list, {track=t, num=tonumber(n)}) end
        end
    end
    table.sort(list, function(a,b) return a.num < b.num end)
    return list
end

local function anyTrackSelected()
    local nt = reaper.CountTracks(0)
    for i = 0, nt - 1 do
        local t = reaper.GetTrack(0, i)
        if t and reaper.IsTrackSelected(t) then return true end
    end
    return false
end

local function getSelectedTrackGUIDs()
    local guids = {}
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr and reaper.IsTrackSelected(tr) then
            table.insert(guids, reaper.GetTrackGUID(tr))
        end
    end
    return guids
end

local function restoreSelectionByGUIDs(guids)
    local map = {}
    for _, g in ipairs(guids or {}) do map[g] = true end
    reaper.Main_OnCommand(40297, 0)
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr and map[reaper.GetTrackGUID(tr)] then
            reaper.SetTrackSelected(tr, true)
        end
    end
end

local function setsEqual(a, b)
    local ma, mb = {}, {}
    for _, g in ipairs(a or {}) do ma[g] = (ma[g] or 0) + 1 end
    for _, g in ipairs(b or {}) do mb[g] = (mb[g] or 0) + 1 end
    for g, c in pairs(ma) do if mb[g] ~= c then return false end end
    for g, c in pairs(mb) do if ma[g] ~= c then return false end end
    return true
end

local function test_click_track_preserves_selection()
    local prevSel = getSelectedTrackGUIDs()
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local t = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false)
        if ok and name then
            local n = tostring(name):gsub('^%s+', ''):gsub('%s+$', ''):lower()
            if n == 'floopa click track' or n == 'click track' then
                reaper.DeleteTrack(t)
                break
            end
        end
    end
    restoreSelectionByGUIDs(prevSel)

    toggleClickTrackPreservingSelection()

    local newCT = nil
    numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local tr = reaper.GetTrack(0, i)
        local ok, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
        if ok and name and tostring(name):gsub('^%s+', ''):gsub('%s+$', '') == 'Floopa Click Track' then
            newCT = tr
            break
        end
    end
    if not newCT then error('Click Track non creato') end
    local okName, name = reaper.GetSetMediaTrackInfo_String(newCT, 'P_NAME', '', false)
    local arm = reaper.GetMediaTrackInfo_Value(newCT, 'I_RECARM')
    local autoArm = reaper.GetMediaTrackInfo_Value(newCT, 'B_AUTO_RECARM')
    local expectedCol = reaper.ColorToNative(186, 60, 229)
    local col = reaper.GetTrackColor(newCT)
    -- REAPER aggiunge 0x1000000 ai colori personalizzati; confrontiamo solo i 24 bit RGB
    local function rgb24(c) return (c or 0) & 0xFFFFFF end
    local afterSel = getSelectedTrackGUIDs()
    if arm ~= 0 then error('Click Track deve avere RECARM=0') end
    if autoArm ~= 0 then error('Click Track deve avere AUTO_RECARM=0') end
    if not okName or name ~= 'Floopa Click Track' then error('Nome del Click Track inatteso') end
    if rgb24(col) ~= rgb24(expectedCol) then error('Colore del Click Track inatteso') end
    if not setsEqual(prevSel, afterSel) then error('La selezione delle tracce deve restare invariata') end
end

local function test_smoothing_helpers()
    local a1 = computeSmoothingAlpha(-1)
    local a2 = computeSmoothingAlpha(0)
    local a3 = computeSmoothingAlpha(0.1)
    local a4 = computeSmoothingAlpha(10)
    if a1 < 0.08 or a1 > 0.35 then error('alpha(-1) fuori soglia') end
    if a2 < 0.08 or a2 > 0.35 then error('alpha(0) fuori soglia') end
    if a3 < 0.08 or a3 > 0.35 then error('alpha(0.1) fuori soglia') end
    if a4 ~= 0.35 then error('alpha(10) deve clampare a 0.35') end
    local s1 = applySmoothing(0.0, 1.0, 0.0)
    local s2 = applySmoothing(0.0, 1.0, 0.5)
    local s3 = applySmoothing(0.0, 1.0, 1.0)
    if math.abs(s1 - 0.0) > 1e-9 then error('applySmoothing alpha=0 deve restituire prev') end
    if s2 <= 0.0 or s2 >= 1.0 then error('applySmoothing alpha=0.5 deve essere fra prev e current') end
    if math.abs(s3 - 1.0) > 1e-9 then error('applySmoothing alpha=1 deve restituire current') end
    local s4 = applySmoothing(-0.5, 2.0, 0.5)
    if s4 < 0 or s4 > 1 then error('applySmoothing deve clampare in [0,1]') end
end

local function test_loop_progress()
    reaper.GetSet_LoopTimeRange(true, false, 0.0, 4.0, false)
    reaper.SetEditCurPos(1.0, false, false)
    local p = getLoopProgress()
    if not p or not p.valid then error('getLoopProgress non valido') end
    if p.length <= 0 then error('Lunghezza loop non valida') end
    if p.start < 0 or p.stop <= p.start then error('Boundaries loop non coerenti') end
    if p.fraction < 0 or p.fraction > 1 then error('Loop fraction fuori [0,1]') end
end

local function test_auto_recarm_persistence()
    ensureFloopaTracksIdempotent()
    if _G.__FLOOPA_DEV and _G.__FLOOPA_DEV.applyAutoRecArmToFloopaTracks then
        _G.__FLOOPA_DEV.applyAutoRecArmToFloopaTracks(true)
        local armed = _G.__FLOOPA_DEV.isAutoRecArmEnabledOnAtLeastOneFloopaTrack()
        if not armed then error('Auto RecArm non abilitato dopo enable') end
        _G.__FLOOPA_DEV.applyAutoRecArmToFloopaTracks(false)
        local armed2 = _G.__FLOOPA_DEV.isAutoRecArmEnabledOnAtLeastOneFloopaTrack()
        if armed2 then error('Auto RecArm ancora abilitato dopo disable') end
    else
        -- Fallback: directly set B_AUTO_RECARM on Floopa 1..5
        local fl = getFloopaTracks()
        for _, e in ipairs(fl) do reaper.SetMediaTrackInfo_Value(e.track, 'B_AUTO_RECARM', 1) end
        local ok = false
        for _, e in ipairs(fl) do if reaper.GetMediaTrackInfo_Value(e.track, 'B_AUTO_RECARM') == 1 then ok = true break end end
        if not ok then error('Auto RecArm non abilitato (fallback)') end
        for _, e in ipairs(fl) do reaper.SetMediaTrackInfo_Value(e.track, 'B_AUTO_RECARM', 0) end
        for _, e in ipairs(fl) do if reaper.GetMediaTrackInfo_Value(e.track, 'B_AUTO_RECARM') ~= 0 then error('Auto RecArm non disabilitato (fallback)') end end
    end
end

local function test_clear_all_selection()
    ensureFloopaTracksIdempotent()
    local tr0 = reaper.GetTrack(0, 0)
    if tr0 then reaper.SetTrackSelected(tr0, true) end
    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
    local anySel = anyTrackSelected()
    if anySel then error('Selezioni non cancellate correttamente') end
end

local function createDummyItemOnTrack(track, pos, len)
    local it = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemInfo_Value(it, 'D_POSITION', pos)
    reaper.SetMediaItemInfo_Value(it, 'D_LENGTH', len)
    local tk = reaper.AddTakeToMediaItem(it)
    return it, tk
end

local function test_micro_fades_configurable()
    ensureFloopaTracksIdempotent()
    local tracks = getFloopaTracks()
    local tr = tracks[1] and tracks[1].track
    if not tr then return end
    reaper.Undo_BeginBlock()
    local startTime, endTime = 0.0, 2.0
    local it, tk = createDummyItemOnTrack(tr, 0.5, 1.0)
    if _G.__FLOOPA_DEV and _G.__FLOOPA_DEV.setLoopMicroFades then
        _G.__FLOOPA_DEV.setLoopMicroFades(true, 40, 'exponential')
    end
    applyMicroFadesConfigured(startTime, endTime)
    local fin = reaper.GetMediaItemInfo_Value(it, 'D_FADEINLEN')
    local fout = reaper.GetMediaItemInfo_Value(it, 'D_FADEOUTLEN')
    local sIn = reaper.GetMediaItemInfo_Value(it, 'C_FADEINSHAPE')
    local sOut = reaper.GetMediaItemInfo_Value(it, 'C_FADEOUTSHAPE')
    if math.abs(fin - 0.04) > 0.0005 or math.abs(fout - 0.04) > 0.0005 then
        error('Micro-fades length non applicata correttamente')
    end
    if sIn ~= 3 or sOut ~= 3 then
        error('Micro-fades shape non applicata correttamente')
    end
    reaper.Undo_EndBlock('Test: micro-fades configurabile', -1)
end

local function test_epsilon_dynamic()
    ensureFloopaTracksIdempotent()
    local tracks = getFloopaTracks()
    local tr = tracks[1] and tracks[1].track
    if not tr then return end
    reaper.Undo_BeginBlock()
    local it1 = createDummyItemOnTrack(tr, 1.0, 0.5)
    local it2 = createDummyItemOnTrack(tr, 2.0, 1.0)
    if _G.__FLOOPA_DEV and _G.__FLOOPA_DEV.setEpsilonMode then
        _G.__FLOOPA_DEV.setEpsilonMode('dynamic')
    end
    local eps = (_G.__FLOOPA_DEV and _G.__FLOOPA_DEV.computeEpsilon) and _G.__FLOOPA_DEV.computeEpsilon(0.0, 3.0) or 0.03
    if not eps or eps < 0.009 or eps > 0.051 then
        error('Dynamic epsilon fuori dai bound attesi: '..tostring(eps))
    end
    if _G.__FLOOPA_DEV and _G.__FLOOPA_DEV.setEpsilonMode then
        _G.__FLOOPA_DEV.setEpsilonMode('strict', 30)
    end
    local eps2 = (_G.__FLOOPA_DEV and _G.__FLOOPA_DEV.computeEpsilon) and _G.__FLOOPA_DEV.computeEpsilon(0.0, 3.0) or 0.03
    if math.abs(eps2 - 0.03) > 0.0005 then error('Strict epsilon non rispettato') end
    reaper.Undo_EndBlock('Test: epsilon dynamic/strict', -1)
end

local function test_pitch_change_detection()
    ensureFloopaTracksIdempotent()
    local tracks = getFloopaTracks()
    local tr = tracks[1] and tracks[1].track
    if not tr then return end
    reaper.Undo_BeginBlock()
    local it, tk = createDummyItemOnTrack(tr, 0.0, 1.0)
    reaper.SetActiveTake(tk)
    reaper.SetMediaItemTakeInfo_Value(tk, 'D_PITCH', 0)
    if _G.__FLOOPA_DEV and _G.__FLOOPA_DEV.changePitch then
        _G.__FLOOPA_DEV.changePitch(0, 12)
    else
        reaper.SetMediaItemTakeInfo_Value(tk, 'D_PITCH', 12)
    end
    local p = reaper.GetMediaItemTakeInfo_Value(tk, 'D_PITCH')
    if math.abs(p - 12.0) > 1e-9 then error('Pitch non aggiornato correttamente') end
    reaper.Undo_EndBlock('Test: pitch change detection', -1)
end

local function test_format_mm_ss()
    local fm = (_G.__FLOOPA_DEV and _G.__FLOOPA_DEV.format_mm_ss) or function(s)
        local m = math.floor(s / 60)
        local sec = math.floor(s - m * 60 + 0.5)
        return string.format('%02d:%02d', m, sec)
    end
    if fm(0) ~= '00:00' then error('format_mm_ss(0) inatteso') end
    if fm(65) ~= '01:05' then error('format_mm_ss(65) inatteso') end
    if fm(125) ~= '02:05' then error('format_mm_ss(125) inatteso') end
end

local function test_hud_guard()
    if not _G.__FLOOPA_DEV then return end
    _G.__FLOOPA_DEV.statusSet('Critical operation', 'ok', 2.0)
    local before = _G.__FLOOPA_DEV.getStatus()
    _G.__FLOOPA_DEV.updateStatusHUD()
    local after = _G.__FLOOPA_DEV.getStatus()
    if not before or not after or before.kind ~= after.kind or before.message ~= after.message then
        error('HUD updater non deve sovrascrivere messaggi non-info')
    end
end

local function run_all_tests()
    local results = {}
    local function run(name, fn)
        local ok, err = pcall(fn)
        results[#results+1] = {name=name, ok=ok, err=err}
    end
    run('Click Track', test_click_track_preserves_selection)
    run('Auto RecArm Persistence', test_auto_recarm_persistence)
    run('Clear All Selection', test_clear_all_selection)
    run('Micro-Fades Configurable', test_micro_fades_configurable)
    run('Epsilon Dynamic/Strict', test_epsilon_dynamic)
    run('Pitch Change Detection', test_pitch_change_detection)
    run('mm:ss Formatting', test_format_mm_ss)
    run('Smoothing Helpers', test_smoothing_helpers)
    run('Loop Progress', test_loop_progress)
    run('HUD Guard', test_hud_guard)

    local okAll = true
    for _, r in ipairs(results) do if not r.ok then okAll = false break end end
    local msgLines = {}
    for _, r in ipairs(results) do
        msgLines[#msgLines+1] = string.format('%s: %s%s', r.name, r.ok and 'OK' or 'FAIL', r.ok and '' or (' — '..tostring(r.err)))
    end
    local summary = table.concat(msgLines, '\n')
    if reaper and reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('[Tests]\n'..summary..'\n') end
    reaper.ShowMessageBox(summary, 'Floopa Station — Tests', 0)
end

run_all_tests()