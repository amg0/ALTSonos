-- // This program is free software: you can redistribute it and/or modify
-- // it under the condition that it is for private or home useage and
-- // this whole comment is reproduced in the source code file.
-- // Commercial utilisation is not authorized without the appropriate
-- // written agreement from amg0 / alexis . mermet @ gmail . com
-- // This program is distributed in the hope that it will be useful,
-- // but WITHOUT ANY WARRANTY; without even the implied warranty of
-- // MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE .
local MSG_CLASS		= "ALTSonos"
local ALTSonos_SERVICE	= "urn:upnp-org:serviceId:altsonos1"
local devicetype	= "urn:schemas-upnp-org:device:altsonos:1"
local DEBUG_MODE	= false -- controlled by UPNP action
local version		= "v0.1"
local JSON_FILE = "D_ALTSonos.json"
local UI7_JSON_FILE = "D_ALTSonos_UI7.json"
local this_device = nil
local retry_timer = 1/2			-- in mn, retry time
local json = require("dkjson")
local socket = require("socket")
local modurl = require ("socket.url")
local mime = require("mime")
local https = require ("ssl.https")

local APPID = "ALTSONOS_KEY"
local ALTSONOS_KEY = "e9720bf5-83b2-474b-a6fd-a7eb3a27e835"
local ALTSONOS_SECRET = "211e0fc7-67af-4cc5-a7f6-5928b346e005"
local CF_AUTH = "https://europe-west1-altui-cloud-function.cloudfunctions.net/SonosAuthorization"
local CF_EVENT = "https://europe-west1-altui-cloud-function.cloudfunctions.net/SonosEvent"
local EVENTCB_URL = "http://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=EventCB&DeviceNum=264"
local AUTHORIZATIONCB_URL = "http://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=AuthorizationCB&DeviceNum=264"		

------------------------------------------------
-- Debug --
------------------------------------------------
function log(text, level)
  luup.log(string.format("%s: %s", MSG_CLASS, text), (level or 50))
end

function debug(text)
  if (DEBUG_MODE) then
	log("debug: " .. text)
  end
end

function warning(stuff)
  log("warning: " .. stuff, 2)
end

function error(stuff)
  log("error: " .. stuff, 1)
end

local function isempty(s)
  return s == nil or s == ""
end

------------------------------------------------
-- VERA Device Utils
------------------------------------------------
local function getParent(lul_device)
  return luup.devices[lul_device].device_num_parent
end

local function getAltID(lul_device)
  return luup.devices[lul_device].id
end

-----------------------------------
-- from a altid, find a child device
-- returns 2 values
-- a) the index === the device ID
-- b) the device itself luup.devices[id]
-----------------------------------
local function findChild( lul_parent, altid )
  -- debug(string.format("findChild(%s,%s)",lul_parent,altid))
  for k,v in pairs(luup.devices) do
	if( getParent(k)==lul_parent) then
	  if( v.id==altid) then
		return k,v
	  end
	end
  end
  return nil,nil
end

local function getParent(lul_device)
  return luup.devices[lul_device].device_num_parent
end

local function getRoot(lul_device)
  while( getParent(lul_device)>0 ) do
	lul_device = getParent(lul_device)
  end
  return lul_device
end

------------------------------------------------
-- Device Properties Utils
------------------------------------------------
local function getSetVariable(serviceId, name, deviceId, default)
  local curValue = luup.variable_get(serviceId, name, deviceId)
  if (curValue == nil) then
	curValue = default
	luup.variable_set(serviceId, name, curValue, deviceId)
  end
  return curValue
end

local function getSetVariableIfEmpty(serviceId, name, deviceId, default)
  local curValue = luup.variable_get(serviceId, name, deviceId)
  if (curValue == nil) or (curValue:trim() == "") then
	curValue = default
	luup.variable_set(serviceId, name, curValue, deviceId)
  end
  return curValue
end

local function setVariableIfChanged(serviceId, name, value, deviceId)
  debug(string.format("setVariableIfChanged(%s,%s,%s,%s)",serviceId, name, value or 'nil', deviceId))
  local curValue = luup.variable_get(serviceId, name, tonumber(deviceId)) or ""
  value = value or ""
  if (tostring(curValue)~=tostring(value)) then
	luup.variable_set(serviceId, name, value or '', tonumber(deviceId))
  end
end

local function setAttrIfChanged(name, value, deviceId)
  debug(string.format("setAttrIfChanged(%s,%s,%s)",name, value or 'nil', deviceId))
  local curValue = luup.attr_get(name, deviceId)
  if ((value ~= curValue) or (curValue == nil)) then
	luup.attr_set(name, value or '', deviceId)
	return true
  end
  return value
