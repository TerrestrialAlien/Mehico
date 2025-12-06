local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Players = game:GetService("Players")
local Workspace = workspace
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Teams = game:GetService("Teams")

local MovementController = {}

-- State
local isSliding = false
local isDiving = false
local isStunned = false
local isHovering = false

-- WallJump State
local isWallStuck = false
local isGrinding = false 
local stuckTime = 0
local lastDetachTime = 0
local lastWall = nil
local lastBoostTime = 0 
local currentWallNormal = Vector3.new(0,0,0)
local stickVelocity = nil
local stickAlign = nil
local currentJumpPad = nil 
local grindParticles = nil 
local grindAttachment = nil 

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local humanoid = nil
local rootPart = nil
local animator = nil

-- GUI
local MovementGui = playerGui:WaitForChild("MovementGui")
local MovementContainer = MovementGui:WaitForChild("MovementContainer")
local ABILITIES = {
	Slide = {
		Key = Enum.KeyCode.C,
		Cooldown = GameConfig.Movement.SlideCooldown,
		Frame = MovementContainer:WaitForChild("SlideFrame"),
		LastUse = 0
	},
	Dive = {
		Key = Enum.KeyCode.X,
		Cooldown = GameConfig.Movement.DiveCooldown,
		Frame = MovementContainer:WaitForChild("DiveFrame"),
		LastUse = 0
	},
	Hoverboard = {
		Key = Enum.KeyCode.LeftShift,
		Cooldown = GameConfig.Movement.HoverCooldown,
		Frame = MovementContainer:WaitForChild("HoverboardFrame"),
		LastUse = 0
	}
}
local IS_MOBILE = UserInputService.TouchEnabled

-- Events
local eventFolder = ReplicatedStorage:WaitForChild("GameEvents")
local requestAbilityEvent = eventFolder:WaitForChild("RequestMovementAbility")
local abilityUsedEvent = eventFolder:WaitForChild("MovementAbilityUsed")
local playerStunnedEvent = eventFolder:WaitForChild("PlayerStunned")
local reportStunEvent = eventFolder:WaitForChild("ReportStun")
local requestWallJumpEvent = eventFolder:WaitForChild("RequestWallJump")
local requestWallBoostEvent = eventFolder:WaitForChild("RequestWallBoost")

-- Assets
local wallJumpSound = ReplicatedStorage:WaitForChild("WallJumpSound")
local grindSparksTemplate = ReplicatedStorage:WaitForChild("GrindSparks", 5)

-- Animation Tracks
local slideTrack = nil
local diveTrack = nil
local stunTrack = nil
local slideStunTrack = nil
local diveStunTrack = nil

-- Animation IDs
local SLIDE_ANIM_ID       = "rbxassetid://120248514621144"
local DIVE_ANIM_ID        = "rbxassetid://134711263142666"
local STUN_ANIM_ID        = "rbxassetid://104284166770718"
local SLIDE_STUN_ANIM_ID  = "rbxassetid://104284166770718"
local DIVE_STUN_ANIM_ID   = "rbxassetid://79168835316610"

-- Connections
local slideConnection = nil
local diveConnection = nil
local hoverConnection = nil

-- Hover Physics
local hoverTargetPart = nil
local hoverTargetAttachment = nil
local rootHoverAttachment = nil
local hoverAlign = nil
local hoverOrient = nil
local hoverLinear = nil
local lastEquippedTool = nil

local slideInvincibleTag = nil

-- Constants
local SLIDE_GROUND_CHECK = 6
local SLIDE_GROUND_SNAP_MAX = 3.0
local SLIDE_FREEFALL_MIN_VY = -10
local SLIDE_FORCE = Vector3.new(1e5, 0, 1e5)
local DIVE_FORCE  = Vector3.new(3e5, 0, 3e5)

local HOVER_TARGET_OFFSET = 3.5
local HOVER_MOVE_SPEED = GameConfig.Movement.HoverSpeed
local HOVER_TURN_SPEED = 45
local HOVER_DESCEND_SPEED = 50
local HOVER_MIN_DESCEND = -100
local HOVER_RAY_MAX = 50
local HOVER_FORWARD_LEAD = 1.5

local baseWalkSpeed = 25
local BASE_JUMP_POWER = GameConfig.Game.BaseJumpPower
local savedJumpPower = BASE_JUMP_POWER

-- WallJump Config
local WALL_JUMP_TAG = "WallJump"
local WALL_BOOST_TAG = "WallBoost"
local PAD_TAG_BLUE = "JumpPad_Blue"
local PAD_TAG_PINK = "JumpPad_Pink"
local GRIND_TAG = "GrindRail"

