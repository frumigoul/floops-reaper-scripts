-- Floop Ess Hunter: taming hiss in a single pass.
-- @description Floop Ess Hunter: tame hiss and sibilance with envelopes.
-- @version 1.1.1
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   - Improved envelope visibility and stability when applying from preview.
--   - Added segment gain handles with live update when Live Edit is enabled.
--   - Hardened analysis and preview via median clamp on extreme sibilant material.
-- @about
--   Floop Ess Hunter
--   Taming hiss.
--
--   Detects and attenuates sibilance in vocal items by writing Volume envelope points.
--   Features multi-band analysis, adaptive thresholds, and ZCR.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--
--   For full documentation and changelog, please refer to the README file.
--   Keywords: vocal, de-esser, envelope, processing, analysis
-- @provides [main] floop-ess-hunter.lua


-- Support reaper.ImGui and legacy ImGui_* APIs

local min, max, floor, abs, sqrt, log = math.min, math.max, math.floor, math.abs, math.sqrt, math.log
local table_insert = table.insert
local table_remove = table.remove

if not reaper then return end
if not reaper.ImGui and not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui not found. Install via ReaPack 'Dear ImGui for ReaScript'.", "Floop Ess Hunter", 0)
  return
end

local ImGui = reaper.ImGui
if not ImGui then
  -- Minimal wrapper over reaper.ImGui_* functions
  ImGui = {}
  function ImGui.CreateContext(name) return reaper.ImGui_CreateContext(name) end
  function ImGui.DestroyContext(ctx)
    if reaper.ImGui_DestroyContext then
      return reaper.ImGui_DestroyContext(ctx)
    end
    -- No-op destroy if API is missing
  end
  function ImGui.SetNextWindowSize(ctx, w, h, cond) return reaper.ImGui_SetNextWindowSize(ctx, w, h, cond) end
  function ImGui.Begin(ctx, title, open, flags) return reaper.ImGui_Begin(ctx, title, open, flags) end
  function ImGui.End(ctx) return reaper.ImGui_End(ctx) end
  function ImGui.Text(ctx, txt) return reaper.ImGui_Text(ctx, txt) end
  function ImGui.TextWrapped(ctx, txt) return reaper.ImGui_TextWrapped(ctx, txt) end
  function ImGui.Separator(ctx) return reaper.ImGui_Separator(ctx) end
  function ImGui.Button(ctx, label, w, h) return reaper.ImGui_Button(ctx, label, w, h) end
  function ImGui.SliderInt(ctx, label, v, min, max) return reaper.ImGui_SliderInt(ctx, label, v, min, max) end
  function ImGui.SliderFloat(ctx, label, v, min, max)
    local f = reaper.ImGui_SliderFloat or reaper.ImGui_SliderDouble
    return f(ctx, label, v, min, max)
  end
  function ImGui.Checkbox(ctx, label, v) return reaper.ImGui_Checkbox(ctx, label, v) end
  function ImGui.WindowFlags_NoCollapse() return reaper.ImGui_WindowFlags_NoCollapse() end
  function ImGui.Cond_Appearing() return reaper.ImGui_Cond_Appearing() end
  -- Add combo/selectable wrappers
  function ImGui.BeginCombo(ctx, label, preview, flags) return reaper.ImGui_BeginCombo(ctx, label, preview, flags or 0) end
  function ImGui.EndCombo(ctx) return reaper.ImGui_EndCombo(ctx) end
  function ImGui.Selectable(ctx, label, selected) return reaper.ImGui_Selectable(ctx, label, selected or false) end
  function ImGui.SameLine(ctx, pos_x, spacing) return reaper.ImGui_SameLine(ctx, pos_x or nil, spacing or nil) end
  function ImGui.InputText(ctx, label, buf, flags)
    local f = reaper.ImGui_InputText
    if not f then return false, buf end
    local changed, out = f(ctx, label, buf or '', flags or 0)
    return changed, out
  end
  function ImGui.ProgressBar(ctx, frac, w, h, overlay)
    local f = reaper.ImGui_ProgressBar
    if f then return f(ctx, frac or 0.0, w or 0, h or 0, overlay or nil) end
    reaper.ImGui_Text(ctx, string.format('Progress: %d%%', floor((frac or 0)*100+0.5)))
    return true
  end
end

-- ProgressBar compatibility wrapper
if ImGui and not ImGui.ProgressBar then
  function ImGui.ProgressBar(ctx, frac, w, h, overlay)
    local f = reaper.ImGui_ProgressBar
    if f then return f(ctx, frac or 0.0, w or 0, h or 0, overlay or nil) end
    reaper.ImGui_Text(ctx, string.format('Progress: %d%%', floor((frac or 0)*100+0.5)))
    return true
  end
end

local ctx = ImGui.CreateContext('Floop Ess Hunter')
-- Style: attach font (English labels)
local sans_serif_font = (reaper.ImGui_CreateFont and reaper.ImGui_CreateFont('sans-serif', 12))
if sans_serif_font and reaper.ImGui_Attach then
  reaper.ImGui_Attach(ctx, sans_serif_font)
end

-- Style: theme palette
local THEME_COLORS = {
  [reaper.ImGui_Col_WindowBg()]         = 0x1e2328FF,
  [reaper.ImGui_Col_TitleBg()]          = 0x14B8A6FF,
  [reaper.ImGui_Col_TitleBgActive()]    = 0x0F766EFF,
  [reaper.ImGui_Col_Button()]           = 0x14B8A6FF,
  [reaper.ImGui_Col_ButtonHovered()]    = 0x0F766EFF,
  [reaper.ImGui_Col_ButtonActive()]     = 0x0D9488FF,
  [reaper.ImGui_Col_FrameBg()]          = 0x0F766EFF,
  [reaper.ImGui_Col_FrameBgHovered()]   = 0x0F766EFF,
  [reaper.ImGui_Col_FrameBgActive()]    = 0x0D9488FF,
  [reaper.ImGui_Col_SliderGrab()]       = 0xFFFFFFFF,
  [reaper.ImGui_Col_SliderGrabActive()] = 0xFFFFFFFF,
  -- Check mark color boosted for contrast on hover/active
  [reaper.ImGui_Col_CheckMark()]        = 0xFBBF24FF,
  [reaper.ImGui_Col_Header()]           = 0x1F2937FF,
  [reaper.ImGui_Col_HeaderHovered()]    = 0x14B8A6FF,
  [reaper.ImGui_Col_HeaderActive()]     = 0x0F766EFF,
  [reaper.ImGui_Col_Separator()]        = 0x14B8A6FF,
  [reaper.ImGui_Col_Text()]             = 0xF7FAFCFF,
  [reaper.ImGui_Col_TextDisabled()]     = 0x929292FF,
  [reaper.ImGui_Col_ResizeGrip()]       = 0x14B8A6FF,
  [reaper.ImGui_Col_ResizeGripHovered()] = 0x2DD4BFFF,
  [reaper.ImGui_Col_ResizeGripActive()]  = 0x0EA5A5FF,
}

local function apply_theme()
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 16.0, 16.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 5.0, 5.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 5.0, 5.0)
  if reaper.ImGui_StyleVar_GrabRounding then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 4.0)
  end

  local color_count = 0
  for k, v in pairs(THEME_COLORS) do
    reaper.ImGui_PushStyleColor(ctx, k, v)
    color_count = color_count + 1
  end
  return color_count
end

local function end_theme(color_count)
  reaper.ImGui_PopStyleColor(ctx, color_count)
  local to_pop = 5 + (reaper.ImGui_StyleVar_GrabRounding and 1 or 0)
  reaper.ImGui_PopStyleVar(ctx, to_pop)
end

-- Modifier detection (Ctrl/Alt) across ReaImGui versions
local function mod_ctrl()
  local mods = reaper.ImGui_GetKeyMods(ctx)
  local ctrl = (reaper.ImGui_KeyModFlags_Ctrl and reaper.ImGui_KeyModFlags_Ctrl()) or (reaper.ImGui_ModFlags_Ctrl and reaper.ImGui_ModFlags_Ctrl()) or 0
  return (mods & ctrl) ~= 0
end

local function mod_alt()
  local mods = reaper.ImGui_GetKeyMods(ctx)
  local alt = (reaper.ImGui_KeyModFlags_Alt and reaper.ImGui_KeyModFlags_Alt()) or (reaper.ImGui_ModFlags_Alt and reaper.ImGui_ModFlags_Alt()) or 0
  return (mods & alt) ~= 0
end

local function is_valid_item(item)
  if not item then return false end
  if reaper.ValidatePtr2 then
    return reaper.ValidatePtr2(0, item, "MediaItem*")
  end
  return true
end

-- State: defaults
local state = {
  band_min = 3500,
  band_max = 9500,
  band_step = 1000,
  band_Q = 4.0,
  window_ms = 12,
  hop_ms = 6,
  min_level_db = -45.0,
  zcr_thresh = 0.12,
  delta_on = 0.08,
  delta_off = 0.05,
  min_seg_ms = 25,
  max_gap_ms = 18,
  reduction_db = 4.0,
  pre_ramp_ms = 8,
  post_ramp_ms = 12,
  overwrite = true,
  target_mode = 2, -- 0=Track, 1=Track Pre-FX, 2=Take Volume
  -- Preview interaction state
  auto_analyze = false,
  last_change_time = nil,
  last_auto_analyze = nil,
  drag_threshold = false,
  drag_seg_index = -1,
  drag_edge = 0, -- 0 none, 1 left, 2 right
  drag_seg_vol_index = -1,
  view_start_frac = 0.0,
  view_len_frac = 1.0,
  snap_to_hop = true,
  live_edit = false,
  new_seg_active = false,
  new_seg_start_t = nil,
  new_seg_end_t = nil,
  custom_preset_name = '',
  selected_custom_index = 0,
  msg = "",
  preset_index = 0,
  -- Detection toggles (no UI)
  centers_log = false,       -- Use logarithmic spacing for band centers
  bands_per_oct = 4,         -- Band density per octave for log spacing
  -- Help modal state
  show_help = false,
}
-- ExtState: namespace
local EXT_NS = 'FloopEssHunter'

