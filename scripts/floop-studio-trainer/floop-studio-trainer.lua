-- Floop Studio Trainer
-- @description Floop Studio Trainer: practice your instrument inside Reaper.
-- @version 1.2
-- @author Floop-s
-- @license GPL v-3.0
-- @changelog
--   v1.2 (2026-02-05)
--   - Fix: Solved crash with fractional Project BPM values.
-- @about
--    Floop Studio Trainer
--   © 2025-2026 Floop-s
--
--   Practice your instrument inside Reaper using either an audio track or the metronome.
--   Set repetitions and BPM increments to practice hands-free.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--   Keywords: practice, loop, trainer, bpm, metronome
-- @provides [main] floop-studio-trainer.lua



-- Ensure ReaImGui dependency is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is not installed!\nPlease install ReaImGui Api package from ReaPack and try again.", "Error", 0)
    return
end

local Trainer = {}

-- Initialize ReaImGui context
Trainer.ctx = reaper.ImGui_CreateContext("Loop Trainer")

Trainer.num_repeats = 10
Trainer.bpm_increment = 3
Trainer.running = false
Trainer.remaining_repeats = 10
Trainer.metronome_active = (reaper.GetToggleCommandState(40364) == 1)
Trainer.script_running = true
Trainer.project_bpm = reaper.Master_GetTempo()
Trainer.original_bpm = Trainer.project_bpm -- Store original BPM
Trainer.restore_on_close = true -- Default setting
Trainer.scale_factor = 1.0
Trainer.font_size = 14

-- Initialize UI font
Trainer.sans_serif = reaper.ImGui_CreateFont("sans-serif", Trainer.font_size)
reaper.ImGui_Attach(Trainer.ctx, Trainer.sans_serif)

-- Loop state variables
Trainer.repeat_count = 0

-- Updates font size based on scale factor
function Trainer.updateFont()
    local size = math.floor(16 * Trainer.scale_factor)
    Trainer.font_size = size
    -- Re-create font resource
    local new_font = reaper.ImGui_CreateFont("sans-serif", size)
    reaper.ImGui_Attach(Trainer.ctx, new_font)
    Trainer.sans_serif = new_font
end

-- Syncs internal state with REAPER metronome
function Trainer.updateMetronomeState()
    Trainer.metronome_active = (reaper.GetToggleCommandState(40364) == 1)
end

-- Toggles REAPER metronome
function Trainer.toggleMetronome()
    reaper.Main_OnCommand(40364, 0)  
    Trainer.updateMetronomeState()  
end

-- Applies target BPM to project
function Trainer.setProjectBPM()
    -- Clamp BPM range (10-960)
    if Trainer.project_bpm < 10 then Trainer.project_bpm = 10 end
    if Trainer.project_bpm > 960 then Trainer.project_bpm = 960 end
    reaper.SetCurrentBPM(0, Trainer.project_bpm, true)
end

-- Restores original BPM if enabled
function Trainer.cleanup()
    if Trainer.restore_on_close and Trainer.original_bpm then
        reaper.SetCurrentBPM(0, Trainer.original_bpm, false)
    end
end

reaper.atexit(Trainer.cleanup)

function Trainer.closeScript()
    Trainer.running = false  
    Trainer.script_running = false  
end

-- Validates loop selection and transport state
function Trainer.checkConditions()
    local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if loop_start == loop_end then
        reaper.ShowMessageBox("No selection in Time Selection!\nPlease select an area of the timeline before running the script.", "Error", 0)
        return false
    end

    local repeat_state = reaper.GetToggleCommandState(1068)  
    if repeat_state ~= 1 then
        reaper.ShowMessageBox("The Repeat button is not enabled!\nEnable the loop in the Transport before running the script.", "Error", 0)
        return false
    end


    
    return true 
end