local STICK_DURATION = 2.0 
local WALL_SLIDE_SPEED = 10 
local WALL_CHECK_DISTANCE = 3.5 
local JUMP_POWER_MULTIPLIER = 1.2 
local WALL_PUSH_POWER = 30 
local REGRAB_COOLDOWN = 0.8 
local BOOST_HEIGHT_OFFSET = 25 
local PAD_HEIGHT = 30 
local BOOST_COOLDOWN = 2.0
local GRAVITY = workspace.Gravity 
local GRIND_SPEED = 60 
local SLOPE_THRESHOLD = 0.1 

-- Teams
local blueTeam = Teams["Bright blue"]
local pinkTeam = Teams["Carnation pink"]

function MovementController:Init(controllers)
end

function MovementController:Start()
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		self:HandleInput(input)
	end)

	UserInputService.JumpRequest:Connect(function()
		self:OnJumpRequest()
	end)

	RunService.Heartbeat:Connect(function(dt)
		self:OnHeartbeat(dt)
	end)

	-- Character Added
	if player.Character then self:OnCharAdded(player.Character) end
	player.CharacterAdded:Connect(function(char) self:OnCharAdded(char) end)

	abilityUsedEvent.OnClientEvent:Connect(function(p, abilityName)
		if p ~= player then return end
		if abilityName == "Slide" then self:StartSlide()
		elseif abilityName == "Dive" then self:StartDive()
		elseif abilityName == "Hoverboard" then 
			if isHovering then self:ToggleHoverboardOff()
			else self:SetupHoverboard() end
		end
	end)

	playerStunnedEvent.OnClientEvent:Connect(function(p, duration)
		if p and p ~= player then 
			-- Visuals handled in InterfaceController
		end
	end)

	-- Initialize UI
	self:SetupUI()
	RunService.RenderStepped:Connect(function() self:UpdateUI() end)
end

function MovementController:SetupUI()
	for name, config in pairs(ABILITIES) do
		config.Icon = config.Frame:WaitForChild("Icon")
		config.CooldownBar = config.Icon:WaitForChild("CooldownBar")
		config.TimerLabel = config.Icon:WaitForChild("TimerLabel")
		config.KeybindLabel = config.Icon:WaitForChild("KeybindLabel")

		if IS_MOBILE then config.KeybindLabel.Visible = false end

		config.Icon.Activated:Connect(function()
			self:RequestAbility(name)
		end)
	end
end

function MovementController:UpdateUI()
	local now = os.clock()
	for _, config in pairs(ABILITIES) do
		if config.Icon and config.TimerLabel and config.TimerLabel.Visible then
			local rem = (config.LastUse + config.Cooldown) - now
			if rem > 0 then
				config.TimerLabel.Text = string.format("%.1fs", rem)
			else
				config.Icon.Active = true
				config.TimerLabel.Visible = false
				config.CooldownBar.Visible = false
			end
		end
	end
end

function MovementController:RequestAbility(abilityName)
	local config = ABILITIES[abilityName]
	if not config then return end

	local now = os.clock()
	if now - config.LastUse < config.Cooldown then return end

	if abilityName == "Slide" then
		if not self:CanSlide() then return end
	elseif abilityName == "Dive" then
		if not self:CanDive() then return end
	elseif abilityName == "Hoverboard" then
		-- Toggle logic handled by server response usually, but visual feedback is immediate
	end

	if abilityName ~= "Hoverboard" then
		config.LastUse = now
		self:StartCooldownUI(config)
	end

	requestAbilityEvent:FireServer(abilityName)
end

function MovementController:StartCooldownUI(config)
	if config.Icon and config.TimerLabel and config.CooldownBar then
		config.Icon.Active = false
		config.TimerLabel.Visible = true
		config.CooldownBar.Visible = true
		config.CooldownBar.Size = UDim2.new(1, 0, 1, 0)

		local tweenInfo = TweenInfo.new(config.Cooldown, Enum.EasingStyle.Linear)
		TweenService:Create(config.CooldownBar, tweenInfo, { Size = UDim2.new(1, 0, 0, 0) }):Play()
	end
end

function MovementController:OnCharAdded(char)
	self:SafeCleanup()
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")

	self:LoadAnims()

	baseWalkSpeed = humanoid.WalkSpeed
	BASE_JUMP_POWER = humanoid.JumpPower
	lastDetachTime = tick()
	lastWall = nil
	currentJumpPad = nil

	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if not isSliding and not isStunned and not isDiving and not isHovering and not isWallStuck then
			baseWalkSpeed = humanoid.WalkSpeed
		end
	end)

	humanoid.StateChanged:Connect(function(old, new)
		if isStunned and new == Enum.HumanoidStateType.Jumping then
			humanoid.Jump = false
			humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		elseif new == Enum.HumanoidStateType.Jumping then
			if isSliding then self:CancelSlideImmediate()
			elseif isHovering then requestAbilityEvent:FireServer("Hoverboard") end
		end
	end)
