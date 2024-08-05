--
-- Rotorflight Custom Telemetry Decoder for ELRS
--
rf2elrstelemetry = {}

local CRSF_FRAME_CUSTOM_TELEM = 0x88


rf2elrstelemetry.sensorTABLE = {}
rf2elrstelemetry.sensorRecheck = {}
rf2elrstelemetry.initialiseTime = 15
rf2elrstelemetry.initialise = os.clock()
rf2elrstelemetry.initialiseSensors = false


function rf2elrstelemetry.setTelemetryValue(id, subId, instance, value, unit, dec, name)

	local uid = id .. "_" .. instance
		
	if id ~= nil then
	
		if rf2elrstelemetry.initialiseSensors == true then
	
            print("Checking sensor exists: [" .. name .. "]")
            rf2elrstelemetry.sensorTABLE[uid] = {}
            rf2elrstelemetry.sensorTABLE[uid] = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = id})
			
            -- create sensor if it does not exist
            if rf2elrstelemetry.sensorTABLE[uid] == nil then
                print("Creating sensor: [" .. name .. "]")
                rf2elrstelemetry.sensorTABLE[uid] = model.createSensor()
                rf2elrstelemetry.sensorTABLE[uid]:name(name)
                rf2elrstelemetry.sensorTABLE[uid]:appId(id)
                rf2elrstelemetry.sensorTABLE[uid]:physId(instance)
            end

            -- we always re-set these values below on a check cycle.
            -- this is to ensure that if a user edits the sensor that
            -- we put it back to the correct settings.
            rf2elrstelemetry.sensorTABLE[uid]:maximum(65000)
            rf2elrstelemetry.sensorTABLE[uid]:minimum(-65000)

            if dec ~= nil then
                rf2elrstelemetry.sensorTABLE[uid]:decimals(dec)
                rf2elrstelemetry.sensorTABLE[uid]:protocolDecimals(dec)
            end
            if unit ~= nil then
                rf2elrstelemetry.sensorTABLE[uid]:unit(unit)
                rf2elrstelemetry.sensorTABLE[uid]:protocolUnit(unit)
            end

		end

        if rf2elrstelemetry.sensorTABLE[uid] ~= nil then rf2elrstelemetry.sensorTABLE[uid]:value(value) end
		
	end
end

function rf2elrstelemetry.crossfireTelemetryPop()
    local command, data = crsf.popFrame()
    return command, data
end

function rf2elrstelemetry.trim(n)
    return n & 0xFFFFFFFF
end

function rf2elrstelemetry.mask(w)
    return ~(0xFFFFFFFF << w)
end

function rf2elrstelemetry.lshift(x, disp)
    return rf2elrstelemetry.trim(x << disp)
end

function rf2elrstelemetry.fieldargs(f, w)
    w = w or 1
    assert(f >= 0, "field cannot be negative")
    assert(w > 0, "width must be positive")
    assert(f + w <= 32, "trying to access non-existent bits")
    return f, w
end

function rf2elrstelemetry.extract(n, field, width)
    local f, w = rf2elrstelemetry.fieldargs(field, width)
    return (n >> f) & rf2elrstelemetry.mask(w)
end

function rf2elrstelemetry.decNil(data, pos)
    return nil, pos
end

function rf2elrstelemetry.decU8(data, pos)
    return data[pos], pos + 1
end

function rf2elrstelemetry.decS8(data, pos)
    local val, ptr = rf2elrstelemetry.decU8(data, pos)
    return val < 0x80 and val or val - 0x100, ptr
end

function rf2elrstelemetry.decU16(data, pos)
    return rf2elrstelemetry.lshift(data[pos], 8) + data[pos + 1], pos + 2
end

function rf2elrstelemetry.decS16(data, pos)
    local val, ptr = rf2elrstelemetry.decU16(data, pos)
    return val < 0x8000 and val or val - 0x10000, ptr
end

function rf2elrstelemetry.decU12U12(data, pos)
    local a = rf2elrstelemetry.lshift(rf2elrstelemetry.extract(data[pos], 0, 4), 8) + data[pos + 1]
    local b = rf2elrstelemetry.lshift(rf2elrstelemetry.extract(data[pos], 4, 4), 8) + data[pos + 2]
    return a, b, pos + 3
end

function rf2elrstelemetry.decS12S12(data, pos)
    local a, b, ptr = rf2elrstelemetry.decU12U12(data, pos)
    return a < 0x0800 and a or a - 0x1000, b < 0x0800 and b or b - 0x1000, ptr
