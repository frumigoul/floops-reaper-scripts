-- Floop Scratchpad - Per-track notes system for REAPER.
-- @description Floop Scratchpad: per-track notes system
-- @version 1.2.4
-- @author Floop-s
-- @license GPL-3.0
-- @changelog
--   + Added: Numeric JSFX font size input next to the Font Scale slider (14–40 px).
--   + Improved: Increased JSFX font size range and clamping for large projects and high-DPI layouts.
--   + Fixed: JSFX reader now updates immediately when confirming font size changes from numeric input.
-- @about
--   Per-track notes system for REAPER.
--
--   Allows writing, viewing, and managing notes for each track.
--   Notes are automatically saved and recalled when switching tracks.
--
--   Requires:
--     - ReaImGui (ReaTeam Extensions repository), v0.10.2 or newer
--     - SWS/S&M extension
--
--   Dynamically generates a companion JSFX (FloopNoteReader)
--   to display notes in the Track Control Panel.
--
--   Keywords: notes, track, text, workflow.
-- @provides
--   [main] floop-scratchpad.lua
--   [main] floop-startup-refresh.lua


local reaper = reaper

-- ReaImGui availability check
if not reaper or not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui API not found!\nPlease install 'ReaImGui' via ReaPack and restart REAPER.", "Error", 0)
  return
end

-- SWS availability check (project startup action)
if not reaper.NF_SetProjectStartupAction then
  reaper.ShowMessageBox("SWS/S&M extension not installed.\nThe project startup action for headless refresh cannot be set automatically.\nInstall SWS to enable auto-refresh on project open.", "Floop Scratchpad", 0)
end

local ctx = reaper.ImGui_CreateContext('Floop Scratchpad')

-- Safety check: ensure the ImGui context was created
if not ctx then
  reaper.ShowMessageBox("Failed to create ImGui context.\nPlease verify ReaImGui installation and compatibility.", "Error", 0)
  return
end

-- Load custom font
local sans_serif_font = reaper.ImGui_CreateFont('sans-serif', 12)
reaper.ImGui_Attach(ctx, sans_serif_font)

-- Theme colors
local THEME_COLORS = {
    [reaper.ImGui_Col_WindowBg()]         = 0x1e2328FF,
    [reaper.ImGui_Col_TitleBg()]          = 0xe99854FF,
    [reaper.ImGui_Col_TitleBgActive()]    = 0xd77624FF,
    [reaper.ImGui_Col_Button()]           = 0xd77624FF,
    [reaper.ImGui_Col_ButtonHovered()]    = 0xff7602FF,
    [reaper.ImGui_Col_ButtonActive()]     = 0xcb7933FF,
    [reaper.ImGui_Col_FrameBg()]          = 0xd77624FF,
    [reaper.ImGui_Col_FrameBgHovered()]   = 0xff7602FF,
    [reaper.ImGui_Col_FrameBgActive()]    = 0xff7602FF,
    [reaper.ImGui_Col_SliderGrab()]       = 0xFFFFFFFF,
    [reaper.ImGui_Col_SliderGrabActive()] = 0xFFFFFFFF,
    [reaper.ImGui_Col_CheckMark()]        = 0x68d391FF,
    [reaper.ImGui_Col_Header()]           = 0x2d3748FF,
    [reaper.ImGui_Col_HeaderHovered()]    = 0xd77624FF,
    [reaper.ImGui_Col_HeaderActive()]     = 0x718096FF,
    [reaper.ImGui_Col_Separator()]        = 0xd77624FF,
    [reaper.ImGui_Col_Text()]             = 0xf7fafcFF,
    [reaper.ImGui_Col_TextDisabled()]     = 0x585858FF,
    [reaper.ImGui_Col_ResizeGrip()]       = 0xd77624FF,
    [reaper.ImGui_Col_ResizeGripHovered()] = 0xff7602FF,
    [reaper.ImGui_Col_ResizeGripActive()]  = 0xff7602FF,
}

-- Apply theme function
local function apply_theme()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 16.0, 16.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8.0, 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8.0, 8.0)

    if reaper.ImGui_StyleVar_GrabRounding then
      reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 6.0)
    end

    local color_count = 0
    for k, v in pairs(THEME_COLORS) do
        reaper.ImGui_PushStyleColor(ctx, k, v)
        color_count = color_count + 1
    end

    return color_count
end

-- End theme function
local function end_theme(color_count)
    reaper.ImGui_PopStyleColor(ctx, color_count)
    -- Pop 5 standard vars plus optional GrabRounding
    local to_pop = 5 + (reaper.ImGui_StyleVar_GrabRounding and 1 or 0)
    reaper.ImGui_PopStyleVar(ctx, to_pop)
end

-- Global state
local noteText = ''
local currentTrack = nil
local statusMsg = '✅ System ready'
local lastTrackGUID = nil
local showHelpModal = false  -- Controls help modal visibility
local isDirty = false
local jsfxFontScale = 1.30   -- Default JSFX font scale
local jsfxForceLarge = false -- Optional: keep larger font even in compact MCP
local showConfirmClear = false
local notesCache = nil
local notesCachePath = nil
local lastProjectPath = nil -- Tracks project save / Save As transitions
local lastProjectPtr = nil  -- Tracks project tab switches