end

function MovementController:LoadAnims()
	if not humanoid then return end
	animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function load(id, name)
		local a = Instance.new("Animation")
		a.AnimationId = id
		a.Name = name
		local track = animator:LoadAnimation(a)
		track.Priority = Enum.AnimationPriority.Action
		return track
	end

	pcall(function()
		slideTrack = load(SLIDE_ANIM_ID, "Slide")
		diveTrack = load(DIVE_ANIM_ID, "Dive")
		stunTrack = load(STUN_ANIM_ID, "Stun")
		slideStunTrack = load(SLIDE_STUN_ANIM_ID, "SlideStun")
		diveStunTrack = load(DIVE_STUN_ANIM_ID, "DiveStun")
	end)
end

function MovementController:SafeCleanup()
	isSliding = false
	isDiving = false
	isHovering = false
	isStunned = false

	-- WallJump Cleanup
	if stickVelocity then stickVelocity:Destroy() stickVelocity = nil end
	if stickAlign then stickAlign:Destroy() stickAlign = nil end
	if grindParticles then
		if grindParticles:IsA("ParticleEmitter") then grindParticles.Enabled = false end
		Debris:AddItem(grindParticles, 1)
		grindParticles = nil
	end
	if grindAttachment then Debris:AddItem(grindAttachment, 1) grindAttachment = nil end
	isWallStuck = false
	isGrinding = false
	lastDetachTime = tick()

	if slideConnection then slideConnection:Disconnect() slideConnection = nil end
	if diveConnection then diveConnection:Disconnect() diveConnection = nil end
	if hoverConnection then hoverConnection:Disconnect() hoverConnection = nil end

	if slideTrack then pcall(function() slideTrack:Stop() end) end
	if diveTrack then pcall(function() diveTrack:Stop() end) end
	if stunTrack then pcall(function() stunTrack:Stop() end) end
	if slideStunTrack then pcall(function() slideStunTrack:Stop() end) end
	if diveStunTrack then pcall(function() diveStunTrack:Stop() end) end

	if hoverTargetPart then pcall(function() hoverTargetPart:Destroy() end) hoverTargetPart = nil end
	if rootHoverAttachment then pcall(function() rootHoverAttachment:Destroy() end) rootHoverAttachment = nil end
	if hoverTargetAttachment then pcall(function() hoverTargetAttachment:Destroy() end) hoverTargetAttachment = nil end
	if hoverAlign then pcall(function() hoverAlign:Destroy() end) hoverAlign = nil end
	if hoverOrient then pcall(function() hoverOrient:Destroy() end) hoverOrient = nil end
	if hoverLinear then pcall(function() hoverLinear:Destroy() end) hoverLinear = nil end

	if slideInvincibleTag then pcall(function() slideInvincibleTag:Destroy() end) slideInvincibleTag = nil end

	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid.WalkSpeed = baseWalkSpeed
		humanoid.JumpPower = BASE_JUMP_POWER
		humanoid.Jump = false
	end

	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)

	if rootPart then
		for _, name in ipairs({"SlideVelocity", "DiveVelocity", "HoverLinearVelocity", "WallStickVelocity", "GrindVelocity"}) do
			local v = rootPart:FindFirstChild(name)
			if v then pcall(function() v:Destroy() end) end
		end
	end

	-- Restore tool if needed
	if lastEquippedTool and lastEquippedTool.Parent == player.Backpack then
		humanoid:EquipTool(lastEquippedTool)
	end
	lastEquippedTool = nil
end

function MovementController:HandleInput(input)
	if input.KeyCode == Enum.KeyCode.C then
		if not isWallStuck and not isGrinding then
			self:RequestAbility("Slide")
		end
	elseif input.KeyCode == Enum.KeyCode.X then
		if not isWallStuck and not isGrinding then
			self:RequestAbility("Dive")
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		if not isWallStuck and not isGrinding then
			self:RequestAbility("Hoverboard")
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		if isWallStuck then self:PerformUnstick() end
	end
end

-- Predicates
function MovementController:CanSlide()
	if not humanoid or not rootPart then return false end
	if isSliding or isDiving or isStunned or isHovering then return false end
	if humanoid.FloorMaterial == Enum.Material.Air then return false end
	if humanoid.MoveDirection.Magnitude < 0.1 then return false end
	if self:IsSlidingUphill() then return false end
	return true
end

function MovementController:CanDive()
	if not humanoid or not rootPart then return false end
	if isSliding or isDiving or isStunned or isHovering then return false end
	if humanoid.FloorMaterial == Enum.Material.Air then return false end
	return true
end

