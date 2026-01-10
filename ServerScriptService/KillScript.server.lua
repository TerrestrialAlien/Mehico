-- ServerScriptService/TaggedKillBricks.lua
local CollectionService = game:GetService("CollectionService")
local TAG = "KillBrick"
local debounce = {}

local function onTouched(part, hit)
	local char = hit.Parent
	local player = game.Players:GetPlayerFromCharacter(char)
	if not player then return end
	if debounce[player] then return end
	debounce[player] = true

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end

	task.wait(0.5)
	debounce[player] = nil
end

local function hookPart(p)
	if not p:IsA("BasePart") then return end
	p.Touched:Connect(function(hit) onTouched(p, hit) end)
end

-- Hook existing tagged parts
for _, p in pairs(CollectionService:GetTagged(TAG)) do
	hookPart(p)
end

-- Hook future tagged parts
CollectionService:GetInstanceAddedSignal(TAG):Connect(hookPart)