end

function rf2elrstelemetry.decU24(data, pos)
    return rf2elrstelemetry.lshift(data[pos], 16) + rf2elrstelemetry.lshift(data[pos + 1], 8) + data[pos + 2], pos + 3
end

function rf2elrstelemetry.decS24(data, pos)
    local val, ptr = rf2elrstelemetry.decU24(data, pos)
    return val < 0x800000 and val or val - 0x1000000, ptr
end

function rf2elrstelemetry.decU32(data, pos)
    return rf2elrstelemetry.lshift(data[pos], 24) + rf2elrstelemetry.lshift(data[pos + 1], 16) + rf2elrstelemetry.lshift(data[pos + 2], 8) + data[pos + 3], pos + 4
end

function rf2elrstelemetry.decS32(data, pos)
    local val, ptr = rf2elrstelemetry.decU32(data, pos)
    return val < 0x80000000 and val or val - 0x100000000, ptr
end

function rf2elrstelemetry.decCellV(data, pos)
    local val, ptr = rf2elrstelemetry.decU8(data, pos)
    return val > 0 and val + 200 or 0, ptr
end

function rf2elrstelemetry.decCells(data, pos)
    local cnt, val, vol
    cnt, pos = rf2elrstelemetry.decU8(data, pos)
    rf2elrstelemetry.setTelemetryValue(0x1020, 0, 0, cnt, UNIT_RAW, 0, "Cel#")
    for i = 1, cnt do
        val, pos = rf2elrstelemetry.decU8(data, pos)
        val = val > 0 and val + 200 or 0
        vol = rf2elrstelemetry.lshift(cnt, 24) + rf2elrstelemetry.lshift(i - 1, 16) + val
        rf2elrstelemetry.setTelemetryValue(0x102F, 0, 0, vol, UNIT_CELLS, 2, "Cels")
    end
    return nil, pos
end

function rf2elrstelemetry.decControl(data, pos)
    local r, p, y, c
    p, r, pos = rf2elrstelemetry.decS12S12(data, pos)
    y, c, pos = rf2elrstelemetry.decS12S12(data, pos)
    rf2elrstelemetry.setTelemetryValue(0x1031, 0, 0, p, UNIT_DEGREE, 2, "CPtc")
    rf2elrstelemetry.setTelemetryValue(0x1032, 0, 0, r, UNIT_DEGREE, 2, "CRol")
    rf2elrstelemetry.setTelemetryValue(0x1033, 0, 0, y, UNIT_DEGREE, 2, "CYaw")
    rf2elrstelemetry.setTelemetryValue(0x1034, 0, 0, c, UNIT_DEGREE, 2, "CCol")
    return nil, pos
end

function rf2elrstelemetry.decAttitude(data, pos)
    local p, r, y
    p, pos = rf2elrstelemetry.decS16(data, pos)
    r, pos = rf2elrstelemetry.decS16(data, pos)
    y, pos = rf2elrstelemetry.decS16(data, pos)
    rf2elrstelemetry.setTelemetryValue(0x1101, 0, 0, p, UNIT_DEGREE, 1, "Ptch")
    rf2elrstelemetry.setTelemetryValue(0x1102, 0, 0, r, UNIT_DEGREE, 1, "Roll")
    rf2elrstelemetry.setTelemetryValue(0x1103, 0, 0, y, UNIT_DEGREE, 1, "Yaw")
    return nil, pos
end

function rf2elrstelemetry.decAccel(data, pos)
    local x, y, z
    x, pos = rf2elrstelemetry.decS16(data, pos)
    y, pos = rf2elrstelemetry.decS16(data, pos)
    z, pos = rf2elrstelemetry.decS16(data, pos)
    rf2elrstelemetry.setTelemetryValue(0x1111, 0, 0, x, UNIT_G, 2, "AccX")
    rf2elrstelemetry.setTelemetryValue(0x1112, 0, 0, y, UNIT_G, 2, "AccY")
    rf2elrstelemetry.setTelemetryValue(0x1113, 0, 0, z, UNIT_G, 2, "AccZ")
    return nil, pos
end

function rf2elrstelemetry.decLatLong(data, pos)
    local lat, lon
    lat, pos = rf2elrstelemetry.decS32(data, pos)
    lon, pos = rf2elrstelemetry.decS32(data, pos)
    rf2elrstelemetry.setTelemetryValue(0x1125, 0, 0, 0, UNIT_GPS, 0, "GPS")
    rf2elrstelemetry.setTelemetryValue(0x1125, 0, 0, lat, UNIT_GPS_LATITUDE)
    rf2elrstelemetry.setTelemetryValue(0x1125, 0, 0, lon, UNIT_GPS_LONGITUDE)
    return nil, pos
