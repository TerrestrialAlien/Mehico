local InterfaceController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Teams = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")

local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")

-- --- GUI OBJECTS ---
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameGui = playerGui:WaitForChild("GameGui")

-- Progress Bar UI
local HackProgressFrame = GameGui:WaitForChild("HackProgressFrame")
local BlueBarBG = HackProgressFrame:WaitForChild("BlueBarBG")
local BlueProgress = BlueBarBG:WaitForChild("BlueProgress")
local BluePercentLabel = BlueBarBG:WaitForChild("BluePercentLabel")
local BluePercentFrame = BluePercentLabel:WaitForChild("Frame")
local PinkBarBG = HackProgressFrame:WaitForChild("PinkBarBG")
local PinkProgress = PinkBarBG:WaitForChild("PinkProgress")
local PinkPercentLabel = PinkBarBG:WaitForChild("PinkPercentLabel")
local PinkPercentFrame = PinkPercentLabel:WaitForChild("Frame")

-- Avatar Containers
local BlueAvatarContainer = BlueBarBG:WaitForChild("BlueAvatarContainer")
local PinkAvatarContainer = PinkBarBG:WaitForChild("PinkAvatarContainer")
local PlayerAvatarTemplate = HackProgressFrame:WaitForChild("PlayerAvatarTemplate")

-- Player Info & Status UI
local PlayerInfoFrame = GameGui:WaitForChild("PlayerInfoFrame")
local StatusLabel = PlayerInfoFrame:WaitForChild("StatusLabel")
local TimerLabel = PlayerInfoFrame:WaitForChild("TimerLabel")
local PointsLabel = PlayerInfoFrame:WaitForChild("PointsLabel")
local MapChangeSound = PlayerInfoFrame:WaitForChild("MapChangeSound")
local MapRumbleSound = PlayerInfoFrame:WaitForChild("MapRumbleSound")
local HackAlertSound = PlayerInfoFrame:WaitForChild("HackAlertSound")
local HackStopSound = PlayerInfoFrame:WaitForChild("HackStopSound")
local ZoneAlertOnePoleSound = PlayerInfoFrame:WaitForChild("ZoneAlertOnePoleSound")
local ZoneAlertBothPolesSound = PlayerInfoFrame:WaitForChild("ZoneAlertBothPolesSound")

-- Zone Control Icons
local PoleIcon1 = PlayerInfoFrame:WaitForChild("PoleIcon1")
local PoleIcon2 = PlayerInfoFrame:WaitForChild("PoleIcon2")

-- Health GUI
local HealthBarGui = playerGui:WaitForChild("PlayerHealthGui")
local HealthBarFrame = HealthBarGui:WaitForChild("HealthBarFrame")
local BarForeground = HealthBarFrame:WaitForChild("BarBackground"):WaitForChild("BarForeground")
local HealthText = HealthBarFrame:WaitForChild("HealthText")

-- Upgrade GUI
local UpgradeGui = playerGui:WaitForChild("UpgradeGui")
local MainFrame = UpgradeGui:WaitForChild("MainFrame")
local CloseButton = MainFrame:WaitForChild("CloseButton")
local UpgradesContainer = MainFrame:WaitForChild("UpgradesContainer")
local HealthFrame = UpgradesContainer:WaitForChild("HealthFrame")
local SpeedFrame = UpgradesContainer:WaitForChild("SpeedFrame")
local RespawnFrame = UpgradesContainer:WaitForChild("RespawnFrame")

-- Assets
local stunEffectTemplate = ReplicatedStorage:WaitForChild("StunStars", 2)

-- --- LOCAL CACHE & STATE ---
local playerAvatarCache = {}
local proximityHighlights = {}
local blueTeam = Teams["Bright blue"]
local pinkTeam = Teams["Carnation pink"]

local currentGamemode = ""
local currentGameState = ""
local defaultStatusText = "Waiting for players..."
local activeAlert = false
local currentAlertId = 0
local HACK_WOBBLE_TIME = 0.8
local HACK_TWEEN_INFO_RESET = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local blueHackThread = nil
local pinkHackThread = nil

local NUMBER_TWEEN_DURATION = 0.45
local BAR_TWEEN_DURATION = 0.45

local displayedBlueFraction = 0
local displayedPinkFraction = 0
local displayedBluePercentValue = 0
local displayedPinkPercentValue = 0

local activeBlueBarTween = nil
local activePinkBarTween = nil
local DEFAULT_PERCENT_FRAME_COLOR = Color3.fromRGB(27, 42, 53)

-- Zone Visuals State
local isInitialized = false
local zoneBase = nil
local zoneRing = nil
local rings = {}
local bobTweens = {}
local activeRiseTweens = {}
local TWEEN_RISE = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SINK = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HIDDEN_OFFSET = 20

-- Upgrade State
local currentPoints = 0
local currentLevels = { Health = 0, Speed = 0, Respawn = 0 }
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local UPGRADE_CONFIG = GameConfig.Upgrades

