-- @noindex
-- Floopa MIDI Map - Internal module
-- @author Flora Tarantino
-- @license GPL-3.0
-- MIDI Map module (shared by Floopa Station modal and standalone wrapper)
local M = {}

local SCRIPT_TITLE = "Floopa MIDI Map"
local CONTROL_TRACK_NAME = "Floopa MIDI Control"
local EXT_NS = "FLOOPA_MIDI"
local JSFX_FILE_NAME = "Floopa_MIDI_Listener.jsfx"
local GMEM_NAME = "FLOOPA_MIDI"

M.state = {
  enabled = false,
  channel = 16,
  hideTrack = false,
  lastSeq = -1,
  track = nil,
  fxIndex = -1,
  lastTrigger = "",
  lastCommand = "",
  lastMsgType = 0,
  lastD1 = 0,
  lastD2 = 0,
  lastCh = 0,
  heartbeat = false,
  learningActionId = nil,
  ccOnly = true,
}

 

local function getResourcePath()
  return reaper.GetResourcePath() or ""
end

local function joinPath(base, leaf)
  local sep = package.config:sub(1,1)
  if base:sub(-1) == sep then return base .. leaf end
  return base .. sep .. leaf
end

local function ensureJSFXInstalled()
  local effectsDir = joinPath(getResourcePath(), 'Effects')
  local jsfxPath = joinPath(effectsDir, JSFX_FILE_NAME)
  local jsfxContent = [[desc:Floopa MIDI Listener
options:gmem=FLOOPA_MIDI
slider1:channel=16<1,16,1>Channel
slider2:cc_only=1<0,1,1>CC Only

@init
seq = 0;

@block
while (midirecv(offset, msg1, msg2, msg3)) (
  status = msg1 & 0xF0;
  ch = (msg1 & 0x0F) + 1;
  ch == channel ? (
    cc_only >= 0.5 ? (
      status == 0xB0 ? (
        gmem[0] = 2; gmem[1] = msg2; gmem[2] = msg3; gmem[3] = ch; seq += 1; gmem[4] = seq;
      );
    ) : (
      status == 0x90 && msg3 > 0 ? (
        gmem[0] = 1; gmem[1] = msg2; gmem[2] = msg3; gmem[3] = ch; seq += 1; gmem[4] = seq;
      );
      status == 0xB0 ? (
        gmem[0] = 2; gmem[1] = msg2; gmem[2] = msg3; gmem[3] = ch; seq += 1; gmem[4] = seq;
      );
    );
  );
);
]]
  local existing = io.open(jsfxPath, 'r')
  if existing then
    local cur = existing:read("*a") or ""; existing:close()
    if cur == jsfxContent then return true, jsfxPath end
  end
  reaper.RecursiveCreateDirectory(effectsDir, 0)
  local f = io.open(jsfxPath, 'w'); if not f then return false, "Error creating JSFX in Effects" end
  f:write(jsfxContent); f:close(); return true, jsfxPath
end

M.actions = {
  { id = 'play_pause',    label = 'Play/Pause' },
  { id = 'record_toggle', label = 'Record Toggle' },
  { id = 'toggle_click',  label = 'Toggle Click Track' },
  { id = 'select_trk:1',  label = 'Select Track 1' },
  { id = 'select_trk:2',  label = 'Select Track 2' },
  { id = 'select_trk:3',  label = 'Select Track 3' },
  { id = 'select_trk:4',  label = 'Select Track 4' },
  { id = 'select_trk:5',  label = 'Select Track 5' },
  { id = 'mute_trk',      label = 'Mute Selected Track' },
  { id = 'fx_trk',        label = 'Effects Selected Track' },
  { id = 'rev_trk',       label = 'Reverse Selected Track' },
  { id = 'toggle_input',  label = 'Toggle Input (Audio/MIDI)' },
  { id = 'pitch_up',      label = 'Transpose +12' },
  { id = 'pitch_down',    label = 'Transpose -12' },
  { id = 'undo_all',      label = 'Undo All Lanes' },
  { id = 'undo_lane',     label = 'Undo Lane' },
}

M.map = {}

local function projGet(key)
  if reaper.GetProjExtState then
    local ok, val = reaper.GetProjExtState(0, EXT_NS, key)
    if ok == 1 and val ~= "" then return val end
  end
  local v = reaper.GetExtState(EXT_NS, key)
  return (v ~= "" and v) or nil
