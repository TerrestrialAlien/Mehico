local PhysicsService = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local Teams = game:GetService("Teams")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

-- Events
local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local playerStunnedEvent = eventFolder:WaitForChild("PlayerStunned")
local splatEvents = ReplicatedStorage:WaitForChild("SplatEvents")
local requestThrowEvent = splatEvents:WaitForChild("RequestThrowBomb")

-- Assets
local bombTemplate = game:GetService("ServerStorage"):WaitForChild("Assets"):FindFirstChild("SplatBombModel")
local soundFolder = ReplicatedStorage:WaitForChild("SplatSounds")
local throwSound = soundFolder:FindFirstChild("ThrowSound")
local impactSound = soundFolder:FindFirstChild("ImpactSound")
local fuseSound = soundFolder:FindFirstChild("FuseSound")
local explosionSound = soundFolder:FindFirstChild("ExplosionSound")

-- Anti-Cheat State
local playerCooldowns = {}
local playerHoverStates = {}
local playerActionStates = {}
local bombCooldowns = {}
local playerHoverBoards = {}

-- Teams
local blueTeam = Teams["Bright blue"]
local pinkTeam = Teams["Carnation pink"]

function PhysicsService:Init(services)
    -- Movement Events
    local requestAbilityEvent = eventFolder:WaitForChild("RequestMovementAbility")
    local abilityUsedEvent = eventFolder:WaitForChild("MovementAbilityUsed")

    requestAbilityEvent.OnServerEvent:Connect(function(player, abilityName)
        self:OnAbilityRequested(player, abilityName, abilityUsedEvent)
    end)

    local requestWallJumpEvent = eventFolder:WaitForChild("RequestWallJump")
    local requestWallBoostEvent = eventFolder:WaitForChild("RequestWallBoost")

    requestWallJumpEvent.OnServerEvent:Connect(function(player, pos)
        self:OnWallJumpRequest(player, pos)
    end)
    requestWallBoostEvent.OnServerEvent:Connect(function(player, pos)
        self:OnWallBoostRequest(player, pos)
    end)

    -- Bomb Events
    requestThrowEvent.OnServerEvent:Connect(function(player, aimCFrame, power)
        self:OnBombThrowRequested(player, aimCFrame, power)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:OnPlayerRemoving(player)
    end)

    -- Anti-Cheat Loop
    task.spawn(function()
        while true do
            local dt = RunService.Heartbeat:Wait()
            self:CheckSpeedLimits()
        end
    end)

    local reportStunEvent = eventFolder:WaitForChild("ReportStun")
    reportStunEvent.OnServerEvent:Connect(function(player, duration)
        if type(duration) ~= "number" or duration > 10 then return end
        playerStunnedEvent:FireAllClients(player, duration)
    end)
end

function PhysicsService:Start()
end

function PhysicsService:OnPlayerRemoving(player)
    playerCooldowns[player.UserId] = nil
    playerHoverStates[player.UserId] = nil
    playerActionStates[player] = nil
    bombCooldowns[player.UserId] = nil
    self:DestroyHoverboard(player)
end

function PhysicsService:CreateHoverboard(player)
    self:DestroyHoverboard(player)

    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local board = Instance.new("Part")
    board.Name = "HoverboardVisual"
    board.Size = Vector3.new(4, 0.4, 2)
    board.Material = Enum.Material.Neon

    if player.Team then
        board.BrickColor = player.Team.TeamColor
    else
        board.BrickColor = BrickColor.new("Bright blue")
    end

    board.Anchored = false
    board.CanCollide = false
    board.Massless = true

    local weld = Instance.new("Weld")
    weld.Part0 = root
    weld.Part1 = board
    weld.C0 = CFrame.new(0, -2.8, 0)
    weld.Parent = board

    board.Parent = char
    board:SetNetworkOwner(player)
    playerHoverBoards[player] = board
end

function PhysicsService:DestroyHoverboard(player)
    if playerHoverBoards[player] then
        pcall(function() playerHoverBoards[player]:Destroy() end)
        playerHoverBoards[player] = nil
    end