-- Console debug helper
local function log(msg)
  -- if reaper then
  --   reaper.ShowConsoleMsg("[FloopScratchpad] " .. tostring(msg) .. "\n")
  -- end
end

-- Compatibility wrapper for slider-like float controls across ReaImGui versions
local function SliderFloatCompat(label, value, min, max)
  min = min or 0.0
  max = max or 1.0
  if reaper.ImGui_SliderFloat then
    return reaper.ImGui_SliderFloat(ctx, label, value, min, max)
  elseif reaper.ImGui_SliderDouble then
    return reaper.ImGui_SliderDouble(ctx, label, value, min, max)
  elseif reaper.ImGui_DragFloat then
    return reaper.ImGui_DragFloat(ctx, label, value, 0.01, min, max)
  elseif reaper.ImGui_DragDouble then
    return reaper.ImGui_DragDouble(ctx, label, value, 0.01, min, max)
  else
    -- Fallback: input number
    if reaper.ImGui_InputDouble then
      local changed, newVal = reaper.ImGui_InputDouble(ctx, label, value)
      return changed, newVal
    else
      local changed, str = reaper.ImGui_InputText(ctx, label, tostring(value))
      local newVal = value
      if changed then
        local parsed = tonumber(str)
        if parsed then newVal = parsed end
      end
      return changed, newVal
    end
  end
end

-- Functions to handle paths
local function getResourcePath()
  local path = reaper.GetResourcePath()
  return path
end

-- Forward declarations for Lua scoping
local ensureDirectoryExists, readFile, writeFile, getProjectTrackGUIDSet, filterNotesByGUIDSet, isDirWritable

-- joinPath used for cross-platform path joining
local function joinPath(...)
  local parts = {...}
  local sep = package.config:sub(1,1)
  return table.concat(parts, sep)
end

local function getSystemHome()
  if package.config:sub(1,1) == "\\" then
    return os.getenv("USERPROFILE") or os.getenv("HOME") or ""
  else
    return os.getenv("HOME") or ""
  end
end

local function getProjectPath()
  local projectPath = reaper.GetProjectPath("")
  if projectPath == "" then
    -- Use REAPER Media for unsaved projects
    local docs = joinPath(getSystemHome(), "Documents")
    return joinPath(docs, "REAPER Media")
  end
  return projectPath
end

local function getNotesFilePath()
  local projectPath = getProjectPath()

  local r1, r2 = reaper.GetProjectName(0, "")
  local projectName = (type(r2) == "string" and r2 ~= "" and r2)
                      or (type(r1) == "string" and r1 or "")
  
  if projectName == "" then
    projectName = "unsaved_project"
  else
    projectName = projectName:gsub("%.rpp$", "")
  end
  local candidate = joinPath(projectPath, projectName .. "_notes.txt")
  local writable = select(1, isDirWritable(candidate))
  if writable then
    
    return candidate
  else
    local fallbackDir = joinPath(getResourcePath(), "FloopNotes")
    reaper.RecursiveCreateDirectory(fallbackDir, 0)
    local fallbackPath = joinPath(fallbackDir, projectName .. "_notes.txt")
    log("Path candidate not writable: " .. candidate .. ". Using fallback: " .. fallbackPath)
    return fallbackPath
  end
end

local function ensureDirectoryExists(filePath)
  local dir = filePath:match("^(.*)[/\\][^/\\]+$")
  if dir and dir ~= "" then
    local success = reaper.RecursiveCreateDirectory(dir, 0)
    return success
  end
  return false
end

local function readFile(filePath)
  local file, err = io.open(filePath, "r")
  if file then
    local content = file:read("*all")
    file:close()
    return content
  else
    return nil, err
  end
end

local function writeFile(filePath, content)
  ensureDirectoryExists(filePath)
  local file, err = io.open(filePath, "w")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

local function appendFile(filePath, content)
  ensureDirectoryExists(filePath)
  local file, err = io.open(filePath, "a")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

local function getLogFilePath()
  local projectPath = getProjectPath()
  return joinPath(projectPath, "FloopScratchpad.log")
end

local function logError(msg)
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local line = "[" .. ts .. "] " .. tostring(msg) .. "\n"
  appendFile(getLogFilePath(), line)
end

function isDirWritable(filePath)
  local dir = filePath:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == "" then return false, "Invalid directory" end
  local sep = package.config:sub(1,1)
  local testPath = dir .. sep .. ".floop_writable_test_" .. tostring(math.random(1000000))
  local f, err = io.open(testPath, "w")
  if not f then return false, err end
  f:write("ok")
  f:close()
  os.remove(testPath)
  return true
end

