-- Floop Startup Refresh
-- VERSION: 1.2.3
-- DATE: 06-01-2026

-- Purpose: Project startup helper to refresh JSFX note readers per track
-- It reads the project notes file, re-writes the single JSFX file with the
-- track-specific text, removes any existing instances, and re-adds the JSFX
-- to tracks that have non-empty notes. This avoids multiplying JSFX files.

local reaper = reaper

-- Helper functions defined first to avoid scope issues

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
  local projectName = (type(r2) == "string" and r2 ~= "" and r2) or (type(r1) == "string" and r1 or "")
  if projectName == "" then
    projectName = "unsaved_project"
  else
    projectName = projectName:gsub("%.rpp$", "")
  end
  return joinPath(projectPath, projectName .. "_notes.txt")
end

local function readFile(filePath)
  local f = io.open(filePath, "r")
  if not f then return nil end
  local c = f:read("*all")
  f:close()
  return c
end

local function appendFile(filePath, content)
  local f = io.open(filePath, "a")
  if not f then return false end
  f:write(content)
  f:close()
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

local function isDirWritable(filePath)
  local dir = filePath:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == "" then return false end
  local sep = package.config:sub(1,1)
  local testPath = dir .. sep .. ".floop_writable_test_" .. tostring(math.random(1000000))
  local f = io.open(testPath, "w")
  if not f then return false end
  f:write("ok")
  f:close()
  os.remove(testPath)
  return true
end

-- Notes parsing
local function getNoteForGUID(allNotes, guid)
  if not allNotes or allNotes == "" or not guid then return "" end
  
  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end
  
  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local bguid = block:match("GUID:%s*(%S+)")
      if bguid == guid then
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

-- read FontScale for GUID (fallback to 1.30)
local function getFontScaleForGUID(allNotes, guid)
  if not allNotes or allNotes == "" or not guid then return 1.30 end
  
  local padded = allNotes:gsub("\r\n", "\n")
  if not padded:match("\n=====\n$") then padded = padded .. "\n=====\n" end
  
  for block in padded:gmatch("(.-)\n=====\n") do
    if block:match("%S") then
      local bguid = block:match("GUID:%s*(%S+)")
      if bguid == guid then
        local fs = block:match("FontScale:%s*([%d%.]+)")
        local n = tonumber(fs)
        if n then return n end
        break
      end
    end
  end
  return 1.30
end

-- JSFX writer
local function createJSFXFile(noteContent, fontScale)
  local resourcePath = reaper.GetResourcePath()
  local effectsDir = joinPath(resourcePath, 'Effects')
  local jsfxPath = joinPath(effectsDir, 'FloopNoteReader.jsfx')
  reaper.RecursiveCreateDirectory(effectsDir, 0)
  -- simple JSFX that displays a note string
  local safe = (noteContent or ""):gsub('"','\\"'):gsub('\n','\\n')
  if #safe > 200 then safe = safe:sub(1,200) .. "..." end
  local scale = tonumber(fontScale) or 1.30
  local jsfx = string.format([[desc:Floop Note Reader
@init
#note_text = "%s";
font_scale = %.2f;
force_big = 0;

@gfx 400 140
gfx_r = 0.93; gfx_g = 0.95; gfx_b = 0.65;
gfx_rect(0,0,gfx_w,gfx_h);
pad = 6;
area_w = max(10, gfx_w - pad*2);
compact = (gfx_w < 260) || (gfx_h < 90);
base_sz = (compact ? 14 : 18) * font_scale;
sz = min(max(base_sz, 12), 28);
while (sz > 10 && area_w < (sz*3)) (
  sz -= 1;
);
gfx_setfont(1, "sans-serif", sz);
strlen(#note_text) > 0 ? (
  gfx_r = 0.31; gfx_g = 0.31; gfx_b = 0.30;
  gfx_x = pad; gfx_y = pad; gfx_drawstr(#note_text);
) : (
  gfx_r = 0.8; gfx_g = 0.5; gfx_b = 0.5;
  gfx_x = pad; gfx_y = pad; gfx_drawstr("No saved note for this track");
);
]], safe, scale)
  if not isDirWritable(jsfxPath) then
    logError("JSFX path not writable " .. jsfxPath)
    return false, 'Cannot create JSFX file'
  end
  local f, ferr = io.open(jsfxPath, 'w')
  if not f then
    logError("Cannot create JSFX file at " .. jsfxPath .. ": " .. tostring(ferr))
    return false, 'Cannot create JSFX file'
  end
  f:write(jsfx)
  f:close()
  return true, jsfxPath
end

-- Track helpers
local function deleteExistingJSFX(track)
  local fxCount = reaper.TrackFX_GetCount(track)
  for i = fxCount - 1, 0, -1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, i, '')
    if fxName and (fxName:find('FloopNoteReader') or fxName:find('Floop Note Reader')) then
      reaper.TrackFX_Delete(track, i)
    end
  end