function InterfaceController:Init(controllers)
end

function InterfaceController:Start()
    -- Event Listeners
    local updateTimerEvent = eventFolder:WaitForChild("UpdateGameTimer")
    updateTimerEvent.OnClientEvent:Connect(function(s) self:OnUpdateTimer(s) end)

    local updateGameStateEvent = eventFolder:WaitForChild("UpdateGameState")
    updateGameStateEvent.OnClientEvent:Connect(function(s, stat) self:OnUpdateGameState(s, stat) end)

    local updateTeamRosterEvent = eventFolder:WaitForChild("UpdateTeamRoster")
    updateTeamRosterEvent.OnClientEvent:Connect(function(r, id, alive) self:OnUpdateTeamRoster(r, id, alive) end)

    local playerSyncEvent = eventFolder:WaitForChild("PlayerSync")
    playerSyncEvent.OnClientEvent:Connect(function(...) self:OnPlayerSync(...) end)

    local updatePointsEvent = eventFolder:WaitForChild("UpdatePoints")
    updatePointsEvent.OnClientEvent:Connect(function(p) self:OnUpdatePoints(p) end)

    local updateHackAlertEvent = eventFolder:WaitForChild("UpdateHackAlert")
    updateHackAlertEvent.OnClientEvent:Connect(function(...) self:OnHackAlert(...) end)

    local triggerMapAlertEvent = eventFolder:WaitForChild("TriggerMapAlert")
    triggerMapAlertEvent.OnClientEvent:Connect(function() self:OnMapAlert() end)

    local revealTerminalEvent = eventFolder:WaitForChild("RevealTerminal")
    revealTerminalEvent.OnClientEvent:Connect(function(...) self:OnRevealTerminal(...) end)

    local proximityHighlightGained = eventFolder:WaitForChild("ProximityHighlightGained")
    proximityHighlightGained.OnClientEvent:Connect(function(t) self:OnProximityGained(t) end)

    local proximityHighlightLost = eventFolder:WaitForChild("ProximityHighlightLost")
    proximityHighlightLost.OnClientEvent:Connect(function(t) self:OnProximityLost(t) end)

    local updateGameMode = eventFolder:WaitForChild("UpdateGameMode")
    updateGameMode.OnClientEvent:Connect(function(m) self:OnUpdateGameMode(m) end)

    local updateZoneControlUI = eventFolder:WaitForChild("UpdateZoneControlUI")
    updateZoneControlUI.OnClientEvent:Connect(function(...) self:OnUpdateZoneUI(...) end)

    local zoneAlertEvent = eventFolder:WaitForChild("ZoneAlert")
    zoneAlertEvent.OnClientEvent:Connect(function(...) self:OnZoneAlert(...) end)

    local updateProgressEvent = eventFolder:WaitForChild("UpdateHackProgress")
    updateProgressEvent.OnClientEvent:Connect(function(...)
        if currentGamemode == "TerminalFrenzy" then self:OnUpdateProgress(...) end
    end)

    local updateZoneCountdown = eventFolder:WaitForChild("UpdateZoneCountdown")
    updateZoneCountdown.OnClientEvent:Connect(function(...)
        if currentGamemode == "ZoneControl" then self:OnUpdateZoneCountdown(...) end
    end)

    local updateZoneEffect = eventFolder:WaitForChild("UpdateZoneEffect")
    updateZoneEffect.OnClientEvent:Connect(function(e) self:ShowZoneEffect(e) end)

    local playerStunnedEvent = eventFolder:WaitForChild("PlayerStunned")
    playerStunnedEvent.OnClientEvent:Connect(function(p, d)
        if p then self:ShowStunVisual(p.Character, d) end
    end)

    local showUpgradeGuiEvent = eventFolder:WaitForChild("ShowUpgradeGui")
    showUpgradeGuiEvent.OnClientEvent:Connect(function() self:ShowUpgradeGui(true) end)

    local updateUpgradeLevelsEvent = eventFolder:WaitForChild("UpdateUpgradeLevels")
    updateUpgradeLevelsEvent.OnClientEvent:Connect(function(t, type, lvl) self:OnUpgradeLevelsChanged(t, type, lvl) end)

    -- Set default rotations
    BluePercentLabel.Rotation = -2
    PinkPercentLabel.Rotation = 2
    BluePercentFrame.BackgroundColor3 = DEFAULT_PERCENT_FRAME_COLOR
    PinkPercentFrame.BackgroundColor3 = DEFAULT_PERCENT_FRAME_COLOR

    -- Health Bar Setup
    if player.Character then self:OnCharacterAdded(player.Character) end
    player.CharacterAdded:Connect(function(char) self:OnCharacterAdded(char) end)

    -- Upgrade GUI Setup
    CloseButton.MouseButton1Click:Connect(function() self:ShowUpgradeGui(false) end)
    HealthFrame:WaitForChild("UpgradeButton").MouseButton1Click:Connect(function() self:OnUpgradeClicked("Health") end)
    SpeedFrame:WaitForChild("UpgradeButton").MouseButton1Click:Connect(function() self:OnUpgradeClicked("Speed") end)
    RespawnFrame:WaitForChild("UpgradeButton").MouseButton1Click:Connect(function() self:OnUpgradeClicked("Respawn") end)

    print("InterfaceController Started")
