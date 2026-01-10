local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")

local loadedServices = {}

-- 1. Load all modules
for _, module in ipairs(Services:GetChildren()) do
    if module:IsA("ModuleScript") then
        loadedServices[module.Name] = require(module)
    end
end

-- 2. Initialize them
for _, service in pairs(loadedServices) do
    if service.Init then service:Init(loadedServices) end
end

-- 3. Start them
for _, service in pairs(loadedServices) do
    if service.Start then service:Start() end
end

print("ServerLoader finished loading services.")
