local PhysicsService = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

-- Events
local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local playerStunnedEvent = eventFolder:WaitForChild("PlayerStunned")
local splatEvents = ReplicatedStorage:WaitForChild("SplatEvents")
local requestThrowEvent = splatEvents:WaitForChild("RequestThrowBomb")

-- Assets
local bombTemplate = ReplicatedStorage:FindFirstChild("SplatBombModel")
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

function PhysicsService:Init(services)
    -- Movement Events
    local requestAbilityEvent = eventFolder:WaitForChild("RequestMovementAbility")
    local abilityUsedEvent = eventFolder:WaitForChild("MovementAbilityUsed")

    requestAbilityEvent.OnServerEvent:Connect(function(player, abilityName)
        self:OnAbilityRequested(player, abilityName, abilityUsedEvent)
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
end

function PhysicsService:Start()
end

function PhysicsService:OnPlayerRemoving(player)
    playerCooldowns[player.UserId] = nil
    playerHoverStates[player.UserId] = nil
    playerActionStates[player] = nil
    bombCooldowns[player.UserId] = nil
    -- Destroy hoverboard visual if tracked (not implemented fully)
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
            -- Destroy hoverboard visual (Not implemented here, assumed Client handles visual or separate VisualService)
            -- MovementServer had server-side hoverboard visual creation.
            abilityUsedEvent:FireAllClients(player, abilityName)
        else
            local lastUse = playerCooldowns[userId][abilityName] or 0
            if now - lastUse < config.Cooldown - 0.1 then return end

            playerHoverStates[userId] = true
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