end

function rf2elrstelemetry.decAdjFunc(data, pos)
    local fun, val
    fun, pos = rf2elrstelemetry.decU16(data, pos)
    val, pos = rf2elrstelemetry.decS32(data, pos)
    rf2elrstelemetry.setTelemetryValue(0x1221, 0, 0, fun, UNIT_RAW, 0, "AdjF")
    rf2elrstelemetry.setTelemetryValue(0x1222, 1, 0, val, UNIT_RAW, 0, "AdjV")
    return nil, pos
end

rf2elrstelemetry.RFSensors = {
    -- No data
    [0x1000] = {name = "NULL", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decNil},
    -- Heartbeat (millisecond uptime % 60000)
    [0x1001] = {name = "BEAT", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU16},

    -- Main battery voltage
    [0x1011] = {name = "Vbat", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- Main battery current
    [0x1012] = {name = "Curr", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- Main battery used capacity
    [0x1013] = {name = "Capa", unit = UNIT_MILLIAMPERE_HOUR, prec = 0, dec = rf2elrstelemetry.decU16},
    -- Main battery charge / fuel level
    [0x1014] = {name = "Bat%", unit = UNIT_PERCENT, prec = 0, dec = rf2elrstelemetry.decU8},

    -- Main battery cell count
    [0x1020] = {name = "Cel#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Main battery cell voltage (minimum/average)
    [0x1021] = {name = "Vcel", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decCellV},
    -- Main battery cell voltages
    [0x102F] = {name = "Cels", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decCells},

    -- Control Combined (hires)
    [0x1030] = {name = "Ctrl", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decControl},
    -- Pitch Control angle
    [0x1031] = {name = "CPtc", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Roll Control angle
    [0x1032] = {name = "CRol", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Yaw Control angle
    [0x1033] = {name = "CYaw", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Collective Control angle
    [0x1034] = {name = "CCol", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Throttle output %
    [0x1035] = {name = "Thr", unit = UNIT_PERCENT, prec = 0, dec = rf2elrstelemetry.decS8},

    -- ESC#1 voltage
    [0x1041] = {name = "EscV", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- ESC#1 current
    [0x1042] = {name = "EscI", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- ESC#1 capacity/consumption
    [0x1043] = {name = "EscC", unit = UNIT_MILLIAMPERE_HOUR, prec = 0, dec = rf2elrstelemetry.decU16},
    -- ESC#1 eRPM
    [0x1044] = {name = "EscR", unit = UNIT_RPM, prec = 0, dec = rf2elrstelemetry.decU16},
    -- ESC#1 PWM/Power
    [0x1045] = {name = "EscP", unit = UNIT_PERCENT, prec = 1, dec = rf2elrstelemetry.decU16},
    -- ESC#1 throttle
    [0x1046] = {name = "Esc%", unit = UNIT_PERCENT, prec = 1, dec = rf2elrstelemetry.decU16},
    -- ESC#1 temperature
    [0x1047] = {name = "EscT", unit = UNIT_CELSIUS, prec = 0, dec = rf2elrstelemetry.decU8},
    -- ESC#1 / BEC temperature
    [0x1048] = {name = "BecT", unit = UNIT_CELSIUS, prec = 0, dec = rf2elrstelemetry.decU8},
    -- ESC#1 / BEC voltage
    [0x1049] = {name = "BecV", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- ESC#1 / BEC current
    [0x104A] = {name = "BecI", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- ESC#1 Status Flags
    [0x104E] = {name = "EscF", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU32},
    -- ESC#1 Model Id
    [0x104F] = {name = "Esc#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},

    -- ESC#2 voltage
    [0x1051] = {name = "Es2V", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- ESC#2 current
    [0x1052] = {name = "Es2I", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- ESC#2 capacity/consumption
    [0x1053] = {name = "Es2C", unit = UNIT_MILLIAMPERE_HOUR, prec = 0, dec = rf2elrstelemetry.decU16},
    -- ESC#2 eRPM
    [0x1054] = {name = "Es2R", unit = UNIT_RPM, prec = 0, dec = rf2elrstelemetry.decU16},
    -- ESC#2 temperature
    [0x1057] = {name = "Es2T", unit = UNIT_CELSIUS, prec = 0, dec = rf2elrstelemetry.decU8},
    -- ESC#2 Model Id
    [0x105F] = {name = "Es2#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},

    -- Combined ESC voltage
    [0x1080] = {name = "Vesc", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- BEC voltage
    [0x1081] = {name = "Vbec", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- BUS voltage
    [0x1082] = {name = "Vbus", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},
    -- MCU voltage
    [0x1083] = {name = "Vmcu", unit = UNIT_VOLT, prec = 2, dec = rf2elrstelemetry.decU16},

    -- Combined ESC current
    [0x1090] = {name = "Iesc", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- BEC current
    [0x1091] = {name = "Ibec", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- BUS current
    [0x1092] = {name = "Ibus", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},
    -- MCU current
    [0x1093] = {name = "Imcu", unit = UNIT_AMPERE, prec = 2, dec = rf2elrstelemetry.decU16},

    -- Combined ESC temeperature
    [0x10A0] = {name = "Tesc", unit = UNIT_CELSIUS, prec = 0, dec = rf2elrstelemetry.decU8},
    -- BEC temperature
    [0x10A1] = {name = "Tbec", unit = UNIT_CELSIUS, prec = 0, dec = rf2elrstelemetry.decU8},
    -- MCU temperature
    [0x10A3] = {name = "Tmcu", unit = UNIT_CELSIUS, prec = 0, dec = rf2elrstelemetry.decU8},

    -- Heading (combined gyro+mag+GPS)
    [0x10B1] = {name = "Hdg", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Altitude (combined baro+GPS)
    [0x10B2] = {name = "Alt", unit = UNIT_METER, prec = 2, dec = rf2elrstelemetry.decS24},
    -- Variometer (combined baro+GPS)
    [0x10B3] = {name = "Var", unit = UNIT_METER_PER_SECOND, prec = 2, dec = rf2elrstelemetry.decS16},

    -- Headspeed
    [0x10C0] = {name = "Hspd", unit = UNIT_RPM, prec = 0, dec = rf2elrstelemetry.decU16},
    -- Tailspeed
    [0x10C1] = {name = "Tspd", unit = UNIT_RPM, prec = 0, dec = rf2elrstelemetry.decU16},

    -- Attitude (hires combined)
    [0x1100] = {name = "Attd", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decAttitude},
    -- Attitude pitch
    [0x1101] = {name = "Ptch", unit = UNIT_DEGREE, prec = 0, dec = rf2elrstelemetry.decS16},
    -- Attitude roll
    [0x1102] = {name = "Roll", unit = UNIT_DEGREE, prec = 0, dec = rf2elrstelemetry.decS16},
    -- Attitude yaw
    [0x1103] = {name = "Yaw", unit = UNIT_DEGREE, prec = 0, dec = rf2elrstelemetry.decS16},

    -- Acceleration (hires combined)
    [0x1110] = {name = "Accl", unit = UNIT_G, prec = 2, dec = rf2elrstelemetry.decAccel},
    -- Acceleration X
    [0x1111] = {name = "AccX", unit = UNIT_G, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Acceleration Y
    [0x1112] = {name = "AccY", unit = UNIT_G, prec = 1, dec = rf2elrstelemetry.decS16},
    -- Acceleration Z
    [0x1113] = {name = "AccZ", unit = UNIT_G, prec = 1, dec = rf2elrstelemetry.decS16},

    -- GPS Satellite count
    [0x1121] = {name = "Sats", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- GPS PDOP
    [0x1122] = {name = "PDOP", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- GPS HDOP
    [0x1123] = {name = "HDOP", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- GPS VDOP
    [0x1124] = {name = "VDOP", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- GPS Coordinates
    [0x1125] = {name = "GPS", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decLatLong},
    -- GPS altitude
    [0x1126] = {name = "GAlt", unit = UNIT_METER, prec = 1, dec = rf2elrstelemetry.decS16},
    -- GPS heading
    [0x1127] = {name = "GHdg", unit = UNIT_DEGREE, prec = 1, dec = rf2elrstelemetry.decS16},
    -- GPS ground speed
    [0x1128] = {name = "GSpd", unit = UNIT_METER_PER_SECOND, prec = 2, dec = rf2elrstelemetry.decU16},
    -- GPS home distance
    [0x1129] = {name = "GDis", unit = UNIT_METER, prec = 1, dec = rf2elrstelemetry.decU16},
    -- GPS home direction
    [0x112A] = {name = "GDir", unit = UNIT_METER, prec = 1, dec = rf2elrstelemetry.decU16},

    -- CPU load
    [0x1141] = {name = "CPU%", unit = UNIT_PERCENT, prec = 0, dec = rf2elrstelemetry.decU8},
    -- System load
    [0x1142] = {name = "SYS%", unit = UNIT_PERCENT, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Realtime CPU load
    [0x1143] = {name = "RT%", unit = UNIT_PERCENT, prec = 0, dec = rf2elrstelemetry.decU8},

    -- Model ID
    [0x1200] = {name = "MDL#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Flight mode flags
    [0x1201] = {name = "Mode", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU16},
    -- Arming flags
    [0x1202] = {name = "ARM", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Arming disable flags
    [0x1203] = {name = "ARMD", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU32},
    -- Rescue state
    [0x1204] = {name = "Resc", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Governor state
    [0x1205] = {name = "Gov", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},

    -- Current PID profile
    [0x1211] = {name = "PID#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Current Rate profile
    [0x1212] = {name = "RTE#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},
    -- Current LED profile
    [0x1213] = {name = "LED#", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decU8},

    -- Adjustment function
    [0x1220] = {name = "ADJ", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decAdjFunc},

    -- Debug
    [0xDB00] = {name = "DBG0", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB01] = {name = "DBG1", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB02] = {name = "DBG2", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB03] = {name = "DBG3", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB04] = {name = "DBG4", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB05] = {name = "DBG5", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB06] = {name = "DBG6", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32},
    [0xDB07] = {name = "DBG7", unit = UNIT_RAW, prec = 0, dec = rf2elrstelemetry.decS32}
}

rf2elrstelemetry.telemetryFrameId = 0
rf2elrstelemetry.telemetryFrameSkip = 0
rf2elrstelemetry.telemetryFrameCount = 0

function rf2elrstelemetry.crossfirePop()

	-- break out of loop if we loose rssi
	if rf2elrstelemetry.rssiSensor == nil and not rf2elrstelemetry.rssiSensor:state() then
		return false
	end

    local command, data = rf2elrstelemetry.crossfireTelemetryPop()
    if command and data then
        if command == CRSF_FRAME_CUSTOM_TELEM then
            local fid, sid, val
            local ptr = 3
            fid, ptr = rf2elrstelemetry.decU8(data, ptr)
            local delta = (fid - rf2elrstelemetry.telemetryFrameId) & 0xFF -- Replace bit32.band with native bitwise AND
            if delta > 1 then rf2elrstelemetry.telemetryFrameSkip = rf2elrstelemetry.telemetryFrameSkip + 1 end
            rf2elrstelemetry.telemetryFrameId = fid
            rf2elrstelemetry.telemetryFrameCount = rf2elrstelemetry.telemetryFrameCount + 1
            while ptr < #data do
                sid, ptr = rf2elrstelemetry.decU16(data, ptr)
                local sensor = rf2elrstelemetry.RFSensors[sid]
                if sensor then
                    val, ptr = sensor.dec(data, ptr)
                    if val then rf2elrstelemetry.setTelemetryValue(sid, 0, 0, val, sensor.unit, sensor.prec, sensor.name) end
                else
                    break
                end
            end
            rf2elrstelemetry.setTelemetryValue(0xEE01, 0, 0, rf2elrstelemetry.telemetryFrameCount, UNIT_RAW, 0, "*Cnt")
            rf2elrstelemetry.setTelemetryValue(0xEE02, 0, 0, rf2elrstelemetry.telemetryFrameSkip, UNIT_RAW, 0, "*Skp")
            --rf2elrstelemetry.setTelemetryValue(0xEE03, 0, 0, rf2elrstelemetry.telemetryFrameId, UNIT_RAW, 0, "*Frm")
        end
        return true
    end
    return false
end

function rf2elrstelemetry.crossfirePopAll()

		local rssiNames = {"Rx RSSI1", "Rx RSSI2"}
		for i, name in ipairs(rssiNames) do
			rf2elrstelemetry.rssiSensor = system.getSource(name)
		end
		if rf2elrstelemetry.rssiSensor ~= nil and rf2elrstelemetry.rssiSensor:state() then
			if (os.clock() <= (rf2elrstelemetry.initialise) + rf2elrstelemetry.initialiseTime) then
				rf2elrstelemetry.initialiseSensors = true
			else
				rf2elrstelemetry.initialiseSensors = false
			end
			
			while rf2elrstelemetry.crossfirePop() do end
			 
		else	
			-- link is down
			rf2elrstelemetry.initialise = os.clock()
			rf2elrstelemetry.initialiseSensors = false
		end

end

return rf2elrstelemetry
