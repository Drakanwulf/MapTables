--[[################################################################################################################################

LibMaps - A standalone library add-on to create and maintain Map tables for the QuestMap2 project
	by Drakanwulf and Hawkeye1889

A standalone library to create and initialize or to retrieve and update Map information for all accounts and characters on on 
any game megaserver.

WARNING: This add-on is a standalone library. Do NOT embed its folder within any other add-on folder!

################################################################################################################################--]]

--[[--------------------------------------------------------------------------------------------------------------------------------
Local variables shared by multiple functions within this add-on.
----------------------------------------------------------------------------------------------------------------------------------]]
local strformat = string.format

--[[--------------------------------------------------------------------------------------------------------------------------------
Same variables for AddonStub as for LibStub except MINOR must match the AddOnVersion number in the manifest.
----------------------------------------------------------------------------------------------------------------------------------]]
local MAJOR, MINOR = "LibMaps", 100

--[[--------------------------------------------------------------------------------------------------------------------------------
Bootstrap code to either load or update this add-on.
----------------------------------------------------------------------------------------------------------------------------------]]
local addon, version = AddonStub:Get( MAJOR )
if addon then
	assert( version < MINOR, "LibMaps: Add-on is already loaded. Do NOT load LibMaps multiple times!" )
--	if version = MINOR then
--		return
--	else
--		error( strformat( "LibMaps:V%q: Will not load older versions of itself!", tostring( version ) ), 2 )
--	end
end

local addon, version = AddonStub:New( MAJOR, MINOR )
assert( addon, "LibMaps: AddonStub failed to create a control entry!" )

--[[--------------------------------------------------------------------------------------------------------------------------------
Define local variables and tables including a "defaults" Saved Variables table.
----------------------------------------------------------------------------------------------------------------------------------]]
-- Create empty Maps reference tables
local coordsByIndex = {}			-- Global x,y coordinates (topleft corner) by mapIndex
local indexByName = {}				-- Mapindexes by Map Name
local infoByIndex = {}				-- General information by mapIndex
local nameByIndex = {}				-- Map names by mapIndex
local mapToZoneByIndex = {}			-- Map Index to Zone Identifier Cross-References by mapIndex

local defaults = {					-- This is the Saved Variables "defaults" table
	coords = coordsByIndex,
	indexs = indexByName,
	info = infoByIndex,
	names = nameByIndex,
	xrefs = mapToZoneByIndex,
	apiVersion = 0,					-- ESO API Version in use the last time this library was loaded.
	numMaps = 0,					-- Number of maps in the world the last time this library was loaded.
}

addon.defaults = defaults

--[[--------------------------------------------------------------------------------------------------------------------------------
Obtain a local link to "LibGPS2" and define a measurements table for its use.
----------------------------------------------------------------------------------------------------------------------------------]]
local GPS = LibStub:GetLibrary( "LibGPS2", SILENT )
assert( GPS, "LibMaps: LibStub refused to create a link to LibGPS2!" )

local measurement = {
	scaleX = 0,
	scaleY = 0,
	offsetX = 0,
	offsetY = 0,
	mapIndex = 0,
	zoneIndex = 0,
}

--[[--------------------------------------------------------------------------------------------------------------------------------
Local functions to load the Maps reference tables.
----------------------------------------------------------------------------------------------------------------------------------]]
-- Loads the data for one Map into the reference tables
local function LoadOneMap( mdx: number )
	-- Get the reference information for this map
	local name, mtype, ctype, zid				-- Information about each map. See GetMapInfo()
	name, mtype, ctype, zid = GetMapInfo( mdx )

	-- Load the reference tables for this Map
	indexByName[name] = mdx											-- Indexes table
	nameByIndex[mdx] = name											-- Names table
	infoByIndex[mdx] = { mapType = mtype, content = ctype }			-- Info table
	if zid and type( zid ) == "number" and zid > 0 then				-- Map to Zone xref table
		mapToZoneByIndex[mdx] = zid
	end

	-- Get the global x,y coordinate values
	SetMapToMapListIndex( mdx )										-- Change maps
	measurement = GPS:GetCurrentMapMeasurements() or {}				-- "or {}" because The Aurbis map returns nil!
	coordsByIndex[mdx] = { measurement.offsetX or 0, measurement.offsetY or 0 }
end

-- Resets and loads the reference tables for every Map in the world
local function LoadAllMaps( tmax: number )		-- tmax := The number of maps in the world
	-- Reset the reference tables
	coordsByIndex = {}
	indexByName = {}
	infoByIndex = {}
	nameByIndex = {}
	mapToZoneByIndex = {}
	-- Loop through all the maps
	local mdx									-- mapIndex
	for mdx = 1, tmax do
		LoadOneMap( mdx )						-- Load the data for one Map
	end
end

-- Updates any missing entries in each reference table for every Map in the world
local function UpdateAllMaps( tmax: number )	-- tmax := The number of maps in the world
	-- Loop through all the maps
	local mdx									-- mapIndex
	for mdx = 1, tmax do
		if not nameByIndex[mdx]
		or not coordsByIndex[mdx] or coordsByIndex[mdx] == {}
		or not infoByIndex[mdx] or infoByIndex[mdx] == {}
		or not mapToZoneByIndex[mdx] or mapToZoneByIndex[mdx] == {} then
			LoadOneMap( mdx )					-- Load the data for one Map
		end
	end
end

--[[--------------------------------------------------------------------------------------------------------------------------------
The "OnAddonLoaded" function reads the saved variables table (sv) from the saved variables file, "...\SavedVariables\LibMaps.lua"
if the file exists; otherwise, the function loads partially filled, default tables into the "sv" variable. Finally, the function
links everything in its local tables to their equivalent LibMaps table entries.
----------------------------------------------------------------------------------------------------------------------------------]]
local function OnAddonLoaded( event, name )
	if name ~= MAJOR then
		return
	end
	EVENT_MANAGER:UnregisterForEvent( MAJOR, EVENT_ADD_ON_LOADED )

	-- Define megaserver constants and a saved variables filenames table. Default is the PTS megaserver.
	local SERVER_EU = "EU Megaserver" 
	local SERVER_NA = "NA Megaserver"
	local SERVER_PTS = "PTS"

	local savedVarsNameTable = {
		[SERVER_EU] = "EU_SavedVars",
		[SERVER_NA] = "NA_SavedVars",
		[SERVER_PTS] = "PTS_SavedVars",
	}	 	

	-- Retrieve the saved variables data or load their default values
	local savedVarsFile = savedVarsNameTable[GetWorldName()] or savedVarsNameTable[SERVER_PTS]
	local sv = _G[savedVarsFile] or defaults
	local tables = sv
	
	--Update the Maps reference tables from their Saved Data variables
	coordsByIndex = tables.coords 
	indexByName = tables.indexs 
	infoByIndex = tables.info 
	nameByIndex = tables.names
	mapToZoneByIndex = tables.xrefs

	-- Wait for a player to become active; LibGPS2 needs this
	EVENT_MANAGER:RegisterForEvent( MAJOR, EVENT_PLAYER_ACTIVATED,
		function( event, initial )
			EVENT_MANAGER:UnregisterForEvent( MAJOR, EVENT_PLAYER_ACTIVATED )
		end
	)
	assert( GPS:IsReady(), "LibMaps: LibGPS2 cannot function until a player is active!" )

	-- Save wherever we are in the world
	SetMapToPlayerLocation()					-- Set the current map to wherever we are in the world
	GPS:PushCurrentMap()						-- Save the current map settings

	-- If either the APIVersion or the number of maps has changed, reload the Maps reference tables
	local currentAPI = GetAPIVersion()
	local numMaps = GetNumMaps()
	if currentAPI ~= tables.apiVersion
	or numMaps ~= tables.numMaps then
		tables.apiVersion = currentAPI			-- Update the API version number
		tables.numMaps = numMaps				-- Update the number of Maps in the world
		LoadAllMaps( numMaps )					-- Reload every reference table for all maps
	-- Otherwise, update the Maps reference tables whenever a map or its data are missing
	else
		UpdateAllMaps( numMaps )				-- Update missing tables, maps, and their data
	end

	-- Put us back to wherever we were in the world
	GPS:PopCurrentMap()

	-- Transfer the loaded or updated reference table variables to their Saved Data variables.
	tables.coords = coordsByIndex
	tables.indexs = indexByName
	tables.info = infoByIndex
	tables.names = nameByIndex
	tables.xrefs = mapToZoneByIndex

	-- Create or update the saved variables table in a "...\SavedVariables\LibMaps.lua" file
	sv = tables
	_G[savedVarsFile] = sv
end

--[[--------------------------------------------------------------------------------------------------------------------------------
Define the public API functions for this add-on.
----------------------------------------------------------------------------------------------------------------------------------]]
-- Get the content type of this map
function LibMaps:GetContentType( mapIndex: number )
	return infoByIndex[mapIndex].content or nil
end

-- Get the map type of this map
function LibMaps:GetMapType( mapIndex: number )
	return infoByIndex[mapIndex].mapType or nil
end

-- Get the index of this Map
function LibMaps:GetMapIndex( mapName: string )
	return indexByName[mapName] or nil
end

-- Get the name of this Map
function LibMaps:GetMapName( mapIndex: number )
	return nameByIndex[mapIndex] or nil
end

-- Get the global x,y coordinates for the top left corner of this Map
function LibMaps:GetMapTopLeft( mapIndex: number )
	return coordsByIndex[mapIndex][1] or nil, coordsByIndex[mapIndex][2] or nil
end

-- Get the equivalent Zone Identifier for this Map
function LibMaps:GetMapZoneId( mapIndex: number )
	return mapToZoneByIndex[mapIndex] or nil
end

--[[--------------------------------------------------------------------------------------------------------------------------------
And the last thing we do in every add-on is to wait for ESO to notify us that all our modules and dependencies have been loaded.
----------------------------------------------------------------------------------------------------------------------------------]]
EVENT_MANAGER:RegisterForEvent( MAJOR, EVENT_ADD_ON_LOADED,	OnAddonLoaded )

