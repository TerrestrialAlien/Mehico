local TerminalFrenzy = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local blueTeam = Teams["Bright blue"]
local pinkTeam = Teams["Carnation pink"]

local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local updateProgressEvent = eventFolder:WaitForChild("UpdateHackProgress")
local updateHackAlertEvent = eventFolder:WaitForChild("UpdateHackAlert")
local revealTerminalEvent = eventFolder:WaitForChild("RevealTerminal")
local updatePointsEvent = eventFolder:WaitForChild("UpdatePoints")
local proximityHighlightGained = eventFolder:WaitForChild("ProximityHighlightGained")
local proximityHighlightLost = eventFolder:WaitForChild("ProximityHighlightLost")

local tf_blueTeamProgress = 0
local tf_pinkTeamProgress = 0
local tf_playersHacking = {}
local tf_playerHackData = {}
local tf_lastBluePercent = -1
local tf_lastPinkPercent = -1
local wasBlueBaseAlertSent = false
local wasPinkBaseAlertSent = false
local mapEventTriggered = false
local terminalRevealCooldowns = {}
local currentMap = nil
local GamemodeService = nil

local PlayerService = nil

function TerminalFrenzy:Init(services)
    PlayerService = services.PlayerService
end

function TerminalFrenzy:Start(map, gamemodeService)
    currentMap = map
    GamemodeService = gamemodeService
    tf_blueTeamProgress = 0
    tf_pinkTeamProgress = 0
    tf_playersHacking = {}
    tf_playerHackData = {}
    wasBlueBaseAlertSent = false
    wasPinkBaseAlertSent = false
    tf_lastBluePercent = -1
    tf_lastPinkPercent = -1
    mapEventTriggered = false
    terminalRevealCooldowns = {}

    currentMap.Terminals.BlueTerminals.BlueSpawn.Enabled = true
    currentMap.Terminals.PinkTerminals.PinkSpawn.Enabled = true

    self:BindTerminals("PinkTerminals", pinkTeam)
    self:BindTerminals("BlueTerminals", blueTeam)
    self:UpdateHoldDurations(blueTeam)
    self:UpdateHoldDurations(pinkTeam)

    updateProgressEvent:FireAllClients(0, 0, GameConfig.TerminalFrenzy.TotalHackPoints)
end

function TerminalFrenzy:Cleanup()
    tf_playersHacking = {}
    tf_playerHackData = {}
end

function TerminalFrenzy:BindTerminals(folderName, teamToHack)
    local f = currentMap.Terminals:FindFirstChild(folderName)
    if f then
        for _, p in ipairs(f:GetChildren()) do
            if (p:IsA("BasePart") or p:IsA("Model")) and not p:IsA("SpawnLocation") then
                local pp = p:FindFirstChildWhichIsA("ProximityPrompt", true)
                if pp then
                    pp.Enabled = true
                    pp.PromptButtonHoldBegan:Connect(function(pl) self:OnHackStarted(pl, p, teamToHack) end)
                    pp.PromptButtonHoldEnded:Connect(function(pl) self:OnHackEnded(pl) end)
                end
            end
        end
    end
end

function TerminalFrenzy:OnHackStarted(player, terminalPart, teamToHack)
    local char = player.Character
    if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then return end

    if player.Team ~= teamToHack then
        tf_playersHacking[player] = terminalPart
        local currentProgress = (teamToHack == blueTeam) and tf_blueTeamProgress or tf_pinkTeamProgress

        local milestone = GameConfig.TerminalFrenzy.TotalHackPoints * GameConfig.TerminalFrenzy.HackMilestonePercent

        tf_playerHackData[player] = {
            nextHackMilestone = math.floor(currentProgress / milestone) * milestone + milestone,
            nextRevealMilestone = math.floor(currentProgress / milestone) * milestone + milestone
        }
    end
end

function TerminalFrenzy:OnHackEnded(player)
    local terminalPart = tf_playersHacking[player]
    if terminalPart then
        local teamToHack = (terminalPart.Parent.Name == "PinkTerminals") and pinkTeam or blueTeam

        -- Tie break logic (simplified)

        tf_playersHacking[player] = nil
        tf_playerHackData[player] = nil
        self:UpdateHoldDurations(teamToHack)
        self:FireTerminalReveal(terminalPart, teamToHack.Name)
    end
end

function TerminalFrenzy:UpdateHoldDurations(teamWhoseTerminalsToUpdate)
    local remainingTime
    local terminalFolder

    if teamWhoseTerminalsToUpdate == blueTeam then
        terminalFolder = currentMap.Terminals.BlueTerminals
        remainingTime = GameConfig.TerminalFrenzy.TotalHackPoints - tf_blueTeamProgress
    else
        terminalFolder = currentMap.Terminals.PinkTerminals
        remainingTime = GameConfig.TerminalFrenzy.TotalHackPoints - tf_pinkTeamProgress
    end

    for _, terminalPart in ipairs(terminalFolder:GetChildren()) do
        if (terminalPart:IsA("BasePart") or terminalPart:IsA("Model")) and not terminalPart:IsA("SpawnLocation") then
            local hackPrompt = terminalPart:FindFirstChildWhichIsA("ProximityPrompt", true)
            if hackPrompt then
                hackPrompt.HoldDuration = math.max(0, remainingTime + 1)
            end
        end
    end
