local config = {}
config.taskName = "RF2 ELRS Telemetry"
config.taskKey = "pasfkas"
config.taskDir = "/scripts/rf2elrstelemetry/"
config.useCompiler = true

local compile = assert(loadfile(config.taskDir .. "compile.lua"))(config)

rf2elrstelemetry = assert(compile.loadScript(config.taskDir .. "rf2elrstelemetry.lua"))(config, compile)

local function init()
    system.registerTask({name = config.taskName, key = config.taskKey, wakeup = rf2elrstelemetry.run})
end

return {init = init}