-- Initializes training session
function Trainer.startLoop()
    if Trainer.running then return end
    if not Trainer.checkConditions() then return end  
    Trainer.running = true
    Trainer.repeat_count = 0
    local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    reaper.SetEditCurPos(loop_start, true, false)
    reaper.CSurf_OnPlay()

    local last_position = reaper.GetPlayPosition()

    local function checkLoop()
        if not Trainer.running then return end
        if reaper.GetPlayState() == 0 then Trainer.stopScript() return end

        local current_position = reaper.GetPlayPosition()
        local l_start, l_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local loop_len = l_end - l_start

        -- Detect loop restart. Threshold prevents false positives during seek
        if current_position < last_position then
             local jump_dist = last_position - current_position
             if jump_dist > (loop_len * 0.2) then -- Threshold: 20% of loop length
                Trainer.repeat_count = Trainer.repeat_count + 1
                Trainer.remaining_repeats = Trainer.num_repeats - Trainer.repeat_count  
                
                if Trainer.repeat_count >= Trainer.num_repeats then
                    Trainer.repeat_count = 0
                    Trainer.remaining_repeats = Trainer.num_repeats  
                    local bpm = reaper.Master_GetTempo()
                    
                    -- Clamp new BPM to REAPER limit
                    local new_bpm = bpm + Trainer.bpm_increment
                    if new_bpm > 960 then new_bpm = 960 end 
                    
                    reaper.SetCurrentBPM(0, new_bpm, true)
                    Trainer.project_bpm = new_bpm -- Update UI variable
                    
                    -- Update tracking position to current cursor
                    last_position = reaper.GetPlayPosition()
                    
                    -- Defer checks to allow audio engine/cursor update
                    local wait_frames = 0
                    local function safeWait()
                        if not Trainer.running then return end
                        wait_frames = wait_frames + 1
                        if wait_frames > 5 then -- Debounce period (~150ms)
                             last_position = reaper.GetPlayPosition()
                             reaper.defer(checkLoop)
                        else
                             reaper.defer(safeWait)
                        end
                    end
                    reaper.defer(safeWait)
                    return
                end
            end
        end

        last_position = current_position
        reaper.defer(checkLoop)
    end

    reaper.defer(checkLoop)
end

-- Stops playback and training session
function Trainer.stopScript()
    Trainer.running = false
    reaper.CSurf_OnStop()
end

-- Applies ImGui style/theme
function Trainer.applyTheme()
    local s = Trainer.scale_factor or 1.0
    reaper.ImGui_PushStyleVar(Trainer.ctx, reaper.ImGui_StyleVar_WindowRounding(), 9 * s)
    reaper.ImGui_PushStyleVar(Trainer.ctx, reaper.ImGui_StyleVar_FrameRounding(), 12 * s)
    reaper.ImGui_PushStyleVar(Trainer.ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1 * s)
    reaper.ImGui_PushStyleVar(Trainer.ctx, reaper.ImGui_StyleVar_GrabRounding(), 4 * s)
    reaper.ImGui_PushStyleVar(Trainer.ctx, reaper.ImGui_StyleVar_WindowPadding(), 20 * s, 20 * s)
    reaper.ImGui_PushStyleVar(Trainer.ctx, reaper.ImGui_StyleVar_WindowMinSize(), 360 * s, 420 * s)

    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_WindowBg(), 0x1E1E1EFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_Border(), 0x1E1E1EFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_TitleBg(), 0x1A686BFF) 
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_TitleBgActive(), 0x1A686BFF) 
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_FrameBg(), 0x1A686BFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_FrameBgHovered(), 0x32878AFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_FrameBgActive(), 0x135E61FF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_SliderGrab(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_SliderGrabActive(), 0xC6CFDAFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_Button(), 0x1A686BFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_ButtonHovered(), 0x32878AFF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_ButtonActive(), 0x135E61FF)
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_ResizeGrip(), 0x135E61FF)  
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_ResizeGripHovered(), 0x32878AFF) 
    reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_ResizeGripActive(), 0x135E61FF) 