-- Help content
local HELP_CONTENT = {
  overview = {
    title = "Floop Ess Hunter — Overview",
    content = [[
Floop Ess Hunter automatically detects and reduces sibilant sounds ('s', 'sh', 'ch') in vocal recordings.

Taming the hiss, one S at a time.

It writes volume envelope points only on detected sibilant segments to preserve natural dynamics.
]]
  },
  
  quick_start = {
    title = "Quick Start",
    content = [[
1) Select one or more vocal items in your project.
2) Launch "Floop Ess Hunter" from the Actions List.
3) Click "Analyze (Preview)" to preview detection.
4) Click "Apply from preview" or "Analyze and apply" to write envelope points.
5) Adjust parameters under "Fine Tuning" as needed.
    ]]
  },
  
  parameters = {
    analysis = {
      title = "ANALYSIS",
      params = {
        {
          name = "Min Hz / Max Hz",
          type = "Integer range",
          range = "2500-12000 Hz",
          default = "3500-9500 Hz", 
          description = "Frequency range for sibilance detection. Sibilants typically occur between 3.5-9.5 kHz. Lower values catch softer sibilants, higher values focus on harsh consonants."
        },
        {
          name = "Step Hz", 
          type = "Integer",
          range = "250-2000 Hz",
          default = "1000 Hz",
          description = "Frequency spacing between analysis bands. Smaller steps provide finer frequency resolution but increase processing time."
        },
        {
          name = "Q Factor",
          type = "Float", 
          range = "2.0-7.0",
          default = "4.0",
          description = "Filter sharpness for frequency bands. Higher Q = narrower bands, more selective detection. Lower Q = broader bands, more forgiving detection."
        }
      }
    },
    
    detection = {
      title = "DETECTION", 
      params = {
        {
          name = "Window",
          type = "Integer",
          range = "6-20 ms", 
          default = "12 ms",
          description = "Analysis window size. Smaller windows provide better time resolution but less frequency accuracy. Larger windows are more stable but less precise."
        },
        {
          name = "Hop",
          type = "Integer", 
          range = "3-10 ms",
          default = "6 ms", 
          description = "Time step between analysis windows. Smaller hops provide smoother detection but increase processing time. Should be ≤ Window/2."
        },
        {
          name = "Min Level",
          type = "Float",
          range = "-60.0 to -20.0 dB",
          default = "-45.0 dB",
          description = "Minimum signal level for sibilance detection. Prevents processing of quiet background noise. Auto-adjusted based on median level."
        },
        {
          name = "ZCR Threshold", 
          type = "Float",
          range = "0.05-0.30",
          default = "0.12",
          description = "Zero-crossing rate threshold. Sibilants have high ZCR due to their noisy nature. Higher values = more selective, lower values = more inclusive."
        },
        {
          name = "Delta IN",
          type = "Float", 
          range = "0.00-0.25",
          default = "0.08",
          description = "Threshold offset above median ratio for sibilance onset detection. Higher values = less sensitive, fewer false positives."
        },
        {
          name = "Delta OUT",
          type = "Float",
          range = "0.00-0.25", 
          default = "0.05",
          description = "Threshold offset above median ratio for sibilance offset detection. Lower values = quicker release, shorter segments."
        }
      }
    },
    
    segments = {
      title = "SEGMENTS",
      params = {
        {
          name = "Min Segment",
          type = "Integer",
          range = "15-60 ms",
          default = "25 ms", 
          description = "Minimum duration for a valid sibilant segment. Shorter segments are discarded to avoid processing transients or noise."
        },
        {
          name = "Max Gap",
          type = "Integer",
          range = "10-40 ms",
          default = "18 ms",
          description = "Maximum gap within a sibilant segment before splitting. Helps merge closely spaced sibilant parts into single segments."
        },
        {
          name = "Pre Ramp",
          type = "Integer", 
          range = "0-25 ms",
          default = "8 ms",
          description = "Fade-in duration before volume reduction. Prevents abrupt level changes that could cause artifacts."
        },
        {
          name = "Post Ramp",
          type = "Integer",
          range = "0-40 ms", 
          default = "12 ms",
          description = "Fade-out duration after volume reduction. Ensures smooth transition back to original level."
        }
      }
    }
  },
  
  workflow = {
    title = "Recommended Workflow",
    content = [[
1) Set frequency bounds and reduction dB based on material.
2) Click "Analyze (Preview)" and audition A/B; toggle envelope visibility in REAPER.
3) Tweak Min/Max gap and ramps for natural transitions on fast/mellow phrases.
4) Adjust ZCR Threshold and Delta IN/OUT to reduce false positives/negatives.
5) Use "Replace segments (non‑cumulative)" to keep the envelope tidy.
]]
  },
  
  presets = {
    title = "Presets",
    content = [[
SPEECH PRESET:
Optimized for spoken word content with moderate sibilance.
• Frequency range: 3500-9500 Hz (standard sibilant range)
• Moderate sensitivity (Delta IN: 0.08)
• Balanced segment timing (25ms min, 18ms max gap)
• Conservative reduction (4.0 dB)

SOFT SINGING PRESET: 
Designed for gentle vocal performances with subtle sibilants.
• Slightly lower frequency range: 3200-9000 Hz
• Higher sensitivity (Delta IN: 0.06, ZCR: 0.10)
• Longer segments (28ms min, 20ms max gap)
• Gentle reduction (3.0 dB)

AGGRESSIVE SINGING PRESET:
For powerful vocals with prominent, harsh sibilants.
• Extended frequency range: 3600-10000 Hz
• Lower sensitivity (Delta IN: 0.10, ZCR: 0.13) 
• Shorter, tighter segments (22ms min, 16ms max gap)
• Stronger reduction (6.0 dB)

CUSTOM PRESETS:
Save your own configurations using the preset dropdown.
Custom presets are stored per-project and persist across sessions.
]]
  },
  
  envelope_model = {
    title = "Envelope Model",
    content = [[
• Track Volume envelope operates on linear amplitude (not dB).
• Reduction multiplies the local level by a factor < 1.
• Conversion: factor = 10^(dB/20). Examples: −6 dB ≈ 0.50×, −3 dB ≈ 0.71×.
• REAPER clamps envelope values; typical Track Volume range is 0..2.
• "Pre‑FX" writes before the FX chain; otherwise it is post‑fader.
]]
  },
  
  technical = {
    title = "Technical Notes",
    content = [[
• Effective sample rate accounts for the take’s playback rate for correct timing.
• Envelope writes are wrapped in Undo blocks for a safe workflow.
]]
  },
  
  troubleshooting = {
    title = "Troubleshooting",
    content = [[
COMMON ISSUES:

OVER-PROCESSING (too much reduction):
• Increase Delta IN threshold (less sensitive)
• Raise ZCR threshold (more selective)
• Increase Min Level (ignore quiet parts)
• Reduce frequency range (focus on harsh sibilants only)

UNDER-PROCESSING (sibilants missed):
• Decrease Delta IN threshold (more sensitive)
• Lower ZCR threshold (less selective)  
• Expand frequency range (catch more sibilant types)
• Reduce Min Segment duration (catch shorter sibilants)

CHOPPY/UNNATURAL RESULTS:
• Increase Pre/Post Ramp durations (smoother transitions)
• Increase Max Gap (merge fragmented segments)
• Reduce reduction amount (gentler processing)
• Check "Replace segments" to avoid cumulative processing

NO DETECTION:
• Verify audio item is selected and has content
• Check Min Level isn't too high for your material
• Try "Soft singing" preset for subtle sibilants
• Ensure frequency range covers your sibilant content

PERFORMANCE ISSUES:
• Increase Hop size (faster processing, less precision)
• Reduce frequency range (fewer analysis bands)
• Process shorter audio segments
• Close other resource-intensive applications

ERROR MESSAGES:
• "No active take": Select item with valid audio
• "Cannot create accessor": Audio file may be corrupted
• "Analysis canceled": User interruption or system issue
      ]]
  }
}

-- Help modal rendering function
local function draw_help_modal()

  local modalW, modalH = 800, 680
  local winX, winY = reaper.ImGui_GetWindowPos(ctx)
  local winW, winH = reaper.ImGui_GetWindowSize(ctx)
  if winX and winY and winW and winH then
    reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowPos(ctx, winX + (winW - modalW) * 0.5, winY + (winH - modalH) * 0.5, reaper.ImGui_Cond_Appearing())
  end
  local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove() | reaper.ImGui_WindowFlags_NoDocking()
  if reaper.ImGui_BeginPopupModal(ctx, "Help", true, flags) then
    local childFlags = (reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders()) or 0
    local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local avail_h = select(2, reaper.ImGui_GetContentRegionAvail(ctx))
    local btn_w = 100
    local btn_h = 25
    local child_h = math.max(120, (avail_h or 0) - (btn_h + 12))
    if reaper.ImGui_BeginChild(ctx, "HelpScroll", -1, child_h, childFlags) then
      -- Overview
  reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.overview.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.overview.content)
      reaper.ImGui_Spacing(ctx)

      -- Quick Start
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.quick_start.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.quick_start.content)
      reaper.ImGui_Spacing(ctx)

      -- Parameters heading
      reaper.ImGui_SeparatorText(ctx, 'Parameters (Fine Tuning)')

      -- Parameters: Analysis
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.parameters.analysis.title)
      for _, param in ipairs(HELP_CONTENT.parameters.analysis.params) do
        reaper.ImGui_Text(ctx, param.name)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%s | Range: %s | Default: %s)", param.type, param.range, param.default))
        reaper.ImGui_TextWrapped(ctx, param.description)
        reaper.ImGui_Spacing(ctx)
      end

      -- Parameters: Detection
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.parameters.detection.title)
      for _, param in ipairs(HELP_CONTENT.parameters.detection.params) do
        reaper.ImGui_Text(ctx, param.name)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%s | Range: %s | Default: %s)", param.type, param.range, param.default))
        reaper.ImGui_TextWrapped(ctx, param.description)
        reaper.ImGui_Spacing(ctx)
      end

      -- Parameters: Segments
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.parameters.segments.title)
      for _, param in ipairs(HELP_CONTENT.parameters.segments.params) do
        reaper.ImGui_Text(ctx, param.name)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%s | Range: %s | Default: %s)", param.type, param.range, param.default))
        reaper.ImGui_TextWrapped(ctx, param.description)
        reaper.ImGui_Spacing(ctx)
      end

      -- Preview & Interactions
      reaper.ImGui_SeparatorText(ctx, 'Preview & Interactions')
      reaper.ImGui_TextWrapped(ctx, [[
• Zoom: mouse wheel over the waveform; pan with right-button drag.
• Drag segments: adjust edges to refine boundaries; optional hop snapping for temporal consistency.
• Segment gain: drag the square handle at the bottom of each segment to change reduction; right-click to delete.
• Apply from preview: available only after "Analyze (Preview)".
      ]])
      reaper.ImGui_Spacing(ctx)

      -- Workflow
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.workflow.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.workflow.content)
      reaper.ImGui_Spacing(ctx)

      -- Presets
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.presets.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.presets.content)
      reaper.ImGui_Spacing(ctx)

      -- Envelope Model
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.envelope_model.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.envelope_model.content)
      reaper.ImGui_Spacing(ctx)

      -- Technical Notes
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.technical.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.technical.content)
      reaper.ImGui_Spacing(ctx)

      -- Troubleshooting
      reaper.ImGui_SeparatorText(ctx, HELP_CONTENT.troubleshooting.title)
      reaper.ImGui_TextWrapped(ctx, HELP_CONTENT.troubleshooting.content)
      reaper.ImGui_Spacing(ctx)

      reaper.ImGui_EndChild(ctx)
    end

    local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    reaper.ImGui_SetCursorPosX(ctx, (avail_w - btn_w) * 0.5)
    if reaper.ImGui_Button(ctx, "Close", btn_w, 25) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

