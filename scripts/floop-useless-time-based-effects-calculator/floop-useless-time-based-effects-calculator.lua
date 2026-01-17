-- Floop Useless Time-Based Effects Calculator
-- @description Floop Useless Time-Based Effects Calculator: time-based FX helper.
-- @version 1.1.0
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   v1.1 (2025-01-09)
--     + Live calculation (removed Calculate buttons).
--     + Added unit toggle (ms / seconds).
--     + Improved UI layout and theme.
-- @about
--   A utility script for REAPER to calculate time-based effect parameters.
--
--   Calculates compressor release times, reverb decay/predelay, and delay times
--   based on the project BPM or custom values.
--
--   Features:
--   * Real-time updates.
--   * Supports standard, dotted, and triplet notes.
--   * Reverb multipliers for Hall, Plate, and Room.
--
--    Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--
-- @provides
--   [main] floop-useless-time-based-effects-calculator.lua


-- Check if ReaImGui is installed
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("Error: ReaImGui is not installed!\nPlease install ReaImGui API package from ReaPack and try again.", "Error", 0)
    return
end

local r = reaper
local ctx = r.ImGui_CreateContext('Floop Useless Time-Based Effects Calculator')

-- Load custom font
local sans_serif_font = r.ImGui_CreateFont('sans-serif', 14)
r.ImGui_Attach(ctx, sans_serif_font)

-- Theme colors
local THEME_COLORS = {
    [r.ImGui_Col_WindowBg()]         = 0x262c30FF,
    [r.ImGui_Col_TitleBg()]          = 0xFF007AFF,
    [r.ImGui_Col_TitleBgActive()]    = 0xFF007AFF,
    [r.ImGui_Col_Button()]           = 0xe72280FF,
    [r.ImGui_Col_ButtonHovered()]    = 0xFF60B9FF,
    [r.ImGui_Col_ButtonActive()]     = 0xFF2089FF,
    [r.ImGui_Col_FrameBg()]          = 0xe72280FF,
    [r.ImGui_Col_FrameBgHovered()]   = 0xe72280FF,
    [r.ImGui_Col_FrameBgActive()]    = 0xFF2089FF,
    [r.ImGui_Col_CheckMark()]        = 0xFFFFFFFF,
    [r.ImGui_Col_Header()]           = 0xe72280FF,
    [r.ImGui_Col_HeaderHovered()]    = 0xFF505050,
    [r.ImGui_Col_HeaderActive()]     = 0xFF606060,
    [r.ImGui_Col_Separator()]        = 0xe72280FF,
    [r.ImGui_Col_Text()]             = 0xFFFFFFFF,
    [r.ImGui_Col_ResizeGrip()]       = 0xe72280FF,
    [r.ImGui_Col_ResizeGripHovered()] = 0xFF60B9FF,
    [r.ImGui_Col_ResizeGripActive()]  = 0xFF2089FF,
}

-- Style variables
local function apply_theme()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 8.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 20.0, 20.0)

    local color_count = 0
    for k, v in pairs(THEME_COLORS) do
        r.ImGui_PushStyleColor(ctx, k, v)
        color_count = color_count + 1
    end

    return color_count
end

local function end_theme(color_count)
    r.ImGui_PopStyleColor(ctx, color_count)
    r.ImGui_PopStyleVar(ctx, 3)
end

-- Check if the window is open
local is_open = true  

-- Constants
local MULTIPLIER_RELEASE_TIME = 4  -- Release time multiplier (4x beat)
local REVERB_MULTIPLIERS = {
    Hall = 2.5,   
    Plate = 1.5,  
    Room = 0.8    
}
local MS_CONVERSION_FACTOR = 1000
local DEFAULT_BPM = 120

-- State variables
local bpm = r.Master_GetTempo()
if bpm <= 0 then bpm = DEFAULT_BPM end

local note_values = {
    "1/1", "1/2", "1/4", "1/8", "1/16", "1/32", "1/64",  
    "1/1.", "1/2.", "1/4.", "1/8.", "1/16.", "1/32.",    
    "1/1t", "1/2t", "1/4t", "1/8t", "1/16t", "1/32t"     
}
local selected_note_idx = 3 -- Default 1/4
local show_ms = true
local show_seconds = true

-- Reverb parameters
local reverb_types = {"Hall", "Plate", "Room"}
local selected_reverb_type_idx = 1

-- Helpers
local function parse_note_value(note_value)
    local numerator, denominator, modifier = note_value:match("(%d+)/(%d+)([%.t]?)")
    numerator, denominator = tonumber(numerator), tonumber(denominator)
    local note_fraction = numerator / denominator

    if modifier == "." then
        note_fraction = note_fraction * 1.5  -- Dotted: 150%
    elseif modifier == "t" then
        note_fraction = note_fraction * (2 / 3)  -- Triplet: 2/3
    end

    return note_fraction
end