end

function PhysicsService:OnAbilityRequested(player, abilityName, abilityUsedEvent)
    local config
    if abilityName == "Slide" then config = { Cooldown = GameConfig.Movement.SlideCooldown }
    elseif abilityName == "Dive" then config = { Cooldown = GameConfig.Movement.DiveCooldown }
    elseif abilityName == "Hoverboard" then config = { Cooldown = GameConfig.Movement.HoverCooldown }
    end

    if not config then return end

    local now = os.clock()
    local userId = player.UserId

    if not playerCooldowns[userId] then playerCooldowns[userId] = {} end

    if abilityName == "Hoverboard" then
        local isHovering = playerHoverStates[userId] or false
        if isHovering then
            playerHoverStates[userId] = false
            playerCooldowns[userId][abilityName] = now
            self:DestroyHoverboard(player)
            abilityUsedEvent:FireAllClients(player, abilityName)
        else
            local lastUse = playerCooldowns[userId][abilityName] or 0
            if now - lastUse < config.Cooldown - 0.1 then return end

            playerHoverStates[userId] = true
            self:CreateHoverboard(player)
            abilityUsedEvent:FireAllClients(player, abilityName)
        end
        return
    end

    local lastUse = playerCooldowns[userId][abilityName] or 0
    if now - lastUse < config.Cooldown - 0.1 then return end

    playerCooldowns[userId][abilityName] = now

    local duration = (abilityName == "Slide") and 1.2 or 0.5
    playerActionStates[player] = { Action = abilityName, EndTime = now + duration }

    abilityUsedEvent:FireAllClients(player, abilityName)
end

function PhysicsService:CheckSpeedLimits()
    local now = os.clock()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local root = player.Character.HumanoidRootPart
            local velocity = root.AssemblyLinearVelocity
            local horizSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

            local limit = 40 -- Max Walk Speed base
            local state = playerActionStates[player]

            if playerHoverStates[player.UserId] then
                limit = GameConfig.Movement.HoverSpeed + 55 -- Buffer
            elseif state and now < state.EndTime then
                if state.Action == "Slide" then limit = GameConfig.Movement.SlideSpeed + 20
                elseif state.Action == "Dive" then limit = GameConfig.Movement.DiveSpeed + 20 end
            end

            if horizSpeed > limit then
                local clamped = velocity * (limit / horizSpeed)
                root.AssemblyLinearVelocity = clamped
            end
        end
    end
end

-- WallJump Validation
function PhysicsService:OnWallJumpRequest(player, wallPosition)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = (root.Position - wallPosition).Magnitude
    if dist > 12 then return end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterDescendantsInstances = {char}
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude

    local parts = workspace:GetPartBoundsInRadius(wallPosition, 6, overlapParams)
    local foundWall = false

    for _, part in ipairs(parts) do
        if CollectionService:HasTag(part, "WallJump") then
            foundWall = true
            break
        end
    end

    if not foundWall then
        warn("Possible cheat: " .. player.Name .. " tried to wall jump off invalid part.")
    end
end

function PhysicsService:OnWallBoostRequest(player, wallPosition)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = (root.Position - wallPosition).Magnitude
    if dist > 12 then
        warn("Possible cheat: " .. player.Name .. " tried to boost from too far away.")
        return
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterDescendantsInstances = {char}
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude

    local parts = workspace:GetPartBoundsInRadius(wallPosition, 6, overlapParams)
    local isValid = false

    for _, part in ipairs(parts) do
        if CollectionService:HasTag(part, "WallBoost") then
            isValid = true
            break
        end

        if CollectionService:HasTag(part, "JumpPad_Blue") then
            if player.Team == blueTeam then
                isValid = true
                break
            else
                warn("Cheat Attempt: " .. player.Name .. " tried to use Blue Pad but is not on Blue Team!")
            end
        end

        if CollectionService:HasTag(part, "JumpPad_Pink") then
            if player.Team == pinkTeam then
                isValid = true
                break
            else
                warn("Cheat Attempt: " .. player.Name .. " tried to use Pink Pad but is not on Pink Team!")
            end
        end
    end

    if not isValid then
        warn("Boost Validation Failed for " .. player.Name)
    end
