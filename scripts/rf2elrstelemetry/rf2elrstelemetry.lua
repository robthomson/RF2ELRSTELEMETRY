--
-- Rotorflight Custom Telemetry Decoder for ELRS
--
rf2elrstelemetry = {}

local CRSF_FRAME_CUSTOM_TELEM   = 0x88

rf2elrstelemetry.sensorTABLE = {}
rf2elrstelemetry.sensorRecheck = {}
rf2elrstelemetry.sensorRecheckInterval = 60
rf2elrstelemetry.initialiseTime = 30
rf2elrstelemetry.initialise = os.clock()


function rf2elrstelemetry.setTelemetryValue(id, subId, instance, value , unit , dec , name)
	if id ~= nil then

		local uid = id .. "_" .. instance .. "_" .. name:gsub('%W','')
		
		

		if rf2elrstelemetry.sensorRecheck[uid] == nil then
			rf2elrstelemetry.sensorRecheck[uid] = os.clock()
		end

		-- check every now and again that the sensor exists.  if not - create it.
		-- we run this cycle every loop until rf2elrstelemetry.initialiseTime expires.
		-- this simple ensures that all sensors are gathered on first power uptime
		-- after that we drop to low priority checking set by rf2elrstelemetry.sensorRecheckInterval
		if (os.clock() >= (rf2elrstelemetry.sensorRecheck[uid] + rf2elrstelemetry.sensorRecheckInterval)) or (os.clock() <= (rf2elrstelemetry.initialise) + rf2elrstelemetry.initialiseTime) then

			print("Checking sensor exists: [" .. name .. "]")
			rf2elrstelemetry.sensorTABLE[uid] = {}
			rf2elrstelemetry.sensorTABLE[uid]  = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = id})
			rf2elrstelemetry.sensorRecheck[uid] = os.clock()

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

		if rf2elrstelemetry.sensorTABLE[uid] ~= nil then
			rf2elrstelemetry.sensorTABLE[uid]:value(value)
		end


	end
end

function rf2elrstelemetry.crossfireTelemetryPop()
	local command, data = crsf.popFrame()
	return command,data
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


function rf2elrstelemetry.decU8(data, pos)
    return data[pos], pos+1
end

function rf2elrstelemetry.decS8(data, pos)
    local val,ptr = rf2elrstelemetry.decU8(data,pos)
    return val < 0x80 and val or val - 0x100, ptr
end

function rf2elrstelemetry.decU16(data, pos)
    return rf2elrstelemetry.lshift(data[pos],8) + data[pos+1], pos+2
end

function rf2elrstelemetry.decS16(data, pos)
    local val,ptr = rf2elrstelemetry.decU16(data,pos)
    return val < 0x8000 and val or val - 0x10000, ptr
end

function rf2elrstelemetry.decU12U12(data, pos)
    local a = rf2elrstelemetry.lshift(rf2elrstelemetry.extract(data[pos],0,4),8) + data[pos+1]
    local b = rf2elrstelemetry.lshift(rf2elrstelemetry.extract(data[pos],4,4),8) + data[pos+2]
    return a,b,pos+3
end

function rf2elrstelemetry.decS12S12(data, pos)
    local a,b,ptr = rf2elrstelemetry.decU12U12(data, pos)
    return a < 0x0800 and a or a - 0x1000, b < 0x0800 and b or b - 0x1000, ptr
end

function rf2elrstelemetry.decU24(data, pos)
    return rf2elrstelemetry.lshift(data[pos],16) + rf2elrstelemetry.lshift(data[pos+1],8) + data[pos+2], pos+3
end

function rf2elrstelemetry.decS24(data, pos)
    local val,ptr = rf2elrstelemetry.decU24(data,pos)
    return val < 0x800000 and val or val - 0x1000000, ptr
end

function rf2elrstelemetry.decU32(data, pos)
    return rf2elrstelemetry.lshift(data[pos],24) + rf2elrstelemetry.lshift(data[pos+1],16) + rf2elrstelemetry.lshift(data[pos+2],8) + data[pos+3], pos+4
