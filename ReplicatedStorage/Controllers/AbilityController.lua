local AbilityController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = workspace
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local splatEvents = ReplicatedStorage:WaitForChild("SplatEvents")
local requestThrowEvent = splatEvents:WaitForChild("RequestThrowBomb")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- State
local isAiming = false
local aimMarker = nil
local currentPower = 0
local currentAimCFrame = CFrame.new()
local lastThrowTime = 0
local lastEquippedTool = nil

-- Config
local THROW_KEY = Enum.KeyCode.R
local MAX_THROW_DIST = 60
local MIN_THROW_DIST = 10
local PITCH_LOOK_DOWN = -0.6
local PITCH_LOOK_UP = 0.2

function AbilityController:Init(controllers)
end

function AbilityController:Start()
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == THROW_KEY then
            self:StartThrow()
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gp)
        if input.KeyCode == THROW_KEY then
            self:ReleaseThrow()
        end
    end)

    -- PC Cancel (Left Click)
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if not UserInputService.TouchEnabled and isAiming and input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:CancelThrow()
        end
    end)
end

function AbilityController:CanThrow()
    if tick() - lastThrowTime < GameConfig.Bomb.Cooldown then return false end
    local char = player.Character
    if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then return false end
    return true
end

function AbilityController:StartThrow()
    if isAiming or not self:CanThrow() then return end
    isAiming = true

    self:StashWeapon()
    aimMarker = self:CreateAimMarker()

    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.AutoRotate = false
    end

    if not UserInputService.TouchEnabled then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    end

    RunService:BindToRenderStep("SplatAim", Enum.RenderPriority.Camera.Value + 1, function() self:UpdateAiming() end)
end

function AbilityController:UpdateAiming()
    if not isAiming then return end

    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local root = char.HumanoidRootPart

    local lookVector = camera.CFrame.LookVector
    local pitch = lookVector.Y

    local alpha = (pitch - PITCH_LOOK_DOWN) / (PITCH_LOOK_UP - PITCH_LOOK_DOWN)
    currentPower = math.clamp(alpha, 0, 1)

    local targetDistance = MIN_THROW_DIST + (currentPower * (MAX_THROW_DIST - MIN_THROW_DIST))
    local flatLookDir = Vector3.new(lookVector.X, 0, lookVector.Z).Unit

    local rayOrigin = root.Position
    local rayDir = flatLookDir * targetDistance
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {char, aimMarker}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local wallHit = Workspace:Raycast(rayOrigin, rayDir, rayParams)
    local finalFlatPos
    if wallHit then
        finalFlatPos = wallHit.Position
        local actualDist = (wallHit.Position - root.Position).Magnitude
        currentPower = math.clamp((actualDist - MIN_THROW_DIST) / (MAX_THROW_DIST - MIN_THROW_DIST), 0, 1)
    else
        finalFlatPos = rayOrigin + rayDir
    end

    local floorRayOrigin = finalFlatPos + Vector3.new(0, 10, 0)
    local floorRayDir = Vector3.new(0, -50, 0)
    local floorHit = Workspace:Raycast(floorRayOrigin, floorRayDir, rayParams)

    local markerPos
    if floorHit then
        markerPos = floorHit.Position
    else
        markerPos = Vector3.new(finalFlatPos.X, root.Position.Y - 2.5, finalFlatPos.Z)
    end

    if aimMarker then
        aimMarker.CFrame = CFrame.new(markerPos) * CFrame.Angles(0,0, math.rad(90)) + Vector3.new(0, 0.2, 0)
    end

    local lookAtPos = root.Position + flatLookDir * 10
    root.CFrame = CFrame.lookAt(root.Position, Vector3.new(lookAtPos.X, root.Position.Y, lookAtPos.Z))

    currentAimCFrame = camera.CFrame
end

function AbilityController:ReleaseThrow()
    if not isAiming then return end
    isAiming = false

    pcall(function() RunService:UnbindFromRenderStep("SplatAim") end)

    if not UserInputService.TouchEnabled then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
    if aimMarker then aimMarker:Destroy() aimMarker = nil end

    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.AutoRotate = true
    end

    requestThrowEvent:FireServer(currentAimCFrame, currentPower)
    lastThrowTime = tick()
    self:RestoreWeapon()
end

function AbilityController:CancelThrow()
    if not isAiming then return end
    isAiming = false

    pcall(function() RunService:UnbindFromRenderStep("SplatAim") end)

    if not UserInputService.TouchEnabled then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
    if aimMarker then aimMarker:Destroy() aimMarker = nil end

    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.AutoRotate = true
    end

    self:RestoreWeapon()
    print("🚫 Bomb Throw Cancelled")
end

function AbilityController:CreateAimMarker()
    if aimMarker then aimMarker:Destroy() end
    local part = Instance.new("Part")
    part.Name = "AimMarker"
    part.Size = Vector3.new(4, 0.2, 4)
    part.Shape = Enum.PartType.Cylinder
    part.Transparency = 0.5
    part.Material = Enum.Material.Neon
    part.BrickColor = BrickColor.new("Really red")
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Parent = Workspace
    return part
end

function AbilityController:StashWeapon()
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return end

    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        lastEquippedTool = tool
        humanoid:UnequipTools()
    else
        lastEquippedTool = nil
    end
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end

function AbilityController:RestoreWeapon()
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChild("Humanoid")

    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)

    if lastEquippedTool and lastEquippedTool.Parent == player.Backpack and humanoid then
        humanoid:EquipTool(lastEquippedTool)
    end
    lastEquippedTool = nil
end

return AbilityController