end

-- Main GUI render loop
function Trainer.loopTrainerGUI()
    if not Trainer.script_running then return end
    
    Trainer.updateMetronomeState()  

    Trainer.applyTheme()
    reaper.ImGui_PushFont(Trainer.ctx, Trainer.sans_serif, Trainer.font_size)
    
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
        
    local visible, open = reaper.ImGui_Begin(Trainer.ctx, "Floop Studio - Trainer", true, window_flags)

    if visible then
        if reaper.ImGui_IsKeyPressed(Trainer.ctx, reaper.ImGui_Key_Space()) then
            if Trainer.running then
                Trainer.stopScript()
            else
                Trainer.startLoop()
            end
        end

        local window_width = reaper.ImGui_GetWindowWidth(Trainer.ctx)
        
        reaper.ImGui_Text(Trainer.ctx, "Settings")
        reaper.ImGui_SameLine(Trainer.ctx)

        -- Render Help tooltip
        local help_text = "(?)"
        local help_w = reaper.ImGui_CalcTextSize(Trainer.ctx, help_text)
        reaper.ImGui_SetCursorPosX(Trainer.ctx, window_width - help_w - (15 * Trainer.scale_factor))
        reaper.ImGui_TextDisabled(Trainer.ctx, help_text)
        
        if reaper.ImGui_IsItemHovered(Trainer.ctx) then
            reaper.ImGui_BeginTooltip(Trainer.ctx)
            reaper.ImGui_PushTextWrapPos(Trainer.ctx, 300 * Trainer.scale_factor)
            reaper.ImGui_Text(Trainer.ctx, "IMPORTANT:\nTo prevent synchronization issues, please ensure that the Project Timebase or the Track Timebase (containing the audio) is set to 'Beats (position, length, rate)'.")
            reaper.ImGui_PopTextWrapPos(Trainer.ctx)
            reaper.ImGui_EndTooltip(Trainer.ctx)
        end

        reaper.ImGui_Separator(Trainer.ctx)
        reaper.ImGui_Dummy(Trainer.ctx, 0, 10 * Trainer.scale_factor)
        
        -- Render Control Panel
        reaper.ImGui_Text(Trainer.ctx, "Number of repetitions")
        reaper.ImGui_SetNextItemWidth(Trainer.ctx, window_width - 40)
        local repeats_changed
        repeats_changed, Trainer.num_repeats = reaper.ImGui_SliderInt(Trainer.ctx, "##num_repeats", Trainer.num_repeats, 1, 30)
        -- Validate repetitions range
        if Trainer.num_repeats < 1 then Trainer.num_repeats = 1 end
        if Trainer.num_repeats > 100 then Trainer.num_repeats = 100 end
        
        Trainer.remaining_repeats = Trainer.num_repeats - Trainer.repeat_count

        reaper.ImGui_Spacing(Trainer.ctx)
        reaper.ImGui_Text(Trainer.ctx, "Increase BPM by")
        reaper.ImGui_SetNextItemWidth(Trainer.ctx, window_width - 40)
        _, Trainer.bpm_increment = reaper.ImGui_SliderInt(Trainer.ctx, "##bpm_increment", Trainer.bpm_increment, 1, 20)
        -- Validate increment range
        if Trainer.bpm_increment < 1 then Trainer.bpm_increment = 1 end
        if Trainer.bpm_increment > 50 then Trainer.bpm_increment = 50 end

        reaper.ImGui_Spacing(Trainer.ctx)
        reaper.ImGui_PushStyleColor(Trainer.ctx, reaper.ImGui_Col_CheckMark(), 0xFFFFFFFF)
        _, Trainer.restore_on_close = reaper.ImGui_Checkbox(Trainer.ctx, "Restore original BPM on close", Trainer.restore_on_close)
        reaper.ImGui_PopStyleColor(Trainer.ctx)

        reaper.ImGui_Spacing(Trainer.ctx)
        
      reaper.ImGui_Text(Trainer.ctx, "Project BPM: press Enter to apply the new BPM.")
      reaper.ImGui_SetNextItemWidth(Trainer.ctx, window_width - 40)
      
      -- Sync UI BPM with Project BPM when idle
      if not reaper.ImGui_IsItemActive(Trainer.ctx) and not Trainer.running then
          Trainer.project_bpm = reaper.Master_GetTempo()
      end

      local changed
      changed, Trainer.project_bpm = reaper.ImGui_InputDouble(Trainer.ctx, "##project_bpm", Trainer.project_bpm, 0, 0, "%.2f")
      if changed or reaper.ImGui_IsItemDeactivatedAfterEdit(Trainer.ctx) then
          Trainer.setProjectBPM()
      end

        reaper.ImGui_Dummy(Trainer.ctx, 0, 5)
        reaper.ImGui_Separator(Trainer.ctx)
        reaper.ImGui_Dummy(Trainer.ctx, 0, 5)

        -- Render Metronome toggle
        local metronome_text = Trainer.metronome_active and "Metronome: ON" or "Metronome: OFF"
        
        local available_width = reaper.ImGui_GetContentRegionAvail(Trainer.ctx)
        local metronome_btn_width = 180 * Trainer.scale_factor
        if metronome_btn_width > available_width then metronome_btn_width = available_width end
        
        reaper.ImGui_SetCursorPosX(Trainer.ctx, (window_width - metronome_btn_width) / 2)
        if reaper.ImGui_Button(Trainer.ctx, metronome_text, metronome_btn_width, 35 * Trainer.scale_factor) then
            Trainer.toggleMetronome()
        end
        reaper.ImGui_Dummy(Trainer.ctx, 0, 5 * Trainer.scale_factor) 
        reaper.ImGui_Text(Trainer.ctx, "Repetitions remaining: " .. Trainer.remaining_repeats)
        reaper.ImGui_Dummy(Trainer.ctx, 0, 10 * Trainer.scale_factor)

        -- Render Transport controls        
        local spacing = 20 * Trainer.scale_factor
        local button_height = 30 * Trainer.scale_factor
        
        -- Dynamic button sizing
        local total_spacing = spacing * 2
        local button_width = (available_width - total_spacing) / 3
        
        -- Enforce max button width
        local max_btn_width = 120 * Trainer.scale_factor
        if button_width > max_btn_width then 
             button_width = max_btn_width 
            
             local total_width = (button_width * 3) + total_spacing
             reaper.ImGui_SetCursorPosX(Trainer.ctx, (window_width - total_width) / 2)
        end

        reaper.ImGui_BeginDisabled(Trainer.ctx, Trainer.running)
        if reaper.ImGui_Button(Trainer.ctx, "Start", button_width, button_height) then
            Trainer.startLoop()
        end
        reaper.ImGui_EndDisabled(Trainer.ctx)
        reaper.ImGui_SameLine(Trainer.ctx, nil, spacing)
        if reaper.ImGui_Button(Trainer.ctx, "Stop", button_width, button_height) then
            Trainer.stopScript()
        end
        reaper.ImGui_SameLine(Trainer.ctx, nil, spacing)
        if reaper.ImGui_Button(Trainer.ctx, "Close", button_width, button_height) then
            Trainer.closeScript()
        end
    end

    -- Cleanup ImGui frame
    reaper.ImGui_End(Trainer.ctx)
    reaper.ImGui_PopFont(Trainer.ctx)
    reaper.ImGui_PopStyleVar(Trainer.ctx, 6)
    reaper.ImGui_PopStyleColor(Trainer.ctx, 15)

    if not open then
        Trainer.closeScript()
        return
    end

    if Trainer.script_running then
        reaper.defer(Trainer.loopTrainerGUI)
    end
end

-- Entry point
reaper.defer(Trainer.loopTrainerGUI)