function MovementController:IsSlidingUphill()
	if not rootPart then return false end
	local rayOrigin = rootPart.Position
	local rayDirection = Vector3.new(0, -6, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {player.Character}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local groundCheck = Workspace:Raycast(rayOrigin, rayDirection, params)
	if not (groundCheck and groundCheck.Normal) then return false end

	local groundNormal = groundCheck.Normal
	local slopeXZ = Vector3.new(-groundNormal.X, 0, -groundNormal.Z)
	if slopeXZ.Magnitude < 0.01 then return false end
	local slopeDirection = slopeXZ.Unit

	local movementXZ = Vector3.new(rootPart.Velocity.X, 0, rootPart.Velocity.Z)
	if movementXZ.Magnitude < 0.5 then
		movementXZ = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	if movementXZ.Magnitude < 0.01 then return false end

	local dot = movementXZ.Unit:Dot(slopeDirection)
	local groundAngle = math.deg(math.acos(groundNormal.Y))
	if groundAngle > 8 and dot > 0.45 then return true end
	return false
end

-- Abilities
function MovementController:StartSlide()
	if not humanoid or not rootPart then return end

	isSliding = true
	if slideTrack then
		slideTrack.Priority = Enum.AnimationPriority.Action
		slideTrack:Play()
	end

	if slideInvincibleTag then slideInvincibleTag:Destroy() end
	slideInvincibleTag = Instance.new("BoolValue")
	slideInvincibleTag.Name = "Invincible"
	slideInvincibleTag.Parent = player.Character

	local dir = rootPart.CFrame.LookVector
	local vel = Instance.new("BodyVelocity")
	vel.Name = "SlideVelocity"
	vel.MaxForce = SLIDE_FORCE
	vel.Velocity = Vector3.new(dir.X * GameConfig.Movement.SlideSpeed, 0, dir.Z * GameConfig.Movement.SlideSpeed)
	vel.Parent = rootPart

	local av = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(dir.X * GameConfig.Movement.SlideSpeed, av.Y, dir.Z * GameConfig.Movement.SlideSpeed)

	humanoid.WalkSpeed = 0

	if slideConnection then slideConnection:Disconnect() end
	slideConnection = RunService.Heartbeat:Connect(function() self:OnSlideUpdate() end)

	task.delay(1.0, function()
		if isSliding then self:CancelSlideImmediate() end
	end)
end

function MovementController:CancelSlideImmediate()
	if not isSliding then return end
	isSliding = false

	if rootPart then
		local v = rootPart:FindFirstChild("SlideVelocity")
		if v then v:Destroy() end
	end
	if slideTrack then slideTrack:Stop() end
	if slideInvincibleTag then slideInvincibleTag:Destroy() slideInvincibleTag = nil end

	if humanoid and not isStunned then
		humanoid.WalkSpeed = baseWalkSpeed
	end
	if slideConnection then slideConnection:Disconnect() slideConnection = nil end
end

function MovementController:OnSlideUpdate()
	if not isSliding or not humanoid or not rootPart or humanoid.Health <= 0 then
		self:CancelSlideImmediate()
		return
	end

	if self:CheckWallCollision(rootPart.CFrame.LookVector, 3) then
		print("Slide hit wall!")
		self:CancelSlideImmediate()
		self:ApplyStun(1.7, slideStunTrack or stunTrack)
		return
	end

	if self:IsSlidingUphill() then
		self:CancelSlideImmediate()
		return
	end

	-- Ground Snapping
	local rayOrigin = rootPart.Position + Vector3.new(0, 1, 0)
	local rayDir = Vector3.new(0, -SLIDE_GROUND_CHECK, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {player.Character}
	local hit = Workspace:Raycast(rayOrigin, rayDir, params)

	if hit then
		local desiredY = hit.Position.Y + 2
		local diff = rootPart.Position.Y - desiredY
		if diff > 0.15 and diff <= SLIDE_GROUND_SNAP_MAX then
			local av = rootPart.AssemblyLinearVelocity
			if av.Y > -12 then
				rootPart.AssemblyLinearVelocity = Vector3.new(av.X, math.max(-35, -diff * 20), av.Z)
			end
		end
	else
		local av = rootPart.AssemblyLinearVelocity
		if av.Y < SLIDE_FREEFALL_MIN_VY then
			self:CancelSlideImmediate()
			return
		end
	end
end

function MovementController:StartDive()
	isDiving = true
	if diveTrack then
		diveTrack.Priority = Enum.AnimationPriority.Action
		diveTrack:Play()
	end

	local tag = Instance.new("BoolValue")
	tag.Name = "Invincible"
	tag.Parent = player.Character

	local dir = humanoid.MoveDirection
	if dir.Magnitude == 0 then dir = rootPart.CFrame.LookVector end

	local vel = Instance.new("BodyVelocity")
	vel.Name = "DiveVelocity"
	vel.MaxForce = DIVE_FORCE
	vel.Velocity = Vector3.new(dir.Unit.X * GameConfig.Movement.DiveSpeed, 0, dir.Unit.Z * GameConfig.Movement.DiveSpeed)
	vel.Parent = rootPart

	local av = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(dir.Unit.X * GameConfig.Movement.DiveSpeed, av.Y, dir.Unit.Z * GameConfig.Movement.DiveSpeed)

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	if diveConnection then diveConnection:Disconnect() end
	diveConnection = RunService.Heartbeat:Connect(function() self:OnDiveUpdate() end)

	task.delay(0.3, function()
		if isDiving then
			isDiving = false
			if vel.Parent then vel:Destroy() end
			if diveTrack then diveTrack:Stop() end
			if tag.Parent then tag:Destroy() end
			if humanoid and not isStunned then
				humanoid.WalkSpeed = baseWalkSpeed
				humanoid.JumpPower = BASE_JUMP_POWER
			end
			if diveConnection then diveConnection:Disconnect() diveConnection = nil end
		end
	end)
end

function MovementController:OnDiveUpdate()
	if not isDiving or not humanoid or not rootPart or humanoid.Health <= 0 then
		isDiving = false
		if diveConnection then diveConnection:Disconnect() diveConnection = nil end
		if diveTrack then diveTrack:Stop() end
		if humanoid and not isStunned then
			humanoid.WalkSpeed = baseWalkSpeed
			humanoid.JumpPower = BASE_JUMP_POWER
		end
		return
	end

	local vel = rootPart.Velocity
	local dir = (vel.Magnitude > 0) and vel.Unit or rootPart.CFrame.LookVector

	if self:CheckWallCollision(dir, 3) then
		print("Dive hit wall!")
		isDiving = false
		if rootPart:FindFirstChild("DiveVelocity") then rootPart.DiveVelocity:Destroy() end
		if diveTrack then diveTrack:Stop() end
		self:ApplyStun(1.6, diveStunTrack or stunTrack)
		return
	end
end

function MovementController:SetupHoverboard()
	if not humanoid or not rootPart or not player.Character then return false end

	lastEquippedTool = player.Character:FindFirstChildOfClass("Tool")
	if lastEquippedTool then
		lastEquippedTool.Parent = player.Backpack
	end

	self:SafeCleanup()

	hoverTargetPart = Instance.new("Part")
	hoverTargetPart.Name = "HoverboardTarget"
	hoverTargetPart.Size = Vector3.new(1,1,1)
	hoverTargetPart.Transparency = 1
	hoverTargetPart.Anchored = true
	hoverTargetPart.CanCollide = false
	hoverTargetPart.Parent = Workspace
	hoverTargetPart.Position = rootPart.Position

	rootHoverAttachment = Instance.new("Attachment")
	rootHoverAttachment.Parent = rootPart
	hoverTargetAttachment = Instance.new("Attachment")
	hoverTargetAttachment.Parent = hoverTargetPart

	hoverAlign = Instance.new("AlignPosition")
	hoverAlign.MaxForce = 30000
	hoverAlign.MaxVelocity = 60
	hoverAlign.Responsiveness = 100
	hoverAlign.Attachment0 = rootHoverAttachment
	hoverAlign.Attachment1 = hoverTargetAttachment
	hoverAlign.Parent = rootPart

	hoverOrient = Instance.new("AlignOrientation")
	hoverOrient.MaxTorque = 20000
	hoverOrient.Responsiveness = HOVER_TURN_SPEED
	hoverOrient.Attachment0 = rootHoverAttachment
	hoverOrient.Attachment1 = hoverTargetAttachment
	hoverOrient.Parent = rootPart

	hoverLinear = Instance.new("LinearVelocity")
	hoverLinear.Attachment0 = rootHoverAttachment
	hoverLinear.MaxForce = 25000
	hoverLinear.Parent = rootPart
	hoverLinear.VectorVelocity = Vector3.zero

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	isHovering = true
	if hoverConnection then hoverConnection:Disconnect() end
	hoverConnection = RunService.Heartbeat:Connect(function(dt) self:UpdateHoverboard(dt) end)

	local config = ABILITIES.Hoverboard
	config.LastUse = os.clock()
	self:StartCooldownUI(config)

	return true
end

function MovementController:UpdateHoverboard(dt)
	if not isHovering or not humanoid or not rootPart or not hoverTargetPart then
		if hoverConnection then hoverConnection:Disconnect() end
		return
	end

	local rayOrigin = rootPart.Position + Vector3.new(0, 2, 0)
	local groundHit = self:PerformHoverboardRaycast(rayOrigin, Vector3.new(0, -HOVER_RAY_MAX, 0))

	local targetY
	if groundHit then
		targetY = groundHit.Position.Y + HOVER_TARGET_OFFSET
	else
		targetY = math.max(rootPart.Position.Y + HOVER_MIN_DESCEND, hoverTargetPart.Position.Y - (HOVER_DESCEND_SPEED * dt))
	end

	local moveDir = humanoid.MoveDirection
	local vel = (moveDir.Magnitude > 0.05) and Vector3.new(moveDir.X * HOVER_MOVE_SPEED, 0, moveDir.Z * HOVER_MOVE_SPEED) or Vector3.zero
	if hoverLinear then hoverLinear.VectorVelocity = vel end

	local forwardOffset = (moveDir.Magnitude > 0.05) and Vector3.new(moveDir.Unit.X * HOVER_FORWARD_LEAD, 0, moveDir.Unit.Z * HOVER_FORWARD_LEAD) or Vector3.zero
	hoverTargetPart.Position = Vector3.new(rootPart.Position.X, targetY, rootPart.Position.Z) + forwardOffset

	local cam = Workspace.CurrentCamera
	if cam then
		local lookDir
		if moveDir.Magnitude > 0.1 then
			lookDir = moveDir
		else
			lookDir = cam.CFrame.LookVector
		end
		local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
		if flatLook.Magnitude > 0.01 then
			hoverTargetPart.CFrame = CFrame.new(hoverTargetPart.Position, hoverTargetPart.Position + flatLook.Unit)
		end
	end
end

function MovementController:ToggleHoverboardOff()
	if not isHovering then return end
	isHovering = false

	if hoverConnection then hoverConnection:Disconnect() hoverConnection = nil end
	self:SafeCleanup() -- Re-using cleanup for simplicity as it clears everything.

	local config = ABILITIES.Hoverboard
	config.LastUse = os.clock()
	self:StartCooldownUI(config)
end

function MovementController:PerformHoverboardRaycast(origin, direction)
	local params = RaycastParams.new()
	local filter = {player.Character}
	params.FilterDescendantsInstances = filter
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hit = Workspace:Raycast(origin, direction, params)
	if hit and hit.Instance and not hit.Instance.CanCollide then
		local traveled = (hit.Position - origin).Magnitude
		local rem = direction.Magnitude - traveled
		if rem > 0 then
			return self:PerformHoverboardRaycast(hit.Position + direction.Unit * 0.1, direction.Unit * rem)
		end
		return nil
	end
	return hit
end

function MovementController:CheckWallCollision(direction, distance)
	if not rootPart then return false end
	local rayOrigin = rootPart.Position
	local rayDirection = direction * distance
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local hit = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	return (hit and hit.Instance and hit.Instance.CanCollide)
end

function MovementController:ApplyStun(duration, animTrack)
	if not isStunned and humanoid then
		savedJumpPower = humanoid.JumpPower
	end

	isStunned = true
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.Jump = false
		if humanoid:GetState() == Enum.HumanoidStateType.Jumping then
			humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		end
	end

	if slideTrack then pcall(function() slideTrack:Stop() end) end
	if diveTrack then pcall(function() diveTrack:Stop() end) end

	local played = false
	if animTrack then
		played = pcall(function() animTrack.Priority = Enum.AnimationPriority.Action; animTrack:Play(0.15) end)
	end
	if not played and stunTrack then
		pcall(function() stunTrack.Priority = Enum.AnimationPriority.Action; stunTrack:Play(0.15) end)
	end

	reportStunEvent:FireServer(duration or 1.6)

	task.delay(duration or 1.6, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = baseWalkSpeed
			humanoid.JumpPower = savedJumpPower
			humanoid.Jump = false
		end
		if animTrack then pcall(function() animTrack:Stop(0.15) end) end
		if stunTrack then pcall(function() stunTrack:Stop(0.15) end) end
		isStunned = false
	end)
end

-- ===================================================================
-- WALL JUMP & BOOST LOGIC
-- ===================================================================

function MovementController:OnJumpRequest()
	if isStunned and humanoid then
		humanoid.Jump = false
		humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		return
	end

	if isSliding then
		self:CancelSlideImmediate()
	end

	if isWallStuck then
		self:PerformWallJump()
		return
	end

	if isGrinding then
		self:SafeCleanup()
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		rootPart.Velocity = rootPart.Velocity + Vector3.new(0, 50, 0)
		return
	end

	if currentJumpPad then
		self:LaunchFromPad()
		return
	end
end

function MovementController:PerformUnstick()
	if not isWallStuck and not isGrinding then return end
	print("Unsticking...")
	self:SafeCleanup()
end

function MovementController:StartGrinding(railResult)
	if isGrinding or isWallStuck then return end

	local currentTool = player.Character:FindFirstChildOfClass("Tool")
	if currentTool then lastEquippedTool = currentTool end
	humanoid:UnequipTools()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	isGrinding = true

	local att = Instance.new("Attachment", rootPart)

	stickVelocity = Instance.new("LinearVelocity")
	stickVelocity.Name = "GrindVelocity"
	stickVelocity.Attachment0 = att
	stickVelocity.MaxForce = 50000
	stickVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	stickVelocity.Parent = rootPart

	stickAlign = Instance.new("AlignOrientation")
	stickAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	stickAlign.Attachment0 = att
	stickAlign.RigidityEnabled = false
	stickAlign.Responsiveness = 50
	stickAlign.Parent = rootPart

	-- Sparks
	if grindSparksTemplate then
		grindAttachment = Instance.new("Attachment")
		grindAttachment.Position = Vector3.new(0, -2.8, 0)
		grindAttachment.Parent = rootPart

		local sparkClone = grindSparksTemplate:Clone()
		if sparkClone:IsA("ParticleEmitter") then
			grindParticles = sparkClone
		else
			local realEmitter = sparkClone:FindFirstChildWhichIsA("ParticleEmitter", true)
			if realEmitter then
				grindParticles = realEmitter:Clone()
				sparkClone:Destroy()
			end
		end

		if grindParticles then
			grindParticles.Parent = grindAttachment
			grindParticles.Enabled = true
		end
	end

	humanoid.PlatformStand = true
end

function MovementController:UpdateGrind()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {player.Character}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(rootPart.Position, Vector3.new(0, -5, 0), params)

	if not result or not CollectionService:HasTag(result.Instance, GRIND_TAG) then
		self:SafeCleanup()
		return
	end

	local railPart = result.Instance
	local railDir = railPart.CFrame.LookVector

	if math.abs(railDir.Y) > SLOPE_THRESHOLD then
		if railDir.Y > 0 then railDir = -railDir end
	else
		local playerFace = rootPart.CFrame.LookVector
		if playerFace:Dot(railDir) < 0 then railDir = -railDir end
	end

	if stickVelocity then stickVelocity.VectorVelocity = railDir * GRIND_SPEED end
	if stickAlign then stickAlign.CFrame = CFrame.lookAt(Vector3.new(0,0,0), railDir) end
end

function MovementController:LaunchFromPad()
	if not currentJumpPad then return end
	if tick() - lastBoostTime < BOOST_COOLDOWN then return end

	if wallJumpSound then
		local s = wallJumpSound:Clone()
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, s.TimeLength + 0.1)
	end

	lastBoostTime = tick()
	requestWallBoostEvent:FireServer(currentJumpPad.Position)

	local currentY = rootPart.Position.Y
	local targetY = currentY + PAD_HEIGHT
	local displacement = targetY - currentY
	if displacement < 0 then displacement = 0 end
	local upVelocity = math.sqrt(2 * GRAVITY * displacement)

	local currentVel = rootPart.Velocity
	rootPart.Velocity = Vector3.new(currentVel.X, upVelocity, currentVel.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

function MovementController:PerformWallBoost(wallResult)
	local now = tick()
	if now - lastBoostTime < BOOST_COOLDOWN then return end
	lastBoostTime = now

	if wallJumpSound then
		local s = wallJumpSound:Clone()
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, s.TimeLength + 0.1)
	end

	local wallPart = wallResult.Instance
	local wallTopY = wallPart.Position.Y + (wallPart.Size.Y / 2)
	local targetY = wallTopY + BOOST_HEIGHT_OFFSET
	local currentY = rootPart.Position.Y
	if currentY >= wallTopY then targetY = currentY + 20 end

	local displacement = targetY - currentY
	if displacement < 0 then displacement = 0 end
	local upVelocity = math.sqrt(2 * GRAVITY * displacement)

	local currentVel = rootPart.Velocity
	rootPart.Velocity = Vector3.new(currentVel.X, upVelocity, currentVel.Z)

	requestWallBoostEvent:FireServer(wallPart.Position)
end

function MovementController:AttachToWall(wallResult)
	if isWallStuck then return end
	if not rootPart or not humanoid then return end

	if wallJumpSound then
		local s = wallJumpSound:Clone()
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, s.TimeLength + 0.1)
	end

	requestWallJumpEvent:FireServer(wallResult.Instance.Position)

	isWallStuck = true
	stuckTime = tick()
	currentWallNormal = wallResult.Normal
	lastWall = wallResult.Instance

	local currentTool = player.Character:FindFirstChildOfClass("Tool")
	if currentTool then lastEquippedTool = currentTool end

	humanoid:UnequipTools()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	local att = Instance.new("Attachment", rootPart)

	stickVelocity = Instance.new("LinearVelocity")
	stickVelocity.Name = "WallStickVelocity"
	stickVelocity.Attachment0 = att
	stickVelocity.MaxForce = 100000
	stickVelocity.VectorVelocity = Vector3.new(0, 0, 0)
	stickVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	stickVelocity.Parent = rootPart

	local lookDir = -wallResult.Normal
	local targetCFrame = CFrame.lookAt(Vector3.new(0,0,0), Vector3.new(lookDir.X, 0, lookDir.Z))

	stickAlign = Instance.new("AlignOrientation")
	stickAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	stickAlign.Attachment0 = att
	stickAlign.RigidityEnabled = false
	stickAlign.Responsiveness = 50
	stickAlign.CFrame = targetCFrame
	stickAlign.Parent = rootPart

	humanoid.AutoRotate = false