local function loadNotesFromFile()
  local filePath = getNotesFilePath()
  if notesCache and notesCachePath == filePath then
    return notesCache
  end
  local content, err = readFile(filePath)
  
  -- If file exists and has actual content, use it
  if content and content:match("%S") then
    log("Loaded notes from: " .. filePath)
    notesCache = content
    notesCachePath = filePath
    return content
  end
  
  -- Check whether notes must be migrated from the unsaved location
  local projectPath = reaper.GetProjectPath("")
  if projectPath ~= "" then
    -- Project is saved: migrate notes from the unsaved location if present
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local unsavedPath = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local unsavedContent = readFile(unsavedPath)
    
    if unsavedContent and unsavedContent:match("%S") then
      log("Migrating notes from unsaved location: " .. unsavedPath .. " to " .. filePath)
      -- Preserve all notes from the unsaved project and migrate them to the project location
      local success, err = writeFile(filePath, unsavedContent)
      if success then
        log("Migration successful.")
        -- Backup unsaved notes with timestamp before deletion
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(reaperMedia, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        writeFile(backup, unsavedContent)
        os.remove(unsavedPath)
        notesCache = unsavedContent
        notesCachePath = filePath
        return unsavedContent
      else
        logError("Migration failed: " .. tostring(err))
      end
    end
    
    -- Legacy fallback: older versions saved unsaved notes to Desktop on first save
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacyPath = joinPath(desktop, "unsaved_project_notes.txt")
    local legacyContent = readFile(legacyPath)
    if legacyContent and legacyContent:match("%S") then
      log("Migrating legacy notes from: " .. legacyPath)
      -- Preserve all legacy notes and migrate them to the project location
      local success, err = writeFile(filePath, legacyContent)
      if success then
        log("Legacy migration successful.")
        -- Backup legacy unsaved notes with timestamp before deletion
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(desktop, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        writeFile(backup, legacyContent)
        os.remove(legacyPath)
        notesCache = legacyContent
        notesCachePath = filePath
        return legacyContent
      end
    end
    
    -- Ensure project notes file exists, even if there is nothing to migrate
    if not content then
      log("No existing notes found. Creating empty file at: " .. filePath)
      writeFile(filePath, "")
      notesCache = ""
      notesCachePath = filePath
      return ""
    end
    notesCache = content or ""
    notesCachePath = filePath
    return content or ""
  else
    -- Project not saved yet: use fallback locations
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local fallbackPath = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local fallbackContent = readFile(fallbackPath)
    if fallbackContent and fallbackContent:match("%S") then
      log("Loaded unsaved notes from: " .. fallbackPath)
      notesCache = fallbackContent
      notesCachePath = filePath
      return fallbackContent
    end
    
    -- Legacy fallback: older versions stored unsaved notes on Desktop
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacyPath = joinPath(desktop, "unsaved_project_notes.txt")
    local legacyContent = readFile(legacyPath)
    if legacyContent and legacyContent:match("%S") then
      log("Loaded legacy unsaved notes from: " .. legacyPath)
      notesCache = legacyContent
      notesCachePath = filePath
      return legacyContent
    end
  end
  
  notesCache = ""
  notesCachePath = filePath
  return ""
end


local function saveNotesToFile(notes)
  local filePath = getNotesFilePath()
  local oldContent = select(1, readFile(filePath))
  local writable, werr = isDirWritable(filePath)
  if not writable then
    logError("Write permission error for " .. filePath .. ": " .. tostring(werr))
    return false, werr or "Permission denied"
  end
  local success, err = writeFile(filePath, notes)
  if success then
    log("Saved notes to: " .. filePath)
    notesCache = notes
    notesCachePath = filePath
    return true, filePath
  else
    logError("Failed to write notes to " .. filePath .. ": " .. tostring(err))
    if oldContent ~= nil then
      local rbOk = select(1, writeFile(filePath, oldContent))
      if not rbOk then
        logError("Rollback failed for " .. filePath)
      end
    end
    return false, err or "Error writing file"
  end
end

-- Manage tracks
local function isValidTrack(track)
  if not track then return false end
  if reaper.ValidatePtr2 then
    return reaper.ValidatePtr2(0, track, "MediaTrack*")
  end
  return true
end

local function getTrackGUID(track)
  if not isValidTrack(track) then
    return nil
  end
  return reaper.GetTrackGUID(track)
end

local function getTrackName(track)
  if not isValidTrack(track) then
    return "Unknown Track"
  end
  local _, name = reaper.GetTrackName(track)
  return name
end

local function getSelectedTrack()
  local trackCount = reaper.CountSelectedTracks(0)
  if trackCount > 0 then
    return reaper.GetSelectedTrack(0, 0)
  else
    return nil
  end
end

-- Note helpers
local function getNoteForTrack(trackGUID)
  if not trackGUID then return "" end
  local allNotes = loadNotesFromFile() or ""
  if allNotes == "" then return "" end

  -- Normalize separators and ensure trailing delimiter
  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end

  for block in padded:gmatch("(.-)\n=====\n") do
    -- Trim whitespace from block to ensure it's valid
    if block:match("%S") then
      local guid = block:match("GUID:%s*(%S+)")
      if guid == trackGUID then
        local contentPos = block:find("Content:")
        if contentPos then
          local content = block:sub(contentPos + #("Content:"))
          content = content:gsub("^%s*", "")
          return content
        end
        return ""
      end
    end
  end
  return ""
end

local function getFontScaleForTrack(trackGUID)
  if not trackGUID then return 1.30 end
  local allNotes = loadNotesFromFile() or ""
  if allNotes == "" then return 1.30 end

  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end

  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local guid = block:match("GUID:%s*(%S+)")
      if guid == trackGUID then
        local fs = block:match("FontScale:%s*([%d%.]+)")
        local n = tonumber(fs)
        if n then return n end
        break
      end
    end
  end
  return 1.30
end

local function saveNoteForTrack(trackGUID, noteContent)
  if not trackGUID then return false, "Missing track GUID" end
  local allNotes = loadNotesFromFile() or ""

  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end

  local blocks = {}
  
  for block in padded:gmatch("(.-)\n=====\n") do
    -- Only keep valid non-empty blocks
    if block:match("%S") then
      local guid = block:match("GUID:%s*(%S+)")
      -- Keep block if it has a GUID and it's NOT the one we are saving now
      if guid and guid ~= trackGUID then
        table.insert(blocks, block)
      end
    end
  end

  -- Add the new/updated note block
  -- Ensure consistent format
  local newNote = "GUID: " .. trackGUID .. "\nFontScale: " .. (jsfxFontScale or 1.30) .. "\nContent: " .. (noteContent or "")
  table.insert(blocks, newNote)

  -- Reconstruct file content
  local newAll = table.concat(blocks, "\n=====\n") .. "\n=====\n"
  
  local success, info = saveNotesToFile(newAll)
  return success, info
end

-- Dynamic JSFX creation
local JSFX_FILE_NAME = 'FloopNoteReader.jsfx'

local function createDynamicJSFXContent(trackGUID, noteContent, fontScale, forceLarge)
  -- Escape special characters
  local safeNote = noteContent:gsub('"', '\\"'):gsub('\n', '\\n')
  local safeGUID = trackGUID or "No Track"
  local scale = tonumber(fontScale) or jsfxFontScale or 1.0
  local forceBig = (forceLarge and 1 or 0)
  
  if not noteContent or noteContent == "" then
    safeNote = "No notes found - Please add a note first"
  end
  
  -- Limit note length to 200 characters
  if #safeNote > 200 then
    safeNote = safeNote:sub(1, 200) .. "..."
  end
  
  local jsfxContent = string.format([[desc:Floop Note Reader

@init
note_text = "%s";
track_guid = "%s";
font_scale = %.2f;
force_big = %d;

// Compact rendering settings for TCP/MCP embedded UI
bg_r = 0.93; bg_g = 0.95; bg_b = 0.65; // background
txt_r = 0.31; txt_g = 0.31; txt_b = 0.30; // note text color
dim_r = 0.6; dim_g = 0.6; dim_b = 0.6; // dimmed text
hdr_r = 0.38; hdr_g = 0.38; hdr_b = 0.37; // header color

@gfx 400 140
// Background
gfx_r = bg_r; gfx_g = bg_g; gfx_b = bg_b;
gfx_rect(0,0,gfx_w,gfx_h);

pad = 6;
area_w = max(10, gfx_w - pad*2);
area_h = max(10, gfx_h - pad*2);

// Decide compact mode based on available space
compact = (gfx_w < 260) || (gfx_h < 90);

// Skip header; draw note content directly
gfx_x = pad; gfx_y = pad;

// Dynamic font size based on width/height
  base_sz = (compact ? 14 : 18) * font_scale;
  sz = min(max(base_sz, 12), 40);
// Scale down if too narrow (less aggressive)
  force_big ? (
    sz = sz;
  ) : (
    while (sz > 10 && area_w < (sz*3)) (
      sz -= 1;
    );
  );
gfx_setfont(1, "sans-serif", sz);

// Draw note or placeholder
strlen(note_text) > 0 ? (
  gfx_r = txt_r; gfx_g = txt_g; gfx_b = txt_b;
  gfx_drawstr(note_text);
) : (
  gfx_r = 0.8; gfx_g = 0.5; gfx_b = 0.5;
  gfx_drawstr("No saved note for this track");
  gfx_y += 18; gfx_x = pad;
  gfx_r = dim_r; gfx_g = dim_g; gfx_b = dim_b;
  gfx_drawstr("Use floop scratchpad to add notes");
);

]], safeNote, safeGUID, scale, forceBig)

  return jsfxContent
end

local function createJSFXFile(trackGUID, noteContent, fontScale, forceLarge)
  local resourcePath = getResourcePath()
  local effectsDir = joinPath(resourcePath, 'Effects')
  local jsfxPath = joinPath(effectsDir, JSFX_FILE_NAME)
  
  reaper.RecursiveCreateDirectory(effectsDir, 0)
  
  local jsfxContent = createDynamicJSFXContent(trackGUID, noteContent or "", fontScale, forceLarge)
  
  local writable, werr = isDirWritable(jsfxPath)
  if not writable then
    logError("JSFX path not writable " .. jsfxPath .. ": " .. tostring(werr))
    return false, "JSFX path not writable"
  end
  local file, ferr = io.open(jsfxPath, 'w')
  if file then
    file:write(jsfxContent)
    file:close()
    return true, jsfxPath
  else
    logError("Cannot create JSFX file at " .. jsfxPath .. ": " .. tostring(ferr))
    return false, "Cannot create JSFX file"
  end
end

local function addJSFXToTrack(track, fontScale, forceLarge)
  if not isValidTrack(track) then
    return false, "No valid track selected"
  end
  
  local trackGUID = getTrackGUID(track)
  local noteContent = getNoteForTrack(trackGUID)
  
  -- Avoid duplicates: if FX already exists on track, skip adding
  local fxCount = reaper.TrackFX_GetCount(track)
  for i = 0, fxCount - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      return true, "JSFX already present on this track (no new instance)"
    end
  end
  
  local success, jsfxPath = createJSFXFile(trackGUID, noteContent, fontScale or jsfxFontScale, forceLarge or jsfxForceLarge)
  if not success then
    return false, jsfxPath
  end
  
  local fxIndex = reaper.TrackFX_AddByName(track, JSFX_FILE_NAME, false, -1)
  
  if fxIndex >= 0 then
    -- Automatically set the embedded UI in the TCP using the correct function
    reaper.TrackFX_SetNamedConfigParm(track, fxIndex, "ui_embed", "1")
    
    -- Force Ui Refresh
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    
  return true, "JSFX added to track with dynamic notes (embedded in TCP)"
  else
    return false, "Error adding JSFX"
  end
end

-- Refresh JSFX note reader for a single track (delete + conditional re-add)
-- Note: To keep the UI embedded after re-adds, configure
-- "Default settings for new instance" to include TCP/MCP embedding in the FX Browser.
local function refreshJSFXForTrack(track)
  if not track then return end
  local wasPresent = false
  local fxCount = reaper.TrackFX_GetCount(track)
  -- iterate backwards when deleting
  for i = fxCount - 1, 0, -1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      reaper.TrackFX_Delete(track, i)
      wasPresent = true
    end
  end
  -- Re-add only when the track has notes or previously had the JSFX
  local trackGUID = getTrackGUID(track)
  local noteContent = getNoteForTrack(trackGUID)
  if (noteContent and noteContent:match('%S')) or wasPresent then
    addJSFXToTrack(track, jsfxFontScale)
  end
end

-- Refresh JSFX note readers on all tracks
local function refreshAllJSFXReaders()
  local total = reaper.CountTracks(0)
  for t = 0, total - 1 do
    local tr = reaper.GetTrack(0, t)
    refreshJSFXForTrack(tr)
  end
end

-- UI Functions
local function initializeUI()
  local proj, projPath = reaper.EnumProjects(-1)
  lastProjectPtr = proj
  lastProjectPath = projPath
  log("Script started. Initial Project Path: " .. (lastProjectPath == "" and "[Unsaved]" or lastProjectPath))
  currentTrack = getSelectedTrack()
  if currentTrack and isValidTrack(currentTrack) then
    local trackGUID = getTrackGUID(currentTrack)
    noteText = getNoteForTrack(trackGUID)
    jsfxFontScale = getFontScaleForTrack(trackGUID)
  else
    noteText = ""
    jsfxFontScale = 1.30
  end
end

local function renderUI()
  -- check if selected track is changed
  local newSelectedTrack = getSelectedTrack()
  if newSelectedTrack ~= currentTrack then
    -- if we have unsaved changes, autosave them before switching
    if isDirty and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      local success, info = saveNoteForTrack(trackGUID, noteText)
      if success then
        statusMsg = '✅ Note autosaved for track: ' .. getTrackName(currentTrack)
        isDirty = false
        -- Refresh JSFX for this track only
        refreshJSFXForTrack(currentTrack)
      else
        statusMsg = '❌ Autosave failed: ' .. (info or 'unknown')
      end
    end
    -- now switch
    currentTrack = newSelectedTrack
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      noteText = getNoteForTrack(trackGUID)
      jsfxFontScale = getFontScaleForTrack(trackGUID)
      isDirty = false
    else
      noteText = ""
      jsfxFontScale = 1.30
    end
  end
  
  
  reaper.ImGui_Text(ctx, '✅ Floop Scratchpad')
  reaper.ImGui_Separator(ctx)
  
  -- Track info
  if currentTrack and isValidTrack(currentTrack) then
    local trackName = getTrackName(currentTrack)
    local trackGUID = getTrackGUID(currentTrack)
    reaper.ImGui_Text(ctx, '🎯 Track: ' .. trackName)
    reaper.ImGui_Text(ctx, '🔑 GUID: ' .. trackGUID)
  else
    reaper.ImGui_Text(ctx, '⚠️  No track selected')
  end
  
  -- Info file
  local notesPath = getNotesFilePath()
  reaper.ImGui_Text(ctx, '📁 Notes file: ' .. notesPath)
  
  reaper.ImGui_Separator(ctx)
  
  -- TEXTAREA MULTILINE
  reaper.ImGui_Text(ctx, '📝 Notes:')
  
  -- Set textarea size
  local availWidth, availHeight = reaper.ImGui_GetContentRegionAvail(ctx)
  local textareaWidth = math.max(150, availWidth - 10)
  local textareaHeight = math.max(120, math.min(150, availHeight - 120)) 
  
  -- Input
  local changed, newText = reaper.ImGui_InputTextMultiline(ctx, '##note_textarea', noteText, textareaWidth, textareaHeight)
  if changed then
    noteText = newText
    isDirty = true
  end
  
  reaper.ImGui_Spacing(ctx)
  
  -- Character count
  reaper.ImGui_Text(ctx, "📊 Text Length: " .. #noteText .. " characters")
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  
  local baseAbsSize = 18
  local currentAbsSize = math.floor(jsfxFontScale * baseAbsSize + 0.5)
  
  reaper.ImGui_Text(ctx, '🔡 JSFX font')
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format("%d px", currentAbsSize))
  
  local scaleChanged, newScale = SliderFloatCompat('##jsfx_font_scale', jsfxFontScale, 0.8, 2.25)
  if scaleChanged then
    jsfxFontScale = newScale
    isDirty = true
  end
  -- Refresh JSFX only after edit ends to avoid flicker
  if reaper.ImGui_IsItemDeactivatedAfterEdit and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    if currentTrack and isValidTrack(currentTrack) then
      -- Auto-save notes and font scale before refreshing JSFX
      -- This ensures the JSFX is rebuilt with the current text and scale, not the old file content
      local trackGUID = getTrackGUID(currentTrack)
      local saved, err = saveNoteForTrack(trackGUID, noteText)
      
      if saved then
        refreshJSFXForTrack(currentTrack)
        statusMsg = '✅ Font scale updated'
        isDirty = false
      else
        statusMsg = '❌ Autosave failed: ' .. (err or "unknown")
      end
    end
  end
  
  local absChanged = false
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SetNextItemWidth then
    reaper.ImGui_SetNextItemWidth(ctx, 60)
  end
  local ch, str = reaper.ImGui_InputText(ctx, '##jsfx_font_abs', tostring(currentAbsSize))
  absChanged = ch
  if absChanged then
    local parsed = tonumber(str)
    if parsed then
      local newAbs = math.floor(parsed + 0.5)
      if newAbs < 14 then newAbs = 14 end
      if newAbs > 40 then newAbs = 40 end
      jsfxFontScale = newAbs / baseAbsSize
      isDirty = true
    end
  end
  if reaper.ImGui_IsItemDeactivatedAfterEdit and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      local saved, err = saveNoteForTrack(trackGUID, noteText)
      if saved then
        refreshJSFXForTrack(currentTrack)
        statusMsg = '✅ Font size updated'
        isDirty = false
      else
        statusMsg = '❌ Autosave failed: ' .. (err or "unknown")
      end
    end
  end
  reaper.ImGui_Spacing(ctx)
  
  if reaper.ImGui_Button(ctx, '💾 Save') then
    if currentTrack and isValidTrack(currentTrack) then
      local trackGUID = getTrackGUID(currentTrack)
      local success, info = saveNoteForTrack(trackGUID, noteText)
      if success then
        statusMsg = '✅ Note saved for track: ' .. getTrackName(currentTrack)
        
        -- Update JSFX
        local fxCount = reaper.TrackFX_GetCount(currentTrack)
        
        for i = 0, fxCount - 1 do
          local _, fxName = reaper.TrackFX_GetFXName(currentTrack, i, '')
          
          -- Search for "FloopNoteReader" or "Floop Note Reader"
          if fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader') then
            
            
            reaper.TrackFX_Delete(currentTrack, i)
            
            -- Re-add only if the saved note is non-empty
            if noteText and noteText:match('%S') then
              local newSuccess, newInfo = addJSFXToTrack(currentTrack, jsfxFontScale, jsfxForceLarge)
              if newSuccess then
                statusMsg = statusMsg .. ' - JSFX updated automatically'
              else
                statusMsg = statusMsg .. ' - Error updating JSFX'
              end
            else
              statusMsg = statusMsg .. ' - JSFX removed (empty note)'
            end
            
            break
          end
        end
        
      else
        statusMsg = '❌ Error: ' .. info
      end
    else
      statusMsg = '❌ Error: Select a track before saving'
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '🎨 Add JSFX') then
    if currentTrack and isValidTrack(currentTrack) then
      local success, info = addJSFXToTrack(currentTrack, jsfxFontScale, jsfxForceLarge)
      if success then
        statusMsg = '✅ ' .. info
      else
        statusMsg = '❌ ' .. info
      end
    else
      statusMsg = '❌ Error: Select a track before adding JSFX'
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '🗑 Clear Note File') then
    showConfirmClear = true
    reaper.ImGui_OpenPopup(ctx, 'Confirm Clear')
  end
  
  -- Add Help button
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '❔ Help') then
    showHelpModal = true
    reaper.ImGui_OpenPopup(ctx, 'Help Guide')
  end
  
  -- Help Modal
  if showHelpModal then
    local modalW, modalH = 600, 500
    reaper.ImGui_SetNextWindowSize(ctx, modalW, modalH, reaper.ImGui_Cond_Always())

    -- Center above the script window when it appears
    local winX, winY = reaper.ImGui_GetWindowPos(ctx)
    local winW, winH = reaper.ImGui_GetWindowSize(ctx)
    if winX and winY and winW and winH then
      local posX = winX + (winW - modalW) * 0.5
      local posY = winY + (winH - modalH) * 0.5
      reaper.ImGui_SetNextWindowPos(ctx, posX, posY, reaper.ImGui_Cond_Appearing())
    else
      -- Fallback: position near main viewport work area
      local viewport = reaper.ImGui_GetMainViewport(ctx)
      local work_pos_x, work_pos_y = reaper.ImGui_Viewport_GetWorkPos(viewport)
      reaper.ImGui_SetNextWindowPos(ctx, work_pos_x + 50, work_pos_y + 50, reaper.ImGui_Cond_Appearing())
    end

    -- Prevent movement and resizing to keep it centered
    local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
    if reaper.ImGui_BeginPopupModal(ctx, 'Help Guide', true, flags) then
  reaper.ImGui_Text(ctx, '📖 Floop Scratchpad - User Guide')
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      
      -- Getting Started Section
      reaper.ImGui_Text(ctx, '🚀 Getting Started:')
      reaper.ImGui_BulletText(ctx, 'Select a track in REAPER to start taking notes')
      reaper.ImGui_BulletText(ctx, 'The track name and GUID will appear in the interface')
      reaper.ImGui_BulletText(ctx, 'Notes are automatically loaded when switching tracks')
      reaper.ImGui_BulletText(ctx, 'JSFX Setup: open FX Browser and press F5 to refresh plugins')
      reaper.ImGui_BulletText(ctx, 'Find FloopNoteReader, right-click and select "Default settings for new instance"')
      reaper.ImGui_BulletText(ctx, 'Enable "Show embedded UI in TCP or MCP" for automatic display')
      reaper.ImGui_Spacing(ctx)
      
      -- Taking Notes Section  
      reaper.ImGui_Text(ctx, '📝 Taking Notes:')
      reaper.ImGui_BulletText(ctx, 'Type your notes in the text area')
      reaper.ImGui_BulletText(ctx, 'JSFX displays up to 200 characters (extra text is truncated)')
      reaper.ImGui_BulletText(ctx, 'Character count is displayed below the text area')
      reaper.ImGui_Spacing(ctx)
      
      -- Saving and JSFX Section
      reaper.ImGui_Text(ctx, '💾 Saving & JSFX:')
      reaper.ImGui_BulletText(ctx, '💾 Save: Manually saves notes to the file')
      reaper.ImGui_BulletText(ctx, '🎨 Add JSFX: Adds a visual note reader to the track TCP')
      reaper.ImGui_BulletText(ctx, '🔡 Font Size: Use slider or numeric input (14–40 px). Updates on release.')
      reaper.ImGui_BulletText(ctx, '🔁 Autosave: Notes are saved automatically when switching tracks or tabs')
      reaper.ImGui_BulletText(ctx, '🗓 Startup: Notes restore automatically. SWS extension enables auto-refresh.')
      reaper.ImGui_BulletText(ctx, '🗑️ Clear: Deletes all notes for the current project (creates backup)')
      reaper.ImGui_Spacing(ctx)
      
      -- File Management Section
      reaper.ImGui_Text(ctx, '📁 File Management:')
      reaper.ImGui_BulletText(ctx, 'Saved Projects: Notes stored in [ProjectName]_notes.txt')
      reaper.ImGui_BulletText(ctx, 'Unsaved Projects: Notes stored in a central fallback file')
      reaper.ImGui_BulletText(ctx, '🚀 Migration: When saving a project for the first time, notes are automatically moved to the new project folder.')
      reaper.ImGui_BulletText(ctx, '📍 Path: The current note file path is displayed in the main window.')
      reaper.ImGui_Spacing(ctx)
      
      -- Tips Section
      reaper.ImGui_Text(ctx, '💡 Tips:')
      reaper.ImGui_BulletText(ctx, 'Keep notes concise for better JSFX display')
      reaper.ImGui_BulletText(ctx, 'Use the JSFX for quick reference while mixing')
      reaper.ImGui_BulletText(ctx, 'Notes and font settings persist across REAPER sessions')
      reaper.ImGui_BulletText(ctx, 'Each track has its own note and font settings')
      
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      
      -- Close button 
      local availWidth = reaper.ImGui_GetContentRegionAvail(ctx)
      local buttonWidth = 100
      reaper.ImGui_SetCursorPosX(ctx, (availWidth - buttonWidth) * 0.5)
      
      if reaper.ImGui_Button(ctx, 'Close', buttonWidth, 30) then
        showHelpModal = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      
      reaper.ImGui_EndPopup(ctx)
    else
      showHelpModal = false
    end
  end
  
  if showConfirmClear then
    local flags = reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()
    if reaper.ImGui_BeginPopupModal(ctx, 'Confirm Clear', true, flags) then
      reaper.ImGui_Text(ctx, 'Clear all saved notes? This cannot be undone.')
      if reaper.ImGui_Button(ctx, 'Yes', 100, 30) then
        local filePath = getNotesFilePath()
        local existing, _ = readFile(filePath)
        if existing and existing ~= "" then
          local ts = os.date('%Y%m%d_%H%M%S')
          local backupPath = filePath .. '.bak.' .. ts
          local okb, errb = writeFile(backupPath, existing)
          if not okb then
            statusMsg = '❌ Backup failed: ' .. (errb or 'unknown')
            logError('Backup failed: ' .. tostring(errb))
          end
        end
        local ok, err = writeFile(filePath, "")
        if ok then
          notesCache = ""
          notesCachePath = filePath
          noteText = ""
          isDirty = false
          statusMsg = '✅ Note file cleared (backup created)'
          refreshAllJSFXReaders()
        else
          statusMsg = '❌ Error clearing note file: ' .. (err or "unknown")
          logError('Clear failed: ' .. tostring(err))
        end
        showConfirmClear = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, 'No', 100, 30) then
        showConfirmClear = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    else
      showConfirmClear = false
    end
  end
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  
  -- Status
  reaper.ImGui_Text(ctx, statusMsg)
  
  reaper.ImGui_Spacing(ctx)
