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
local version		= "v0.11"
local JSON_FILE = "D_ALTSonos.json"
local UI7_JSON_FILE = "D_ALTSonos_UI7.json"
local this_device = nil
local retry_timer = 1/2			-- in mn, retry time
local json = require("dkjson")
local socket = require("socket")
local modurl = require ("socket.url")
local mime = require("mime")
local https = require ("ssl.https")	
local SonosEventTimer = 2
local SonosEventTimerMin = SonosEventTimer
local SonosEventTimerMax = 3600
local SonosEventDecayCount = 4
local SonosPlayStreamStopTimeSec = 7
local SonosDB = {}
local SeqId = 0 	-- for changing timer duration of pending calldelay ...

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
local function findGroupHousehold(gid)
	for hid,household in pairs(SonosDB) do
		if (household.groupId[gid] ~= nil) then
			return hid
		end
	end
	return null
end

local function enumerateGroups()
	local groupkeys = {}
	for hid,household in pairs(SonosDB) do
		for gid,group in pairs(household.groupId) do
			table.insert(groupkeys,gid)
		end
	end
	return groupkeys
end

local function getDBValue(lul_device,householdid,target_type,target_value,sonos_type )
	SonosDB[householdid] = SonosDB[householdid] or {}
	if (target_type ~=nil) then
		if (SonosDB[householdid]==nil) then
			SonosDB[householdid]={}
		end
		if (target_value~=nil) then
			if (SonosDB[householdid][target_type]==nil) then
				SonosDB[householdid][target_type]={}
			end
			if (sonos_type~=nil) then
				if (SonosDB[householdid][target_type][target_value]==nil) then
					SonosDB[householdid][target_type][target_value]={}
				end
				return SonosDB[householdid][target_type][target_value][sonos_type] 
			else
				return SonosDB[householdid][target_type][target_value] 
			end
		else
			return SonosDB[householdid][target_type]
		end
	else
		return SonosDB[householdid] 
	end
	return null
end

function clearDBValue(lul_device,seq_id,householdid,target_type,target_value,sonos_type)
	debug(string.format("clearDBValue(%s,%s,%s,%s,%s)",lul_device,seq_id or 'nil',householdid,target_type or '',target_value or ''))
	if (target_type ~=nil) and (target_value ~= nil) then
		SonosDB[householdid][target_type][target_value] = nil
		return true
	end
	return false
end