end

local function projSet(key, value)
  local val = value or ""
  if reaper.SetProjExtState then reaper.SetProjExtState(0, EXT_NS, key, val) end
  reaper.SetExtState(EXT_NS, key, val, true)
end

local function loadSettings()
  local chv = projGet('cfg_channel'); if chv then local vv = tonumber(chv); if vv then M.state.channel = math.max(1, math.min(16, vv)) end end
  local cov = projGet('cfg_cc_only'); if cov then M.state.ccOnly = (cov == '1' or cov == 'true') end
end

loadSettings()

local function loadMap()
  M.map = {}
  for _, a in ipairs(M.actions) do
    local t = projGet('map_type_'..a.id)
    local n = projGet('map_num_'..a.id)
    if t and n then
      local num = tonumber(n)
      if num then M.map[a.id] = { type = t, number = num } end
    end
  end
end

local function saveMap()
  for _, a in ipairs(M.actions) do
    local ev = M.map[a.id]
    local tkey = 'map_type_'..a.id
    local nkey = 'map_num_'..a.id
    if ev then
      projSet(tkey, ev.type or '')
      projSet(nkey, tostring(ev.number or ''))
    else
      projSet(tkey, '')
      projSet(nkey, '')
    end
  end
end

local function clearMap()
  M.map = {}
  saveMap()
end

local function bindingToText(ev)
  if not ev then return '-' end
  if ev.type == 'note' then return 'NOTE '..tostring(ev.number) end
  if ev.type == 'cc' then return 'CC '..tostring(ev.number) end
  return '-'
end

local function findOrCreateControlTrack()
  local savedGuid = projGet("MidiControlTrackGUID")
  local foundTr = nil
  local proj = 0
  local total = reaper.CountTracks(proj)

  -- 1. Try GUID match
  if savedGuid then
      for i = 0, total - 1 do
        local tr = reaper.GetTrack(proj, i)
        if reaper.GetTrackGUID(tr) == savedGuid then
            foundTr = tr
            break
        end
      end
  end

  -- 2. Fallback to name match
  if not foundTr then
      for i = 0, total - 1 do
        local tr = reaper.GetTrack(proj, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
        if name == CONTROL_TRACK_NAME then 
            foundTr = tr
            break 
        end
      end
  end

  if foundTr then
      -- Ensure GUID is saved/refreshed
      local currentGuid = reaper.GetTrackGUID(foundTr)
      if currentGuid ~= savedGuid then
          projSet("MidiControlTrackGUID", currentGuid)
      end
      return foundTr
  end

  -- 3. Create new
  reaper.Undo_BeginBlock();
  local idx = total
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(proj, idx)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', CONTROL_TRACK_NAME, true)
  projSet("MidiControlTrackGUID", reaper.GetTrackGUID(tr))
  reaper.Undo_EndBlock('Create Floopa MIDI Control track', -1)
  return tr
end


local function isTrackMonitorOnly(tr)
  if not tr then return false end
  local ok, chunk = reaper.GetTrackStateChunk(tr, '', false)
  if not ok or type(chunk) ~= 'string' then return false end
  local a,b,c,d,e = chunk:match('REC%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)')
  if b then
    return tonumber(b) == 0 -- record mode none
  end
  return false
end

local function applyMonitorOnlyAction(tr)
  if not tr then return end
  if isTrackMonitorOnly(tr) then return end
  local proj = 0
  local total = reaper.CountTracks(proj)
  local prev_sel = {}
  reaper.PreventUIRefresh(1)
  for i = 0, total - 1 do
    local t = reaper.GetTrack(proj, i)
    prev_sel[i] = reaper.IsTrackSelected(t)
    reaper.SetTrackSelected(t, false)
  end
  reaper.SetTrackSelected(tr, true)
  reaper.Main_OnCommand(40498, 0) -- Track: Set track record mode to none (monitoring only)
  for i = 0, total - 1 do
    local t = reaper.GetTrack(proj, i)
    reaper.SetTrackSelected(t, prev_sel[i] or false)
  end
  reaper.PreventUIRefresh(-1)
end

local function configureTrackForMIDI(tr, hide)
  if not tr then return end
  reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', 4096 + 0x7E0)
  reaper.SetMediaTrackInfo_Value(tr, 'I_RECMON', 1)
  -- Disable auto-recarm to prevent REAPER from disarming when not selected
  reaper.SetMediaTrackInfo_Value(tr, 'B_AUTO_RECARM', 0)
  -- Ensure "monitor-only" record mode (40498), then re‑arm explicitly
  applyMonitorOnlyAction(tr)
  reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 1)
  
  local armed = reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM')
  if armed ~= 1 then
    -- Try a redundant arm and UI refresh to overcome timing issues
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 1)
    reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
  end
  if hide then
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 0)
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 0)
  else
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 1)
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 1)
  end