end

function TerminalFrenzy:FireTerminalReveal(terminalPart, teamToHackName)
    local now = os.clock()
    local lastPing = terminalRevealCooldowns[terminalPart]
    if lastPing and (now - lastPing < GameConfig.TerminalFrenzy.RevealCooldown) then return end
    terminalRevealCooldowns[terminalPart] = now
    revealTerminalEvent:FireAllClients(terminalPart, teamToHackName)
end

function TerminalFrenzy:CheckHackMilestones(player, progress, teamToHack)
    local data = tf_playerHackData[player]
    if not data then return end

    local milestoneAmt = GameConfig.TerminalFrenzy.TotalHackPoints * GameConfig.TerminalFrenzy.HackMilestonePercent

    if progress >= data.nextHackMilestone then
        data.nextHackMilestone = data.nextHackMilestone + milestoneAmt
        PlayerService:AddPoints(player, 1)
    end

    if progress >= data.nextRevealMilestone then
        data.nextRevealMilestone = data.nextRevealMilestone + milestoneAmt
        local terminalPart = tf_playersHacking[player]
        if terminalPart then
            self:FireTerminalReveal(terminalPart, teamToHack.Name)
        end
    end
end

function TerminalFrenzy:Update(dt)
    local isBlueBaseBeingHacked = false
    local isPinkBaseBeingHacked = false

    for player, terminalPart in pairs(tf_playersHacking) do
        if player and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
            local teamToHack = terminalPart.Parent.Name == "PinkTerminals" and pinkTeam or blueTeam

            if teamToHack == blueTeam then
                tf_blueTeamProgress = math.min(tf_blueTeamProgress + dt, GameConfig.TerminalFrenzy.TotalHackPoints)
                isBlueBaseBeingHacked = true
                self:CheckHackMilestones(player, tf_blueTeamProgress, blueTeam)
            elseif teamToHack == pinkTeam then
                tf_pinkTeamProgress = math.min(tf_pinkTeamProgress + dt, GameConfig.TerminalFrenzy.TotalHackPoints)
                isPinkBaseBeingHacked = true
                self:CheckHackMilestones(player, tf_pinkTeamProgress, pinkTeam)
            end
        else
            self:OnHackEnded(player)
        end
    end

    local total = GameConfig.TerminalFrenzy.TotalHackPoints
    local bluePct = math.floor((tf_pinkTeamProgress / total) * 100)

    if bluePct ~= tf_lastBluePercent or math.floor((tf_blueTeamProgress/total)*100) ~= tf_lastPinkPercent then
         updateProgressEvent:FireAllClients(tf_pinkTeamProgress, tf_blueTeamProgress, total)
         -- Optimization skipped
    end

    if tf_blueTeamProgress >= total then return pinkTeam end
    if tf_pinkTeamProgress >= total then return blueTeam end

    -- Hack Alert
    if isBlueBaseBeingHacked ~= wasBlueBaseAlertSent then
        updateHackAlertEvent:FireAllClients(blueTeam.TeamColor, pinkTeam.TeamColor, isBlueBaseBeingHacked)
        wasBlueBaseAlertSent = isBlueBaseBeingHacked
    end
    if isPinkBaseBeingHacked ~= wasPinkBaseAlertSent then
        updateHackAlertEvent:FireAllClients(pinkTeam.TeamColor, blueTeam.TeamColor, isPinkBaseBeingHacked)
        wasPinkBaseAlertSent = isPinkBaseBeingHacked
    end

    if not mapEventTriggered then
        if (tf_pinkTeamProgress / total) >= GameConfig.Game.DynamicMapThreshold or
           (tf_blueTeamProgress / total) >= GameConfig.Game.DynamicMapThreshold then
            mapEventTriggered = true
            GamemodeService:TriggerDynamicMapEvents(currentMap)
        end
    end

    return nil -- No winner yet
end

function TerminalFrenzy:CheckWinner()
    if tf_pinkTeamProgress > tf_blueTeamProgress then return blueTeam
    elseif tf_blueTeamProgress > tf_pinkTeamProgress then return pinkTeam end
    return nil
end

function TerminalFrenzy:OnGameTick()
    -- Proximity Highlight
    local players = game.Players:GetPlayers()
    for _, player in ipairs(players) do
        if player.Team and player.Character then
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local enemyFolder = (player.Team == blueTeam) and currentMap.Terminals.PinkTerminals or currentMap.Terminals.BlueTerminals
                for _, term in ipairs(enemyFolder:GetChildren()) do
                    if (term:IsA("BasePart") or term:IsA("Model")) and not term:IsA("SpawnLocation") then
                        local dist = (root.Position - term.Position).Magnitude

                        -- Ideally check PlayerService data for state, but simplified:
                        if dist <= GameConfig.TerminalFrenzy.ProximityRevealRange then
                             proximityHighlightGained:FireClient(player, term)
                        else
                             proximityHighlightLost:FireClient(player, term)
                        end
                    end
                end
            end
        end
    end
end

return TerminalFrenzy