end

-- ===================================================================
-- Character & Health
-- ===================================================================

function InterfaceController:OnCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    self:UpdateHealthBar(hum)
    hum.HealthChanged:Connect(function() self:UpdateHealthBar(hum) end)
    hum:GetPropertyChangedSignal("MaxHealth"):Connect(function() self:UpdateHealthBar(hum) end)

    hum.Running:Connect(function(speed)
        if speed > 0.1 and MainFrame.Visible then self:ShowUpgradeGui(false) end
    end)
end

function InterfaceController:UpdateHealthBar(humanoid)
    local currentHealth = math.floor(humanoid.Health)
    local maxHealth = math.floor(humanoid.MaxHealth)
    HealthText.Text = currentHealth .. " / " .. maxHealth
    local percent = currentHealth / maxHealth
    BarForeground.Size = UDim2.new(percent, 0, 1, 0)
end

-- ===================================================================
-- Upgrade Shop
-- ===================================================================

function InterfaceController:ShowUpgradeGui(show)
    if show then
        self:RefreshAllUpgrades()
        MainFrame.Visible = true
    else
        MainFrame.Visible = false
    end
end

function InterfaceController:RefreshAllUpgrades()
    local getUpgradeLevelsEvent = eventFolder:WaitForChild("GetUpgradeLevels")
    local success, levels = pcall(getUpgradeLevelsEvent.InvokeServer, getUpgradeLevelsEvent)

    if success and levels then
        currentLevels = levels
        self:UpdateUpgradeRow(HealthFrame, "Health", levels.Health)
        self:UpdateUpgradeRow(SpeedFrame, "Speed", levels.Speed)
        self:UpdateUpgradeRow(RespawnFrame, "Respawn", levels.Respawn)
    end
end

function InterfaceController:UpdateUpgradeRow(frame, upgradeType, level)
    local config = UPGRADE_CONFIG[upgradeType]
    -- UpgradeConfig structure: { Costs = {}, Values = {}, MaxLevel = 3, Suffix = "" }
    -- Wait, Config in GameConfig has Values and Costs, but need to check structure compatibility.
    -- GameConfig.Upgrades = { Health = { Costs={2,3,5}, Values={100,105...} } }
    -- Suffix is not in GameConfig. I need to handle it or add it.
    -- Original UpgradeGuiClient had Suffix. I'll add logic.
    local suffix = ""
    if upgradeType == "Health" then suffix = " HP"
    elseif upgradeType == "Speed" then suffix = " Speed"
    elseif upgradeType == "Respawn" then suffix = "s Respawn" end

    local levelLabel = frame:WaitForChild("LevelLabel")
    local costLabel = frame:WaitForChild("CostLabel")
    local button = frame:WaitForChild("UpgradeButton")

    -- Max Level check. In GameConfig costs array size implies levels.
    -- Assuming max level is number of costs.
    local maxLevel = #config.Costs
    -- Or manual check? Original code had MaxLevel = 3.

    if level >= maxLevel then
        levelLabel.Text = config.Values[level + 1] .. suffix
        costLabel.Text = "MAX LEVEL"
        button.Text = "MAX"
        button.Active = false
    else
        local currentVal = config.Values[level + 1]
        local nextVal = config.Values[level + 2]
        local cost = config.Costs[level + 1]

        levelLabel.Text = currentVal .. " -> " .. nextVal .. suffix
        costLabel.Text = "Cost: " .. cost .. " Pt"
        button.Text = "UPGRADE"
        button.Active = (currentPoints >= cost)
    end
end

function InterfaceController:OnUpgradeClicked(upgradeType)
    local button = UpgradesContainer[upgradeType .. "Frame"]:WaitForChild("UpgradeButton")
    button.Active = false
    button.Text = "..."

    local requestUpgradeEvent = eventFolder:WaitForChild("RequestUpgrade")
    requestUpgradeEvent:FireServer(upgradeType)
    task.wait(0.5)
    self:RefreshAllUpgrades()
end

function InterfaceController:OnUpgradeLevelsChanged(team, upgradeType, newLevel)
    if player.Team == team then
        currentLevels[upgradeType] = newLevel
        self:RefreshAllUpgrades()
    end
end

-- ===================================================================
-- Zone Visuals
-- ===================================================================

function InterfaceController:StopBobbingAnimations()
    for _, tween in pairs(bobTweens) do tween:Cancel() end
    bobTweens = {}
end

function InterfaceController:StopRiseAnimations()
    for _, tween in pairs(activeRiseTweens) do tween:Cancel() end
    activeRiseTweens = {}
end