-- Core calculation: returns duration in MILLISECONDS
local function calculate_note_duration_ms(curr_bpm, note_value)
    if curr_bpm <= 0 then curr_bpm = DEFAULT_BPM end
    local beat_duration_sec = 60 / curr_bpm
    local note_fraction = parse_note_value(note_value)
    return beat_duration_sec * note_fraction * MS_CONVERSION_FACTOR
end

-- Format result string based on settings
local function format_result(ms_value)
    local parts = {}
    if show_seconds then
        table.insert(parts, string.format("%.3f s", ms_value / 1000))
    end
    if show_ms then
        table.insert(parts, string.format("%.2f ms", ms_value))
    end
    if #parts == 0 then return "Select a unit" end
    return table.concat(parts, " / ")
end

-- Main Loop
local function loop()
    local color_count = apply_theme()
    r.ImGui_PushFont(ctx, sans_serif_font, 15)
    r.ImGui_SetNextWindowSize(ctx, 420, 650, r.ImGui_Cond_FirstUseEver()) 
    r.ImGui_SetNextWindowSizeConstraints(ctx, 350, 500, math.huge, math.huge)

    local visible, open = r.ImGui_Begin(ctx, 'Floop Useless Time-Based Effects Calculator', true, r.ImGui_WindowFlags_NoCollapse())
    
    if visible then
        
        -- --- SETTINGS SECTION ---
        r.ImGui_Text(ctx, "SETTINGS")
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 5)

        -- BPM Input
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, 'BPM:')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 100)
        local rv, new_bpm = r.ImGui_InputDouble(ctx, '##BPM', bpm, 0, 0, "%.2f")
        if rv then
            if new_bpm < 1 then new_bpm = 1 end
            if new_bpm > 999 then new_bpm = 999 end
            bpm = new_bpm
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Get Project BPM') then
            local prj_bpm = r.Master_GetTempo()
            if prj_bpm > 0 then bpm = prj_bpm end
        end

        -- Note Value Combo
        r.ImGui_Dummy(ctx, 0, 5)
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, 'Note Value:')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, '##NoteValue', note_values[selected_note_idx]) then
            for i, note in ipairs(note_values) do
                local is_selected = (i == selected_note_idx)
                if r.ImGui_Selectable(ctx, note, is_selected) then
                    selected_note_idx = i
                end
                if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end

        -- Unit Checkboxes
        r.ImGui_Dummy(ctx, 0, 5)
        r.ImGui_Text(ctx, "Show:")
        r.ImGui_SameLine(ctx)
        local _, s_ms = r.ImGui_Checkbox(ctx, "ms", show_ms)
        if _ then show_ms = s_ms end
        r.ImGui_SameLine(ctx)
        local _, s_sec = r.ImGui_Checkbox(ctx, "seconds", show_seconds)
        if _ then show_seconds = s_sec end

        r.ImGui_Dummy(ctx, 0, 15)

        -- Pre-calculate base duration for current frame
        local base_ms = calculate_note_duration_ms(bpm, note_values[selected_note_idx])

        -- --- COMPRESSOR SECTION ---
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "COMPRESSOR (Release)")
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "Typical release time (4x Note):")
        
        local release_ms = base_ms * MULTIPLIER_RELEASE_TIME
        r.ImGui_Text(ctx, "Release: " .. format_result(release_ms))
        
        r.ImGui_Dummy(ctx, 0, 15)

        -- --- REVERB SECTION ---
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "REVERB")
        
        -- Reverb Type
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, 'Type:')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, '##ReverbType', reverb_types[selected_reverb_type_idx]) then
            for i, rev_type in ipairs(reverb_types) do
                local is_selected = (i == selected_reverb_type_idx)
                if r.ImGui_Selectable(ctx, rev_type, is_selected) then
                    selected_reverb_type_idx = i
                end
                if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end

        local rev_mult = REVERB_MULTIPLIERS[reverb_types[selected_reverb_type_idx]] or 1.0
        -- Reverb Decay (Base * 4 * ReverbMultiplier = Release * ReverbMultiplier)
        -- Note: Original script logic was: release_time * multiplier. 
        -- release_time was beat * 4. So decay is beat * 4 * multiplier.
        local decay_ms = release_ms * rev_mult
        
        -- Reverb Predelay (Base Note Duration)
        local predelay_ms = base_ms

        r.ImGui_Dummy(ctx, 0, 5)
        r.ImGui_Text(ctx, "Decay:    " .. format_result(decay_ms))
        r.ImGui_Text(ctx, "Predelay: " .. format_result(predelay_ms))

        r.ImGui_Dummy(ctx, 0, 15)

        -- --- DELAY SECTION ---
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "DELAY")
        
        local delay_ms = base_ms
        r.ImGui_Text(ctx, "Time:     " .. format_result(delay_ms))

        r.ImGui_End(ctx)
    end

    r.ImGui_PopFont(ctx)
    end_theme(color_count)
    
    if open then
        r.defer(loop)  
    else
        is_open = false 
    end
end

r.defer(loop)
