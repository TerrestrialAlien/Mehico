local ZoneControl = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players") -- Added Players service
local Teams = game:GetService("Teams")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local blueTeam = Teams["Bright blue"]
local pinkTeam = Teams["Carnation pink"]

local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local updateZoneControlUI = eventFolder:WaitForChild("UpdateZoneControlUI")
local updateZoneCountdown = eventFolder:WaitForChild("UpdateZoneCountdown")
local zoneAlertEvent = eventFolder:WaitForChild("ZoneAlert")
local updateZoneEffect = eventFolder:WaitForChild("UpdateZoneEffect")

local zc_pole1, zc_pole2
local zc_pole1Owner, zc_pole2Owner
local zc_blueProgress = 0
local zc_pinkProgress = 0
local zc_currentEffect = nil
local zc_zone = nil
local zc_fogEmitter = nil
local zc_playersInZone = {}
local zc_damageTimer = 0
local zc_zoneCheckTimer = 0
local mapEventTriggered = false
local GamemodeService = nil

local zc_bluePenalty = 0
local zc_pinkPenalty = 0
local zc_lastZoneOwner = nil
local zc_blueStartStats = { score = 0, penalty = 0, opponentScore = 0 }
local zc_pinkStartStats = { score = 0, penalty = 0, opponentScore = 0 }

local ZC_EFFECTS_LIST = {
	"Low Gravity",
	"Speed Boost",
	"Low Health",
	"Burning Ground",
	"High Jump",
	"Fog"
}

local PlayerService = nil

function ZoneControl:Init(services)
	PlayerService = services.PlayerService
end

function ZoneControl:CalculateZonePenalty(startStats, currentScore, currentPenalty)
	local target = GameConfig.ZoneControl.TargetPoints
	local startRem = (target - startStats.score) + (startStats.penalty or 0)
	local endRem = (target - currentScore) + (currentPenalty or 0)

	if startStats.score < (startStats.opponentScore or 0) and currentScore >= (startStats.opponentScore or 0) then
		endRem = (target - startStats.opponentScore) + (currentPenalty or 0)
	end

	local delta = startRem - endRem
	if delta <= 0 then return 0 end

	local penalty = math.floor((0.75 * delta) + 0.5)
	if math.abs(startRem - target) < 1e-6 then
		penalty = penalty + 1
	end
	return penalty
end