end

local function addJSFXToTrack(track)
  local fxIndex = reaper.TrackFX_AddByName(track, 'FloopNoteReader.jsfx', false, -1)
  if fxIndex >= 0 then
    reaper.TrackFX_SetNamedConfigParm(track, fxIndex, 'ui_embed', '1')
    return true
  end
  return false
end

-- Utility to read notes with fallback and migration for first-save scenario
local function readNotesWithFallback()
  local primary = getNotesFilePath()
  local c = readFile(primary)
  if c and c:match("%S") then return c end
  
  -- Check if we need to migrate notes from unsaved location
  local projectPath = reaper.GetProjectPath("")
  if projectPath ~= "" then
    -- Project is saved, try to migrate from unsaved location
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local unsavedPath = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local unsavedContent = readFile(unsavedPath)
    
    if unsavedContent and unsavedContent:match("%S") then
      -- Do NOT filter notes; keep all notes from unsaved project to ensure migration
      -- Migrate notes to project location
      local file = io.open(primary, "w")
      if file then
        file:write(unsavedContent)
        file:close()
        -- Backup unsaved notes with timestamp before deletion
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(reaperMedia, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        local bf = io.open(backup, 'w')
        if bf then bf:write(unsavedContent); bf:close() end
        os.remove(unsavedPath)
        return unsavedContent
      end
    end
    
    -- Legacy fallback: older versions saved to Desktop on first save
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacyPath = joinPath(desktop, "unsaved_project_notes.txt")
    local legacyContent = readFile(legacyPath)
    if legacyContent and legacyContent:match("%S") then
      -- Do NOT filter notes; keep all notes from unsaved project to ensure migration
      -- Migrate legacy notes to project location
      local file = io.open(primary, "w")
      if file then
        file:write(legacyContent)
        file:close()
        -- Backup legacy unsaved notes with timestamp before deletion
        local ts = os.date('%Y%m%d_%H%M%S')
        local backup = joinPath(desktop, 'unsaved_project_notes.bak.' .. ts .. '.txt')
        local bf = io.open(backup, 'w')
        if bf then bf:write(legacyContent); bf:close() end
        os.remove(legacyPath)
        return legacyContent
      end
    end
    
    -- Ensure project notes file exists even if no content to migrate
    -- But only if it doesn't exist yet
    if not c then
      local f = io.open(primary, "w")
      if f then f:write(""); f:close() end
      return ""
    end
    return c or ""
  else
    -- Project not saved yet, use fallback locations
    local docs = joinPath(getSystemHome(), "Documents")
    local reaperMedia = joinPath(docs, "REAPER Media")
    local fallback = joinPath(reaperMedia, "unsaved_project_notes.txt")
    local fc = readFile(fallback)
    if fc and fc:match("%S") then return fc end
    
    -- Legacy fallback: older versions saved to Desktop on first save
    local desktop = joinPath(getSystemHome(), "Desktop")
    local legacy = joinPath(desktop, "unsaved_project_notes.txt")
    local lc = readFile(legacy)
    if lc and lc:match("%S") then return lc end
    return ""
  end
  
  return ""
end

-- Main refresh across tracks
local function refreshAll()
  local notes = readNotesWithFallback()
  local total = reaper.CountTracks(0)
  for t = 0, total - 1 do
    local tr = reaper.GetTrack(0, t)
    local guid = reaper.GetTrackGUID(tr)
    local note = getNoteForGUID(notes, guid)
    local scale = getFontScaleForGUID(notes, guid)
    deleteExistingJSFX(tr)
    if note and note:match('%S') then
      local ok = select(1, createJSFXFile(note, scale))
      if ok then addJSFXToTrack(tr) end
    end
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

refreshAll()
