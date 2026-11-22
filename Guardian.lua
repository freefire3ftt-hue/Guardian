-- ============================================================
-- GUARDIAN v2 — teleport-safe, anti-crash em stage transition
-- ============================================================

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local BABIS_URL = "https://raw.githubusercontent.com/freefire3ftt-hue/Sblr.lua/refs/heads/main/biblioteca.lua"

local Guard = {}
local S = {
    teleporting = false,
    startedAt = 0,
    lastCharAt = 0,
    reloadPending = false,
    reloadAt = 0,
    reloadCount = 0,
    reloadCoolUntil = 0,
    charAlive = false,
    heartbeat = tick(),
    stuckWarn = 0,
    pausedFeatures = {},
}
Guard.__pauseFns = {}
Guard.__resumeFns = {}

local notif = function(msg, color, dur)
    pcall(function()
        if genv.Babis and genv.Babis.Notify then
            genv.Babis.Notify({ Title = "Guard", Message = msg, Duration = dur or 4, Color = color })
        end
    end)
end
local GREEN  = Color3.fromRGB(120, 220, 130)
local RED    = Color3.fromRGB(230, 100, 100)
local YELLOW = Color3.fromRGB(240, 200, 80)

function Guard.IsTeleporting() return S.teleporting end
function Guard.IsCharAlive()   return S.charAlive end
function Guard.IsSafe()        return S.charAlive and not S.teleporting end
function Guard.Status()
    return { teleporting = S.teleporting, charAlive = S.charAlive,
             reloads = S.reloadCount, pending = S.reloadPending }
end
function Guard.OnPause(fn)  table.insert(Guard.__pauseFns, fn) end
function Guard.OnResume(fn) table.insert(Guard.__resumeFns, fn) end
local function fire(t) for _, fn in ipairs(t) do pcall(fn) end end

local function pauseHeavyFeatures()
    pcall(function()
        local B = genv.Babis
        if not B or not B.Options then return end
        if B.Registry then
            for _, key in ipairs({ "silent_aim", "sandman_slide", "esp_skeleton", "esp_box", "esp_lines" }) do
                if B.Options[key] == true and B.Registry[key] then
                    pcall(B.Registry[key], false)
                    S.pausedFeatures[key] = true
                end
            end
        end
    end)
end

local function resumeHeavyFeatures()
    pcall(function()
        local B = genv.Babis
        if not B or not B.Registry then return end
        for key, was in pairs(S.pausedFeatures) do
            if was and B.Registry[key] then pcall(B.Registry[key], true) end
        end
        S.pausedFeatures = {}
    end)
end

local function scheduleReload(delay)
    if tick() < S.reloadCoolUntil then return end
    S.reloadPending = true
    S.reloadAt = tick() + (delay or 3)
end

local function doReload()
    if not S.reloadPending then return end
    if tick() < S.reloadAt then return end
    if tick() < S.reloadCoolUntil then return end
    S.reloadPending = false
    S.reloadCoolUntil = tick() + 10
    S.reloadCount = S.reloadCount + 1
    notif("Recarregando UI (" .. S.reloadCount .. ")", YELLOW, 4)
    task.spawn(function()
        task.wait(0.5)
        local ok, err = pcall(function()
            local fn = loadstring(game:HttpGet(BABIS_URL))
            if type(fn) == "function" then
                local res = fn()
                if res and res.Version then
                    notif("UI restaurada v" .. res.Version, GREEN, 3)
                end
            end
        end)
        if not ok then warn("[Guard] reload falhou: " .. tostring(err)) end
    end)
end

pcall(function()
    player.OnTeleport:Connect(function(state, placeId)
        pcall(function()
            if state == Enum.TeleportState.Started
            or state == Enum.TeleportState.WaitingForServer
            or state == Enum.TeleportState.InProgress then
                if not S.teleporting then
                    S.teleporting = true
                    S.startedAt = tick()
                    pauseHeavyFeatures()
                    fire(Guard.__pauseFns)
                end
            elseif state == Enum.TeleportState.Failed
            or state == Enum.TeleportState.Cancelled then
                S.teleporting = false
                fire(Guard.__resumeFns)
                resumeHeavyFeatures()
                scheduleReload(2)
            end
        end)
    end)
end)

if player.Character then S.charAlive = true end
player.CharacterAdded:Connect(function()
    local wasTeleporting = S.teleporting
    S.charAlive = true
    S.lastCharAt = tick()
    S.teleporting = false
    S.stuckWarn = 0
    fire(Guard.__resumeFns)
    resumeHeavyFeatures()
    if wasTeleporting then scheduleReload(3) end
end)
player.CharacterRemoving:Connect(function()
    S.charAlive = false
end)

-- Watchdog: teleporte travado > 60s
task.spawn(function()
    while true do
        task.wait(3)
        pcall(function()
            if S.teleporting and (tick() - S.startedAt) > 60 then
                S.teleporting = false
                fire(Guard.__resumeFns)
                resumeHeavyFeatures()
                notif("Teleporte travou 60s — liberando", RED, 5)
                scheduleReload(2)
            end
        end)
    end
end)

-- Watchdog: reload pendente
task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(doReload)
    end
end)

-- Heartbeat monitor
task.spawn(function()
    RunService.Heartbeat:Connect(function() S.heartbeat = tick() end)
end)
task.spawn(function()
    while true do
        task.wait(5)
        pcall(function()
            local gap = tick() - S.heartbeat
            if gap > 3 and S.stuckWarn < 3 then
                S.stuckWarn = S.stuckWarn + 1
                warn(string.format("[Guard] Main thread travada %.1fs — loop sem task.wait?", gap))
            elseif gap <= 1 then
                S.stuckWarn = 0
            end
        end)
    end
end)

function Guard.run(loopFn, interval)
    interval = interval or 0.2
    return task.spawn(function()
        while true do
            if S.teleporting then
                task.wait(0.5)
            else
                local ok, err = pcall(loopFn)
                if not ok then warn("[Guard.run] " .. tostring(err)) end
                task.wait(interval)
            end
        end
    end)
end

Guard.__conns = {}
function Guard.track(c) table.insert(Guard.__conns, c); return c end
function Guard.untrackAll()
    for _, c in ipairs(Guard.__conns) do pcall(function() c:Disconnect() end) end
    Guard.__conns = {}
end

genv.BabisGuard = Guard
return Guard
