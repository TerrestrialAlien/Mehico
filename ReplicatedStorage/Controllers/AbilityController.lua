local AbilityController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = workspace
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local splatEvents = ReplicatedStorage:WaitForChild("SplatEvents")
local requestThrowEvent = splatEvents:WaitForChild("RequestThrowBomb")
local updateGameStateEvent = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("UpdateGameState")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local THROW_KEY = Enum.KeyCode.R
local MAX_THROW_DIST = 60
local MIN_THROW_DIST = 10
local PITCH_LOOK_DOWN = -0.6
local PITCH_LOOK_UP = 0.2
local TOUCH_SENSITIVITY = Vector2.new(0.005, 0.003)
local IS_MOBILE = UserInputService.TouchEnabled

-- State
local isAiming = false
local aimMarker = nil
local currentPower = 0
local currentAimCFrame = CFrame.new()
local lastThrowTime = 0
local lastEquippedTool = nil
local currentGameState = "Intermission"

-- Mobile UI
local mobileGui = nil
local throwButton = nil
local cancelButton = nil
local touchObject = nil
local startTouchPos = Vector2.new(0,0)
local originalButtonPos = UDim2.new(0.8, 0, 0.65, 0)
local cooldownContainer = nil
local cooldownBar = nil

function AbilityController:Init(controllers)
end

function AbilityController:Start()
	updateGameStateEvent.OnClientEvent:Connect(function(state)
		currentGameState = state
	end)

	if IS_MOBILE then
		self:CreateMobileUI()
	else
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
		-- PC Cancel
		UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if isAiming and input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:CancelThrow()
			end
		end)
	end
end

function AbilityController:CanThrow()
	if currentGameState == "Intermission" then return false end
	if tick() - lastThrowTime < GameConfig.Bomb.Cooldown then return false end
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then return false end
	return true
end