end

local function addListenerFX(tr)
  if not tr then return -1 end
  local fxCount = reaper.TrackFX_GetCount(tr)
  for i = 0, fxCount - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(tr, i, '')
    if fxName and (fxName:find('Floopa_MIDI_Listener') or fxName:find('Floopa MIDI Listener')) then
      return i
    end
  end
  local fxIndex = reaper.TrackFX_AddByName(tr, JSFX_FILE_NAME, false, -1)
  return fxIndex
end

local function setListenerChannel(tr, fxIndex, ch)
  if not tr or fxIndex < 0 then return end
  local norm = (math.max(1, math.min(16, ch)) - 1) / 15.0
  reaper.TrackFX_SetParamNormalized(tr, fxIndex, 0, norm)
end

local function setListenerCcOnly(tr, fxIndex, ccOnly)
  if not tr or fxIndex < 0 then return end
  reaper.TrackFX_SetParamNormalized(tr, fxIndex, 1, ccOnly and 1.0 or 0.0)
end


local function mapEventToCommand(msgType, d1, d2, ch)
  if M.state.ccOnly then
    if msgType == 2 then
      if d2 and d2 < 1 then return nil end
      for id, ev in pairs(M.map) do
        if ev.type == 'cc' and ev.number == d1 then return id end
      end
    end
  else
    if msgType == 1 then
      if d2 and d2 < 1 then return nil end
      for id, ev in pairs(M.map) do
        if ev.type == 'note' and ev.number == d1 then return id end
      end
    elseif msgType == 2 then
      if d2 and d2 < 1 then return nil end
      for id, ev in pairs(M.map) do
        if ev.type == 'cc' and ev.number == d1 then return id end
      end
    end
  end
  return nil
end

local function bridgeLoop()
  if not M.state.enabled then return end
  if not M.state.track then reaper.defer(bridgeLoop); return end
  reaper.gmem_attach(GMEM_NAME)
  local seq = reaper.gmem_read(4)
  if seq and seq ~= 0 and seq ~= M.state.lastSeq then
    M.state.lastSeq = seq
    local msgType = reaper.gmem_read(0)
    local d1 = reaper.gmem_read(1)
    local d2 = reaper.gmem_read(2)
    local ch = reaper.gmem_read(3)
    local trig = (msgType == 1) and string.format("NOTE:%d:%d:CH%d", d1, d2, ch) or ((msgType == 2) and string.format("CC:%d:%d:CH%d", d1, d2, ch) or nil)
    if trig then
      reaper.SetExtState(EXT_NS, "trigger", trig, false)
      reaper.SetExtState(EXT_NS, "ts", tostring(reaper.time_precise()), false)
      if M.state.learningActionId and ((msgType == 1 and (d2 or 0) > 0) or (msgType == 2 and (d2 or 0) > 0)) then
        local evType = (msgType == 1) and 'note' or 'cc'
        M.map[M.state.learningActionId] = { type = evType, number = d1 }
        M.state.learningActionId = nil
        saveMap()
      end
      local cmd = mapEventToCommand(msgType, d1, d2, ch)
      if cmd then
        reaper.SetExtState(EXT_NS, "command", cmd, false)
        reaper.SetExtState(EXT_NS, "command_ts", tostring(reaper.time_precise()), false)
      end
      M.state.lastTrigger = trig
      M.state.lastCommand = cmd or ""
      M.state.lastMsgType = msgType
      M.state.lastD1 = d1; M.state.lastD2 = d2; M.state.lastCh = ch
      M.state.heartbeat = not M.state.heartbeat
    end
  end
  reaper.defer(bridgeLoop)
