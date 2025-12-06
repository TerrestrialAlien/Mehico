local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Controllers = ReplicatedStorage:WaitForChild("Controllers")

local loadedControllers = {}

-- 1. Load all modules
for _, module in ipairs(Controllers:GetChildren()) do
    if module:IsA("ModuleScript") then
        loadedControllers[module.Name] = require(module)
    end
end

-- 2. Initialize them
for _, controller in pairs(loadedControllers) do
    if controller.Init then controller:Init(loadedControllers) end
end

-- 3. Start them
for _, controller in pairs(loadedControllers) do
    if controller.Start then controller:Start() end
end

print("ClientLoader finished loading controllers.")