end

function rf2elrstelemetry.decS32(data, pos)
    local val,ptr = rf2elrstelemetry.decU32(data,pos)
    return val < 0x80000000 and val or val - 0x100000000, ptr
end

function rf2elrstelemetry.decCellV(data, pos)
    local val,ptr = rf2elrstelemetry.decU8(data,pos)
    return val > 0 and val + 200 or 0, ptr
end

function rf2elrstelemetry.decCells(data, pos)
    local cnt,val,vol
    cnt,pos = rf2elrstelemetry.decU8(data,pos)
    rf2elrstelemetry.setTelemetryValue(0x0020, 0, 0, cnt, UNIT_RAW, 0, "Cel#")
    for i = 1, cnt
    do
        val,pos = rf2elrstelemetry.decU8(data,pos)
        val = val > 0 and val + 200 or 0
        vol = rf2elrstelemetry.lshift(cnt,24) + rf2elrstelemetry.lshift(i-1, 16) + val
        rf2elrstelemetry.setTelemetryValue(0x0021, 0, 0, vol, UNIT_CELLS, 2, "Cels")
    end
    return nil, pos
end

function rf2elrstelemetry.decControl(data, pos)
    local r,p,y,c
    p,r,pos = rf2elrstelemetry.decS12S12(data,pos)
    y,c,pos = rf2elrstelemetry.decS12S12(data,pos)
    rf2elrstelemetry.setTelemetryValue(0x0031, 0, 0, p, UNIT_DEGREE, 2, "CPtc")
    rf2elrstelemetry.setTelemetryValue(0x0032, 0, 0, r, UNIT_DEGREE, 2, "CRol")
    rf2elrstelemetry.setTelemetryValue(0x0033, 0, 0, y, UNIT_DEGREE, 2, "CYaw")
    rf2elrstelemetry.setTelemetryValue(0x0034, 0, 0, c, UNIT_DEGREE, 2, "CCol")
    return nil, pos
end

function rf2elrstelemetry.decAttitude(data, pos)
    local p,r,y
    p,pos = rf2elrstelemetry.decS16(data,pos)
    r,pos = rf2elrstelemetry.decS16(data,pos)
    y,pos = rf2elrstelemetry.decS16(data,pos)
    rf2elrstelemetry.setTelemetryValue(0x0101, 0, 0, p, UNIT_DEGREE, 1, "Ptch")
    rf2elrstelemetry.setTelemetryValue(0x0102, 0, 0, r, UNIT_DEGREE, 1, "Roll")
    rf2elrstelemetry.setTelemetryValue(0x0103, 0, 0, y, UNIT_DEGREE, 1, "Yaw")
    return nil, pos
end

function rf2elrstelemetry.decAccel(data, pos)
    local x,y,z
    x,pos = rf2elrstelemetry.decS16(data,pos)
    y,pos = rf2elrstelemetry.decS16(data,pos)
    z,pos = rf2elrstelemetry.decS16(data,pos)
    rf2elrstelemetry.setTelemetryValue(0x0111, 0, 0, x, UNIT_G, 2, "AccX")
    rf2elrstelemetry.setTelemetryValue(0x0112, 0, 0, y, UNIT_G, 2, "AccY")
    rf2elrstelemetry.setTelemetryValue(0x0113, 0, 0, z, UNIT_G, 2, "AccZ")
    return nil, pos
end

function rf2elrstelemetry.decLatLong(data, pos)
    local lat,lon
    lat,pos = rf2elrstelemetry.decS32(data,pos)
    lon,pos = rf2elrstelemetry.decS32(data,pos)
    rf2elrstelemetry.setTelemetryValue(0x0070, 0, 0, 0, UNIT_GPS, 0, "GPS")
    rf2elrstelemetry.setTelemetryValue(0x0070, 0, 0, lat, UNIT_GPS_LATITUDE)
    rf2elrstelemetry.setTelemetryValue(0x0070, 0, 0, lon, UNIT_GPS_LONGITUDE)
    return nil, pos