end

-- Bomb Logic
function PhysicsService:OnBombThrowRequested(player, aimCFrame, power)
    local now = tick()
    local lastThrow = bombCooldowns[player.UserId] or 0

    if now - lastThrow < GameConfig.Bomb.Cooldown then return end
    if typeof(aimCFrame) ~= "CFrame" or typeof(power) ~= "number" then return end
    power = math.clamp(power, 0, 1)

    bombCooldowns[player.UserId] = now
    self:SpawnBomb(player, aimCFrame, power)
end

function PhysicsService:SpawnBomb(player, aimCFrame, power)
    local character = player.Character
    if not character or not character:FindFirstChild("Head") then return end

    local bomb
    if bombTemplate then
        bomb = bombTemplate:Clone()
    else
        bomb = Instance.new("Part")
        bomb.Name = "SplatBomb"
        bomb.Shape = Enum.PartType.Ball
        bomb.Size = Vector3.new(1.5, 1.5, 1.5)
        bomb.Material = Enum.Material.Neon
    end

    local physPart = bomb
    if bomb:IsA("Model") then
        if not bomb.PrimaryPart then
            local p = bomb:FindFirstChildWhichIsA("BasePart")
            if p then
                bomb.PrimaryPart = p
                physPart = p
            end
        else
            physPart = bomb.PrimaryPart
        end
    end

    local teamColor = BrickColor.new("Bright green")
    if player.Team then teamColor = player.Team.TeamColor end

    if physPart then
        physPart.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.5)
        physPart.CanCollide = true
        physPart.Anchored = false

        if bomb:IsA("BasePart") then
            bomb.BrickColor = teamColor
        elseif bomb:IsA("Model") then
            for _, child in ipairs(bomb:GetDescendants()) do
                if child:IsA("BasePart") then
                    child.BrickColor = teamColor
                end
            end
        end
    end

    if bomb:IsA("Model") then
        bomb:SetPrimaryPartCFrame(character.Head.CFrame * CFrame.new(0, 0, -3))
    else
        bomb.CFrame = character.Head.CFrame * CFrame.new(0, 0, -3)
    end

    bomb.Parent = workspace
    self:PlaySoundAt(throwSound, self:GetPosition(bomb))

    local speed = GameConfig.Bomb.ThrowSpeedMin + (power * (GameConfig.Bomb.ThrowSpeedMax - GameConfig.Bomb.ThrowSpeedMin))
    local velocity = (aimCFrame.LookVector * speed) + Vector3.new(0, GameConfig.Bomb.ThrowUpForce, 0)

    if physPart then
        physPart.AssemblyLinearVelocity = velocity
    end

    local hasLanded = false
    local touchPart = bomb
    if bomb:IsA("Model") then touchPart = bomb.PrimaryPart end

    touchPart.Touched:Connect(function(hit)
        if hasLanded then return end
        if hit:IsDescendantOf(character) then return end
        if not hit.CanCollide then return end

        hasLanded = true

        self:PlaySoundAt(impactSound, self:GetPosition(bomb))
        self:StartBlinking(bomb, teamColor)

        task.delay(GameConfig.Bomb.FuseTime, function()
            if bomb and bomb.Parent then
                self:ExplodeBomb(bomb, player)
            end
        end)
    end)

    Debris:AddItem(bomb, 10)
end