function onDefaultNotification(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
	debug(string.format("onDefaultNotification(%s,%s,%s,%s,%s,%s)",lul_device,seq_id or 'nil',householdid,target_type or '',target_value or '',sonos_type or ''))
	-- all other use cases
	SonosDB[householdid][target_type][target_value] = SonosDB[householdid][target_type][target_value] or {}
	local tbl = SonosDB[householdid][target_type][target_value]
	if (tbl[sonos_type] == nil) or (tbl[sonos_type]['seq_id'] == nil ) then
		tbl[sonos_type] = body
		tbl[sonos_type]['seq_id'] = seq_id
		return true
	else
		if (tbl[sonos_type]['seq_id'] <= seq_id ) then
			tbl[sonos_type] = body
			tbl[sonos_type]['seq_id'] = seq_id
			return true
		else
			debug(string.format("ignoring out of sequence seq_id %s , DB contains %s",seq_id , tbl[sonos_type]['seq_id'] ))
		end
	end
	return false
end

function onGroupCoordinatorChanged(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
	debug(string.format("onGroupCoordinatorChanged(%s,%s,%s,%s,%s,%s)",lul_device,seq_id or 'nil',householdid,target_type or '',target_value or '',sonos_type or ''))
	if (body.groupStatus=="GROUP_STATUS_GONE") then
		-- clearDBValue(lul_device,seq_id,householdid,target_type,target_value,sonos_type)
		return false
	end
	return false --  onDefaultNotification(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
end

function onGroupsNotification(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
	debug(string.format("onGroupsNotification(%s,%s,%s,%s,%s,%s)",lul_device,seq_id or 'nil',householdid,target_type or '',target_value or '',sonos_type or ''))
	luup.variable_set(ALTSonos_SERVICE, "Players", json.encode(body.players), lul_device)
	local updatedGroups = {} 
	for i,grp in pairs(body.groups) do
		-- if it is brand new group, we need to properly register for notifications
		local old = getDBValue(lul_device,householdid,'groupId',grp.id)
		setDBValue(lul_device,seq_id,householdid,'groupId',grp.id,'core', grp )
		if (old==nil) then
			--  new group
			debug(string.format("new group advertised %s, registering for notifications",grp.id))
			subscribeGroup(lul_device, SonosDB[householdid].groupId[ grp.id ])
		end
		updatedGroups[ grp.id ] = true
	end
	debug(string.format("updated groups = %s ",json.encode(updatedGroups)))
	-- now remove all the groups from the DB which were not reported back
	local household = SonosDB[householdid]
	for gid,group in pairs(household.groupId) do
		-- if gif was not updated, then kill it
		if (updatedGroups[gid]==nil) then
			debug(string.format("group %s was not updated, delete it",gid))
			unsubscribeGroup(lul_device, group)
			SonosDB[householdid].groupId[gid] = nil
		end
	end
	debug(string.format("END OF onGroupsNotification(%s,%s,%s,%s,%s,%s)",lul_device,seq_id or 'nil',householdid,target_type or '',target_value or '',sonos_type or ''))
	return true
end

function setDBValue(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body )
	debug(string.format("setDBValue(%s,%s,%s,%s,%s,%s)",lul_device,seq_id or 'nil',householdid,target_type or '',target_value or '',sonos_type or ''))
	seq_id = tonumber(seq_id or 0)
	SonosDB[householdid] = SonosDB[householdid] or {}
	if (target_type ~=nil) then
		SonosDB[householdid][target_type] = SonosDB[householdid][target_type] or {}
		if (target_value ~= nil) then
			-- SonosDB[householdid][target_type][target_value] = SonosDB[householdid][target_type][target_value] or {}
			if (sonos_type ~=nil) then
				debug(string.format("type:%s body is %s",sonos_type,json.encode(body)))
				
				if (sonos_type=='groupCoordinatorChanged') then
					return onGroupCoordinatorChanged(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
				elseif (sonos_type=='groups') then
					return onGroupsNotification(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
				else 
					return onDefaultNotification(lul_device,seq_id,householdid,target_type,target_value,sonos_type, body)
				end
			end
		end
	else
		SonosDB[householdid] = {}
		return true
	end
	return false
end

local function resetRefreshMetadataLoop(lul_device)
	debug(string.format("resetRefreshMetadataLoop(%s), SeqId %s",lul_device,SeqId))
	warning(string.format("resetLoop, SeqId %s=>%s",SeqId,SeqId+1))
	SeqId = SeqId+1
	SonosEventTimer = SonosEventTimerMin
	luup.call_delay("refreshMetadata", SonosEventTimer, json.encode({lul_device=lul_device, lul_data=SeqId}))
end


local function logSonosHTTP(request,code,headers,data)
	debug(string.format("response request:%s",request))
	debug(string.format("code:%s",code))
	debug(string.format("headers:%s",json.encode(headers)))
	debug(string.format("data:%s",json.encode(data)))
end

local function refreshToken( lul_device )
	debug(string.format("refreshToken(%s)",lul_device))
	lul_device = tonumber(lul_device)

	local ALTSONOS_KEY = getSetVariable(ALTSonos_SERVICE, "ALTSonosKey", lul_device, "")
	local ALTSONOS_SECRET = getSetVariable(ALTSonos_SERVICE, "ALTSonosSecret", lul_device, "")
	local b64credential = "Basic ".. mime.b64(ALTSONOS_KEY..":"..ALTSONOS_SECRET)
	local refresh_token = luup.variable_get(ALTSonos_SERVICE, "RefreshToken", lul_device)
	local body = string.format('grant_type=refresh_token&refresh_token=%s',refresh_token)
	
	local response,msg = SonosHTTP(lul_device,"api.sonos.com/login/v3/oauth/access","POST",body,b64credential)
	if (response ~=nil ) then
		luup.variable_set(ALTSonos_SERVICE, "RefreshToken", response.refresh_token, lul_device)
		luup.variable_set(ALTSonos_SERVICE, "AccessToken", response.access_token, lul_device)
	end
	return response,msg
end

function SonosHTTP(lul_device,path,verb,body,b64credential,contenttype,headers)
	local verb = verb or "GET"
	local url = "https://" .. path
	body = body or ""
	contenttype = contenttype or "application/x-www-form-urlencoded"
	headers = headers or {}

	if (b64credential==nil) then
		local token = luup.variable_get(ALTSonos_SERVICE, "AccessToken", lul_device)	
		b64credential = "Bearer ".. token
	end

	debug(string.format("SonosHTTP(%s,%s,%s,%s,%s,%s,%s)",lul_device,path,verb,body,b64credential or "",contenttype or "", json.encode(headers)))
	
	headers["Authorization"] = b64credential
	headers["Content-Length"] = body:len()
	headers["Cache-Control"] =  'no-cache'
	headers["Content-Type"] = contenttype
	
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
	local data=table.concat(result)
	logSonosHTTP(request or 'nil',code,headers,data or 'nil')
	
	if (request==nil) then
		error(string.format("failed to connect to %s, http.request returned nil", url))
		return nil,"failed to connect"
	elseif (code==401) then
		warning(string.format("Access denied:%d , trying to refresh the token", code))
		if (refreshToken( lul_device ) ~= nil) then
			debug(string.format("Success refreshing the token, retrying the request"))
			return SonosHTTP(lul_device,path,verb,body,nil)	-- nil to force reconstructing credential with new token
		end
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
	local response = json.decode(data)
	return response,""
end

local function onAuthorizationCallback( lul_device, AuthCode) 
	debug(string.format("onAuthorizationCallback(%s,%s)",lul_device,AuthCode))
	lul_device = tonumber(lul_device)

	luup.variable_set(ALTSonos_SERVICE, "AuthCode", AuthCode, lul_device)
	local cfauth = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionAuthUrl", lul_device) 
	local cfauth2 = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionEventUrl", lul_device) 
	local cfauth3 = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionVeraPullUrl", lul_device) 
	local ALTSONOS_KEY = getSetVariable(ALTSonos_SERVICE, "ALTSonosKey", lul_device, "")
	local ALTSONOS_SECRET = getSetVariable(ALTSonos_SERVICE, "ALTSonosSecret", lul_device, "")
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

-- not local, setDBValue calls it
function getGroups(lul_device, hid )
	debug(string.format("getGroups(%s,%s)",lul_device,hid))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/households/%s/groups",hid)
	local response,msg = SonosHTTP(lul_device,cmd,"GET")
	if (response ~=nil ) then
		local updatedGroups= {} -- = SonosDB[hid].groupId
		for i,grp in pairs(response.groups) do
			setDBValue(lul_device,0,hid,'groupId',grp.id,'core', grp )
			updatedGroups[ grp.id ] = true
		end
		debug(string.format("received groups %s",json.encode(updatedGroups)))

		-- now remove all the groups from the DB which were not reported back
		for hid,household in pairs(SonosDB) do
			for gid,group in pairs(household.groupId) do
				-- if gif was not updated, then kill it
				if (updatedGroups[gid]==nil) then
					debug(string.format("group %s was not updated, delete it",gid))
					unsubscribeGroup(lul_device, group)
					SonosDB[hid].groupId[gid] = nil
				end
			end
		end

		debug(string.format("updated DB %s",json.encode(SonosDB)))
		luup.variable_set(ALTSonos_SERVICE, "Players", json.encode(response.players), lul_device)
		-- luup.variable_set(ALTSonos_SERVICE, "Groups", json.encode(response.groups), lul_device)
		return response
	end
	return nil
end

local function getHouseholds(lul_device)
	debug(string.format("getHouseholds(%s)",lul_device))
	local response,msg = SonosHTTP(lul_device,"api.ws.sonos.com/control/api/v1/households","GET")
	if (response ~=nil ) then
		for i,household in pairs(response.households) do
			setDBValue(lul_device,0,household.id)
		end
		debug(string.format("updated DB %s",json.encode(SonosDB)))
		luup.variable_set(ALTSonos_SERVICE, "Households", json.encode(response.households), lul_device)
		return response.households
	end
	return nil
end

local function getFavorites(lul_device, hid)
	debug(string.format("getFavorites(%s,%s)",lul_device,hid))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/households/%s/favorites",hid)
	local response,msg = SonosHTTP(lul_device,cmd,"GET")
	if (response ~=nil ) then
		for i,fav in pairs(response.items) do
			setDBValue(lul_device,0,hid,'favorites',i,'favorite', fav )
		end
		debug(string.format("updated DB %s",json.encode(SonosDB)))
		luup.variable_set(ALTSonos_SERVICE, "Favorites", json.encode(response.items), lul_device)
		return response.items
	end
	return nil
end

local function getVolume(lul_device, gid)
	debug(string.format("getVolume(%s,%s)",lul_device,gid))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/groupVolume",gid)
	local response,msg = SonosHTTP(lul_device,cmd,"GET")
	if (response ~=nil ) then
		debug(string.format("updated DB %s",json.encode(SonosDB)))
		luup.variable_set(ALTSonos_SERVICE, "LastVolume", response.volume, lul_device)
		return response.volume
	end
	return nil
end

local function setVolumeRelative( lul_device, gid, delta )
	debug(string.format("setVolumeRelative(%s,%s,%s)",lul_device,gid,delta))
	lul_device = tonumber(lul_device)
	delta = delta or 0
	
	local householdid = findGroupHousehold(gid)
	local curvol = getDBValue(lul_device,householdid,'groupId',gid,'groupVolume' ) or 0
	curvol.volume = curvol.volume + delta
	setDBValue(lul_device,0,householdid,'groupId',gid,'groupVolume', curvol )

	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/groupVolume/relative",gid)
	local body = json.encode({
		volumeDelta=delta
	})	
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
	debug(string.format("updated DB %s",json.encode(SonosDB)))
	resetRefreshMetadataLoop(lul_device)
	return response,msg
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

local counter = 0
local function increaseTimer(current)
	local result = current
	counter= counter+1
	if (counter>SonosEventDecayCount) then
		counter = 0
		result = math.min( 2*SonosEventTimer , SonosEventTimerMax )
	end
	return result
end

function refreshMetadata(params)
	debug(string.format("refreshMetadata(%s) - current SeqId:#%s",params,SeqId))
	local obj = json.decode(params)
	local lul_device = tonumber(obj.lul_device)
	local oldSeqId = tonumber(obj.lul_data)

	local url = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionVeraPullUrl", lul_device) 
	local code,data,result = luup.inet.wget(url)
	if (code==0) then
		debug(string.format("refreshMetadata: received %s",data))
		if (data =="[]") then
			SonosEventTimer = increaseTimer(SonosEventTimer)
		else
			local arr = json.decode(data)
			debug(string.format("metadata with %d messages",tablelength(arr)))			
			for k,msg in pairs(arr) do
				local obj = msg.data
				setDBValue(lul_device,tonumber(obj.seq_id),obj.householdid,obj.target_type,obj.target_value,obj.sonos_type,obj.body)
			end
			debug(string.format("updated DB %s",json.encode(SonosDB)))
			SonosEventTimer = SonosEventTimerMin
		end
		if (oldSeqId < SeqId ) then
			warning(string.format("Obsolete refreshMetadata callback, ignoring seq:%d expecting:%d",oldSeqId,SeqId))
		else
			debug(string.format("refreshMetadata: received metadata -- rearming for %s seconds.",SonosEventTimer))		
			luup.call_delay("refreshMetadata", SonosEventTimer, json.encode({lul_device=lul_device, lul_data=SeqId}))		
		end
	else
		warning(string.format("luup.inet.wget(%s) returned a bad code: %d , result:%s", url,code,result or 'nil'))
	end
	return true
end

-- cmd = "play" or "pause"
local function groupPlayPauseOneGroup(lul_device,cmd,groupID)
	debug(string.format("groupPlayPauseOneGroup(%s,%s,%s)",lul_device,groupID,cmd))
	lul_device = tonumber(lul_device)
	cmd = cmd or "play"
	local url = string.format("api.ws.sonos.com/control/api/v1/groups/%s/playback/%s",groupID,cmd)
	local response,msg = SonosHTTP(lul_device,url,"POST")
	
	resetRefreshMetadataLoop(lul_device)
	return response,msg
end

local function groupPlayPause(lul_device,cmd,groupID)
	debug(string.format("groupPlayPause(%s,%s,%s)",lul_device,groupID,cmd))
	if (groupID=="ALL") then
		for idx,gid in pairs(enumerateGroups()) do
			local response,msg = groupPlayPauseOneGroup(lul_device,cmd,groupID)
			if (response==nil) then
				warning(string.format("error encountered in PlayPause command : %s, stopping the loop",msg))
				return nil,msg
			end
		end
		return
	end
	return groupPlayPauseOneGroup(lul_device,cmd,groupID)
end

local function loadFavorites(lul_device, gid, fid)
	debug(string.format("loadFavorites(%s,%s,%s)",lul_device,gid,fid))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/favorites",gid)
	local body = json.encode({
		favoriteId=fid,
		playOnCompletion=true
	})
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')

	resetRefreshMetadataLoop(lul_device)
	return response,msg
end

local function audioClip(lul_device, pid, urlClip )
	debug(string.format("audioClip(%s,%s,%s)",lul_device, pid, urlClip))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/players/%s/audioClip",pid)
	local body = json.encode({
		name="altsonos audioClip",
		appId="com.getvera.amg0.altsonos",
		streamUrl=urlClip
	})	

	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
	resetRefreshMetadataLoop(lul_device)
	return response,msg
end

local function joinOrCreateSession(lul_device, gid )
	debug(string.format("joinOrCreateSession(%s,%s)",lul_device, gid ))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/playbackSession/joinOrCreate",gid)
	local body = json.encode({
		appContext="altsonos_audioClip",
		appId="com.getvera.amg0.altsonos"
	})	
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
	return response,msg
end


local function getPlaylist(lul_device,hid,playlistId)
	debug(string.format("getPlaylist(%s,%s,%s)",lul_device, hid,playlistId ))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/households/%s/playlists/getPlaylist",hid)
	local body = json.encode({
		playlistId = playlistId
	})	
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
	return response,msg
end

local function getPlaylists(lul_device,hid)
	debug(string.format("getPlaylists(%s,%s)",lul_device, hid ))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/households/%s/playlists",hid)
	local response,msg = SonosHTTP(lul_device,cmd,"GET")
	return response,msg
end

local function createSession(lul_device, gid )
	debug(string.format("createSession(%s,%s)",lul_device, gid ))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/playbackSession",gid)
	
	local body = json.encode({
		appContext="altsonos_audioClip",
		appId="com.getvera.amg0.altsonos"
	})	
	local headers = {
		-- namespace= "playbackSession:1",
		-- command= "createSession",
		-- "cmdId"= "123",
		householdId= hid,
		groupId= gid
	}
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json',headers)
	return response,msg
end

local function setPlayMode(lul_device, gid)
	debug(string.format("setPlayMode(%s,%s)",lul_device, gid ))
	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/playback/playMode",gid)
	local body = json.encode({
		playModes = {
			["repeat"] = false
			-- repeatOne = false,
			-- crossfade = false,
			-- shuffle = false,
		  }
	})	
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
	resetRefreshMetadataLoop(lul_device)
	return response,msg
end

function stopStreamUrl(data)
	debug(string.format("stopStreamUrl(%s)",data))
	local obj = json.decode(data)
	lul_device = tonumber(obj.lul_device)
	gid = obj.gid
	groupPlayPause(lul_device,"pause",gid)
end	
	
local function loadStreamUrlGid(lul_device, gid, streamUrl, duration )
	debug(string.format("loadStreamUrlGid(%s,%s,%s,%s)",lul_device, gid , streamUrl, duration or '' ))
	duration = tonumber(duration or SonosPlayStreamStopTimeSec)
	duration = math.max( SonosPlayStreamStopTimeSec , duration )
	debug(string.format("corrected duration:%s",duration))
	local response,msg = createSession(lul_device, gid )
	if (response ~= nil) and (response.sessionId ~= nil) then
		local cmd = string.format("api.ws.sonos.com/control/api/v1/playbackSessions/%s/playbackSession/loadStreamUrl",response.sessionId )
		local body = json.encode({
			streamUrl=streamUrl,
			playOnCompletion=true
		})	
		local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
		-- groupPlayPause(lul_device,"play",gid)
		luup.call_delay("stopStreamUrl", duration, json.encode({lul_device=lul_device, gid=gid}))
		resetRefreshMetadataLoop(lul_device)
		return response,msg	
	end
	warning("could not join or create a sonos session")
	return nil,"could not create a sonos session"
end

local function setGroupMembers(lul_device, groupID, playerIDs)
	playerIDs = playerIDs or ''
	debug(string.format("setGroupMembers(%s,%s,'%s')",lul_device, groupID , playerIDs))

	local players = Split(playerIDs, ',', 0)
	local cmd = string.format("api.ws.sonos.com/control/api/v1/groups/%s/groups/setGroupMembers",groupID)
	local body = json.encode({
		["playerIds"] = players
	})	
	local response,msg = SonosHTTP(lul_device,cmd,"POST",body,nil,'application/json')
	if (response~=nil) then
		-- response.group is a group object
		local hid = findGroupHousehold(groupID)
		setDBValue(lul_device,0,hid,'groupId',response.group.id,'core', response.group )
		resetRefreshMetadataLoop(lul_device)
	end
	--"{\"group\":{\"id\":\"RINCON_5CAAFD05CA4E01400:2985\",\"name\":\"Séjour + 1\",\"coordinatorId\":\"RINCON_5CAAFD05CA4E01400\",\"playerIds\":[\"RINCON_5CAAFD05CA4E01400\",\"RINCON_5CAAFD48412A01400\"]}}"
	--luup.call_delay("syncDevices", 5, lul_device)
	return response,msg	
end

local function loadStreamUrl(lul_device, gid, streamUrl , duration )
	debug(string.format("loadStreamUrl(%s,%s,%s,%s)",lul_device, gid , streamUrl, duration or "" ))
	if (gid=="ALL") then
		for idx,gid in pairs(enumerateGroups()) do
			loadStreamUrlGid(lul_device, gid, streamUrl, duration )
		end
		return
	else
		-- TODO split groups by CSV and iterate for specified groups
	end
	return loadStreamUrlGid(lul_device, gid, streamUrl ,duration )
end

function subscribeDeferred(data)
	debug(string.format("subscribeDeferred(%s)",data))
	local tbl = json.decode(data)
	for k,obj in pairs(tbl) do
		local response,msg = SonosHTTP(obj.lul_device,obj.url,obj.verb)
	end
end

function unsubscribeGroup(lul_device,group)
	debug(string.format("unsubscribeGroup(%s,%s)",lul_device,json.encode(group)))
	local tbl = {
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/groups/%s/playbackMetadata/subscription",group.core.id), verb="DELETE"},
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/groups/%s/groupVolume/subscription",group.core.id), verb="DELETE"},
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/groups/%s/playback/subscription",group.core.id), verb="DELETE"},
	}
	luup.call_delay("subscribeDeferred", 1, json.encode(tbl))
end

function subscribeGroup(lul_device,group)
	debug(string.format("subscribeGroup(%s,%s)",lul_device,json.encode(group)))
	local tbl = {
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/groups/%s/playbackMetadata/subscription",group.core.id), verb="POST"},
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/groups/%s/groupVolume/subscription",group.core.id), verb="POST"},
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/groups/%s/playback/subscription",group.core.id), verb="POST"},
	}
	luup.call_delay("subscribeDeferred", 5, json.encode(tbl))
end

local function subscribeMetadata(lul_device,hid)
	debug(string.format("subscribeMetadata(%s)",lul_device))
	lul_device = tonumber(lul_device)
	local response,msg = nil,nil
	-- local groups = luup.variable_get(ALTSonos_SERVICE, "Groups", lul_device)
	-- groups = json.decode( groups )
	groups = SonosDB[hid].groupId
	
	-- unsubscribe groups notifications
	local tbl = {
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/households/%s/groups/subscription",hid), verb="DELETE"},
	}
	luup.call_delay("subscribeDeferred", 1, json.encode(tbl))
	local tbl = {
		{lul_device=lul_device, url=string.format("api.ws.sonos.com/control/api/v1/households/%s/groups/subscription",hid), verb="POST"},
	}
	luup.call_delay("subscribeDeferred", 1, json.encode(tbl))

	for k,group in pairs(groups) do
		unsubscribeGroup(lul_device,group)
	end
	-- subscribe
	for k,group in pairs(groups) do
		subscribeGroup(lul_device,group)
	end
	
	-- start a new engine loop
	resetRefreshMetadataLoop(lul_device)
	-- luup.call_delay("refreshMetadata", SonosEventTimer, json.encode({lul_device=lul_device, lul_data=SeqId}))
	return (response ~= nil )
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
	debug("myALTSonos_Handler:Unknown command received:"..command.." was called. Default function")
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
		["GetDBInfo"] = 
			function(params)
				local result = json.encode(SonosDB)
				return result, "application/json"
			end,
		["GetAppInfo"] = 
			function(params)
				local cfauth = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionAuthUrl", lul_device) 
				local cfauth2 = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionEventUrl", lul_device) 
				local cfauth3 = luup.variable_get(ALTSonos_SERVICE, "CloudFunctionVeraPullUrl", lul_device) 				
				local ALTSONOS_KEY = luup.variable_get(ALTSonos_SERVICE, "ALTSonosKey", lul_device)
				return json.encode( { ip=getIP(), altsonos_key=ALTSONOS_KEY, proxy=cfauth, event=cfauth2, verapull=cfauth3 } ),"application/json"
			end,
		["AuthorizationCB"] = 
			function(params)
				local code = lul_parameters["code"]
				local deviceNum = lul_parameters["DeviceNum"]
				local obj,msg = onAuthorizationCallback( deviceNum, code)
				debug(string.format("received json: {0}",json.encode(obj)))
				return  msg .. " You can close the window and return to the ALTSONOS application" , "text/plain" 
			end,
		["EventCB"] = 
			function(params)
				debug(string.format("received EventCB"))
				return "ok", "text/plain"
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

function syncDevices(lul_device)
	debug(string.format("syncDevices(%s)",lul_device))
	lul_device = tonumber(lul_device)
	local groups=nil
	local households = getHouseholds(lul_device)
	debug(string.format("households response = %s",json.encode(households)))
	if (households~=nil) then
		local householdid = households[1].id
		local groups = getGroups(lul_device, householdid)
		local favorites = getFavorites(lul_device, householdid)
		subscribeMetadata(lul_device,householdid)
	end
	return (households~=nil) and (groups~=nil)
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
	getSetVariable(ALTSonos_SERVICE, "CloudFunctionEventUrl", lul_device, cfauthurl)
	getSetVariable(ALTSonos_SERVICE, "CloudFunctionVeraPullUrl", lul_device, cfauthurl)
	getSetVariable(ALTSonos_SERVICE, "ALTSonosKey", lul_device, "")
	getSetVariable(ALTSonos_SERVICE, "ALTSonosSecret", lul_device, "")
	-- getSetVariable(ALTSonos_SERVICE, "Groups", lul_device, "")
	getSetVariable(ALTSonos_SERVICE, "Players", lul_device, "")
	getSetVariable(ALTSonos_SERVICE, "Households", lul_device, "")
	getSetVariable(ALTSonos_SERVICE, "Favorites", lul_device, "")

		
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

	luup.register_handler("myALTSonos_Handler","ALTSonos_Handler")
	local success = syncDevices(lul_device)
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