end

function rf2elrstelemetry.decAdjFunc(data, pos)
    local fun,val
    fun,pos = rf2elrstelemetry.decU16(data,pos)
    val,pos = rf2elrstelemetry.decS32(data,pos)
    rf2elrstelemetry.setTelemetryValue(0x0220, 0, 0, fun, UNIT_RAW, 0, "AdjF")
    rf2elrstelemetry.setTelemetryValue(0x0220, 1, 0, val, UNIT_RAW, 0, "AdjV")
    return nil, pos
end

rf2elrstelemetry.RFSensors = {
    -- Heartbeat (millisecond uptime % 60000)
    [0x0001]  = { name="BEAT",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU16  },

    -- Main battery voltage
    [0x0011]  = { name="Vbat",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },
    -- Main battery current
    [0x0012]  = { name="Curr",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },
    -- Main battery used capacity
    [0x0013]  = { name="Capa",    unit=UNIT_MILLIAMPERE_HOUR,    prec=0,    dec=rf2elrstelemetry.decU16  },
    -- Main battery State-of-Charge / fuel level
    [0x0014]  = { name="Fuel",    unit=UNIT_PERCENT,             prec=0,    dec=rf2elrstelemetry.decU8   },

    -- Main battery cell count
    [0x0020]  = { name="Cel#",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Main battery cell voltage (minimum/average)
    [0x0020]  = { name="Vcel",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decCellV },
    -- Main battery cell voltages
    [0x002F]  = { name="Cels",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decCells },

    -- Control Combined (hires)
    [0x0030]  = { name="Ctrl",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decControl },
    -- Roll Control angle
    [0x0031]  = { name="CRol",    unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Pitch Control angle
    [0x0032]  = { name="CPtc",    unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Yaw Control angle
    [0x0033]  = { name="CYaw",    unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Collective Control angle
    [0x0034]  = { name="CCol",    unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Throttle output %
    [0x0035]  = { name="Thr",     unit=UNIT_PERCENT,             prec=0,    dec=rf2elrstelemetry.decS8   },

    -- ESC voltage
    [0x0041]  = { name="EscV",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },
    -- ESC current
    [0x0042]  = { name="EscI",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },
    -- ESC capacity/consumption
    [0x0043]  = { name="EscC",    unit=UNIT_MILLIAMPERE_HOUR,    prec=0,    dec=rf2elrstelemetry.decU16  },
    -- ESC eRPM
    [0x0044]  = { name="EscR",    unit=UNIT_RPM,                 prec=0,    dec=rf2elrstelemetry.decU16  },
    -- ESC PWM/Power
    [0x0045]  = { name="EscP",    unit=UNIT_PERCENT,             prec=1,    dec=rf2elrstelemetry.decU16  },
    -- ESC throttle
    [0x0046]  = { name="Esc%",    unit=UNIT_PERCENT,             prec=1,    dec=rf2elrstelemetry.decU16  },
    -- ESC temperature
    [0x0047]  = { name="EscT",    unit=UNIT_CELSIUS,             prec=0,    dec=rf2elrstelemetry.decU8   },
    -- ESC / BEC temperature
    [0x0048]  = { name="BecT",    unit=UNIT_CELSIUS,             prec=0,    dec=rf2elrstelemetry.decU8   },
    -- ESC / BEC voltage
    [0x0049]  = { name="BecV",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },
    -- ESC / BEC current
    [0x004A]  = { name="BecI",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },
    -- ESC Status Flags
    [0x004E]  = { name="EscF",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU32  },
    -- ESC Model Id
    [0x004F]  = { name="Esc#",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },

    -- Combined ESC voltage
    [0x0080]  = { name="Vesc",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },
    -- BEC voltage
    [0x0081]  = { name="Vbec",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },
    -- BUS voltage
    [0x0082]  = { name="Vbus",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },
    -- MCU voltage
    [0x0083]  = { name="Vmcu",    unit=UNIT_VOLT,                prec=2,    dec=rf2elrstelemetry.decU16  },

    -- Combined ESC current
    [0x0090]  = { name="Iesc",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },
    -- BEC current
    [0x0091]  = { name="Ibec",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },
    -- BUS current
    [0x0092]  = { name="Ibus",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },
    -- MCU current
    [0x0093]  = { name="Imcu",    unit=UNIT_AMPERE,              prec=2,    dec=rf2elrstelemetry.decU16  },

    -- Combined ESC temeperature
    [0x00A0]  = { name="Tesc",    unit=UNIT_CELSIUS,             prec=0,    dec=rf2elrstelemetry.decU8   },
    -- BEC temperature
    [0x00A1]  = { name="Tbec",    unit=UNIT_CELSIUS,             prec=0,    dec=rf2elrstelemetry.decU8   },
    --MCU temperature
    [0x00A3]  = { name="Tmcu",    unit=UNIT_CELSIUS,             prec=0,    dec=rf2elrstelemetry.decU8   },

    -- Heading (combined gyro+mag+GPS)
    [0x00B1]  = { name="Hdg",     unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Altitude (combined baro+GPS)
    [0x00B2]  = { name="Alt",     unit=UNIT_METER,               prec=2,    dec=rf2elrstelemetry.decS24  },
    -- Variometer (combined baro+GPS)
    [0x00B3]  = { name="Var",     unit=UNIT_METER_PER_SECOND,    prec=2,    dec=rf2elrstelemetry.decS16  },

    -- Headspeed
    [0x00C0]  = { name="Hspd",    unit=UNIT_RPM,                 prec=0,    dec=rf2elrstelemetry.decU16  },
    -- Tailspeed
    [0x00C1]  = { name="Tspd",    unit=UNIT_RPM,                 prec=0,    dec=rf2elrstelemetry.decU16  },

    -- Attitude (hires combined)
    [0x0100]  = { name="Attd",    unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decAttitude },
    -- Attitude pitch
    [0x0101]  = { name="Ptch",    unit=UNIT_DEGREE,              prec=0,    dec=rf2elrstelemetry.decS16  },
    -- Attitude roll
    [0x0102]  = { name="Roll",    unit=UNIT_DEGREE,              prec=0,    dec=rf2elrstelemetry.decS16  },
    -- Attitude yaw
    [0x0103]  = { name="Yaw",     unit=UNIT_DEGREE,              prec=0,    dec=rf2elrstelemetry.decS16  },

    -- Acceleration (hires combined)
    [0x0110]  = { name="Accl",    unit=UNIT_G,                   prec=2,    dec=rf2elrstelemetry.decAccel },
    -- Acceleration X
    [0x0111]  = { name="AccX",    unit=UNIT_G,                   prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Acceleration Y
    [0x0112]  = { name="AccY",    unit=UNIT_G,                   prec=1,    dec=rf2elrstelemetry.decS16  },
    -- Acceleration Z
    [0x0113]  = { name="AccZ",    unit=UNIT_G,                   prec=1,    dec=rf2elrstelemetry.decS16  },

    -- GPS Satellite count
    [0x0121]  = { name="Sats",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- GPS PDOP
    [0x0122]  = { name="PDOP",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- GPS HDOP
    [0x0123]  = { name="HDOP",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- GPS VDOP
    [0x0124]  = { name="VDOP",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- GPS Coordinates
    [0x0125]  = { name="GPS",     unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decLatLong },
    -- GPS altitude
    [0x0126]  = { name="GAlt",    unit=UNIT_METER,               prec=1,    dec=rf2elrstelemetry.decS16  },
    -- GPS heading
    [0x0127]  = { name="GHdg",    unit=UNIT_DEGREE,              prec=1,    dec=rf2elrstelemetry.decS16  },
    -- GPS ground speed
    [0x0128]  = { name="GSpd",    unit=UNIT_METER_PER_SECOND,    prec=2,    dec=rf2elrstelemetry.decU16  },
    -- GPS home distance
    [0x0129]  = { name="GDis",    unit=UNIT_METER,               prec=1,    dec=rf2elrstelemetry.decU16  },
    -- GPS home direction
    [0x012A]  = { name="GDir",    unit=UNIT_METER,               prec=1,    dec=rf2elrstelemetry.decU16  },

    -- CPU load
    [0x0141]  = { name="CPU%",    unit=UNIT_PERCENT,             prec=0,    dec=rf2elrstelemetry.decU8   },
    -- System load
    [0x0142]  = { name="SYS%",    unit=UNIT_PERCENT,             prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Realtime CPU load
    [0x0143]  = { name="RT%",     unit=UNIT_PERCENT,             prec=0,    dec=rf2elrstelemetry.decU8   },

    -- Model ID
    [0x0200]  = { name="MDL#",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Flight mode flags
    [0x0201]  = { name="Mode",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU16  },
    -- Arming flags
    [0x0202]  = { name="ARM",     unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Arming disable flags
    [0x0203]  = { name="ARMD",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU32  },
    -- Rescue state
    [0x0204]  = { name="Resc",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Governor state
    [0x0205]  = { name="Gov",     unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },

    -- Current PID profile
    [0x0211]  = { name="PID#",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Current Rate profile
    [0x0212]  = { name="RTE#",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },
    -- Current LED profile
    [0x0213]  = { name="LED#",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decU8   },

    -- Adjustment function
    [0x0220]  = { name="ADJ",     unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decAdjFunc },

    -- Debug
    [0xFE00]  = { name="DBG0",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE01]  = { name="DBG1",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE02]  = { name="DBG2",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE03]  = { name="DBG3",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE04]  = { name="DBG4",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE05]  = { name="DBG5",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE06]  = { name="DBG6",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
    [0xFE07]  = { name="DBG7",    unit=UNIT_RAW,                 prec=0,    dec=rf2elrstelemetry.decS32  },
}

rf2elrstelemetry.telemetryFrameId = 0
rf2elrstelemetry.telemetryFrameSkip = 0
rf2elrstelemetry.telemetryFrameCount = 0

function rf2elrstelemetry.crossfirePop()
    local command, data = rf2elrstelemetry.crossfireTelemetryPop()
    if command and data then
        if command == CRSF_FRAME_CUSTOM_TELEM then
            local fid, sid, val
            local ptr = 3
            fid, ptr = rf2elrstelemetry.decU8(data, ptr)
            local delta = (fid - rf2elrstelemetry.telemetryFrameId) & 0xFF  -- Replace bit32.band with native bitwise AND
            if delta > 1 then
                rf2elrstelemetry.telemetryFrameSkip = rf2elrstelemetry.telemetryFrameSkip + 1
            end
            rf2elrstelemetry.telemetryFrameId = fid
            rf2elrstelemetry.telemetryFrameCount = rf2elrstelemetry.telemetryFrameCount + 1
            while ptr < #data do
                sid, ptr = rf2elrstelemetry.decU16(data, ptr)
                local sensor = rf2elrstelemetry.RFSensors[sid]
                if sensor then
                    val, ptr = sensor.dec(data, ptr)
                    if val then
                        rf2elrstelemetry.setTelemetryValue(sid, 0, 0, val, sensor.unit, sensor.prec, sensor.name)
                    end
                else
                    break
                end
            end
            rf2elrstelemetry.setTelemetryValue(0xFF01, 0, 0, rf2elrstelemetry.telemetryFrameCount, UNIT_RAW, 0, "*Cnt")
            rf2elrstelemetry.setTelemetryValue(0xFF02, 0, 0, rf2elrstelemetry.telemetryFrameSkip, UNIT_RAW, 0, "*Skp")
        end
        return true
    end
    return false
end


function rf2elrstelemetry.crossfirePopAll()
  while rf2elrstelemetry.crossfirePop() do end
end

return rf2elrstelemetry
