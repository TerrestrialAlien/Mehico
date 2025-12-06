local GameLoopService = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

-- Shared Config
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

-- Events (creating them if they don't exist is safer, but I'll assume they exist or create them)
local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local updateGameStateEvent = eventFolder:WaitForChild("UpdateGameState")
local updateTimerEvent = eventFolder:WaitForChild("UpdateGameTimer")
local intermissionStartedEvent = eventFolder:WaitForChild("IntermissionStarted")
local updateGameMode = eventFolder:WaitForChild("UpdateGameMode")
local updateTeamRosterEvent = eventFolder:WaitForChild("UpdateTeamRoster")

-- State
local currentGameState = ""
local currentStatus = ""
local intermissionTimer = GameConfig.Game.IntermissionTime
local roundTimer = GameConfig.Game.RoundTime
local currentMap = nil

local GamemodeService = nil
local PlayerService = nil

function GameLoopService:Init(services)
    GamemodeService = services.GamemodeService
    PlayerService = services.PlayerService
end

function GameLoopService:Start()
    self:SetGameState("Intermission")

    task.spawn(function()
        while task.wait(1) do
            self:OnGameTick()
        end
    end)

    RunService.Heartbeat:Connect(function(dt)
        self:OnHeartbeat(dt)
    end)

    Players.PlayerRemoving:Connect(function(player)
        if currentGameState == "RoundInProgress" then
            local blueTeam = Teams["Bright blue"]
            local pinkTeam = Teams["Carnation pink"]
            if #blueTeam:GetPlayers() == 0 or #pinkTeam:GetPlayers() == 0 then
                currentStatus = "Round ended - team was empty."
                updateGameStateEvent:FireAllClients("RoundEnd", currentStatus)
                task.delay(3, function() self:SetGameState("Intermission") end)
            end
        end
    end)
end

function GameLoopService:SetGameState(state, winner)
    print("State: " .. state)
    currentGameState = state

    if state == "Intermission" then
        GamemodeService:Cleanup()
        if currentMap then currentMap:Destroy() currentMap = nil end

        workspace.Gravity = 196.2 -- Reset to Base Gravity
        PlayerService:SetGameActive(false) -- Disable tools

        intermissionTimer = GameConfig.Game.IntermissionTime
        currentStatus = "Intermission - Waiting for players..."

        updateGameStateEvent:FireAllClients(state, currentStatus)
        updateTimerEvent:FireAllClients(intermissionTimer)
        updateGameMode:FireAllClients("Intermission")
        updateTeamRosterEvent:FireAllClients(nil)

        PlayerService:ResetAllPlayers()
        intermissionStartedEvent:Fire()

    elseif state == "RoundInProgress" then
        PlayerService:SetGameActive(true) -- Enable tools
        currentMap = GamemodeService:SelectAndLoadMap()
        GamemodeService:StartRound(currentMap)

        roundTimer = GameConfig.Game.RoundTime
        updateGameStateEvent:FireAllClients(state, currentStatus)
        updateTimerEvent:FireAllClients(roundTimer)

    elseif state == "RoundEnd" then
        local winStatus = winner and (winner.Name .. " wins!") or "Round Draw!"
        currentStatus = "Round Over! " .. winStatus
        updateGameStateEvent:FireAllClients(state, currentStatus)

        GamemodeService:OnRoundEnd()

        task.delay(5, function() self:SetGameState("Intermission") end)
    end
end

function GameLoopService:OnGameTick()
    if currentGameState == "Intermission" then
        intermissionTimer = intermissionTimer - 1
        updateTimerEvent:FireAllClients(intermissionTimer)

        if intermissionTimer <= 0 then
            if #Players:GetPlayers() >= 1 then -- MIN_PLAYERS_TO_START
                self:SetGameState("RoundInProgress")
            else
                intermissionTimer = 5
                updateGameStateEvent:FireAllClients("Intermission", "Waiting for players...")
            end
        end

    elseif currentGameState == "RoundInProgress" then
        roundTimer = roundTimer - 1
        updateTimerEvent:FireAllClients(roundTimer)

        PlayerService:UpdatePassivePoints()
        GamemodeService:OnGameTick()

        if roundTimer <= 0 then
            local winner = GamemodeService:CheckWinner()
            self:SetGameState("RoundEnd", winner)
        end
    end
end

function GameLoopService:OnHeartbeat(dt)
    if currentGameState == "RoundInProgress" then
        local winner = GamemodeService:OnHeartbeat(dt)
        if winner then
            self:SetGameState("RoundEnd", winner)
        end
    end
end

return GameLoopService