end
-- Startup: ensure SWS Project Startup Action points to headless refresh
local function SetupProjectStartupAction()
    -- Silent if SWS is not available
    if not reaper.NF_SetProjectStartupAction then return end

    -- Resolve path to refresh script next to this script
    local _, this_file = reaper.get_action_context()
    local dir = this_file:match('^(.+)[\\/]')
    if not dir then return end
    local sep = package.config:sub(1, 1)
    local target = dir .. sep .. 'Floop Startup Refresh.lua'
    if not reaper.file_exists(target) then return end

    -- Register refresh script in Main section and get named identifier
    local cmd_id = reaper.AddRemoveReaScript(true, 0, target, true)
    if cmd_id == 0 then return end
    local named = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
    if not named or named == '_' then return end

    -- Set per-project startup action (requires saving project for persistence)
    reaper.NF_SetProjectStartupAction(named)
end

pcall(SetupProjectStartupAction)

local function mainLoop()
  -- Check for project save (Unsaved -> Saved transition) or Tab Switch
  local currentProject, currentProjectPath = reaper.EnumProjects(-1)
  
  if lastProjectPtr ~= nil then
    if currentProject == lastProjectPtr then
      -- Same project tab
      if currentProjectPath ~= lastProjectPath then
        -- Path changed => Save As / First Save detected
        log("Project path changed (Same Project) from '" .. tostring(lastProjectPath) .. "' to '" .. tostring(currentProjectPath) .. "'")
        
        if notesCache and notesCache:match("%S") then
          log("Performing proactive in-memory migration...")
          -- Force write cache to new location
          
          local saved, path = saveNotesToFile(notesCache)
          if saved then
            log("In-memory migration successful to: " .. path)
            statusMsg = "✅ Project saved: Notes migrated to new location"
          else
            logError("In-memory migration failed.")
            statusMsg = "❌ Migration failed"
          end
        else
          log("No in-memory notes to migrate, or cache empty.")
        end
        lastProjectPath = currentProjectPath
      end
    else
      -- Project Tab Switched
      if currentProject ~= lastProjectPtr then
        
         log("Switched Project Tab. New Path: " .. tostring(currentProjectPath))
         
         notesCache = nil
         notesCachePath = nil
         lastProjectPtr = currentProject
         lastProjectPath = currentProjectPath
         
         currentTrack = nil 
      end
    end
  else
    -- First run initialization 
    lastProjectPtr = currentProject
    lastProjectPath = currentProjectPath
  end

  reaper.ImGui_PushFont(ctx, sans_serif_font, 12)
  local color_count = apply_theme()
  
  reaper.ImGui_SetNextWindowSize(ctx, 460, 560, reaper.ImGui_Cond_FirstUseEver())
  
  local visible, open = reaper.ImGui_Begin(ctx, 'Floop Scratchpad', true, reaper.ImGui_WindowFlags_NoCollapse())
  
  if visible then
    renderUI()
    reaper.ImGui_End(ctx)
  end
  
  end_theme(color_count)
  reaper.ImGui_PopFont(ctx)
  
  if open then
    reaper.defer(mainLoop)
  end
end

-- Init
initializeUI()
mainLoop()