function InterfaceController:StartBobbingAnimations()
    self:StopBobbingAnimations()
    for _, ringData in ipairs(rings) do
        local part = ringData.part
        local risenCFrame = ringData.risenCFrame
        local bobUp = risenCFrame * CFrame.new(0, 1, 0)
        task.wait(math.random() * 0.5)

        local TWEEN_BOB = TweenInfo.new(2.0 + (math.random() * 1.0), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
        local tweenUp = TweenService:Create(part, TWEEN_BOB, { CFrame = bobUp })
        bobTweens[part] = tweenUp
        tweenUp:Play()
    end
end

function InterfaceController:AnimateRings(targetState, team, baseColor)
    self:StopRiseAnimations()
    self:StopBobbingAnimations()

    local ringColor = Color3.new(1, 1, 1)
    if team == blueTeam then ringColor = blueTeam.TeamColor.Color
    elseif team == pinkTeam then ringColor = pinkTeam.TeamColor.Color end

    if targetState == "Risen" then
        for _, ringData in ipairs(rings) do
            local part = ringData.part
            part.Color = ringColor
            local riseTween = TweenService:Create(part, TWEEN_RISE, { CFrame = ringData.risenCFrame })
            table.insert(activeRiseTweens, riseTween)
            riseTween:Play()
        end
        task.wait(TWEEN_RISE.Time)
        self:StartBobbingAnimations()

        if zoneBase then TweenService:Create(zoneBase, TWEEN_RISE, { Color = ringColor }):Play() end
        if zoneRing then TweenService:Create(zoneRing, TWEEN_RISE, { Color = ringColor }):Play() end

    elseif targetState == "Hidden" then
        for _, ringData in ipairs(rings) do
            local part = ringData.part
            local sinkTween = TweenService:Create(part, TWEEN_SINK, { CFrame = ringData.originalCFrame })
            table.insert(activeRiseTweens, sinkTween)
            sinkTween:Play()
        end
        task.wait(TWEEN_SINK.Time)
        for _, ringData in ipairs(rings) do ringData.part.Color = ringColor end

        if zoneBase then TweenService:Create(zoneBase, TWEEN_SINK, { Color = baseColor }):Play() end
        if zoneRing then TweenService:Create(zoneRing, TWEEN_SINK, { Color = baseColor }):Play() end
    end
end

-- ===================================================================
-- ProgressGuiClient Logic
-- ===================================================================

function InterfaceController:SafeCancelTween(tween)
    if tween then pcall(function() tween:Cancel() end) end
end

function InterfaceController:TweenProgressBar(targetGuiObject, targetFraction, duration)
    local targetUDim = UDim2.new(math.clamp(targetFraction, 0, 1), 0, 1, 0)
    local ti = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(targetGuiObject, ti, {Size = targetUDim})
    tween:Play()
    return tween
end

function InterfaceController:TweenNumber(fromValue, toValue, duration, updateFunc)
    local start = tick()
    local finish = start + duration
    task.spawn(function()
        while true do
            local now = tick()
            local alpha = 1
            if finish > start then
                alpha = math.clamp((now - start) / duration, 0, 1)
            end
            local value = fromValue + (toValue - fromValue) * alpha
            updateFunc(value)
            if alpha >= 1 then break end
            task.wait()
        end
    end)
end

function InterfaceController:FormatPercentText(percentVal, penalty)
    local base = string.format("%.0f%%", percentVal)
    if penalty and penalty > 0 then
        return base .. " (+" .. tostring(penalty) .. ")"
    end
    return base
end

function InterfaceController:SetPercentFrameColor(frame, color)
    local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(frame, ti, { BackgroundColor3 = color }):Play()
end

function InterfaceController:OnUpdateProgress(blueProg, pinkProg, maxProg)
    local blueFraction = 0
    if maxProg > 0 then blueFraction = blueProg / maxProg end
    local pinkFraction = 0
    if maxProg > 0 then pinkFraction = pinkProg / maxProg end

    if activeBlueBarTween then self:SafeCancelTween(activeBlueBarTween) end
    activeBlueBarTween = self:TweenProgressBar(BlueProgress, blueFraction, BAR_TWEEN_DURATION)

    if activePinkBarTween then self:SafeCancelTween(activePinkBarTween) end
    activePinkBarTween = self:TweenProgressBar(PinkProgress, pinkFraction, BAR_TWEEN_DURATION)

    local oldBluePerc = displayedBluePercentValue
    local newBluePerc = (blueFraction * 100)
    self:TweenNumber(oldBluePerc, newBluePerc, NUMBER_TWEEN_DURATION, function(val)
        displayedBluePercentValue = val
        BluePercentLabel.Text = self:FormatPercentText(val, 0)
    end)

    local oldPinkPerc = displayedPinkPercentValue
    local newPinkPerc = (pinkFraction * 100)
    self:TweenNumber(oldPinkPerc, newPinkPerc, NUMBER_TWEEN_DURATION, function(val)
        displayedPinkPercentValue = val
        PinkPercentLabel.Text = self:FormatPercentText(val, 0)
    end)

    displayedBlueFraction = blueFraction
    displayedPinkFraction = pinkFraction
end

function InterfaceController:OnUpdateZoneCountdown(blueProg, pinkProg, maxProg, bluePenalty, pinkPenalty)
    bluePenalty = bluePenalty or 0
    pinkPenalty = pinkPenalty or 0

    local blueFraction = 0
    if maxProg > 0 then blueFraction = blueProg / maxProg end
    local pinkFraction = 0
    if maxProg > 0 then pinkFraction = pinkProg / maxProg end

    if activeBlueBarTween then self:SafeCancelTween(activeBlueBarTween) end
    activeBlueBarTween = self:TweenProgressBar(BlueProgress, blueFraction, BAR_TWEEN_DURATION)

    if activePinkBarTween then self:SafeCancelTween(activePinkBarTween) end
    activePinkBarTween = self:TweenProgressBar(PinkProgress, pinkFraction, BAR_TWEEN_DURATION)

    local oldBluePerc = displayedBluePercentValue
    local newBluePerc = (blueFraction * 100)
    self:TweenNumber(oldBluePerc, newBluePerc, NUMBER_TWEEN_DURATION, function(val)
        displayedBluePercentValue = val
        BluePercentLabel.Text = self:FormatPercentText(val, bluePenalty)
    end)

    local oldPinkPerc = displayedPinkPercentValue
    local newPinkPerc = (pinkFraction * 100)
    self:TweenNumber(oldPinkPerc, newPinkPerc, NUMBER_TWEEN_DURATION, function(val)
        displayedPinkPercentValue = val
        PinkPercentLabel.Text = self:FormatPercentText(val, pinkPenalty)
    end)

    displayedBlueFraction = blueFraction
    displayedPinkFraction = pinkFraction
end

function InterfaceController:OnUpdateZoneUI(pole1, pole1Owner, pole2, pole2Owner)
    if pole1Owner == blueTeam then
        PoleIcon1.BackgroundColor3 = blueTeam.TeamColor.Color
    elseif pole1Owner == pinkTeam then
        PoleIcon1.BackgroundColor3 = pinkTeam.TeamColor.Color
    else
        PoleIcon1.BackgroundColor3 = Color3.new(45/255, 45/255, 45/255)
    end

    if pole2Owner == blueTeam then
        PoleIcon2.BackgroundColor3 = blueTeam.TeamColor.Color
    elseif pole2Owner == pinkTeam then
        PoleIcon2.BackgroundColor3 = pinkTeam.TeamColor.Color
    else
        PoleIcon2.BackgroundColor3 = Color3.new(45/255, 45/255, 45/255)
    end

    if pole1 and pole1:FindFirstChild("GlowPart") then
        pole1.GlowPart.BrickColor = pole1Owner and pole1Owner.TeamColor or BrickColor.new("White")
    end
    if pole2 and pole2:FindFirstChild("GlowPart") then
        pole2.GlowPart.BrickColor = pole2Owner and pole2Owner.TeamColor or BrickColor.new("White")
    end

    if pole1Owner == blueTeam and pole2Owner == blueTeam then
        if not blueHackThread then
            blueHackThread = task.spawn(function()
                while true do
                    BluePercentLabel.Rotation = 10
                    task.wait(HACK_WOBBLE_TIME)
                    BluePercentLabel.Rotation = -10
                    task.wait(HACK_WOBBLE_TIME)
                end
            end)
        end
    else
        if blueHackThread then
            task.cancel(blueHackThread)
            blueHackThread = nil
            TweenService:Create(BluePercentLabel, HACK_TWEEN_INFO_RESET, {Rotation = -2}):Play()
        end
    end

    if pole1Owner == pinkTeam and pole2Owner == pinkTeam then
        if not pinkHackThread then
            pinkHackThread = task.spawn(function()
                while true do
                    PinkPercentLabel.Rotation = 10
                    task.wait(HACK_WOBBLE_TIME)
                    PinkPercentLabel.Rotation = -10
                    task.wait(HACK_WOBBLE_TIME)
                end
            end)
        end
    else
        if pinkHackThread then
            task.cancel(pinkHackThread)
            pinkHackThread = nil
            TweenService:Create(PinkPercentLabel, HACK_TWEEN_INFO_RESET, {Rotation = 2}):Play()
        end
    end

    local blueHasBoth = (pole1Owner == blueTeam and pole2Owner == blueTeam)
    local pinkHasBoth = (pole1Owner == pinkTeam and pole2Owner == pinkTeam)

    if blueHasBoth then
        self:SetPercentFrameColor(BluePercentFrame, blueTeam.TeamColor.Color)
        self:SetPercentFrameColor(PinkPercentFrame, DEFAULT_PERCENT_FRAME_COLOR)
    elseif pinkHasBoth then
        self:SetPercentFrameColor(PinkPercentFrame, pinkTeam.TeamColor.Color)
        self:SetPercentFrameColor(BluePercentFrame, DEFAULT_PERCENT_FRAME_COLOR)
    else
        self:SetPercentFrameColor(BluePercentFrame, DEFAULT_PERCENT_FRAME_COLOR)
        self:SetPercentFrameColor(PinkPercentFrame, DEFAULT_PERCENT_FRAME_COLOR)
    end

    -- Zone Visuals Logic Hook
    if not isInitialized and currentGamemode == "ZoneControl" and pole1 then
        local map = pole1:FindFirstAncestor("CurrentMap")
        if map then
            local visuals = map:FindFirstChild("ZoneVisuals")
            if visuals then
                zoneBase = visuals:FindFirstChild("BasePlatform")
                zoneRing = visuals:FindFirstChild("BaseZone")
                local ringsFolder = visuals:FindFirstChild("Rings")

                if ringsFolder then
                     local basePlatformY = zoneBase and zoneBase.Position.Y or 0

                     for _, part in ipairs(ringsFolder:GetChildren()) do
                        if part:IsA("BasePart") then
                            local risenCFrame = part.CFrame
                            local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = risenCFrame:GetComponents()
                            local hiddenCFrame = CFrame.new(x, basePlatformY - HIDDEN_OFFSET, z) * CFrame.new(0,0,0, R00, R01, R02, R10, R11, R12, R20, R21, R22)

                            table.insert(rings, {
                                part = part,
                                originalCFrame = hiddenCFrame,
                                risenCFrame = risenCFrame
                            })
                            part.CFrame = hiddenCFrame
                        end
                     end
                     isInitialized = true
                end
            end
        end
    end

    if #rings > 0 or zoneBase or zoneRing then
        local baseTargetColor = Color3.new(1, 1, 1)
        local ringsTargetState = "Hidden"
        local ringsTargetTeam = nil

        if blueHasBoth then
            baseTargetColor = blueTeam.TeamColor.Color
            ringsTargetState = "Risen"
            ringsTargetTeam = blueTeam
        elseif pinkHasBoth then
            baseTargetColor = pinkTeam.TeamColor.Color
            ringsTargetState = "Risen"
            ringsTargetTeam = pinkTeam
        elseif pole1Owner or pole2Owner then
             ringsTargetState = "Hidden"
             if pole1Owner and not pole2Owner then baseTargetColor = pole1Owner.TeamColor.Color
             elseif pole2Owner and not pole1Owner then baseTargetColor = pole2Owner.TeamColor.Color
             else baseTargetColor = Color3.new(1, 1, 1) end
        else
            ringsTargetState = "Hidden"
            baseTargetColor = Color3.new(1, 1, 1)
        end

        self:AnimateRings(ringsTargetState, ringsTargetTeam, baseTargetColor)
    end
end

function InterfaceController:OnUpdateGameMode(gamemode)
    currentGamemode = gamemode

    self:StopBobbingAnimations()
    self:StopRiseAnimations()
    rings = {}
    zoneBase = nil
    zoneRing = nil
    isInitialized = false

    if gamemode == "Intermission" then
         -- Hide visuals
    end

    if gamemode == "TerminalFrenzy" then
        BlueAvatarContainer.Visible = true
        PinkAvatarContainer.Visible = true
        PoleIcon1.Visible = false
        PoleIcon2.Visible = false
        defaultStatusText = "Hack the enemy terminal!"
    elseif gamemode == "ZoneControl" then
        BlueAvatarContainer.Visible = false
        PinkAvatarContainer.Visible = false
        PoleIcon1.Visible = true
        PoleIcon2.Visible = true
        defaultStatusText = "Capture the Towers!"
    elseif gamemode == "Intermission" then
        BlueAvatarContainer.Visible = false
        PinkAvatarContainer.Visible = false
        PoleIcon1.Visible = false
        PoleIcon2.Visible = false
        defaultStatusText = "Waiting for players..."
    end
    StatusLabel.Text = defaultStatusText
end

function InterfaceController:OnUpdateTimer(seconds)
    local minutes = math.floor(seconds / 60)
    local remainingSeconds = seconds % 60
    TimerLabel.Text = string.format("%d:%02d", minutes, remainingSeconds)
end

function InterfaceController:OnUpdateGameState(state, status)
    currentGameState = state
    if state == "Intermission" then
        defaultStatusText = "Waiting for players..."
    elseif currentGamemode == "ZoneControl" then
        defaultStatusText = "Capture the Towers!"
    else
        defaultStatusText = "Hack the enemy terminal!"
    end

    if state == "RoundEnd" then
        activeAlert = false
        StatusLabel.Text = status
        StatusLabel.TextColor3 = Color3.new(1, 1, 1)
    elseif not activeAlert then
        StatusLabel.Text = defaultStatusText
        StatusLabel.TextColor3 = Color3.new(1, 1, 1)
    end

    if state == "Intermission" then
        if blueHackThread then task.cancel(blueHackThread) blueHackThread = nil end
        if pinkHackThread then task.cancel(pinkHackThread) pinkHackThread = nil end
        TweenService:Create(BluePercentLabel, HACK_TWEEN_INFO_RESET, {Rotation = -2}):Play()
        TweenService:Create(PinkPercentLabel, HACK_TWEEN_INFO_RESET, {Rotation = 2}):Play()

        for _, highlight in pairs(proximityHighlights) do highlight:Destroy() end
        proximityHighlights = {}
        for _, child in ipairs(GameGui:GetChildren()) do if child:IsA("Highlight") then child:Destroy() end end

        self:SetPercentFrameColor(BluePercentFrame, DEFAULT_PERCENT_FRAME_COLOR)
        self:SetPercentFrameColor(PinkPercentFrame, DEFAULT_PERCENT_FRAME_COLOR)

        self:AnimateRings("Hidden", nil, Color3.new(1,1,1))
    end
end

function InterfaceController:OnUpdateTeamRoster(rosters, targetUserId, isAlive)
    if targetUserId then
        local avatar = playerAvatarCache[targetUserId]
        if avatar then
            avatar.ImageColor3 = isAlive and Color3.new(1, 1, 1) or Color3.new(0.3, 0.3, 0.3)
        end
        return
    end

    BlueAvatarContainer:ClearAllChildren()
    PinkAvatarContainer:ClearAllChildren()
    playerAvatarCache = {}

    if not rosters then return end

    if rosters[blueTeam.Name] then
        for _, playerObj in ipairs(rosters[blueTeam.Name]) do
            local avatar = PlayerAvatarTemplate:Clone()
            avatar.Name = playerObj.Name
            avatar.Visible = true
            avatar.Parent = BlueAvatarContainer
            playerAvatarCache[playerObj.UserId] = avatar
            task.spawn(function()
                local success, content = pcall(Players.GetUserThumbnailAsync, Players, playerObj.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                if success then avatar.Image = content end
            end)
        end
    end

    if rosters[pinkTeam.Name] then
        for _, playerObj in ipairs(rosters[pinkTeam.Name]) do
            local avatar = PlayerAvatarTemplate:Clone()
            avatar.Name = playerObj.Name
            avatar.Visible = true
            avatar.Parent = PinkAvatarContainer
            playerAvatarCache[playerObj.UserId] = avatar
            task.spawn(function()
                local success, content = pcall(Players.GetUserThumbnailAsync, Players, playerObj.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                if success then avatar.Image = content end
            end)
        end
    end
end

function InterfaceController:OnPlayerSync(state, timer, status, blueProg, pinkProg, maxProg, rosters, points, gamemode)
    currentGameState = state
    self:OnUpdateGameMode(gamemode or "Intermission")
    StatusLabel.Text = defaultStatusText
    StatusLabel.TextColor3 = Color3.new(1, 1, 1)
    activeAlert = false
    currentAlertId = 0

    self:OnUpdateTimer(timer)
    self:OnUpdatePoints(points)

    if currentPoints ~= points then
        currentPoints = points
        self:RefreshAllUpgrades() -- Update upgrade buttons enabled/disabled
    end

    if currentGamemode == "TerminalFrenzy" then
        self:OnUpdateProgress(blueProg, pinkProg, maxProg)
    elseif currentGamemode == "ZoneControl" then
        self:OnUpdateZoneCountdown(blueProg, pinkProg, maxProg, 0, 0)
    end

    self:OnUpdateTeamRoster(rosters)
end

function InterfaceController:OnUpdatePoints(points)
    if points then
        PointsLabel.Text = "Points: " .. points
        currentPoints = points
        if MainFrame.Visible then self:RefreshAllUpgrades() end
    end
end

function InterfaceController:OnHackAlert(hackedTeamColor, hackerTeamColor, isBeingHacked)
    currentAlertId = currentAlertId + 1
    local myId = currentAlertId
    activeAlert = true

    local hackedTeam = (hackedTeamColor == blueTeam.TeamColor) and blueTeam or pinkTeam
    local hackerTeam = (hackerTeamColor == blueTeam.TeamColor) and blueTeam or pinkTeam

    if isBeingHacked then
        StatusLabel.Text = hackedTeam.Name .. "'s terminal is being hacked!"
        StatusLabel.TextColor3 = hackerTeam.TeamColor.Color
        if not HackAlertSound.Playing then HackAlertSound:Play() end

        if hackerTeam == blueTeam and not blueHackThread then
            blueHackThread = task.spawn(function()
                while true do
                    BluePercentLabel.Rotation = 10
                    task.wait(HACK_WOBBLE_TIME)
                    BluePercentLabel.Rotation = -10
                    task.wait(HACK_WOBBLE_TIME)
                end
            end)
        elseif hackerTeam == pinkTeam and not pinkHackThread then
            pinkHackThread = task.spawn(function()
                while true do
                    PinkPercentLabel.Rotation = 10
                    task.wait(HACK_WOBBLE_TIME)
                    PinkPercentLabel.Rotation = -10
                    task.wait(HACK_WOBBLE_TIME)
                end
            end)
        end
    else
        StatusLabel.Text = hackedTeam.Name .. "'s terminal has stopped being hacked!"
        StatusLabel.TextColor3 = hackedTeam.TeamColor.Color
        if not HackStopSound.Playing then HackStopSound:Play() end

        if hackedTeam == pinkTeam and blueHackThread then
            task.cancel(blueHackThread)
            blueHackThread = nil
            TweenService:Create(BluePercentLabel, HACK_TWEEN_INFO_RESET, {Rotation = -2}):Play()
        elseif hackedTeam == blueTeam and pinkHackThread then
            task.cancel(pinkHackThread)
            pinkHackThread = nil
            TweenService:Create(PinkPercentLabel, HACK_TWEEN_INFO_RESET, {Rotation = 2}):Play()
        end
    end

    task.delay(3, function()
        if myId == currentAlertId then
            StatusLabel.Text = defaultStatusText
            StatusLabel.TextColor3 = Color3.new(1, 1, 1)
            activeAlert = false
        end
    end)
end

function InterfaceController:OnZoneAlert(alertType, team)
    currentAlertId = currentAlertId + 1
    local myId = currentAlertId
    activeAlert = true

    if alertType == "OnePole" then
        StatusLabel.Text = team.Name .. " captured a pole!"
        if not ZoneAlertOnePoleSound.Playing then ZoneAlertOnePoleSound:Play() end
    elseif alertType == "BothPoles" then
        StatusLabel.Text = team.Name .. " captured both poles and controls the zone!"
        if not ZoneAlertBothPolesSound.Playing then ZoneAlertBothPolesSound:Play() end
    end

    StatusLabel.TextColor3 = team.TeamColor.Color

    task.delay(3, function()
        if myId == currentAlertId then
            StatusLabel.Text = defaultStatusText
            StatusLabel.TextColor3 = Color3.new(1, 1, 1)
            activeAlert = false
        end
    end)
end

function InterfaceController:OnMapAlert()
    activeAlert = true
    currentAlertId = currentAlertId + 1
    local myId = currentAlertId

    StatusLabel.Text = "Last push, the map is changing!"
    StatusLabel.TextColor3 = Color3.fromRGB(255, 170, 0)

    if not MapChangeSound.Playing then MapChangeSound:Play() end
    task.wait(MapChangeSound.TimeLength)
    if not MapRumbleSound.Playing then MapRumbleSound:Play() end

    task.delay(7, function()
        if myId == currentAlertId then
            StatusLabel.Text = defaultStatusText
            StatusLabel.TextColor3 = Color3.new(1, 1, 1)
            activeAlert = false
        end
    end)
end

function InterfaceController:OnRevealTerminal(terminalPart, hackedTeamName)
    if not terminalPart or not terminalPart.Parent then return end
    local highlight = Instance.new("Highlight")

    if player.Team and player.Team.Name == hackedTeamName then
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    else
        highlight.FillColor = Color3.fromRGB(255, 255, 255)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    end

    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.8
    highlight.OutlineTransparency = 0.2
    highlight.Adornee = terminalPart
    highlight.Parent = GameGui

    task.delay(5, function() if highlight.Parent then highlight:Destroy() end end)
end

function InterfaceController:OnProximityGained(terminalPart)
    if not terminalPart or not terminalPart.Parent then return end
    if proximityHighlights[terminalPart] then return end

    local highlight = Instance.new("Highlight")
    highlight.FillColor = Color3.fromRGB(255, 170, 0)
    highlight.OutlineColor = Color3.fromRGB(255, 170, 0)
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.8
    highlight.OutlineTransparency = 0.2
    highlight.Adornee = terminalPart
    highlight.Parent = GameGui

    proximityHighlights[terminalPart] = highlight
end

function InterfaceController:OnProximityLost(terminalPart)
    if not terminalPart or not proximityHighlights[terminalPart] then return end
    proximityHighlights[terminalPart]:Destroy()
    proximityHighlights[terminalPart] = nil
end

function InterfaceController:ShowZoneEffect(effectName)
    if effectName then
        print("Zone Effect: " .. effectName)
    end
end

function InterfaceController:ShowStunVisual(targetChar, duration)
    if not targetChar then return end
    local head = targetChar:FindFirstChild("Head")
    if not head or not stunEffectTemplate then return end

    local visual = stunEffectTemplate:Clone()
    visual.Parent = targetChar
    local startTime = os.clock()

    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not visual or not visual.Parent or not head.Parent then
            if conn then conn:Disconnect() end
            return
        end
        local t = os.clock() - startTime
        local bob = math.sin(t * 5) * 0.5
        local rotation = CFrame.Angles(0, t * 5, 0)

        local p = visual:FindFirstChildWhichIsA("BasePart") or visual.PrimaryPart
        if p then p.CFrame = head.CFrame * CFrame.new(0, 2 + bob, 0) * rotation end
    end)

    task.delay(duration, function()
        if conn then conn:Disconnect() end
        if visual then visual:Destroy() end
    end)
end

return InterfaceController