end

function MovementController:PerformWallJump()
	if not isWallStuck then return end

	local moveDir = humanoid.MoveDirection
	local dot = moveDir:Dot(currentWallNormal)

	if dot > 0.2 then 
		self:SafeCleanup()

		if moveDir.Magnitude > 0 then
			local lookAt = rootPart.Position + moveDir
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(lookAt.X, rootPart.Position.Y, lookAt.Z))
		end

		local jumpDir = (currentWallNormal * WALL_PUSH_POWER) + Vector3.new(0, humanoid.JumpPower * JUMP_POWER_MULTIPLIER, 0)
		rootPart.Velocity = jumpDir
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	else
		stuckTime = tick() - STICK_DURATION - 0.1
	end
end

function MovementController:OnHeartbeat(dt)
	if not humanoid or not rootPart or humanoid.Health <= 0 then 
		if isWallStuck or isGrinding or isSliding or isDiving or isHovering then self:SafeCleanup() end
		return 
	end

	-- States
	if isSliding then 
		self:OnSlideUpdate()
		-- return -- Concurrent states? Slide is aggressive, return might be ok.
	end
	if isDiving then
		self:OnDiveUpdate()
	end
	if isHovering then
		self:UpdateHoverboard(dt)
		return -- Exclusive
	end
	if isGrinding then
		self:UpdateGrind()
		return -- Exclusive
	end

	-- WallJump / Pad Logic
	currentJumpPad = nil
	local padRayParams = RaycastParams.new()
	padRayParams.FilterDescendantsInstances = {player.Character}
	local padResult = Workspace:Raycast(rootPart.Position, Vector3.new(0, -4, 0), padRayParams)

	if padResult then
		local hitPart = padResult.Instance
		local myTeam = player.Team

		if (CollectionService:HasTag(hitPart, PAD_TAG_BLUE) and myTeam == blueTeam) or
			(CollectionService:HasTag(hitPart, PAD_TAG_PINK) and myTeam == pinkTeam) then
			currentJumpPad = hitPart
		elseif CollectionService:HasTag(hitPart, GRIND_TAG) and not isWallStuck then
			if humanoid.FloorMaterial == Enum.Material.Air then
				self:StartGrinding(padResult)
			end
		end
	end

	if not isWallStuck then
		if humanoid.FloorMaterial == Enum.Material.Air and not isSliding and not isDiving then
			local rayOrigin = rootPart.Position
			local directions = {
				rootPart.CFrame.LookVector,
				-rootPart.CFrame.LookVector,
				rootPart.CFrame.RightVector,
				-rootPart.CFrame.RightVector
			}
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = {player.Character}
			params.FilterType = Enum.RaycastFilterType.Exclude

			local foundWallResult = nil

			for _, dir in ipairs(directions) do
				local rayDir = dir * WALL_CHECK_DISTANCE
				local result = Workspace:Raycast(rayOrigin, rayDir, params)
				if result and result.Instance then
					foundWallResult = result
					break 
				end
			end

			if foundWallResult then
				local instance = foundWallResult.Instance
				if CollectionService:HasTag(instance, WALL_BOOST_TAG) then
					self:PerformWallBoost(foundWallResult)
				elseif CollectionService:HasTag(instance, WALL_JUMP_TAG) then
					if instance == lastWall and (tick() - lastDetachTime < REGRAB_COOLDOWN) then
						return 
					end
					self:AttachToWall(foundWallResult)
				end
			end
		end
	else
		-- IF STUCK
		local rayOrigin = rootPart.Position
		local rayDir = Vector3.new(0, -3.5, 0)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {player.Character}
		params.FilterType = Enum.RaycastFilterType.Exclude

		if Workspace:Raycast(rayOrigin, rayDir, params) then
			self:SafeCleanup()
			return
		end

		local timeStuck = tick() - stuckTime
		if timeStuck > STICK_DURATION + 1.5 then
			self:SafeCleanup() 
		elseif timeStuck > STICK_DURATION then
			if stickVelocity then
				stickVelocity.VectorVelocity = Vector3.new(0, -WALL_SLIDE_SPEED, 0)
			end
		end
	end
end

return MovementController
