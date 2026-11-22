-- ============================================================
-- BABIS TELEPORT GUARD — protege teleporte, evita crash
-- Cola depois do loadstring da biblioteca.lua
-- ============================================================

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local BABIS_URL = "https://raw.githubusercontent.com/freefire3ftt-hue/Sblr.lua/refs/heads/main/biblioteca.lua"

local Guard = {}
Guard.__state = {
    teleporting    = false,
    teleportStart  = 0,
    lastState      = nil,
    lastPlace      = nil,
    charAlive      = false,
    reloadCount    = 0,
    reloadCoolUntil = 0,
    lastHeartbeat  = tick(),
    stuckWarnings  = 0,
}
Guard.__pauseFns  = {}
Guard.__resumeFns = {}

local S = Guard.__state
local notif = function(msg, color, dur)
    pcall(function()
        if genv.Babis and genv.Babis.Notify then
            genv.Babis.Notify({ Title = "Guard", Message = msg, Duration = dur or 4, Color = color })
        end
    end)
end
local GREEN = Color3.fromRGB(120, 220, 130)
local RED   = Color3.fromRGB(230, 100, 100)
local YELLOW = Color3.fromRGB(240, 200, 80)

function Guard.IsTeleporting() return S.teleporting end
function Guard.IsCharAlive()   return S.charAlive end
function Guard.IsSafe()        return S.charAlive and not S.teleporting end
function Guard.Status()        return { teleporting = S.teleporting, charAlive = S.charAlive, reloads = S.reloadCount, lastState = S.lastState } end

function Guard.OnPause(fn)  if type(fn) == "function" then table.insert(Guard.__pauseFns, fn) end end
function Guard.OnResume(fn) if type(fn) == "function" then table.insert(Guard.__resumeFns, fn) end end

local function fire(fns)
    for _, fn in ipairs(fns) do
        pcall(fn)
    end
end

local function reloadBabis()
    if tick() < S.reloadCoolUntil then return end
    S.reloadCoolUntil = tick() + 8
    S.reloadCount = S.reloadCount + 1
    notif("Teleporte falhou, recarregando UI (" .. S.reloadCount .. ")", YELLOW, 5)
    task.spawn(function()
        task.wait(1.2)
        local ok, err = pcall(function()
            local lib = loadstring(game:HttpGet(BABIS_URL))
            if type(lib) == "function" then
                local res = lib()
                if res and res.Version then notif("UI restaurada v" .. res.Version, GREEN, 3) end
            end
        end)
        if not ok then warn("[Guard] reload failed: " .. tostring(err)) end
    end)
end

-- OnTeleport PASSEIVO (nunca retorna nada — retornar cancela o teleporte)
pcall(function()
    player.OnTeleport:Connect(function(state, placeId, spawnName)
        pcall(function()
            S.lastState = state
            if placeId then S.lastPlace = placeId end

            if state == Enum.TeleportState.Started
            or state == Enum.TeleportState.WaitingForServer
            or state == Enum.TeleportState.InProgress then
                if not S.teleporting then
                    S.teleporting = true
                    S.teleportStart = tick()
                    fire(Guard.__pauseFns)
                end
                return
            end

            if state == Enum.TeleportState.Failed or state == Enum.TeleportState.Cancelled then
                S.teleporting = false
                S.teleportStart = 0
                fire(Guard.__resumeFns)
                -- Babis se auto-destruiu no Started; recarrega só na falha
                reloadBabis()
                return
            end
        end)
    end)
end)

-- Monitor de character
if player.Character then S.charAlive = true end
player.CharacterAdded:Connect(function(char)
    S.charAlive = true
    S.teleporting = false
    S.teleportStart = 0
    S.stuckWarnings = 0
    fire(Guard.__resumeFns)
end)
player.CharacterRemoving:Connect(function()
    S.charAlive = false
end)

-- Watchdog de teleporte travado (45s sem novo char = reset)
task.spawn(function()
    while true do
        task.wait(3)
        pcall(function()
            if S.teleporting and S.teleportStart > 0 and (tick() - S.teleportStart) > 45 then
                S.teleporting = false
                S.teleportStart = 0
                fire(Guard.__resumeFns)
                notif("Teleporte travou 45s — liberando estado", RED, 5)
            end
        end)
    end
end)

-- Watchdog de heartbeat (detecta main thread travada por loop externo)
task.spawn(function()
    RunService.Heartbeat:Connect(function()
        S.lastHeartbeat = tick()
    end)
end)
task.spawn(function()
    while true do
        task.wait(5)
        pcall(function()
            local gap = tick() - S.lastHeartbeat
            if gap > 3 and S.stuckWarnings < 3 then
                S.stuckWarnings = S.stuckWarnings + 1
                warn(string.format("[Guard] Main thread travada %.1fs — verifica teus loops (task.wait?)", gap))
            elseif gap <= 1 then
                S.stuckWarnings = 0
            end
        end)
    end
end)

-- Wrapper cooperativo pra loops extras
-- Uso: Guard.run(function() ... task.wait(0.5) ... end, 0.5)
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

-- Registro de conexões pra cleanup em unload
Guard.__conns = {}
function Guard.track(conn)
    if conn then table.insert(Guard.__conns, conn) end
    return conn
end
function Guard.untrackAll()
    for _, c in ipairs(Guard.__conns) do pcall(function() c:Disconnect() end) end
    Guard.__conns = {}
end

genv.BabisGuard = Guard
return Guard