function PhysicsService:ExplodeBomb(bombPart, ownerPlayer)
    local position = self:GetPosition(bombPart)
    print("💥 BOOM!")

    self:PlaySoundAt(explosionSound, position)

    local explosionVis = Instance.new("Part")
    explosionVis.Name = "ExplosionVisual"
    explosionVis.Shape = Enum.PartType.Ball
    explosionVis.Size = Vector3.new(1, 1, 1)
    explosionVis.Position = position
    explosionVis.Anchored = true
    explosionVis.CanCollide = false
    explosionVis.Material = Enum.Material.Neon
    explosionVis.Transparency = 0.2

    if ownerPlayer.Team then
        explosionVis.BrickColor = ownerPlayer.Team.TeamColor
    else
        explosionVis.BrickColor = BrickColor.new("Bright green")
    end

    explosionVis.Parent = workspace

    local goal = {
        Size = Vector3.new(GameConfig.Bomb.BlastRadiusOuter * 2, GameConfig.Bomb.BlastRadiusOuter * 2, GameConfig.Bomb.BlastRadiusOuter * 2),
        Transparency = 1
    }
    local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(explosionVis, info, goal):Play()
    Debris:AddItem(explosionVis, 0.6)

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local root = otherPlayer.Character.HumanoidRootPart
            local humanoid = otherPlayer.Character.Humanoid
            local dist = (root.Position - position).Magnitude

            if dist <= GameConfig.Bomb.BlastRadiusOuter then
                if otherPlayer == ownerPlayer then continue end
                if ownerPlayer.Team and otherPlayer.Team and ownerPlayer.Team == otherPlayer.Team then continue end

                local rayParams = RaycastParams.new()
                local filterTable = {bombPart, explosionVis}
                if ownerPlayer.Character then table.insert(filterTable, ownerPlayer.Character) end

                rayParams.FilterDescendantsInstances = filterTable
                rayParams.FilterType = Enum.RaycastFilterType.Exclude

                local hit = workspace:Raycast(position, (root.Position - position), rayParams)

                if hit and hit.Instance:IsDescendantOf(otherPlayer.Character) then
                    if dist <= GameConfig.Bomb.BlastRadiusKill then
                        humanoid:TakeDamage(1000)
                    else
                        local damagePct = 1 - ((dist - GameConfig.Bomb.BlastRadiusKill) / (GameConfig.Bomb.BlastRadiusOuter - GameConfig.Bomb.BlastRadiusKill))
                        local damage = GameConfig.Bomb.Damage * damagePct
                        if damage < 10 then damage = 10 end
                        humanoid:TakeDamage(damage)
                    end
                end
            end
        end
    end

    bombPart:Destroy()
end

function PhysicsService:StartBlinking(bomb, originalColor)
    local blinkRate = 0.5
    local startTime = tick()
    local fuseSoundPlaying = nil

    if fuseSound then
        fuseSoundPlaying = fuseSound:Clone()
        fuseSoundPlaying.Parent = (bomb:IsA("Model") and bomb.PrimaryPart or bomb)
        fuseSoundPlaying.Looped = true
        fuseSoundPlaying:Play()
    end

    task.spawn(function()
        while bomb and bomb.Parent do
            local elapsed = tick() - startTime
            if elapsed > (GameConfig.Bomb.FuseTime * 0.7) then blinkRate = 0.1 end

            local partsToColor = {}
            if bomb:IsA("Model") then
                for _, p in ipairs(bomb:GetDescendants()) do
                    if p:IsA("BasePart") then table.insert(partsToColor, p) end
                end
            else
                table.insert(partsToColor, bomb)
            end

            for _, p in ipairs(partsToColor) do p.BrickColor = BrickColor.new("Really red") end
            task.wait(blinkRate)
            if not bomb or not bomb.Parent then break end

            for _, p in ipairs(partsToColor) do p.BrickColor = originalColor end
            task.wait(blinkRate)
        end

        if fuseSoundPlaying then fuseSoundPlaying:Stop() end
    end)
end

function PhysicsService:PlaySoundAt(sound, position)
    if not sound then return end
    local s = sound:Clone()
    local part = Instance.new("Part")
    part.Transparency = 1
    part.CanCollide = false
    part.Anchored = true
    part.Position = position
    part.Parent = workspace
    s.Parent = part
    s:Play()
    Debris:AddItem(part, s.TimeLength + 1)
end

function PhysicsService:GetPosition(part)
    if part:IsA("BasePart") then return part.Position end
    if part:IsA("Model") then return part:GetPivot().Position end
    return Vector3.new(0,0,0)
end

return PhysicsService