end

function M.enable()
  local ok, path = ensureJSFXInstalled()
  if not ok then reaper.ShowMessageBox("Error installing JSFX: "..tostring(path), SCRIPT_TITLE, 0); return end
  local tr = findOrCreateControlTrack()
  configureTrackForMIDI(tr, M.state.hideTrack)
  local fxIndex = addListenerFX(tr)
  if fxIndex < 0 then reaper.ShowMessageBox("Error adding JSFX.", SCRIPT_TITLE, 0); return end
  setListenerChannel(tr, fxIndex, M.state.channel)
  setListenerCcOnly(tr, fxIndex, M.state.ccOnly)
  M.state.track = tr; M.state.fxIndex = fxIndex; M.state.enabled = true; M.state.lastSeq = -1
  loadMap()
  bridgeLoop(); reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
end

function M.disable()
  M.onRevert()
end

function M.onRevert()
 
  local proj = 0
  local total = reaper.CountTracks(proj)
  for i = 0, total - 1 do
    local tr = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
    if name == CONTROL_TRACK_NAME then reaper.DeleteTrack(tr); break end
  end
  M.state.track = nil; M.state.fxIndex = -1; M.state.enabled = false
end

function M.renderPanel(ctx)
  reaper.ImGui_Text(ctx, "MIDI Configuration")
  reaper.ImGui_Dummy(ctx, 0, 6)
  reaper.ImGui_Text(ctx, "MIDI Channel:")
  reaper.ImGui_SameLine(ctx)
  local chChanged, newCh = reaper.ImGui_InputInt(ctx, "##ch", M.state.channel, 1, 4)
  if chChanged then M.state.channel = math.max(1, math.min(16, newCh)); setListenerChannel(M.state.track, M.state.fxIndex, M.state.channel) end
  reaper.ImGui_SameLine(ctx)
  local ccChanged, ccVal = reaper.ImGui_Checkbox(ctx, "CC Only", M.state.ccOnly)
  if ccChanged then M.state.ccOnly = ccVal; setListenerCcOnly(M.state.track, M.state.fxIndex, M.state.ccOnly) end
  reaper.ImGui_Dummy(ctx, 0, 4)
  local hideChanged, hideVal = reaper.ImGui_Checkbox(ctx, "Hide Control Track", M.state.hideTrack)
  if hideChanged then
    M.state.hideTrack = hideVal
    if M.state.track then configureTrackForMIDI(M.state.track, M.state.hideTrack); reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange() end
  end
  reaper.ImGui_Dummy(ctx, 0, 8)
  local btnW, btnH = 200, 28
  local xAvail = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_SetCursorPosX(ctx, (xAvail > btnW) and ((xAvail - btnW) * 0.5) or 0)
  local pressed = reaper.ImGui_Button(ctx, (M.state.enabled and "Remove MIDI Map" or "Enable MIDI Map"), btnW, btnH)
  if pressed then
    if M.state.enabled then M.disable() else M.enable() end
  end
  reaper.ImGui_Dummy(ctx, 0, 6)
  local rmPressed = reaper.ImGui_Button(ctx, "Remove all mapping", 240, 28)
  if rmPressed then clearMap() end
  reaper.ImGui_Dummy(ctx, 0, 6)
  if reaper.ImGui_BeginTable(ctx, "MapTbl", 4) then
    reaper.ImGui_TableSetupColumn(ctx, "Action")
    reaper.ImGui_TableSetupColumn(ctx, "Binding")
    reaper.ImGui_TableSetupColumn(ctx, "Learn")
    reaper.ImGui_TableSetupColumn(ctx, "Clear")
    reaper.ImGui_TableHeadersRow(ctx)
    for _, a in ipairs(M.actions) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_TableSetColumnIndex(ctx, 0)
      reaper.ImGui_Text(ctx, a.label)
      reaper.ImGui_TableSetColumnIndex(ctx, 1)
      local ev = M.map[a.id]
      reaper.ImGui_Text(ctx, bindingToText(ev))
      reaper.ImGui_TableSetColumnIndex(ctx, 2)
      do
        local bw = 80
        local fontSz = reaper.ImGui_GetFontSize(ctx) or 13
        local bh = 22
        local padY = math.max(0, math.floor((bh - fontSz) / 2))
        local padX = 8
        local avail = reaper.ImGui_GetContentRegionAvail(ctx)
        local curX = reaper.ImGui_GetCursorPosX(ctx)
        local curY = reaper.ImGui_GetCursorPosY(ctx)
        local vshift = 1
        reaper.ImGui_SetCursorPosX(ctx, curX + math.max(0, (avail - bw) * 0.5))
        reaper.ImGui_SetCursorPosY(ctx, curY + vshift)
        if reaper.ImGui_StyleVar_ButtonTextAlign then
          reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
        end
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), padX, padY)
        local lp = reaper.ImGui_Button(ctx, "Learn##"..a.id, bw, bh)
        reaper.ImGui_PopStyleVar(ctx)
        if reaper.ImGui_StyleVar_ButtonTextAlign then reaper.ImGui_PopStyleVar(ctx) end
        if lp then M.state.learningActionId = a.id end
      end
      reaper.ImGui_TableSetColumnIndex(ctx, 3)
      do
        local bw = 80
        local fontSz = reaper.ImGui_GetFontSize(ctx) or 13
        local bh = 22
        local padY = math.max(0, math.floor((bh - fontSz) / 2))
        local padX = 8
        local avail = reaper.ImGui_GetContentRegionAvail(ctx)
        local curX = reaper.ImGui_GetCursorPosX(ctx)
        local curY = reaper.ImGui_GetCursorPosY(ctx)
        local vshift = 1
        reaper.ImGui_SetCursorPosX(ctx, curX + math.max(0, (avail - bw) * 0.5))
        reaper.ImGui_SetCursorPosY(ctx, curY + vshift)
        if reaper.ImGui_StyleVar_ButtonTextAlign then
          reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
        end
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), padX, padY)
        local cp = reaper.ImGui_Button(ctx, "Clear##"..a.id, bw, bh)
        reaper.ImGui_PopStyleVar(ctx)
        if reaper.ImGui_StyleVar_ButtonTextAlign then reaper.ImGui_PopStyleVar(ctx) end
        if cp then M.map[a.id] = nil; saveMap() end
      end
    end
    reaper.ImGui_EndTable(ctx)
  end
  reaper.ImGui_Dummy(ctx, 0, 6)
  local sv = reaper.ImGui_Button(ctx, "Save configuration", 200, 28)
  reaper.ImGui_SameLine(ctx)
  local rf = reaper.ImGui_Button(ctx, "Reset configuration", 200, 28)
  if sv then saveMap(); projSet('cfg_channel', tostring(M.state.channel)); projSet('cfg_cc_only', M.state.ccOnly and '1' or '0') end
  if rf then clearMap() end
  reaper.ImGui_Dummy(ctx, 0, 8)
  if M.state.enabled then
    local ledColor = M.state.heartbeat and 0x66FF66FF or 0x999999FF
    reaper.ImGui_TextColored(ctx, ledColor, "●")
    reaper.ImGui_SameLine(ctx); reaper.ImGui_Text(ctx, "Event Monitoring")
    reaper.ImGui_Dummy(ctx, 0, 4)
    reaper.ImGui_Text(ctx, "Latest Trigger:"); reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0x66CCFFFF, (M.state.lastTrigger ~= "" and M.state.lastTrigger or "-"))
    reaper.ImGui_Text(ctx, "Latest Command:"); reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0xFFCC66FF, (M.state.lastCommand ~= "" and M.state.lastCommand or "-"))
  end
end

function M.runStandalone()
  local ctx = reaper.ImGui_CreateContext(SCRIPT_TITLE)
  local font = reaper.ImGui_CreateFont("sans-serif", 14); reaper.ImGui_Attach(ctx, font)
  local function renderUI()
    reaper.ImGui_SetNextWindowSize(ctx, 280, 160, reaper.ImGui_Cond_Once())
    local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_TITLE, true)
    if not visible then reaper.ImGui_End(ctx); return open end
    M.renderPanel(ctx)
    reaper.ImGui_End(ctx)
    return open
  end
  local function main()
    local open = renderUI()
    if open then reaper.defer(main) else if M.state.enabled then bridgeLoop() end end
  end
  main()
end

return M