function AbilityController:CreateMobileUI()
	if mobileGui then mobileGui:Destroy() end
	mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "SplatBombUI"
	mobileGui.Parent = playerGui
	mobileGui.ResetOnSpawn = false

	throwButton = Instance.new("ImageButton")
	throwButton.Name = "ThrowButton"
	throwButton.Size = UDim2.new(0, 80, 0, 80)
	throwButton.Position = originalButtonPos
	throwButton.AnchorPoint = Vector2.new(0.5, 0.5)
	throwButton.BackgroundColor3 = Color3.new(0, 0, 0)
	throwButton.BackgroundTransparency = 0.5
	throwButton.Parent = mobileGui
	Instance.new("UICorner", throwButton).CornerRadius = UDim.new(1, 0)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://120341749972545"
	icon.Parent = throwButton

	cancelButton = Instance.new("ImageButton")
	cancelButton.Name = "CancelButton"
	cancelButton.Size = UDim2.new(0, 60, 0, 60)
	cancelButton.Position = originalButtonPos - UDim2.new(0.15, 0, 0.15, 0) 
	cancelButton.AnchorPoint = Vector2.new(0.5, 0.5)
	cancelButton.BackgroundColor3 = Color3.fromRGB(255, 85, 85) 
	cancelButton.BackgroundTransparency = 0.8 
	cancelButton.Visible = false 
	cancelButton.Image = "rbxassetid://6940288377" 
	cancelButton.Parent = mobileGui
	Instance.new("UICorner", cancelButton).CornerRadius = UDim.new(1, 0)

	cooldownContainer = Instance.new("Frame")
	cooldownContainer.Name = "CooldownContainer"
	cooldownContainer.Size = UDim2.new(0, 200, 0, 20)
	cooldownContainer.Position = UDim2.new(0.8, 0, 0.8, 0)
	cooldownContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	cooldownContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	cooldownContainer.BackgroundTransparency = 0.3
	cooldownContainer.Visible = false
	cooldownContainer.Parent = mobileGui
	Instance.new("UICorner", cooldownContainer).CornerRadius = UDim.new(0, 4)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "RECHARGING"
	label.TextColor3 = Color3.new(1,1,1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.ZIndex = 2
	label.Parent = cooldownContainer

	cooldownBar = Instance.new("Frame")
	cooldownBar.Name = "Bar"
	cooldownBar.Size = UDim2.new(1, 0, 1, 0) 
	cooldownBar.BackgroundColor3 = Color3.new(1, 0.3, 0.3) 
	cooldownBar.BorderSizePixel = 0
	cooldownBar.ZIndex = 1
	cooldownBar.Parent = cooldownContainer
	Instance.new("UICorner", cooldownBar).CornerRadius = UDim.new(0, 4)

	throwButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not touchObject then
			if not self:CanThrow() then return end
			touchObject = input
			startTouchPos = Vector2.new(input.Position.X, input.Position.Y)
			cancelButton.Visible = true 
			self:StartThrow() 
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == touchObject and isAiming then
			local currentPos = Vector2.new(input.Position.X, input.Position.Y)
			throwButton.Position = UDim2.new(0, currentPos.X, 0, currentPos.Y)

			local cancelAbsPos = cancelButton.AbsolutePosition
			local cancelSize = cancelButton.AbsoluteSize
			local cancelCenter = cancelAbsPos + (cancelSize/2)

			if (currentPos - cancelCenter).Magnitude < (cancelSize.X/2 + 20) then
				cancelButton.BackgroundTransparency = 0.2 
				cancelButton.Size = UDim2.new(0, 70, 0, 70) 
			else
				cancelButton.BackgroundTransparency = 0.8
				cancelButton.Size = UDim2.new(0, 60, 0, 60)
			end

			local diff = currentPos - startTouchPos
			local rotX = -diff.X * TOUCH_SENSITIVITY.X
			local rotY = -diff.Y * TOUCH_SENSITIVITY.Y
			camera.CFrame = CFrame.Angles(0, rotX, 0) * camera.CFrame * CFrame.Angles(rotY, 0, 0)
			startTouchPos = currentPos 
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == touchObject then
			touchObject = nil
			local currentPos = Vector2.new(input.Position.X, input.Position.Y)
			local cancelAbsPos = cancelButton.AbsolutePosition
			local cancelSize = cancelButton.AbsoluteSize
			local cancelCenter = cancelAbsPos + (cancelSize/2)

			if (currentPos - cancelCenter).Magnitude < (cancelSize.X/2 + 20) then
				self:CancelThrow()
			else
				self:ReleaseThrow()
			end

			cancelButton.Visible = false
			cancelButton.BackgroundTransparency = 0.8
			cancelButton.Size = UDim2.new(0, 60, 0, 60)
			throwButton:TweenPosition(originalButtonPos, "Out", "Back", 0.3)
		end
	end)
end

function AbilityController:StartCooldownVisuals()
	lastThrowTime = tick()
	if cooldownContainer and cooldownBar then
		cooldownContainer.Visible = true
		cooldownBar.Size = UDim2.new(1, 0, 1, 0)
		local t = TweenService:Create(cooldownBar, TweenInfo.new(GameConfig.Bomb.Cooldown, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 1, 0)})
		t:Play()
		t.Completed:Connect(function() cooldownContainer.Visible = false end)
	end
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

	if not IS_MOBILE then
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

	if not IS_MOBILE then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
	if aimMarker then aimMarker:Destroy() aimMarker = nil end

	local char = player.Character
	if char and char:FindFirstChild("Humanoid") then
		char.Humanoid.AutoRotate = true
	end

	requestThrowEvent:FireServer(currentAimCFrame, currentPower)
	self:StartCooldownVisuals()
	self:RestoreWeapon()
end

function AbilityController:CancelThrow()
	if not isAiming then return end
	isAiming = false

	pcall(function() RunService:UnbindFromRenderStep("SplatAim") end)

	if not IS_MOBILE then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
	if aimMarker then aimMarker:Destroy() aimMarker = nil end

	local char = player.Character
	if char and char:FindFirstChild("Humanoid") then
		char.Humanoid.AutoRotate = true
	end

	if IS_MOBILE and throwButton then throwButton:TweenPosition(originalButtonPos, "Out", "Back", 0.3) end

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