function ZoneControl:ApplyZoneEffect(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	self:ResetZoneEffect(player)
	if not zc_currentEffect then return end

	if zc_currentEffect == "Speed Boost" then
		humanoid.WalkSpeed = 40
	elseif zc_currentEffect == "Low Health" then
		humanoid.MaxHealth = 75
		if humanoid.Health > 75 then humanoid.Health = 75 end
	elseif zc_currentEffect == "High Jump" then
		humanoid.JumpPower = GameConfig.Game.BaseJumpPower * 2.5
	elseif zc_currentEffect == "Low Gravity" then
		workspace.Gravity = workspace.Gravity * 0.35
		humanoid.JumpPower = GameConfig.Game.BaseJumpPower * 1.5
	end
end

function ZoneControl:ResetZoneEffect(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local team = player.Team
	local upgrades = PlayerService and PlayerService:GetUpgrades(player) or { Health = 0, Speed = 0 }

	local baseHealth = GameConfig.Upgrades.Health.Values[(upgrades.Health or 0) + 1]
	local baseSpeed = GameConfig.Upgrades.Speed.Values[(upgrades.Speed or 0) + 1]

	humanoid.UseJumpPower = true
	humanoid.MaxHealth = baseHealth
	humanoid.WalkSpeed = baseSpeed
	humanoid.JumpPower = GameConfig.Game.BaseJumpPower
	workspace.Gravity = 196.2 

	if humanoid.Health > baseHealth then humanoid.Health = baseHealth end
end

function ZoneControl:Start(map, gamemodeService)
	GamemodeService = gamemodeService
	zc_pole1 = map.ZonePoles:WaitForChild("Pole1")
	zc_pole2 = map.ZonePoles:WaitForChild("Pole2")

	zc_pole1Owner = nil
	zc_pole2Owner = nil
	zc_blueProgress = 0
	zc_pinkProgress = 0
	zc_currentEffect = nil
	zc_zone = map:FindFirstChild("Zone")
	zc_playersInZone = {}
	mapEventTriggered = false

	local fogPart = map:FindFirstChild("Fog")
	if fogPart then
		zc_fogEmitter = fogPart:FindFirstChildWhichIsA("ParticleEmitter", true)
		if zc_fogEmitter then zc_fogEmitter.Enabled = false end
	end

	local p1 = zc_pole1:FindFirstChildWhichIsA("ProximityPrompt")
	local p2 = zc_pole2:FindFirstChildWhichIsA("ProximityPrompt")

	p1.HoldDuration = GameConfig.ZoneControl.CaptureTime
	p2.HoldDuration = GameConfig.ZoneControl.CaptureTime

	p1.Triggered:Connect(function(p) self:OnPoleCaptured(p, 1) end)
	p2.Triggered:Connect(function(p) self:OnPoleCaptured(p, 2) end)

	updateZoneControlUI:FireAllClients(zc_pole1, nil, zc_pole2, nil)
	updateZoneCountdown:FireAllClients(0, 0, GameConfig.ZoneControl.TargetPoints)
	updateZoneEffect:FireAllClients(nil)
end

function ZoneControl:Cleanup()
	zc_playersInZone = {}
end

function ZoneControl:OnPoleCaptured(player, poleNumber)
	if not player.Team then return end
	local team = player.Team
	local prevBlueHasBoth = (zc_pole1Owner == blueTeam and zc_pole2Owner == blueTeam)
	local prevPinkHasBoth = (zc_pole1Owner == pinkTeam and zc_pole2Owner == pinkTeam)

	if poleNumber == 1 then
		if zc_pole1Owner == team then return end
		zc_pole1Owner = team
	elseif poleNumber == 2 then
		if zc_pole2Owner == team then return end
		zc_pole2Owner = team
	end

	local newBlueHasBoth = (zc_pole1Owner == blueTeam and zc_pole2Owner == blueTeam)
	local newPinkHasBoth = (zc_pole1Owner == pinkTeam and zc_pole2Owner == pinkTeam)
	local alertType = "OnePole"
	local justGotBoth = false

	if newBlueHasBoth and not prevBlueHasBoth then
		justGotBoth = true
		alertType = "BothPoles"
		if zc_lastZoneOwner == "Pink" then
			local penalty = self:CalculateZonePenalty(zc_pinkStartStats, zc_pinkProgress, zc_pinkPenalty)
			if penalty > 0 then zc_pinkPenalty = zc_pinkPenalty + penalty end
		end
		zc_lastZoneOwner = "Blue"
		zc_blueStartStats = { score = zc_blueProgress, penalty = zc_bluePenalty, opponentScore = zc_pinkProgress }
	end

	if newPinkHasBoth and not prevPinkHasBoth then
		justGotBoth = true
		alertType = "BothPoles"
		if zc_lastZoneOwner == "Blue" then
			local penalty = self:CalculateZonePenalty(zc_blueStartStats, zc_blueProgress, zc_bluePenalty)
			if penalty > 0 then zc_bluePenalty = zc_bluePenalty + penalty end
		end
		zc_lastZoneOwner = "Pink"
		zc_pinkStartStats = { score = zc_pinkProgress, penalty = zc_pinkPenalty, opponentScore = zc_blueProgress }
	end

	updateZoneControlUI:FireAllClients(zc_pole1, zc_pole1Owner, zc_pole2, zc_pole2Owner)
	zoneAlertEvent:FireAllClients(alertType, team)

	if justGotBoth then
		zc_currentEffect = ZC_EFFECTS_LIST[math.random(1, #ZC_EFFECTS_LIST)]
		updateZoneEffect:FireAllClients(zc_currentEffect)
		if zc_currentEffect == "Fog" and zc_fogEmitter then zc_fogEmitter.Enabled = true end
	elseif zc_pole1Owner ~= zc_pole2Owner and zc_currentEffect then
		if zc_fogEmitter then zc_fogEmitter.Enabled = false end
		zc_currentEffect = nil
		updateZoneEffect:FireAllClients(nil)
	end
end

function ZoneControl:Update(dt)
	local blueHasBoth = (zc_pole1Owner == blueTeam and zc_pole2Owner == blueTeam)
	local pinkHasBoth = (zc_pole1Owner == pinkTeam and zc_pole2Owner == pinkTeam)

	if blueHasBoth then
		if zc_bluePenalty > 0 then
			zc_bluePenalty = math.max(0, zc_bluePenalty - (dt * 2))
		else
			zc_blueProgress = math.min(GameConfig.ZoneControl.TargetPoints, zc_blueProgress + dt)
		end
	end
	if pinkHasBoth then
		if zc_pinkPenalty > 0 then
			zc_pinkPenalty = math.max(0, zc_pinkPenalty - (dt * 2))
		else
			zc_pinkProgress = math.min(GameConfig.ZoneControl.TargetPoints, zc_pinkProgress + dt)
		end
	end

	updateZoneCountdown:FireAllClients(zc_blueProgress, zc_pinkProgress, GameConfig.ZoneControl.TargetPoints, math.ceil(zc_bluePenalty), math.ceil(zc_pinkPenalty))

	if zc_blueProgress >= GameConfig.ZoneControl.TargetPoints then return blueTeam end
	if zc_pinkProgress >= GameConfig.ZoneControl.TargetPoints then return pinkTeam end

	if zc_zone then
		zc_zoneCheckTimer = zc_zoneCheckTimer + dt
		if zc_zoneCheckTimer >= 0.1 then -- ZC_ZONE_CHECK_INTERVAL
			zc_zoneCheckTimer = 0

			local playersInZoneNow = {}
			local partsInZone = workspace:GetPartsInPart(zc_zone)

			for _, part in ipairs(partsInZone) do
				local player = Players:GetPlayerFromCharacter(part.Parent)
				if player and not playersInZoneNow[player] then
					playersInZoneNow[player] = true
					if not zc_playersInZone[player] then
						zc_playersInZone[player] = true
						self:ApplyZoneEffect(player)
					end
				end
			end

			for player, _ in pairs(zc_playersInZone) do
				if not playersInZoneNow[player] then
					zc_playersInZone[player] = nil
					self:ResetZoneEffect(player)
				end
			end
		end
	end

	if zc_currentEffect == "Burning Ground" then
		zc_damageTimer = zc_damageTimer + dt
		if zc_damageTimer >= GameConfig.ZoneControl.DamageTick then
			zc_damageTimer = 0
			for player, _ in pairs(zc_playersInZone) do
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					player.Character.Humanoid:TakeDamage(GameConfig.ZoneControl.DamageAmount)
				end
			end
		end
	end

	if not mapEventTriggered then
		if (zc_blueProgress / GameConfig.ZoneControl.TargetPoints) >= GameConfig.Game.DynamicMapThreshold or 
			(zc_pinkProgress / GameConfig.ZoneControl.TargetPoints) >= GameConfig.Game.DynamicMapThreshold then
			mapEventTriggered = true
			GamemodeService:TriggerDynamicMapEvents(zc_pole1.Parent.Parent)
		end
	end

	return nil
end

function ZoneControl:CheckWinner()
	if zc_blueProgress > zc_pinkProgress then return blueTeam
	elseif zc_pinkProgress > zc_blueProgress then return pinkTeam end
	return nil
end

return ZoneControl
