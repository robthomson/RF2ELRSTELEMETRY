
local config = {}
config.taskName = "RF2 ELRS Telemetry"
config.taskKey = "pasfkas"
config.taskDir = "/scripts/rf2elrstelemetry/"
config.useCompiler = true

local compile = assert(loadfile(config.taskDir .. "compile.lua"))(config)

rf2elrstelemetry = assert(compile.loadScript(config.taskDir .. "rf2elrstelemetry.lua"))(config,compile)

local function paint()
	return rf2elrstelemetry.paint()
end

local function wakeup()
	return rf2elrstelemetry.crossfirePopAll()
end

local function create()
	return rf2elrstelemetry.create()
end

local function init()
	system.registerTask({
		name=config.taskName,
		key=config.taskKey,
		wakeup=wakeup})
end

return {init = init}