-- Persist: last parameters via Project ExtState
local function serialize_last_state()
  local kv = {}
  local function add(k, v)
    kv[#kv+1] = tostring(k) .. '=' .. tostring(v)
  end
  add('band_min', state.band_min)
  add('band_max', state.band_max)
  add('band_step', state.band_step)
  add('band_Q', state.band_Q)
  add('window_ms', state.window_ms)
  add('hop_ms', state.hop_ms)
  add('min_level_db', state.min_level_db)
  add('zcr_thresh', state.zcr_thresh)
  add('delta_on', state.delta_on)
  add('delta_off', state.delta_off)
  add('min_seg_ms', state.min_seg_ms)
  add('max_gap_ms', state.max_gap_ms)
  add('pre_ramp_ms', state.pre_ramp_ms)
  add('post_ramp_ms', state.post_ramp_ms)
  add('reduction_db', state.reduction_db)
  add('overwrite', state.overwrite and 1 or 0)
  add('snap_to_hop', state.snap_to_hop and 1 or 0)
  add('centers_log', state.centers_log and 1 or 0)
  add('bands_per_oct', state.bands_per_oct)
  add('target_mode', state.target_mode)
  add('auto_analyze', state.auto_analyze and 1 or 0)
  return table.concat(kv, ',')
end

local function deserialize_last_state(s)
  if not s or s == '' then return end
  for token in string.gmatch(s, '[^,]+') do
    local k, v = token:match('([^=]+)=([^=]+)')
    if k and v then
      if k == 'overwrite' or k == 'snap_to_hop' or k == 'centers_log' or k == 'auto_analyze' then
        state[k] = (tonumber(v) or 0) ~= 0
      else
        local num = tonumber(v)
        state[k] = num or v
      end
    end
  end
end

local function load_last_state()
  local ok, value = reaper.GetProjExtState(0, EXT_NS, 'last_state')
  if ok ~= 0 and value and value ~= '' then
    deserialize_last_state(value)
  end
end

local function save_last_state()
  local s = serialize_last_state()
  reaper.SetProjExtState(0, EXT_NS, 'last_state', s)
end

-- Persist: load after function defs
if reaper and reaper.GetProjExtState then load_last_state() end

-- Constraints: enforce hop <= window/2 for stability
local function enforce_param_constraints()
  local max_hop = max(1, floor((state.window_ms or 12) / 2))
  if state.hop_ms > max_hop then
    state.hop_ms = max_hop
    state.msg = 'Hop clamped to Window/2 for stability'
  end
end

local PRESETS
local apply_preset
local list_custom_presets
local save_custom_preset
local load_custom_preset
local delete_custom_preset

local function db_to_amp(db) return 10 ^ (db/20) end
local function amp_to_db(amp) return 20 * (log(max(amp, 1e-12)) / log(10)) end

local function current_values_from_state()
  return {
    band_min=state.band_min, band_max=state.band_max, band_step=state.band_step, band_Q=state.band_Q,
    window_ms=state.window_ms, hop_ms=state.hop_ms, min_level_db=state.min_level_db, zcr_thresh=state.zcr_thresh,
    delta_on=state.delta_on, delta_off=state.delta_off, min_seg_ms=state.min_seg_ms, max_gap_ms=state.max_gap_ms,
    reduction_db=state.reduction_db, pre_ramp_ms=state.pre_ramp_ms, post_ramp_ms=state.post_ramp_ms,
  }
end

local function serialize_preset_values(v)
  local parts = {}
  local keys = {
    'band_min','band_max','band_step','band_Q','window_ms','hop_ms','min_level_db','zcr_thresh','delta_on','delta_off','min_seg_ms','max_gap_ms','reduction_db','pre_ramp_ms','post_ramp_ms'
  }
  for i=1,#keys do
    local k = keys[i]
    parts[#parts+1] = k..'='..tostring(v[k])
  end
  return table.concat(parts, ';')
end

local function deserialize_preset_values(str)
  local v = {}
  for token in string.gmatch(str or '', '[^;]+') do
    local k, val = token:match('([^=]+)=(.*)')
    if k then
      local num = tonumber(val)
      v[k] = num or val
    end
  end
  return v
end

list_custom_presets = function()
  local ok, s = reaper.GetProjExtState(0, EXT_NS, 'custom_presets')
  local names = {}
  if ok > 0 and s and s ~= '' then
    for name in s:gmatch('[^;]+') do names[#names+1] = name end
  end
  return names
end

save_custom_preset = function(name)
  local v = current_values_from_state()
  local ser = serialize_preset_values(v)
  reaper.SetProjExtState(0, EXT_NS, 'preset:'..name, ser)
  local names = list_custom_presets()
  local exists = false
  for i=1,#names do if names[i] == name then exists = true; break end end
  if not exists then
    names[#names+1] = name
    reaper.SetProjExtState(0, EXT_NS, 'custom_presets', table.concat(names, ';'))
  end
  state.msg = 'Saved preset: '..name
end

load_custom_preset = function(name)
  local ok, ser = reaper.GetProjExtState(0, EXT_NS, 'preset:'..name)
  if ok == 0 or not ser or ser == '' then state.msg = 'Preset not found: '..name; return end
  local v = deserialize_preset_values(ser)
  apply_preset({ name = name, values = v })
end

delete_custom_preset = function(name)
  reaper.SetProjExtState(0, EXT_NS, 'preset:'..name, '')
  local names = list_custom_presets()
  local kept = {}
  for i=1,#names do if names[i] ~= name then kept[#kept+1] = names[i] end end
  reaper.SetProjExtState(0, EXT_NS, 'custom_presets', table.concat(kept, ';'))
  state.msg = 'Deleted preset: '..name
end

local function rbj_bandpass(fc, Q, fs)
  local w0 = 2 * math.pi * fc / fs
  local cosw0 = math.cos(w0)
  local sinw0 = math.sin(w0)
  local alpha = sinw0 / (2 * Q)
  local b0 = alpha
  local b1 = 0
  local b2 = -alpha
  local a0 = 1 + alpha
  local a1 = -2 * cosw0
  local a2 = 1 - alpha
  return { b0=b0/a0, b1=b1/a0, b2=b2/a0, a1=a1/a0, a2=a2/a0 }
end

local function biquad_new(coeff)
  return { b0=coeff.b0, b1=coeff.b1, b2=coeff.b2, a1=coeff.a1, a2=coeff.a2, x1=0.0, x2=0.0, y1=0.0, y2=0.0 }
end

local function biquad_process(st, x)
  local y = st.b0*x + st.b1*st.x1 + st.b2*st.x2 - st.a1*st.y1 - st.a2*st.y2
  st.x2 = st.x1; st.x1 = x
  st.y2 = st.y1; st.y1 = y
  return y
end

local function build_centers(minf, maxf, step)
  local centers = {}
  if state.centers_log then
    local start_log2 = log(max(1, minf)) / log(2)
    local stop_log2  = log(max(minf+1, maxf)) / log(2)
    local octaves = max(0.25, stop_log2 - start_log2)
    local bpo = max(1, floor(state.bands_per_oct or 4))
    local n = max(1, floor(octaves * bpo + 0.5))
    for i = 0, n do
      local frac = i / max(1, n)
      local fc = minf * (2 ^ (frac * octaves))
      centers[#centers+1] = floor(fc + 0.5)
    end
  else
    local f = max(1000, floor(minf))
    local m = max(f+step, floor(maxf))
    local s = max(250, floor(step))
    for fc = f, m, s do centers[#centers+1] = fc end
  end
  return centers
end

-- Perf: cache filter banks for same (fs, Q, centers)
local BANK_CACHE = {}
local function bank_cache_key(fs, Q, centers)
  local parts = { tostring(fs), string.format('%.6f', Q) }
  for i = 1, #centers do parts[#parts+1] = tostring(centers[i]) end
  return table.concat(parts, '|')
end

local function build_bank(fs, centers, Q)
  local key = bank_cache_key(fs, Q, centers)
  local cached = BANK_CACHE[key]
  if cached then return cached end
  local bank = {}
  for _, fc in ipairs(centers) do
    bank[#bank+1] = biquad_new(rbj_bandpass(fc, Q, fs))
  end
  BANK_CACHE[key] = bank
  return bank
end

-- Target envelope modes
local TARGET_TRACK_VOL = 0
local TARGET_TRACK_PREFX = 1
local TARGET_TAKE_VOL = 2

local function ensure_envelope_visible(env)
  local vis = reaper.GetEnvelopeInfo_Value(env, "VIS")
  if vis >= 0.5 then return end
  if reaper.SetEnvelopeInfo_Value then
    reaper.SetEnvelopeInfo_Value(env, "VIS", 1.0)
    return
  end
  if reaper.GetEnvelopeStateChunk and reaper.SetEnvelopeStateChunk then
    local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    if ok == true and type(chunk) == "string" and #chunk > 0 then
      local new = chunk:gsub("VIS%s+%d", "VIS 1")
      if new ~= chunk then
        reaper.SetEnvelopeStateChunk(env, new, false)
      end
    end
  end
end

local function get_target_envelope(track, item, mode)
  if mode == TARGET_TAKE_VOL then
    local take = reaper.GetActiveTake(item)
    if not take then return nil end
    local env = reaper.GetTakeEnvelopeByName(take, "Volume")
    if env then
      ensure_envelope_visible(env)
      return env, true
    end

    local selected_items = {}
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
      selected_items[#selected_items+1] = reaper.GetSelectedMediaItem(0, i)
    end

    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40693, 0)

    env = reaper.GetTakeEnvelopeByName(take, "Volume")
    if env then
      ensure_envelope_visible(env)
    end

    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(selected_items) do reaper.SetMediaItemSelected(it, true) end

    return env, true
  end

  -- Handle Track Envelopes (Mode 0/1)
  local name = (mode == TARGET_TRACK_PREFX) and "Volume (Pre-FX)" or "Volume"

  -- Save current track selection
  local selected_tracks = {}
  for i = 0, reaper.CountTracks(0)-1 do
    local t = reaper.GetTrack(0, i)
    if reaper.IsTrackSelected(t) then
      selected_tracks[#selected_tracks+1] = t
    end
  end

  -- Ensure only this track is selected, so actions hit the right one
  for i = 0, reaper.CountTracks(0)-1 do
    local t = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(t, false)
  end
  reaper.SetTrackSelected(track, true)

  -- Try to get the envelope
  local env = reaper.GetTrackEnvelopeByName(track, name)

  -- If it doesn't exist, activate/create it and make it visible
  if env == nil then
    if mode == TARGET_TRACK_PREFX then
      reaper.Main_OnCommand(40050, 0) -- Toggle pre-FX volume envelope (create/enable)
    else
      -- Legacy branch: standard volume (compatibility)
      reaper.Main_OnCommand(40406, 0) -- Toggle track volume envelope visible (create/enable)
    end
    env = reaper.GetTrackEnvelopeByName(track, name)
    if env == nil then
      reaper.ShowMessageBox("Unable to create envelope '"..name.."'. Open Track Envelopes and enable it.", "Floop Ess Hunter", 0)
      -- Restore original selection before returning
      for i = 0, reaper.CountTracks(0)-1 do
        reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
      end
      for _, t in ipairs(selected_tracks) do
        reaper.SetTrackSelected(t, true)
      end
      return nil
    end
  end

  ensure_envelope_visible(env)

  -- Restore original track selection
  for i = 0, reaper.CountTracks(0)-1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
  end
  for _, t in ipairs(selected_tracks) do
    reaper.SetTrackSelected(t, true)
  end

  return env, false
end

-- ExtState: per-item overwrite tracking

local function get_item_guid(item)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  return guid
end

local function get_track_guid(track)
  return reaper.GetTrackGUID(track)
end

local function make_key(track, item)
  return string.format('%s|%s', get_track_guid(track), get_item_guid(item))
end

local function save_segments(track, item, segments, pre_ms, post_ms)
  local key = make_key(track, item)
  local parts = { tostring(pre_ms), tostring(post_ms) }
  for i=1,#segments do
    parts[#parts+1] = string.format('%.6f,%.6f', segments[i][1], segments[i][2])
  end
  local value = table.concat(parts, ';')
  reaper.SetProjExtState(0, EXT_NS, key, value)
end

local function load_segments(track, item)
  local key = make_key(track, item)
  local ok, value = reaper.GetProjExtState(0, EXT_NS, key)
  if ok == 0 or not value or value == '' then return nil end
  local segs = {}
  local pre_ms, post_ms = 0, 0
  local first = true
  for token in string.gmatch(value, '[^;]+') do
    if first then pre_ms = tonumber(token); first = false
    elseif post_ms == 0 then post_ms = tonumber(token)
    else
      local a,b = token:match('([^,]+),([^,]+)')
      if a and b then segs[#segs+1] = { tonumber(a), tonumber(b) } end
    end
  end
  return { pre_ms = pre_ms or 0, post_ms = post_ms or 0, segments = segs }
end

local function clear_previous_segments(env, track, item, item_pos, start_offs, playrate, is_take_env)
  local prev = load_segments(track, item)
  if not prev then return end
  local pre = max(0, (prev.pre_ms or 0)/1000)
  local post = max(0, (prev.post_ms or 0)/1000)
  
  local function to_env_time(t_proj)
    if is_take_env then
      return (t_proj - item_pos) * playrate
    else
      return t_proj
    end
  end

  for i=1,#prev.segments do
    local s = prev.segments[i]
    local t1 = to_env_time(max(0, s[1] - pre))
    local t4 = to_env_time(s[2] + post)
    reaper.DeleteEnvelopePointRange(env, t1, t4)
  end
end

local function insert_reduction_points(env, t_start, t_end, factor, pre_ms, post_ms, overwrite, item_pos, start_offs, playrate, is_take_env)
  local pre = max(0, pre_ms/1000)
  local post = max(0, post_ms/1000)
  local shape = 0 -- linear
  
  local function to_env_time(t_proj)
    if is_take_env then
      return (t_proj - item_pos) * playrate
    else
      return t_proj
    end
  end

  local t1 = to_env_time(max(0, t_start - pre))
  local t2 = to_env_time(t_start)
  local t3 = to_env_time(t_end)
  local t4 = to_env_time(t_end + post)
  
  local v_pre = select(2, reaper.Envelope_Evaluate(env, max(0, t1 - 1e-3), 0, 0))
  local v_post = select(2, reaper.Envelope_Evaluate(env, t4 + 1e-3, 0, 0))
  -- Overwrite: remove points in range to prevent accumulation
  if overwrite then
    reaper.DeleteEnvelopePointRange(env, t1, t4)
  end
  -- Envelope: insert points based on baseline
  reaper.InsertEnvelopePointEx(env, -1, t1, v_pre, shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t2, v_pre * factor, shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t3, v_post * factor, shape, 0, false, true)
  reaper.InsertEnvelopePointEx(env, -1, t4, v_post, shape, 0, false, true)
end

local function features_for_window(buf, ch, bank)
  local N = (#buf) / ch
  local sum_sq_wb = 0.0
  local zcr = 0
  local prev_sign = 0
  local band_energy = {}
  for i=1,#bank do band_energy[i] = 0.0 end
  for i = 0, N-1 do
    local mono = 0.0
    for c = 0, ch-1 do mono = mono + buf[(i*ch)+c+1] end
    mono = mono / ch
    sum_sq_wb = sum_sq_wb + mono*mono
    local sign = (mono >= 0) and 1 or -1
    if i > 0 and sign ~= prev_sign then zcr = zcr + 1 end
    prev_sign = sign
    for b = 1, #bank do
      local y = biquad_process(bank[b], mono)
      band_energy[b] = band_energy[b] + y*y
    end
  end
  local rms_wb = sqrt(sum_sq_wb / max(1, N))
  local rms_band_max = 0.0
  for b = 1, #band_energy do
    local rms_b = sqrt(band_energy[b] / max(1, N))
    if rms_b > rms_band_max then rms_band_max = rms_b end
  end
  local ratio_max = (rms_band_max + 1e-12) / (rms_wb + 1e-12)
  local zcr_norm = zcr / max(1, (N-1))
  local level_db = amp_to_db(rms_wb)
  return ratio_max, zcr_norm, level_db
end

local function median(tbl)
  -- Perf: Quickselect median (avg O(n)), avoids full sort
  local n = #tbl
  if n == 0 then return 0.2 end
  -- Copy to avoid mutating caller's table
  local a = {}
  for i = 1, n do a[i] = tbl[i] end

  local function partition(arr, left, right, pivotIndex)
    local pivotValue = arr[pivotIndex]
    arr[pivotIndex], arr[right] = arr[right], arr[pivotIndex]
    local storeIndex = left
    for i = left, right - 1 do
      if arr[i] < pivotValue then
        arr[i], arr[storeIndex] = arr[storeIndex], arr[i]
        storeIndex = storeIndex + 1
      end
    end
    arr[storeIndex], arr[right] = arr[right], arr[storeIndex]
    return storeIndex
  end

  local function quickselect(arr, left, right, k)
    while true do
      if left == right then return arr[left] end
      local pivotIndex = floor((left + right) / 2)
      pivotIndex = partition(arr, left, right, pivotIndex)
      if k == pivotIndex then
        return arr[k]
      elseif k < pivotIndex then
        right = pivotIndex - 1
      else
        left = pivotIndex + 1
      end
    end
  end

  if n % 2 == 1 then
    local k = floor((n + 1) / 2)
    return quickselect(a, 1, n, k)
  else
    local k1 = floor(n / 2)
    local v1 = quickselect(a, 1, n, k1)
    -- For the upper median, run quickselect on a fresh copy to avoid bias
    local b = {}
    for i = 1, n do b[i] = tbl[i] end
    local v2 = quickselect(b, 1, n, k1 + 1)
    return 0.5 * (v1 + v2)
  end
end

local function analyze_item_and_reduce(item, cfg)
  local take = reaper.GetActiveTake(item); if not take then return 0 end
  local src = reaper.GetMediaItemTake_Source(take); if not src then return 0 end
  local sr = reaper.GetMediaSourceSampleRate(src); if not sr or sr<=0 then sr = 48000 end
  local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  if not pr or pr <= 0 then pr = 1.0 end
  sr = floor(sr * pr + 0.5)
  local ch = reaper.GetMediaSourceNumChannels(src); if not ch or ch<1 then ch = 1 end
  local accessor = reaper.CreateTakeAudioAccessor(take); if not accessor then return 0 end
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local t0 = item_pos; local t1 = item_pos + item_len
  -- Enforce Hop <= Window/2 on incoming cfg for stability
  if cfg and cfg.window_ms and cfg.hop_ms then
    local max_hop = max(1, floor(cfg.window_ms/2))
    if cfg.hop_ms > max_hop then
      cfg.hop_ms = max_hop
      state.msg = 'Hop clamped to Window/2 for stability'
    end
  end
  local N = max(64, floor(sr * (cfg.window_ms/1000)))
  local H = max(32, floor(sr * (cfg.hop_ms/1000)))
  local track = reaper.GetMediaItem_Track(item)
  local env, is_take_env = get_target_envelope(track, item, cfg.target_mode or (cfg.use_prefx and 1 or 0))
  if not env then reaper.DestroyAudioAccessor(accessor); return 0 end
  
  local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  local ep_pos = is_take_env and item_pos or 0.0
  local ep_offs = is_take_env and start_offs or 0.0
  local ep_rate = is_take_env and pr or 1.0

  -- If overwrite is active, clear previous segments applied by this script
  if cfg.overwrite then clear_previous_segments(env, track, item, ep_pos, ep_offs, ep_rate, is_take_env) end

  local centers = build_centers(cfg.band_min, cfg.band_max, cfg.band_step)
  local buf = reaper.new_array(N * ch)

  -- Detect: adaptive threshold + dynamic min level
  local bank1 = build_bank(sr, centers, cfg.band_Q)
  local ratios_all = {}
  local levels_all = {}
  local t = t0
  while t + (N/sr) <= t1 do
    local src_t = (t - item_pos) * pr
    buf.clear(); reaper.GetAudioAccessorSamples(accessor, sr, ch, src_t, N, buf)
    local data = buf.table()
    local ratio, zcr, lvl = features_for_window(data, ch, bank1)
    ratios_all[#ratios_all+1] = ratio
    levels_all[#levels_all+1] = lvl
    t = t + (H / sr)
  end
  local med_lvl = median({table.unpack(levels_all)})
  local min_level_use = max(cfg.min_level_db, (med_lvl or cfg.min_level_db) - 12.0)
  local ratios = {}
  for i=1,#ratios_all do if levels_all[i] > min_level_use then ratios[#ratios+1] = ratios_all[i] end end
  if #ratios == 0 then ratios = ratios_all end
  -- Clamp median to remain robust on short or highly sibilant clips
  local raw_median = median(ratios)
  local med_ratio = min(raw_median, 0.55)
  local thr_on = med_ratio + cfg.delta_on
  local thr_off = med_ratio + cfg.delta_off

  -- Segmentation
  local bank2 = build_bank(sr, centers, cfg.band_Q)
  local inS = false
  local seg_start = 0.0
  local gap_run_ms = 0.0
  local segments = {}
  local factor = db_to_amp(-cfg.reduction_db)
  local r_prev1, r_prev2 = nil, nil

  t = t0
  while t + (N/sr) <= t1 do
    local src_t = (t - item_pos) * pr
    buf.clear(); reaper.GetAudioAccessorSamples(accessor, sr, ch, src_t, N, buf)
    local data = buf.table()
    local ratio, zcr, lvl = features_for_window(data, ch, bank2)
    -- Smooth: 3-tap ratio
    local r_s = ratio
    if r_prev1 then r_s = 0.75*ratio + 0.25*r_prev1 end
    if r_prev2 then r_s = 0.6*ratio + 0.3*r_prev1 + 0.1*r_prev2 end
    r_prev2, r_prev1 = r_prev1, ratio
    local pass_on = (lvl > min_level_use) and (r_s >= thr_on) and (zcr >= cfg.zcr_thresh)
    local pass_off = (ratio <= thr_off) or (zcr < cfg.zcr_thresh)

    local win_start = t
    local win_end = t + (N/sr)

    if pass_on then
      if not inS then inS = true; seg_start = win_start; gap_run_ms = 0 else gap_run_ms = 0 end
    else
      if inS then
        gap_run_ms = gap_run_ms + cfg.hop_ms
        if pass_off and gap_run_ms >= cfg.max_gap_ms then
          local seg_end = win_end
          if (seg_end - seg_start) * 1000 >= cfg.min_seg_ms then table.insert(segments, {seg_start, seg_end}) end
          inS = false; gap_run_ms = 0
        end
      end
    end
    t = t + (H / sr)
  end
  if inS then local seg_end = t1; if (seg_end - seg_start)*1000 >= cfg.min_seg_ms then table.insert(segments, {seg_start, seg_end}) end end

  reaper.PreventUIRefresh(1)
  for _, seg in ipairs(segments) do
    insert_reduction_points(env, seg[1], seg[2], factor, cfg.pre_ramp_ms, cfg.post_ramp_ms, cfg.overwrite, ep_pos, ep_offs, ep_rate, is_take_env)
  end
  -- Save new segments for possible future cleanup
  save_segments(track, item, segments, cfg.pre_ramp_ms, cfg.post_ramp_ms)

  reaper.Envelope_SortPoints(env)
  reaper.PreventUIRefresh(-1)
  reaper.DestroyAudioAccessor(accessor)
  return #segments
end

local function apply_on_selection()
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then state.msg = "Select at least one vocal item"; return end
  local t_start = reaper.time_precise()
  reaper.Undo_BeginBlock()
  local total = 0
  local cfg = state
  for i=0,cnt-1 do
    total = total + analyze_item_and_reduce(reaper.GetSelectedMediaItem(0,i), cfg)
  end
  reaper.Undo_EndBlock("Floop Ess Hunter: sibilance reduction", -1)
  reaper.UpdateArrange()
  local elapsed = reaper.time_precise() - t_start
  state.msg = string.format("Sibilant segments reduced: %d (%.2fs)", total, elapsed)
end

-- Loop GUI
-- Cache: preview waveform and segments
local analysis_cache = nil

-- Perf: chunked preview analysis (progress/cancel)
local preview_job = nil

local function preview_start(cfg)
  if preview_job then return end
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt ~= 1 then
    state.msg = 'Preview requires exactly one selected item'
    preview_job = nil
    analysis_cache = nil
    return
  end
  local item = reaper.GetSelectedMediaItem(0, 0)
  local take = reaper.GetActiveTake(item); if not take then state.msg='No active take'; analysis_cache=nil; return end
  local src = reaper.GetMediaItemTake_Source(take); if not src then state.msg='No source'; analysis_cache=nil; return end
  local sr = reaper.GetMediaSourceSampleRate(src); if not sr or sr<=0 then sr = 48000 end
  local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  if not pr or pr <= 0 then pr = 1.0 end
  local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  sr = floor(sr * pr + 0.5)
  local ch = reaper.GetMediaSourceNumChannels(src); if not ch or ch<1 then ch = 1 end
  local accessor = reaper.CreateTakeAudioAccessor(take); if not accessor then state.msg='Cannot create accessor'; return end

  local item_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local t0 = item_pos; local t1 = item_pos + item_len
  -- Enforce Hop <= Window/2 on preview config for stability
  if cfg and cfg.window_ms and cfg.hop_ms then
    local max_hop = max(1, floor(cfg.window_ms/2))
    if cfg.hop_ms > max_hop then
      cfg.hop_ms = max_hop
      state.msg = 'Hop clamped to Window/2 for stability'
    end
  end
  local N = max(64, floor(sr * (cfg.window_ms/1000)))
  local H = max(32, floor(sr * (cfg.hop_ms/1000)))
  local centers = build_centers(cfg.band_min, cfg.band_max, cfg.band_step)
  local bank1 = build_bank(sr, centers, cfg.band_Q)
  local buf = reaper.new_array(N * ch)

  preview_job = {
    phase = 1,
    cancel = false,
    cfg = cfg,
    item = item,
    take = take,
    src = src,
    accessor = accessor,
    sr = sr, ch = ch,
    pr = pr, start_offs = start_offs,
    item_pos = item_pos, item_len = item_len,
    t0 = t0, t1 = t1, 
    t_rel = 0.0, -- Relative time from item start
    N = N, H = H,
    centers = centers,
    bank1 = bank1,
    buf = buf,
    ratios_all = {}, levels_all = {},
    -- Phase 2 state
    bank2 = nil, inS = false, seg_start = 0.0, gap_run_ms = 0.0,
    segments = {}, amp_windows = {}, time_windows = {}, ratio_windows = {}, zcr_windows = {}, level_windows = {},
    r_prev1 = nil, r_prev2 = nil,
    -- Results
    med_ratio = 0.0, thr_on = 0.0, thr_off = 0.0, min_level_use = cfg.min_level_db,
    progress = 0.0,
    t_start = reaper.time_precise(),
    win_count = 0,
  }
 
  state.msg = 'Analyzing...'
end

local function preview_cancel()
  if not preview_job then return end
  preview_job.cancel = true
end

local function preview_cleanup(msg)
  if preview_job then
    if preview_job.accessor then reaper.DestroyAudioAccessor(preview_job.accessor) end
  end
  preview_job = nil
  if msg then state.msg = msg end
end

local function preview_step(budget_seconds)
  if not preview_job then return end
  local job = preview_job
  if job.cancel then preview_cleanup('Analysis canceled'); return end
  local deadline = reaper.time_precise() + (budget_seconds or 0.008)

  if job.phase == 1 then
    while reaper.time_precise() < deadline do
      if job.t_rel + (job.N/job.sr) > job.item_len then
        -- Phase 1 end
        local med_lvl = median({table.unpack(job.levels_all)})
        job.min_level_use = max(job.cfg.min_level_db, (med_lvl or job.cfg.min_level_db) - 12.0)
        local ratios = {}
        for i=1,#job.ratios_all do if job.levels_all[i] > job.min_level_use then ratios[#ratios+1] = job.ratios_all[i] end end
        if #ratios == 0 then ratios = job.ratios_all end
        -- Apply same median clamp for preview to stay robust on extreme material
        local raw_median = median(ratios)
        job.med_ratio = min(raw_median, 0.55)
        job.thr_on = job.med_ratio + job.cfg.delta_on
        job.thr_off = job.med_ratio + job.cfg.delta_off
        job.bank2 = build_bank(job.sr, job.centers, job.cfg.band_Q)
        job.t_rel = 0.0
        job.phase = 2
        break
      end
      local src_t = job.t_rel * job.pr
      job.buf.clear(); reaper.GetAudioAccessorSamples(job.accessor, job.sr, job.ch, src_t, job.N, job.buf)
      local data = job.buf.table()
      local Ns = job.N
      local sum_sq_wb = 0.0
      local zcr = 0
      local prev_sign = 0
      local band_energy = {}
      for i=1,#job.bank1 do band_energy[i] = 0.0 end
      for i = 0, Ns-1 do
        local mono = 0.0
        for c = 0, job.ch-1 do mono = mono + data[(i*job.ch)+c+1] end
        mono = mono / job.ch
        sum_sq_wb = sum_sq_wb + mono*mono
        local sign = (mono >= 0) and 1 or -1
        if i > 0 and sign ~= prev_sign then zcr = zcr + 1 end
        prev_sign = sign
        for b = 1, #job.bank1 do
          local y = biquad_process(job.bank1[b], mono)
          band_energy[b] = band_energy[b] + y*y
        end
      end
      local rms_wb = sqrt(sum_sq_wb / max(1, Ns))
      local rms_band_max = 0.0
      for b = 1, #band_energy do
        local rms_b = sqrt(band_energy[b] / max(1, Ns))
        if rms_b > rms_band_max then rms_band_max = rms_b end
      end
      local ratio = (rms_band_max + 1e-12) / (rms_wb + 1e-12)
      local level_db = amp_to_db(rms_wb)
      job.ratios_all[#job.ratios_all+1] = ratio
      job.levels_all[#job.levels_all+1] = level_db
      job.t_rel = job.t_rel + (job.H / job.sr)
      job.win_count = job.win_count + 1
      job.progress = 0.5 * (job.t_rel / job.item_len)
      if job.cancel then preview_cleanup('Analysis canceled'); return end
    end
    return
  end

  if job.phase == 2 then
    while reaper.time_precise() < deadline do
      if job.t_rel + (job.N/job.sr) > job.item_len then
        -- Phase 2 end
        if job.inS then
          local seg_end = job.item_pos + job.item_len
          if (seg_end - job.seg_start) * 1000 >= job.cfg.min_seg_ms then job.segments[#job.segments+1] = {job.seg_start, seg_end} end
        end
        reaper.DestroyAudioAccessor(job.accessor)
        local ratio_max = 1.0
        for i=1,#job.ratio_windows do if job.ratio_windows[i] > ratio_max then ratio_max = job.ratio_windows[i] end end
        if ratio_max <= 0 then ratio_max = 1.0 end
        analysis_cache = {
          item = job.item,
          item_pos = job.item_pos,
          item_len = job.item_len,
          segments = job.segments,
          amp = job.amp_windows,
          time = job.time_windows,
          ratio = job.ratio_windows,
          zcr = job.zcr_windows,
          level_db = job.level_windows,
          med_ratio = job.med_ratio,
          thr_on = job.thr_on,
          thr_off = job.thr_off,
          auto_min_level_db = job.min_level_use,
          ratio_max = ratio_max,
        }
        local elapsed = max(0.0001, reaper.time_precise() - (job.t_start or reaper.time_precise()))
        local rps = job.win_count / elapsed
        preview_job = nil
        state.msg = string.format('Preview: %d segments (%.2fs, %.0f win/s)', #analysis_cache.segments, elapsed, rps)
        return
      end
      local src_t = job.t_rel * job.pr
      job.buf.clear(); reaper.GetAudioAccessorSamples(job.accessor, job.sr, job.ch, src_t, job.N, job.buf)
      local data = job.buf.table()
      local Ns = job.N
      local sum_sq_wb = 0.0
      local zcr = 0
      local prev_sign = 0
      local band_energy = {}
      for i=1,#job.bank2 do band_energy[i] = 0.0 end
      for i = 0, Ns-1 do
        local mono = 0.0
        for c = 0, job.ch-1 do mono = mono + data[(i*job.ch)+c+1] end
        mono = mono / job.ch
        sum_sq_wb = sum_sq_wb + mono*mono
        local sign = (mono >= 0) and 1 or -1
        if i > 0 and sign ~= prev_sign then zcr = zcr + 1 end
        prev_sign = sign
        for b = 1, #job.bank2 do
          local y = biquad_process(job.bank2[b], mono)
          band_energy[b] = band_energy[b] + y*y
        end
      end
      local rms_wb = sqrt(sum_sq_wb / max(1, Ns))
      local rms_band_max = 0.0
      for b = 1, #band_energy do
        local rms_b = sqrt(band_energy[b] / max(1, Ns))
        if rms_b > rms_band_max then rms_band_max = rms_b end
      end
      local ratio = (rms_band_max + 1e-12) / (rms_wb + 1e-12)
      local zcr_norm = zcr / max(1, (Ns-1))
      local level_db = amp_to_db(rms_wb)

      job.amp_windows[#job.amp_windows+1] = rms_wb
      local t_proj = job.item_pos + job.t_rel
      job.time_windows[#job.time_windows+1] = t_proj
      local r_s = ratio
      if job.r_prev1 then r_s = 0.75*ratio + 0.25*job.r_prev1 end
      if job.r_prev2 then r_s = 0.6*ratio + 0.3*job.r_prev1 + 0.1*job.r_prev2 end
      job.r_prev2, job.r_prev1 = job.r_prev1, ratio
      job.ratio_windows[#job.ratio_windows+1] = r_s
      job.zcr_windows[#job.zcr_windows+1] = zcr_norm
      job.level_windows[#job.level_windows+1] = level_db

      local win_start = t_proj
      local win_end = t_proj + (job.N/job.sr)
      local pass_on = (level_db > job.min_level_use) and (r_s >= job.thr_on) and (zcr_norm >= job.cfg.zcr_thresh)
      local pass_off = (ratio <= job.thr_off) or (zcr_norm < job.cfg.zcr_thresh)
      if pass_on then
        if not job.inS then job.inS = true; job.seg_start = win_start; job.gap_run_ms = 0 else job.gap_run_ms = 0 end
      else
        if job.inS then
          job.gap_run_ms = job.gap_run_ms + job.cfg.hop_ms
          if pass_off and job.gap_run_ms >= job.cfg.max_gap_ms then
            local seg_end = win_end
            if (seg_end - job.seg_start) * 1000 >= job.cfg.min_seg_ms then job.segments[#job.segments+1] = {job.seg_start, seg_end} end
            job.inS = false; job.gap_run_ms = 0
          end
        end
      end

      job.t_rel = job.t_rel + (job.H / job.sr)
      job.win_count = job.win_count + 1
      job.progress = 0.5 + 0.5 * (job.t_rel / job.item_len)
      if job.cancel then preview_cleanup('Analysis canceled'); return end
    end
    return
  end
end


local function apply_cached_segments(cfg)
  if not analysis_cache or not analysis_cache.item then state.msg = 'No preview cached'; return end
  local item = analysis_cache.item
  if not is_valid_item(item) then
    state.msg = 'Item changed, run Analyze (Preview) again'
    analysis_cache = nil
    return
  end
  local track = reaper.GetMediaItem_Track(item)
  local env, is_take_env = get_target_envelope(track, item, cfg.target_mode or (cfg.use_prefx and 1 or 0))
  if not env then state.msg = 'Cannot access envelope'; return end
  
  local take = reaper.GetActiveTake(item)
  local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  
  local ep_pos = is_take_env and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
  local ep_offs = is_take_env and start_offs or 0.0
  local ep_rate = is_take_env and pr or 1.0

  if cfg.overwrite then clear_previous_segments(env, track, item, ep_pos, ep_offs, ep_rate, is_take_env) end
  local factor = db_to_amp(-cfg.reduction_db)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for i=1,#analysis_cache.segments do
    local s = analysis_cache.segments[i]
    local seg_factor = factor
    if s[3] then
      seg_factor = db_to_amp(-s[3])
    end
    insert_reduction_points(env, s[1], s[2], seg_factor, cfg.pre_ramp_ms, cfg.post_ramp_ms, cfg.overwrite, ep_pos, ep_offs, ep_rate, is_take_env)
  end
  save_segments(track, item, analysis_cache.segments, cfg.pre_ramp_ms, cfg.post_ramp_ms)
  reaper.Envelope_SortPoints(env)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Floop Ess Hunter: apply segments from preview', -1)
  reaper.UpdateArrange()
  state.msg = string.format('Applied %d segments from preview', #analysis_cache.segments)
end

local function clear_segments_for_selection()
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then state.msg = "Select at least one item to clear segments"; return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local cleared_count = 0
  for i = 0, cnt - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local env, is_take_env = get_target_envelope(track, item, state.target_mode or (state.use_prefx and 1 or 0))
    if env then
      local take = reaper.GetActiveTake(item)
      local pr = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
      local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
      
      local ep_pos = is_take_env and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
      local ep_offs = is_take_env and start_offs or 0.0
      local ep_rate = is_take_env and pr or 1.0
      
      clear_previous_segments(env, track, item, ep_pos, ep_offs, ep_rate, is_take_env)
      
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      -- Clear points in the entire item range if requested (conceptually)
      -- For Take Envelope: we cleared segments via clear_previous_segments.
      -- If we want to delete ALL points in the item range, we need correct coords.
      
      local range_t1 = item_pos
      local range_t2 = item_pos + item_len
      
      if is_take_env then
        range_t1 = (range_t1 - ep_pos) * ep_rate
        range_t2 = (range_t2 - ep_pos) * ep_rate
      end
      
      reaper.DeleteEnvelopePointRange(env, range_t1, range_t2)
      reaper.Envelope_SortPoints(env)
      -- Clear ExtState data
      local key = make_key(track, item)
      reaper.SetProjExtState(0, EXT_NS, key, '')
      cleared_count = cleared_count + 1
    end
  end
  if cleared_count > 0 then
    reaper.UpdateArrange()
    state.msg = string.format('Cleared segments for %d item(s)', cleared_count)
  else
    state.msg = 'No segments to clear'
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Floop Ess Hunter: clear segments', -1)
end

local function draw_waveform_panel()
  local W_avail, H_avail = reaper.ImGui_GetContentRegionAvail(ctx)
  local W = math.max(420, W_avail)
  local H = 320
  local x0, y0 = reaper.ImGui_GetCursorScreenPos(ctx)
  -- UI: reserve layout space
  reaper.ImGui_InvisibleButton(ctx, '##waveform_panel', W, H)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  -- UI: background
  reaper.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0+W, y0+H, 0x1E1E20FF)
  -- UI: border
  reaper.ImGui_DrawList_AddRect(dl, x0, y0, x0+W, y0+H, 0x3A3A3AFF)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local mx, my = reaper.ImGui_GetMousePos(ctx)
  local wheel = reaper.ImGui_GetMouseWheel(ctx)
  local wave_top = y0
  local wave_h = H
  local wave_scale = 0.80

  if analysis_cache and analysis_cache.amp and #analysis_cache.amp > 0 then
    -- Zoom and pan handling
    local view_start = state.view_start_frac or 0.0
    local view_len = state.view_len_frac or 1.0
    if view_start < 0 then view_start = 0 end
    if view_len < 0.1 then view_len = 0.1 end
    if view_len > 1.0 then view_len = 1.0 end
    if view_start + view_len > 1.0 then view_start = 1.0 - view_len end

    if hovered then
      if wheel ~= 0 then
        local cursor_frac = (mx - x0) / W
        if cursor_frac < 0 then cursor_frac = 0 elseif cursor_frac > 1 then cursor_frac = 1 end
        local ctrl_or_alt = mod_ctrl() or mod_alt()
        if ctrl_or_alt then
          -- Horizontal navigation on Ctrl/Alt + Wheel
          local step = 0.25 * view_len
          local new_start = view_start - (wheel * step)
          if new_start < 0 then new_start = 0 end
          if new_start + view_len > 1.0 then new_start = 1.0 - view_len end
          state.view_start_frac = new_start
          view_start = new_start
        else
          -- Zoom on Wheel
          local factor = math.exp(-wheel * 0.2)
          local new_len = math.max(0.1, math.min(1.0, view_len * factor))
          local delta_len = new_len - view_len
          local new_start = view_start + cursor_frac * (-delta_len)
          if new_start < 0 then new_start = 0 end
          if new_start + new_len > 1.0 then new_start = 1.0 - new_len end
          state.view_len_frac = new_len
          state.view_start_frac = new_start
          view_len = new_len
          view_start = new_start
        end
      end
    end

    local vis_t0 = analysis_cache.item_pos + view_start * analysis_cache.item_len
    local vis_len = view_len * analysis_cache.item_len
    local vis_t1 = vis_t0 + vis_len
    local mid = wave_top + wave_h/2
    -- Waveform bars
    local n = #analysis_cache.amp
    for i = 1, n do
      local t = analysis_cache.time[i]
      if t >= vis_t0 and t <= vis_t1 then
        local x = x0 + ((t - vis_t0) / vis_len) * W
        if x >= x0 and x < x0+W then
          local a = analysis_cache.amp[i]
          if a > 1.0 then a = 1.0 end
          local y = a * (wave_h * wave_scale)
          reaper.ImGui_DrawList_AddLine(dl, x, mid - y, x, mid + y, 0xBFC7CDFF, 1.2)
        end
      end
    end
    -- Sibilant segments overlay
    for i=1,#analysis_cache.segments do
      local s = analysis_cache.segments[i]
      local x1 = x0 + ((math.max(s[1], vis_t0) - vis_t0) / vis_len) * W
      local x2 = x0 + ((math.min(s[2], vis_t1) - vis_t0) / vis_len) * W
      if x2 > x1 then
        -- Highlight sibilant segments with a red overlay
        reaper.ImGui_DrawList_AddRectFilled(dl, x1, wave_top, x2, wave_top+wave_h, 0xEF444455)
        
        -- Handle: Square button at start-bottom (Volume/Delete)
        local h_size = 12
        local h_x = x1 + 2
        local h_y = wave_top + wave_h - h_size - 2
        
        -- Logic for Volume Drag
        local is_handle_hovered = hovered and (mx >= h_x and mx <= h_x + h_size and my >= h_y and my <= h_y + h_size)
        
        if is_handle_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
            state.drag_seg_vol_index = i
            state.drag_vol_start_y = my
            state.drag_vol_start_val = s[3] or state.reduction_db 
        end
        
        local is_dragging_vol = (state.drag_seg_vol_index == i)
        
        if is_dragging_vol then
            if reaper.ImGui_IsMouseDown(ctx, 0) then
                local dy = state.drag_vol_start_y - my 
                local delta_db = dy / 5.0
                local new_db = state.drag_vol_start_val + delta_db
                if new_db < 0 then new_db = 0 end
                if new_db > 24 then new_db = 24 end 
                s[3] = new_db
                reaper.ImGui_SetTooltip(ctx, string.format("Reduction: %.1f dB", s[3]))
            else
                state.drag_seg_vol_index = -1
                state.last_change_time = reaper.time_precise()
                if state.live_edit then apply_cached_segments(state) end
            end
        end

        local h_col = (is_handle_hovered or is_dragging_vol) and 0xFFFFFFFF or 0xBFC7CDAA
        
        reaper.ImGui_DrawList_AddRectFilled(dl, h_x, h_y, h_x + h_size, h_y + h_size, h_col, 2.0)
        
        -- Icon: Vertical bars 
        local bar_x = h_x + 4
        local bar_w = 4
        local bar_h = 6
        local bar_y = h_y + 3
        reaper.ImGui_DrawList_AddRectFilled(dl, bar_x, bar_y, bar_x+bar_w, bar_y+bar_h, 0x2D3748FF)

        if is_handle_hovered and not is_dragging_vol then
           reaper.ImGui_SetTooltip(ctx, string.format("L-Drag: Adjust Reduction (Current: %.1f dB)\nR-Click: Delete Segment", s[3] or state.reduction_db))
           
           if reaper.ImGui_IsMouseClicked(ctx, 1) then
             table.remove(analysis_cache.segments, i)
             state.last_change_time = reaper.time_precise()
             if state.live_edit then apply_cached_segments(state) end
             break 
           end
        end
        
        if s[3] then
             local txt = string.format("%.1f", s[3])
             reaper.ImGui_DrawList_AddText(dl, h_x, h_y - 14, 0xFFFFFFCC, txt)
        end 

        -- UI: segment edge markers
        reaper.ImGui_DrawList_AddCircleFilled(dl, x1, mid, 3.0, 0xEF4444FF)
        reaper.ImGui_DrawList_AddCircleFilled(dl, x2, mid, 3.0, 0xEF4444FF)
        if hovered and my >= wave_top and my <= wave_top+wave_h and not is_handle_hovered and (not state.drag_seg_vol_index or state.drag_seg_vol_index < 0) then
          if state.drag_seg_index < 0 and state.drag_edge == 0 then
            if math.abs(mx - x1) <= 6 then
              -- Drag: start edge
              if reaper.ImGui_IsMouseDown(ctx, 0) then
                state.drag_seg_index = i; state.drag_edge = 1
              end
            elseif math.abs(mx - x2) <= 6 then
              if reaper.ImGui_IsMouseDown(ctx, 0) then
                state.drag_seg_index = i; state.drag_edge = 2
              end
            end
          end
          if state.drag_seg_index == i and state.drag_edge ~= 0 then
            local rel = (mx - x0) / W
            if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end
            local new_t = vis_t0 + rel * vis_len
            if state.snap_to_hop then
              local hop_sec = (state.hop_ms or 6) / 1000.0
              local rel_pos = (new_t - analysis_cache.item_pos) / hop_sec
              local snapped = math.floor(rel_pos + 0.5) * hop_sec + analysis_cache.item_pos
              new_t = snapped
            end
            if state.drag_edge == 1 then
              s[1] = math.min(new_t, s[2] - 0.001)
            else
              s[2] = math.max(new_t, s[1] + 0.001)
            end
            if reaper.ImGui_IsMouseReleased(ctx, 0) then
              state.drag_seg_index = -1; state.drag_edge = 0
              -- Live Edit: apply changes immediately on release
              if state.live_edit then apply_cached_segments(state) end
            end
          end
        end
      end
    end
    -- Threshold overlay: draw horizontal lines at min_level_db
    local thr_amp = db_to_amp(state.min_level_db)
    if thr_amp and thr_amp > 0 then
      local y_thr = thr_amp * (wave_h * wave_scale)
      local col = 0xBFC7CDFF
      -- Overlay: symmetric threshold lines
      reaper.ImGui_DrawList_AddLine(dl, x0, mid - y_thr, x0+W, mid - y_thr, col, 1.5)
      reaper.ImGui_DrawList_AddLine(dl, x0, mid + y_thr, x0+W, mid + y_thr, col, 1.5)
      -- Drag: threshold
      if hovered then
        local near_thr = (math.abs(my - (mid + y_thr)) <= 8) or (math.abs(my - (mid - y_thr)) <= 8)
        if not state.drag_threshold and near_thr and reaper.ImGui_IsMouseDown(ctx, 0) then
          state.drag_threshold = true
        end
        if state.drag_threshold then
          local dy = math.abs(my - mid)
          local new_amp = dy / (wave_h * wave_scale)
          if new_amp < 0 then new_amp = 0 end
          if new_amp > 1 then new_amp = 1 end
          local new_db = amp_to_db(new_amp)
          -- Clamp to UI range
          if new_db < -60 then new_db = -60 end
          if new_db > -20 then new_db = -20 end
          state.min_level_db = new_db
          if reaper.ImGui_IsMouseReleased(ctx, 0) then
            state.drag_threshold = false
          end
        end
      end
    end
    -- Playhead Sync
    if reaper.GetPlayState() & 1 == 1 then
      local play_pos = reaper.GetPlayPosition()
      if play_pos >= vis_t0 and play_pos <= vis_t1 then
        local play_x = x0 + ((play_pos - vis_t0) / vis_len) * W
        reaper.ImGui_DrawList_AddLine(dl, play_x, wave_top, play_x, wave_top+wave_h, 0xFFFFFFFF, 2.0)
      end
    end

    -- Edit Cursor Sync (Always visible)
    local edit_pos = reaper.GetCursorPosition()
    if edit_pos >= vis_t0 and edit_pos <= vis_t1 then
      local edit_x = x0 + ((edit_pos - vis_t0) / vis_len) * W
      -- Yellow line for Edit Cursor
      reaper.ImGui_DrawList_AddLine(dl, edit_x, wave_top, edit_x, wave_top+wave_h, 0xFFD700FF, 1.5)
    end

    -- Mouse Hover Guide
    if hovered and my >= wave_top and my <= wave_top+wave_h then
       local guide_x = mx
       if guide_x >= x0 and guide_x <= x0+W then
         reaper.ImGui_DrawList_AddLine(dl, guide_x, wave_top, guide_x, wave_top+wave_h, 0xFFFFFF44, 1.0)
       end
    end

    -- Safe segment creation: Ctrl/Alt + Right Drag
    if hovered then
      local ctrl_or_alt = mod_ctrl() or mod_alt()
      if ctrl_or_alt and reaper.ImGui_IsMouseClicked(ctx, 1) then
        local frac = (mx - x0) / W
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        state.new_seg_start_t = vis_t0 + frac * vis_len
        state.new_seg_end_t = state.new_seg_start_t
        state.new_seg_active = true
      end
      if state.new_seg_active then
        if reaper.ImGui_IsMouseDown(ctx, 1) then
          local frac = (mx - x0) / W
          if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
          state.new_seg_end_t = vis_t0 + frac * vis_len
          local x1 = x0 + ((math.max(state.new_seg_start_t, vis_t0) - vis_t0) / vis_len) * W
          local x2 = x0 + ((math.min(state.new_seg_end_t, vis_t1) - vis_t0) / vis_len) * W
          if x2 < x1 then x1, x2 = x2, x1 end
          reaper.ImGui_DrawList_AddRectFilled(dl, x1, wave_top, x2, wave_top+wave_h, 0xEF444455)
        else
          if reaper.ImGui_IsMouseReleased(ctx, 1) then
            local t1 = math.min(state.new_seg_start_t or vis_t0, state.new_seg_end_t or vis_t0)
            local t2 = math.max(state.new_seg_start_t or vis_t0, state.new_seg_end_t or vis_t0)
            if (t2 - t1) * 1000 >= (state.min_seg_ms or 25) then
              analysis_cache.segments[#analysis_cache.segments+1] = { t1, t2, state.reduction_db }
              state.last_change_time = reaper.time_precise()
              if state.live_edit then apply_cached_segments(state) end
            end
            state.new_seg_active = false
            state.new_seg_start_t = nil
            state.new_seg_end_t = nil
          end
        end
      end
    end

    -- Navigation: Left Click/Drag to seek (Scrub)
    if hovered and reaper.ImGui_IsMouseDown(ctx, 0) then
      local is_drag_action = (state.drag_seg_index and state.drag_seg_index >= 0) or state.drag_threshold
      -- Only seek if not dragging a segment or threshold
      if not is_drag_action then
         local cursor_frac = (mx - x0) / W
         if cursor_frac < 0 then cursor_frac = 0 elseif cursor_frac > 1 then cursor_frac = 1 end
         local seek_pos = vis_t0 + cursor_frac * vis_len
         reaper.SetEditCurPos(seek_pos, true, false)
      end
    end

    -- UI: caption
    reaper.ImGui_DrawList_AddText(dl, x0+8, y0+8, 0xF7FAFCFF, string.format('Len %.2fs | Segments %d | Red. %.1fdB | MinLvl %.1fdB', analysis_cache.item_len, #analysis_cache.segments, state.reduction_db, state.min_level_db))
  else
    local msg = 'Preview: select one item and press Analyze'
    if state.auto_analyze then
      msg = 'Preview: select one item, then tweak parameters (Auto-analyze on)'
    end
    reaper.ImGui_DrawList_AddText(dl, x0+8, y0+8, 0xF7FAFCFF, msg)
  end
end

-- UI: labeled sliders
local function slider_labeled_int(id, label, v, vmin, vmax, width, suffix)
  if width then reaper.ImGui_SetNextItemWidth(ctx, width) end
  local changed, nv = ImGui.SliderInt(ctx, '##'..id, v, vmin, vmax)
  local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
  local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
  local h = y2 - y1
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local fs = reaper.ImGui_GetFontSize(ctx)
  local ty = y1 + (h - fs) * 0.5
  -- Left label
  reaper.ImGui_DrawList_AddText(dl, x1 + 8, ty, 0xBFC7CDFF, label)
  -- Right value
  local val_str = tostring(nv) .. (suffix or '')
  local tw = select(1, reaper.ImGui_CalcTextSize(ctx, val_str))
  reaper.ImGui_DrawList_AddText(dl, x2 - tw - 8, ty, 0xF7FAFCFF, val_str)
  if changed and state then state.last_change_time = reaper.time_precise() end
  return changed, nv
end

local function slider_labeled_float(id, label, v, vmin, vmax, width, fmt, suffix)
  if width then reaper.ImGui_SetNextItemWidth(ctx, width) end
  local changed, nv = ImGui.SliderFloat(ctx, '##'..id, v, vmin, vmax)
  local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
  local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
  local h = y2 - y1
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local fs = reaper.ImGui_GetFontSize(ctx)
  local ty = y1 + (h - fs) * 0.5
  -- Left label
  reaper.ImGui_DrawList_AddText(dl, x1 + 8, ty, 0xBFC7CDFF, label)
  -- Right value
  local val_str
  if fmt then
    val_str = string.format(fmt, nv)
  else
    val_str = string.format('%.2f', nv)
  end
  val_str = val_str .. (suffix or '')
  local tw = select(1, reaper.ImGui_CalcTextSize(ctx, val_str))
  reaper.ImGui_DrawList_AddText(dl, x2 - tw - 8, ty, 0xF7FAFCFF, val_str)
  if changed and state then state.last_change_time = reaper.time_precise() end
  return changed, nv
end
-- UI: main loop
local function loop()
  -- Perf: step preview with a small time budget per frame
  if preview_job then preview_step(0.008) end
  if not preview_job and state.auto_analyze and state.last_change_time then
    local now = reaper.time_precise()
    if not state.last_auto_analyze or state.last_auto_analyze < state.last_change_time then
      if now - state.last_change_time > 0.35 then
        preview_start(state)
        state.last_auto_analyze = now
      end
    end
  end
  ImGui.SetNextWindowSize(ctx,800, 670, ImGui.Cond_Appearing())
  local color_count = apply_theme()
local visible, open = ImGui.Begin(ctx, 'Floop Ess Hunter', true, ImGui.WindowFlags_NoCollapse())
  if visible then
    -- Keyboard shortcuts: Space to Play/Stop
    if reaper.ImGui_IsWindowFocused(ctx) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
      reaper.Main_OnCommand(40044, 0) -- Transport: Play/Stop
    end

    -- UI: presets row above waveform
    reaper.ImGui_SeparatorText(ctx, 'PRESETS')
    ImGui.Text(ctx, 'Preset')
    ImGui.SameLine(ctx, nil, 8)
    local names = list_custom_presets()
    local preview
    if state.preset_index>0 then
      preview = PRESETS[state.preset_index].name
    elseif state.selected_custom_index>0 then
      preview = names[state.selected_custom_index] or 'None'
    else
      preview = 'None'
    end
    reaper.ImGui_SetNextItemWidth(ctx, 180)
    if ImGui.BeginCombo(ctx, '##combined_preset', preview) then
      reaper.ImGui_SeparatorText(ctx, 'Default presets')
      for i=1,#PRESETS do
        local sel = (state.preset_index == i)
        if ImGui.Selectable(ctx, PRESETS[i].name, sel) then
          state.preset_index = i
          state.selected_custom_index = 0
          apply_preset(PRESETS[i])
        end
      end
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_SeparatorText(ctx, 'User presets')
      if #names == 0 then
        ImGui.Text(ctx, 'No user presets')
      else
        for i=1,#names do
          local sel = (state.selected_custom_index == i)
          if ImGui.Selectable(ctx, names[i], sel) then
            state.selected_custom_index = i
            state.preset_index = 0
            load_custom_preset(names[i])
          end
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx, nil, 6)
    -- Use dynamic frame height to keep button text vertically centered
    local preset_btn_h = reaper.ImGui_GetFrameHeight(ctx)
    if ImGui.Button(ctx, 'Del', 46, preset_btn_h) then
      if state.selected_custom_index>0 then
        delete_custom_preset(names[state.selected_custom_index])
        state.selected_custom_index = 0
      end
    end
    ImGui.SameLine(ctx, nil, 10)
    ImGui.Text(ctx, 'Save as')
    ImGui.SameLine(ctx, nil, 6)
    reaper.ImGui_SetNextItemWidth(ctx, 140)
    local changed
    changed, state.custom_preset_name = ImGui.InputText(ctx, '##preset_name', state.custom_preset_name)
    ImGui.SameLine(ctx, nil, 6)
    if ImGui.Button(ctx, 'Save', 60, preset_btn_h) then
      local name = (state.custom_preset_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if name ~= '' then
        save_custom_preset(name)
        state.custom_preset_name = ''
        local nn = list_custom_presets()
        for i=1,#nn do if nn[i] == name then state.selected_custom_index = i break end end
      end
    end
  reaper.ImGui_Dummy(ctx, 0, 8)
    -- UI: waveform preview & actions
     reaper.ImGui_SeparatorText(ctx, 'WAVEFORM PREVIEW')
      
    local changed
    -- UI: analyze/progress inline
    if not preview_job then
      if ImGui.Button(ctx, 'Analyze (Preview)', 180, 28) then preview_start(state) end
    else
      ImGui.ProgressBar(ctx, preview_job.progress or 0.0, 180, 12, string.format('%d%%', math.floor((preview_job.progress or 0)*100+0.5)))
      ImGui.SameLine(ctx, nil, 8)
      if ImGui.Button(ctx, 'Cancel', 80, 28) then preview_cancel() end
    end
    ImGui.SameLine(ctx, nil, 12)
    do
      local apply_disabled = (not analysis_cache or not analysis_cache.segments or #analysis_cache.segments==0)
      if apply_disabled then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3A3A3A88)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3A3A3AAA)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x3A3A3ACC)
      end
      local clicked = ImGui.Button(ctx, 'Apply from preview', 180, 28)
      if apply_disabled then
        reaper.ImGui_PopStyleColor(ctx, 3)
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, 'Run Analyze (Preview) first')
        end
      else
        if clicked then apply_cached_segments(state) end
      end
    end
    ImGui.SameLine(ctx, nil, 16)
    changed, state.snap_to_hop = ImGui.Checkbox(ctx, 'Snap to frames', state.snap_to_hop)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Quantize segment edges to analysis frames (hop size)')
    end
    ImGui.SameLine(ctx, nil, 16)
    changed, state.live_edit = ImGui.Checkbox(ctx, 'Live Edit', state.live_edit)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Apply envelope changes immediately when releasing mouse drag')
    end
    ImGui.SameLine(ctx, nil, 16)
    changed, state.auto_analyze = ImGui.Checkbox(ctx, 'Auto-analyze', state.auto_analyze)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Automatically re-run analysis when parameters change')
    end
    reaper.ImGui_Dummy(ctx, 0, 4)
    draw_waveform_panel()
    
   
reaper.ImGui_Dummy(ctx, 0, 4)
    -- UI: volume reduction controls & actions
    reaper.ImGui_SetNextItemWidth(ctx, 160)
    changed, state.reduction_db = ImGui.SliderFloat(ctx, '##reduction_db', state.reduction_db, 0.0, 12.0)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Reduction in dB')
    end
    ImGui.SameLine(ctx, nil, 8)
    ImGui.Text(ctx, 'Volume reduction (dB)')
    ImGui.SameLine(ctx, nil, 12)
    reaper.ImGui_SetNextItemWidth(ctx, 150)
    local tm_preview = "Track Vol"
    if state.target_mode == 1 then tm_preview = "Track Pre-FX"
    elseif state.target_mode == 2 then tm_preview = "Take Vol" end
    
    if ImGui.BeginCombo(ctx, '##target_mode', tm_preview) then
      if ImGui.Selectable(ctx, 'Track Volume', state.target_mode == 0) then state.target_mode = 0 end
      if ImGui.Selectable(ctx, 'Track Pre-FX', state.target_mode == 1) then state.target_mode = 1 end
      if ImGui.Selectable(ctx, 'Take Volume', state.target_mode == 2) then state.target_mode = 2 end
      ImGui.EndCombo(ctx)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, 'Select which envelope to automate')
    end
    ImGui.SameLine(ctx, nil, 12)
    changed, state.overwrite = ImGui.Checkbox(ctx, 'Replace segments (non-cumulative)', state.overwrite)
    reaper.ImGui_Dummy(ctx, 0, 4)
    if ImGui.Button(ctx, 'Analyze and apply', 200, 30) then apply_on_selection() end
    ImGui.SameLine(ctx, nil, 12)
    if ImGui.Button(ctx, 'Clear segments on selection', 220, 30) then clear_segments_for_selection() end
    ImGui.SameLine(ctx, nil, 12)
    -- Help button inline next to Clear, with green accent style
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x14B8A6FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x0F766EFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x0D9488FF)
    if reaper.ImGui_Button(ctx, "Help", 80, 30) then
      reaper.ImGui_OpenPopup(ctx, "Help")
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_Dummy(ctx, 0, 18)
    -- Make collapsing header background fully transparent (no bg color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x00000000)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x00000000)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x00000000)
    -- Explicitly use the variant without a close button (p_open = nil)
local adv_open = reaper.ImGui_CollapsingHeader(ctx, 'ADVANCED SETTINGS', nil, 0)
    reaper.ImGui_PopStyleColor(ctx, 3)
    if adv_open then
   
    -- UI: three parameter columns, labeled sliders
    local availW = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local spacing = 16
    local colW = math.max(200, math.floor((availW - spacing*2) / 3))

    -- UI: Analysis column (Hz)
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Text(ctx, 'ANALYSIS')
    local changed
    changed, state.band_min = slider_labeled_int('band_min', 'Min Hz', state.band_min, 2500, 7000, colW, ' Hz')
    changed, state.band_max = slider_labeled_int('band_max', 'Max Hz', state.band_max, 6000, 12000, colW, ' Hz')
    changed, state.band_step = slider_labeled_int('band_step', 'Step Hz', state.band_step, 250, 2000, colW, ' Hz')
    changed, state.band_Q = slider_labeled_float('band_Q', 'Q Factor', state.band_Q, 2.0, 7.0, colW, '%.2f', '')
    reaper.ImGui_EndGroup(ctx)

    ImGui.SameLine(ctx, nil, spacing)

    -- UI: Detection column
    reaper.ImGui_BeginGroup(ctx)
  reaper.ImGui_Text(ctx, 'DETECTION')
    changed, state.window_ms   = slider_labeled_int('window_ms', 'Window', state.window_ms, 6, 20, colW, ' ms')
    changed, state.hop_ms      = slider_labeled_int('hop_ms', 'Hop', state.hop_ms, 3, 10, colW, ' ms')
    changed, state.min_level_db = slider_labeled_float('min_level_db', 'Min Level', state.min_level_db, -60.0, -20.0, colW, '%.1f', ' dB')
    changed, state.zcr_thresh   = slider_labeled_float('zcr_thresh', 'ZCR Threshold', state.zcr_thresh, 0.05, 0.30, colW, '%.2f', '')
    changed, state.delta_on     = slider_labeled_float('delta_on', 'Delta IN', state.delta_on, 0.00, 0.25, colW, '%.2f', '')
    changed, state.delta_off    = slider_labeled_float('delta_off', 'Delta OUT', state.delta_off, 0.00, 0.25, colW, '%.2f', '')
    reaper.ImGui_EndGroup(ctx)

    ImGui.SameLine(ctx, nil, spacing)

    -- UI: Segments column
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_Text(ctx, 'SEGMENTS')
    changed, state.min_seg_ms  = slider_labeled_int('min_seg_ms', 'Min Segment', state.min_seg_ms, 15, 60, colW, ' ms')
    changed, state.max_gap_ms  = slider_labeled_int('max_gap_ms', 'Max Gap', state.max_gap_ms, 10, 40, colW, ' ms')
    changed, state.pre_ramp_ms = slider_labeled_int('pre_ramp_ms', 'Pre Ramp', state.pre_ramp_ms, 0, 25, colW, ' ms')
    changed, state.post_ramp_ms = slider_labeled_int('post_ramp_ms', 'Post Ramp', state.post_ramp_ms, 0, 40, colW, ' ms')
    reaper.ImGui_EndGroup(ctx)

    end 

    if state.msg ~= '' then ImGui.TextWrapped(ctx, state.msg) end
    


    -- Help modal in main frame (dock focus fix)
    draw_help_modal()
    
    ImGui.End(ctx)
  end
  
  end_theme(color_count)
  if reaper and reaper.SetProjExtState then save_last_state() end
  if open then reaper.defer(loop) else ImGui.DestroyContext(ctx) end
end

-- Presets: built-in
PRESETS = {
  { name = 'Speech', values = { -- Preset
      band_min=3500, band_max=9500, band_step=1000, band_Q=4.0,
      window_ms=12, hop_ms=6, min_level_db=-45.0, zcr_thresh=0.12,
      delta_on=0.08, delta_off=0.05, min_seg_ms=25, max_gap_ms=18,
      reduction_db=4.0, pre_ramp_ms=8, post_ramp_ms=12,
    }
  },
  { name = 'Soft singing', values = { -- Preset
      band_min=3200, band_max=9000, band_step=1000, band_Q=3.8,
      window_ms=12, hop_ms=6, min_level_db=-48.0, zcr_thresh=0.10,
      delta_on=0.06, delta_off=0.04, min_seg_ms=28, max_gap_ms=20,
      reduction_db=3.0, pre_ramp_ms=10, post_ramp_ms=14,
    }
  },
  { name = 'Aggressive singing', values = { -- Preset
      band_min=3600, band_max=10000, band_step=1000, band_Q=4.2,
      window_ms=12, hop_ms=6, min_level_db=-42.0, zcr_thresh=0.13,
      delta_on=0.10, delta_off=0.06, min_seg_ms=22, max_gap_ms=16,
      reduction_db=6.0, pre_ramp_ms=6, post_ramp_ms=10,
    }
  },
}

apply_preset = function(p)
  local v = p.values
  -- Apply main parameters, without touching overwrite or msg
  state.band_min = v.band_min; state.band_max = v.band_max; state.band_step = v.band_step; state.band_Q = v.band_Q
  state.window_ms = v.window_ms; state.hop_ms = v.hop_ms
  state.min_level_db = v.min_level_db; state.zcr_thresh = v.zcr_thresh
  state.delta_on = v.delta_on; state.delta_off = v.delta_off
  state.min_seg_ms = v.min_seg_ms; state.max_gap_ms = v.max_gap_ms
  state.reduction_db = v.reduction_db; state.pre_ramp_ms = v.pre_ramp_ms; state.post_ramp_ms = v.post_ramp_ms
  state.msg = 'Preset applied: '..p.name
  state.last_change_time = reaper.time_precise()
end

loop()