end

------------------------------------------------
-- Tasks
------------------------------------------------
local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

--
-- Has to be "non-local" in order for MiOS to call it :(
--
local function task(text, mode)
  if (mode == TASK_ERROR_PERM)
  then
	error(text)
  elseif (mode ~= TASK_SUCCESS)
  then
	warning(text)
  else
	log(text)
  end
  
  if (mode == TASK_ERROR_PERM)
  then
	taskHandle = luup.task(text, TASK_ERROR, MSG_CLASS, taskHandle)
  else
	taskHandle = luup.task(text, mode, MSG_CLASS, taskHandle)

	-- Clear the previous error, since they're all transient
	if (mode ~= TASK_SUCCESS)
	then
	  luup.call_delay("clearTask", 15, "", false)
	end
  end
end

function clearTask()
  task("Clearing...", TASK_SUCCESS)
end

local function UserMessage(text, mode)
  mode = (mode or TASK_ERROR)
  task(text,mode)
end

------------------------------------------------
-- LUA helpers
------------------------------------------------
function tablelength(T)
  local count = 0
  if (T~=nil) then
	for _ in pairs(T) do count = count + 1 end
  end
  return count
end

function tableadd(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

local function Split(str, delim, maxNb)
	-- Eliminate bad cases...
	if string.find(str, delim) == nil then
		return { str }
	end
	if maxNb == nil or maxNb < 1 then
		maxNb = 0	 -- No limit
	end
	local result = {}
	local pat = "(.-)" .. delim .. "()"
	local nb = 0
	local lastPos
	for part, pos in string.gmatch(str, pat) do
		nb = nb + 1
		result[nb] = part
		lastPos = pos
		if nb == maxNb then break end
	end
	-- Handle the last field
	if nb ~= maxNb then
		result[nb + 1] = string.sub(str, lastPos)
	end
	return result
end

local function getIP()
	local mySocket = socket.udp ()
	mySocket:setpeername ("42.42.42.42", "424242")	-- arbitrary IP/PORT
	local ip = mySocket:getsockname ()
	mySocket: close()
	return ip or "127.0.0.1"
end

------------------------------------------------
-- HTTP Interface
------------------------------------------------

local function SonosHTTP(lul_device,path,verb,body,b64credential)
	body = body or ""
	if (b64credential==nil) then
		local token = luup.variable_get(ALTSonos_SERVICE, "AccessToken", lul_device)	
		b64credential = "Bearer ".. token
	end

	debug(string.format("SonosHTTP(%s,%s,%s,%s,%s)",lul_device,path,verb,body,b64credential or ""))
	local url = "https://" .. path
	local verb = verb or "GET"
	
	local headers = {
		["Authorization"] = b64credential,
		["Content-Length"] = body:len(),
		["Cache-Control"] =  'no-cache',
		["Content-Type"] = "application/x-www-form-urlencoded",
	}
	debug(string.format("request headers:%s",json.encode(headers)))
	local result = {}
	local request, code, headers = https.request({
		protocol="tlsv1_2",		-- mandatory, otherwise it fails ( and curl works )
		method=verb,
		url = url,
		source= ltn12.source.string(body),
		headers = headers,
		sink = ltn12.sink.table(result)
	})
	
	-- fail to connect
	if (request==nil) then
		error(string.format("failed to connect to %s, http.request returned nil", url))
		return nil,"failed to connect"
	elseif (code==401) then
		warning(string.format("Access requires a user/password: %d", code))
		return nil,"unauthorized access - 401"
	elseif (code==400) then
		warning(string.format("Invalid client, uri or code: %d", code))
		return nil,"invalid client- 400"
	elseif (code~=200) then
		warning(string.format("https.request returned a bad code: %d", code))
		return nil,"unvalid return code:" .. code
	end
	
	-- everything looks good
	setVariableIfChanged(ALTSonos_SERVICE,"IconCode", 100, lul_device)

	local data = table.concat(result)
	debug(string.format("response request:%s",request))
	debug(string.format("code:%s",code))
	debug(string.format("headers:%s",json.encode(headers)))
	debug(string.format("data:%s",data or ""))
	
	local response = json.decode(data)
	return response,""
end

local function refreshToken( lul_device )
	debug(string.format("refreshToken(%s)",lul_device))
	lul_device = tonumber(lul_device)

	local b64credential = "Basic ".. mime.b64(ALTSONOS_KEY..":"..ALTSONOS_SECRET)
	local refresh_token = luup.variable_get(ALTSonos_SERVICE, "RefreshToken", lul_device)
	local body = string.format('grant_type=refresh_token&refresh_token=%s',refresh_token)
	
	local response,msg = SonosHTTP(lul_device,"api.sonos.com/login/v3/oauth/access","POST",body,b64credential)
	return response,msg
end

local function onAuthorizationCallback( lul_device, AuthCode) 
	debug(string.format("onAuthorizationCallback(%s,%s)",lul_device,AuthCode))
	lul_device = tonumber(lul_device)
	luup.variable_set(ALTSonos_SERVICE, "AuthCode", AuthCode, lul_device)
	local cfauth = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionAuthUrl", lul_device) 
	local b64credential = "Basic ".. mime.b64(ALTSONOS_KEY..":"..ALTSONOS_SECRET)
	local uri = modurl.escape( cfauth )
	local body = string.format('grant_type=authorization_code&code=%s&redirect_uri=%s',AuthCode,uri)
	
	local response,msg = SonosHTTP(lul_device,"api.sonos.com/login/v3/oauth/access","POST",body,b64credential)
	if (response ~=nil ) then
		luup.variable_set(ALTSonos_SERVICE, "RefreshToken", response.refresh_token, lul_device)
		luup.variable_set(ALTSonos_SERVICE, "AccessToken", response.access_token, lul_device)
		luup.variable_set(ALTSonos_SERVICE, "ResourceOwner", response.resource_owner, lul_device)
	end
	return response,msg
end

local function getGroups(lul_device, hid )
	debug(string.format("getGroups(%s,%s)",lul_device,hid))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/households/%s/groups",hid)
	local response,msg = SonosHTTP(lul_device,cmd,"GET")
	if (response ~=nil ) then
		luup.variable_set(ALTSonos_SERVICE, "Players", json.encode(response.players), lul_device)
		luup.variable_set(ALTSonos_SERVICE, "Groups", json.encode(response.groups), lul_device)
		return obj
	end
	return nil
end

local function getHouseholds(lul_device)
	debug(string.format("getHouseholds(%s)",lul_device))
	local response,msg = SonosHTTP(lul_device,"api.ws.sonos.com/control/api/v1/households","GET")
	if (response ~=nil ) then
		luup.variable_set(ALTSonos_SERVICE, "Households", json.encode(response.households), lul_device)
		return response.households
	end
	return nil
end

------------------------------------------------
-- UPNP Actions Sequence
------------------------------------------------
local function setDebugMode(lul_device,newDebugMode)
  lul_device = tonumber(lul_device)
  newDebugMode = tonumber(newDebugMode) or 0
  debug(string.format("setDebugMode(%d,%d)",lul_device,newDebugMode))
  luup.variable_set(ALTSonos_SERVICE, "Debug", newDebugMode, lul_device)
  if (newDebugMode==1) then
	DEBUG_MODE=true
  else
	DEBUG_MODE=false
  end
end

------------------------------------------------------------------------------------------------
-- Http handlers : Communication FROM ALTUI
-- http://192.168.1.5:3480/data_request?id=lr_ALTUI_Handler&command=xxx
-- recommended settings in ALTUI: PATH = /data_request?id=lr_ALTUI_Handler&mac=$M&deviceID=114
------------------------------------------------------------------------------------------------
function switch( command, actiontable)
	-- check if it is in the table, otherwise call default
	if ( actiontable[command]~=nil ) then
		return actiontable[command]
	end
	log("myALTSonos_Handler:Unknown command received:"..command.." was called. Default function")
	return actiontable["default"]
end

function myALTSonos_Handler(lul_request, lul_parameters, lul_outputformat)
	debug(string.format('myALTSonos_Handler: request is: %s parameters:%s' , tostring(lul_request),json.encode(lul_parameters)))
	local command = nil
	local lul_html,mime_type = nil,nil
	
	local lul_device = this_device or tonumber(lul_parameters["DeviceNum"] or 0)
	
	-- find a parameter called "command"
	if ( lul_parameters["command"] ~= nil ) then
		command =lul_parameters["command"]
	else
		debug("ALTUI_Handler:no command specified, taking default")
		command ="default"
	end

	-- switch table
	local action = {
		["GetAppInfo"] = 
			function(params)
				local cfauth = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionAuthUrl", lul_device) 
				return json.encode( { ip=getIP(), altsonos_key=ALTSONOS_KEY, proxy=cfauth } ),"application/json"
			end,
		["AuthorizationCB"] = 
			function(params)
				local code = lul_parameters["code"]
				local deviceNum = lul_parameters["DeviceNum"]
				local obj,msg = onAuthorizationCallback( deviceNum, code)
				debug(string.format("received json: {0}",json.encode(obj)))
				return  msg .. " You can close the window and return to the ALTSONOS application" , "text/plain" 
			end,
		["default"] =
			function(params)
				return "Default Handler", "text/plain"
			end
	}
	
	-- actual call
	lul_html , mime_type = switch(command,action)(lul_parameters)
	debug(string.format("lul_html:%s",lul_html or ""))
	return (lul_html or "") , mime_type
end

local function syncDevices(lul_device)
	local groups=nil
	local households = getHouseholds(lul_device)
	debug(string.format("households respoonse = %s",json.encode(households)))
	if (households~=nil) then
		local householdid = households[1].id
		local groups = getGroups(lul_device, householdid)
	end
	return (households~=nil) and (groups~=nil)
end

local function startEngine(lul_device)
	debug(string.format("startEngine(%s)",lul_device))
	return syncDevices(lul_device)
end

function registerHandlers(lul_device)
	luup.register_handler("myALTSonos_Handler","ALTSonos_Handler")
end

function startupDeferred(lul_device)
	log("startupDeferred, called on behalf of device:"..lul_device)

	lul_device = tonumber(lul_device)
	local ip = getIP()
	local iconCode = luup.variable_set(ALTSonos_SERVICE, "IconCode", 0, lul_device)
	local debugmode = getSetVariable(ALTSonos_SERVICE, "Debug", lul_device, "0")	
	local oldversion = getSetVariable(ALTSonos_SERVICE, "Version", lul_device, version)
	local authurl = string.format("http://%s/port_3480/data_request?id=lr_DENON_Handler&command=AuthorizationCB&DeviceNum=%s",ip,lul_device)
	getSetVariable(ALTSonos_SERVICE, "VeraOAuthCBUrl", lul_device, authurl)
	local cfauthurl = ""
	getSetVariable(ALTSonos_SERVICE, "CloudFunctionAuthUrl", lul_device, cfauthurl)

		
	if (debugmode=="1") then
		DEBUG_MODE = true
		UserMessage("Enabling debug mode for device:"..lul_device,TASK_BUSY)
	end

	local major,minor = 0,0
	if (oldversion~=nil) then
		if (oldversion ~= "") then
		  major,minor = string.match(oldversion,"v(%d+)%.(%d+)")
		  major,minor = tonumber(major),tonumber(minor)
		  debug ("Plugin version: "..version.." Device's Version is major:"..major.." minor:"..minor)

		  newmajor,newminor = string.match(version,"v(%d+)%.(%d+)")
		  newmajor,newminor = tonumber(newmajor),tonumber(newminor)
		  debug ("Device's New Version is major:"..newmajor.." minor:"..newminor)

		  -- force the default in case of upgrade
		  if ( (newmajor>major) or ( (newmajor==major) and (newminor>minor) ) ) then
			-- log ("Version upgrade => Reseting Plugin config to default")
		  end
		else
		  log ("New installation")
		end
		luup.variable_set(ALTSonos_SERVICE, "Version", version, lul_device)
	end

	registerHandlers(lul_device)
	local success = startEngine(lul_device)
	log("startup completed")
end

------------------------------------------------
-- Check UI7
------------------------------------------------
local function checkVersion(lul_device)
  local ui7Check = luup.variable_get(ALTSonos_SERVICE, "UI7Check", lul_device) or ""
  if ui7Check == "" then
	luup.variable_set(ALTSonos_SERVICE, "UI7Check", "false", lul_device)
	ui7Check = "false"
  end
  if( luup.version_branch == 1 and luup.version_major == 7) then
	if (ui7Check == "false") then
		-- first & only time we do this
		luup.variable_set(ALTSonos_SERVICE, "UI7Check", "true", lul_device)
		luup.attr_set("device_json", UI7_JSON_FILE, lul_device)
		luup.reload()
	end
  else
	-- UI5 specific
  end
end

function initstatus(lul_device)
  lul_device = tonumber(lul_device)
  this_device = lul_device
  -- this_device = lul_device
  log("initstatus("..lul_device..") starting version: "..version)
  checkVersion(lul_device)
  -- hostname = getIP()
  local delay = 1	-- delaying first refresh by x seconds
  debug("initstatus("..lul_device..") startup for Root device, delay:"..delay)
  luup.call_delay("startupDeferred", delay, tostring(lul_device))
end

-- do not delete, last line must be a CR according to MCV wiki page
