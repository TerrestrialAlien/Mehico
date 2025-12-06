local PlayerService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local updatePointsEvent = eventFolder:WaitForChild("UpdatePoints")
local updateTeamRosterEvent = eventFolder:WaitForChild("UpdateTeamRoster")
local requestUpgradeEvent = eventFolder:WaitForChild("RequestUpgrade")
local getUpgradeLevelsEvent = eventFolder:WaitForChild("GetUpgradeLevels")
local showUpgradeGuiEvent = eventFolder:WaitForChild("ShowUpgradeGui")
local updateUpgradeLevelsEvent = eventFolder:WaitForChild("UpdateUpgradeLevels")

local playerData = {}
local teamUpgrades = {}

function PlayerService:Init(services)
    -- Listeners
    requestUpgradeEvent.OnServerEvent:Connect(function(player, upgradeType)
        self:OnRequestUpgrade(player, upgradeType)
    end)

    getUpgradeLevelsEvent.OnServerInvoke = function(player)
        return player.Team and teamUpgrades[player.Team] or nil
    end

    Players.PlayerAdded:Connect(function(player)
        self:OnPlayerAdded(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:OnPlayerRemoving(player)
    end)
end

function PlayerService:Start()
    -- Initialize team upgrades
    local Teams = game:GetService("Teams")
    teamUpgrades[Teams["Bright blue"]] = { Respawn = 0, Health = 0, Speed = 0 }
    teamUpgrades[Teams["Carnation pink"]] = { Respawn = 0, Health = 0, Speed = 0 }
end

function PlayerService:ResetAllPlayers()
    for userId, data in pairs(playerData) do
        data.Points = 0
        data.Kills = 0
        data.Deaths = 0
        data.PassiveTimer = 0
        local p = Players:GetPlayerByUserId(userId)
        if p then updatePointsEvent:FireClient(p, 0) end
    end

     local Teams = game:GetService("Teams")
    teamUpgrades[Teams["Bright blue"]] = { Respawn = 0, Health = 0, Speed = 0 }
    teamUpgrades[Teams["Carnation pink"]] = { Respawn = 0, Health = 0, Speed = 0 }
end

function PlayerService:OnPlayerAdded(player)
    playerData[player.UserId] = { Team = nil, Points = 0, Kills = 0, Deaths = 0, PassiveTimer = 0 }

    player.CharacterAdded:Connect(function(char)
        self:OnCharacterAdded(player, char)
    end)
end

function PlayerService:OnCharacterAdded(player, char)
    local humanoid = char:WaitForChild("Humanoid")
    humanoid.UseJumpPower = true
    humanoid.JumpPower = GameConfig.Game.BaseJumpPower

    if player.Team and teamUpgrades[player.Team] then
        local upgrades = teamUpgrades[player.Team]
        humanoid.MaxHealth = GameConfig.Upgrades.Health.Values[upgrades.Health + 1]
        humanoid.Health = humanoid.MaxHealth
        humanoid.WalkSpeed = GameConfig.Upgrades.Speed.Values[upgrades.Speed + 1]
    end

    updateTeamRosterEvent:FireAllClients(nil, player.UserId, true)

    humanoid.Died:Connect(function()
        self:OnPlayerDied(player)
    end)

    -- Give Loadout
    local starterGear = player:WaitForChild("StarterGear")
    starterGear:ClearAllChildren()
    local toolFolder = game:GetService("ServerStorage"):WaitForChild("Assets"):WaitForChild("GameTools")
    for _, tool in ipairs(toolFolder:GetChildren()) do
        tool:Clone().Parent = starterGear
    end

    -- Here I'll just clone to Backpack if character exists.
    for _, tool in ipairs(toolFolder:GetChildren()) do
        tool:Clone().Parent = player.Backpack
    end
end

function PlayerService:OnPlayerDied(player)
    updateTeamRosterEvent:FireAllClients(nil, player.UserId, false)
    if playerData[player.UserId] then playerData[player.UserId].Deaths = playerData[player.UserId].Deaths + 1 end

    local respawnTime = GameConfig.Game.BaseRespawnTime
    if player.Team and teamUpgrades[player.Team] then
        respawnTime = GameConfig.Upgrades.Respawn.Values[teamUpgrades[player.Team].Respawn + 1]
    end

    task.wait(respawnTime)
    if player then player:LoadCharacter() end
end

function PlayerService:OnPlayerRemoving(player)
    playerData[player.UserId] = nil
end

function PlayerService:UpdatePassivePoints()
    for _, player in ipairs(Players:GetPlayers()) do
        local data = playerData[player.UserId]
        if data then
            data.PassiveTimer = data.PassiveTimer + 1
            if data.PassiveTimer >= GameConfig.Game.PassivePointRate then
                data.PassiveTimer = 0
                data.Points = data.Points + 1
                updatePointsEvent:FireClient(player, data.Points)
            end
        end
    end
end

function PlayerService:AddPoints(player, amount)
    local data = playerData[player.UserId]
    if data then
        data.Points = data.Points + amount
        updatePointsEvent:FireClient(player, data.Points)
    end
end

function PlayerService:GetUpgrades(player)
    return player.Team and teamUpgrades[player.Team] or { Health = 0, Speed = 0, Respawn = 0 }
end

function PlayerService:OnRequestUpgrade(player, upgradeType)
    local data = playerData[player.UserId]
    local team = player.Team
    if not data or not team then return end

    local currentLvl = teamUpgrades[team][upgradeType]
    local config = GameConfig.Upgrades[upgradeType]

    if currentLvl >= #config.Values - 1 then return end -- MaxLevel logic check

    local cost = config.Costs[currentLvl + 1]
    if data.Points >= cost then
        data.Points = data.Points - cost
        teamUpgrades[team][upgradeType] = currentLvl + 1
        local newLvl = teamUpgrades[team][upgradeType]

        updatePointsEvent:FireClient(player, data.Points)
        updateUpgradeLevelsEvent:FireAllClients(team, upgradeType, newLvl)

        -- Apply Immediate Effects
        if upgradeType == "Health" or upgradeType == "Speed" then
            for _, p in ipairs(team:GetPlayers()) do
                if p.Character and p.Character:FindFirstChild("Humanoid") then
                    local h = p.Character.Humanoid
                    if upgradeType == "Health" then
                        h.MaxHealth = config.Values[newLvl + 1]
                        h.Health = h.MaxHealth
                    elseif upgradeType == "Speed" then
                        h.WalkSpeed = config.Values[newLvl + 1]
                    end
                end
            end
        end
    end
end

return PlayerService
