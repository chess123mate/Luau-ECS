local ecs = {
	-- Global config
	--- Defaults to true. If you are regularly emptying out and recreating archetypes, consider disabling this (and then consider calling world:Clean() on occasion.)
	AutoDeleteEmptyArchetypes = true,
}
ecs.Config = ecs -- TS support
--- Returns true if it's an entity/component/flag that hasn't been deleted
function ecs.IsLiveEntity(e)
	return type(e) == "table" and e.archetype ~= nil
end
local function validateComponent(C)
	return if C
		then if type(C) == "table" and C.archetype ~= nil
			then C
			else error("Invalid component argument", 3)
		else error("Missing component argument", 3)
end
--[[
Unlike proper ECS, we use tables for entities: {
	Name (for debugging)
	Id (convenience for serialization & replication)
	archetype: Archetype
	entitiesIndex: number (into archetype.entities)
	[Component<T>]: T (not applicable for flags) (note that "nil" is a valid value, i.e. testing to see if a key exists doesn't necessarily tell you if an entity has a component or not)
	OnAdd / other hooks also show up here (primarily for components)
}
Components can be used interchangeably with entities (they are identical internally).
Archetype = {
	entities = List<Entity>
	count (of entities)
	components = List<Component>
	HasComponent = Set<Component>
	key = table.concat(component Ids converted to strings) -- note that this means metatables with __tostring should never be applied to components
}
]]

local function Archetype_addEntity(archetype, e) -- updates e.archetype
	local index = archetype.count + 1
	archetype.entities[index] = e
	archetype.count = index
	e.archetype = archetype
	e.entitiesIndex = index
end
local function Archetype_removeEntity(archetype, e) -- note: does not update e.archetype
	local entities = archetype.entities
	local i = e.entitiesIndex
	local count = archetype.count
	if i == count then
		entities[i] = nil
	else
		local moving = entities[count]
		entities[i] = moving
		moving.entitiesIndex = i
		entities[count] = nil
	end
	archetype.count = count - 1
end

local function findInsertIndex(types: { string }, toAdd: string): number
	for i, id in types do
		if id > toAdd then return i end
	end
	return #types + 1
end
local function Archetype_addGetKey(archetype, C)
	local components = table.clone(archetype.components)
	local s = tostring(C.Id)
	table.insert(components, findInsertIndex(components, s), s)
	return table.concat(components, "_"), components
end
local function Archetype_removeGetKey(archetype, C)
	local components = table.clone(archetype.components)
	local s = tostring(C.Id)
	table.remove(components, table.find(components, s))
	return table.concat(components, "_"), components
end

local function Archetype_associateComponents(archetype)
	for C in archetype.HasComponent do
		-- todo is it faster to say C.archetypes[archetype] = true? query frequency vs change components around frequency? (if so, update disassociateComponents also) [doing it that way would avoid needing `table.find`]
		local count = C.archetypesCount + 1
		C.archetypesCount = count
		C.archetypes[count] = archetype
	end
end
local function Archetype_disassociateComponents(archetype)
	for C in archetype.HasComponent do
		local archetypes = C.archetypes
		local i = table.find(archetypes, archetype)
		local count = C.archetypesCount
		if i == count then
			archetypes[i] = nil
		else
			local moving = archetypes[count]
			archetypes[i] = moving
			archetypes[count] = nil
		end
		C.archetypesCount = count - 1
	end
end

local emptyTable = table.freeze({})
local deletingArchetype = table.freeze({
	entities = emptyTable,
	count = 0,
	components = emptyTable,
	HasComponent = emptyTable,
	key = "",
})

local World = {}
ecs.World = World
World.__index = World
local function World_newEntity(self, name)
	local nextId = self.nextId
	self.nextId = nextId + 1
	local e = {
		Id = nextId,
		Name = name,
		archetypes = {}, -- list of archetypes that the entity (as a component) is in
		archetypesCount = 0,
	}
	self.idToEntity[nextId] = e
	Archetype_addEntity(self.emptyArchetype, e)
	return e
end
function World.new()
	local emptyArchetype = {
		entities = {},
		count = 0,
		components = {},
		HasComponent = {},
		key = "",
	}
	local self = setmetatable({
		keyToArchetype = {[""] = emptyArchetype},
		emptyArchetype = emptyArchetype,
		nextId = 0,
		idToEntity = {},
	}, World)
	self.ComponentFlag = World_newEntity(self, "ComponentFlag")
	self.ComponentFlag.IsFlag = true
	self:Add(self.ComponentFlag, self.ComponentFlag)
	self.EntityFlag = self:Flag("EntityFlag")
	return self
end
function World:IdToEntity(id)
	return self.idToEntity[id]
end
function World:Entity(name)
	local e = World_newEntity(self, name)
	self:Add(e, self.EntityFlag)
	return e
end
function World:Component(name)
	local e = World_newEntity(self, name)
	self:Add(e, self.ComponentFlag)
	return e
end
function World:Flag(name)
	local e = World_newEntity(self, name)
	self:Add(e, self.ComponentFlag)
	e.IsFlag = true
	return e
end

local function World_newArchetypeFor(self, e, key, components, hasComponent)
	local archetype = {
		entities = {e},
		count = 1,
		components = components,
		HasComponent = hasComponent,
		key = key,
	}
	self.keyToArchetype[key] = archetype
	e.archetype = archetype
	e.entitiesIndex = 1
	Archetype_associateComponents(archetype)
end

--- Removes the entity from its currently assigned archetype. Its archetype and entitiesIndex properties should should be cleared/changed after calling this.
--- Returns true if the current operation should be cancelled because the entity is being deleted
local function World_removeEntityFromCurrentArchetype(self, e)
	local archetype = e.archetype
	if archetype == deletingArchetype then return true end -- do not perform this operation
	Archetype_removeEntity(archetype, e)
	if e.count == 0 and ecs.AutoDeleteEmptyArchetypes and archetype.key ~= "" then -- never delete emptyArchetype
		self.keyToArchetype[archetype.key] = nil
		Archetype_disassociateComponents(archetype)
	end
end

--- Add "C" to e's archetype
--- assumes !e.archetype.HasComponent[C]; does not handle hooks nor value
--- Returns true if 'e' is being deleted
local function World_addComponentToEntityArchetype(self, e, C)
	if World_removeEntityFromCurrentArchetype(self, e) then return true end
	local key, components = Archetype_addGetKey(e.archetype, C)
	local archetype = self.keyToArchetype[key]
	if not archetype then
		local hasComponent = table.clone(e.archetype.HasComponent)
		hasComponent[C] = true
		World_newArchetypeFor(self, e, key, components, hasComponent)
	else
		Archetype_addEntity(archetype, e)
	end
end

--- Remove "C" from e's archetype
--- assumes e.archetype.HasComponent[C]; does not handle hooks nor value
--- Returns true if 'e' is being deleted
local function World_removeComponentFromEntityArchetype(self, e, C)
	if World_removeEntityFromCurrentArchetype(self, e) then return true end
	local key, components = Archetype_removeGetKey(e.archetype, C)
	local archetype = self.keyToArchetype[key]
	if not archetype then
		local hasComponent = table.clone(e.archetype.HasComponent)
		hasComponent[C] = nil
		World_newArchetypeFor(self, e, key, components, hasComponent)
	else
		Archetype_addEntity(archetype, e)
	end
end

function World:Add(e, C)
	local archetype = (e or error("Missing entity argument in World:Add", 2)).archetype or error("Argument #1 is not an entity or was already deleted", 2)
	if archetype.HasComponent[C] then return end -- already added
	-- Archetype
	World_addComponentToEntityArchetype(self, e, validateComponent(C))
	-- Hooks
	local onAdd = C.OnAdd
	if onAdd then onAdd(e) end
end
function World:Has(e, C)
	return (e or error("Missing entity argument in World:Has", 2)).archetype.HasComponent[C] == true
end
function World:Get(e, C)
	return e[C]
end

--- Combination of World:Add and associating a value between the entity and component
function World:Set(e, C, value)
	local archetype = (e or error("Missing entity argument in World:Set", 2)).archetype or error("Argument #1 is not an entity or was already deleted", 2)
	local onAdd
	if not archetype.HasComponent[C] then
		World_addComponentToEntityArchetype(self, e, validateComponent(C))
		onAdd = C.OnAdd
	end
	-- Update value
	local prev = e[C]
	e[C] = value
	-- Hooks
	if onAdd then onAdd(e, value) end
	local onChange = C.OnChange
	if onChange and value ~= prev then onChange(e, value, prev) end
end

--- Removes a component from the entity
--- Does nothing if the entity doesn't have the component
function World:Remove(e, C)
	local archetype = (e or error("Missing entity argument in World:Set", 2)).archetype or error("Argument #1 is not an entity or was already deleted", 2)
	if not archetype.HasComponent[C or error("Missing component argument in World:Remove", 2)] then return end -- already removed
	World_removeComponentFromEntityArchetype(self, e, C)
	-- Update value
	local prevValue = e[C]
	e[C] = nil
	-- Hooks
	local onChange = C.OnChange
	if onChange and prevValue ~= nil then onChange(e, nil, prevValue) end
	local onRemove = C.OnRemove
	if onRemove then onRemove(e, prevValue) end
end

--- Deletes all data from the entity, removes the entity from the world, and - treating `e` like a component - removes any data associated with `e` from all other entities.
--- Of course, if you have references to entities in any of your data, this cannot be deleted automatically - use OnDelete hooks for such components.
function World:Delete(e)
	local archetype = (e or error("Missing entity argument in World:Delete", 2)).archetype
	if not archetype then return end -- already deleted
	-- Remove everything from 'e'
	-- Note: if this next line returns, we're already deleting 'e'
	if World_removeEntityFromCurrentArchetype(self, e) then return end -- doesn't clear e.archetype
	local components = e.archetype.HasComponent
	e.archetype = deletingArchetype
	for C in components do
		if C.IsFlag then
			local onRemove = C.OnRemove
			local onDelete = C.OnDelete
			if onRemove then onRemove(e) end
			if onDelete then onDelete(e) end
		else
			-- Update value
			local prevValue = e[C]
			e[C] = nil
			-- Hooks
			local onChange = prevValue ~= nil and C.OnChange
			local onRemove = C.OnRemove
			local onDelete = C.OnDelete
			if onChange then onChange(e, nil, prevValue) end
			if onRemove then onRemove(e, prevValue) end
			if onDelete then onDelete(e, prevValue) end
		end
	end

	-- Remove 'e' from everything
	local onChange = e.OnChange
	local onRemove = e.OnRemove
	local onDelete = e.OnDelete
	for e2 in self:Query(e) do
		World_removeComponentFromEntityArchetype(self, e2, e)
		-- Update value
		local prevValue = e2[e]
		e2[e] = nil
		-- Hooks
		if onChange and prevValue ~= nil then onChange(e2, nil, prevValue) end
		if onRemove then onRemove(e2, prevValue) end
		if onDelete then onDelete(e2, prevValue) end
	end

	self.idToEntity[e.Id] = nil
	e.archetype = nil
end

--- Returns true while the world is deleting 'e'.
function World:IsDeleting(e)
	local archetype = (e or error("Missing entity argument in World:IsDeleting", 2)).archetype
	return archetype == deletingArchetype
end

--- Remove empty archetypes (good for memory and query performance, but at the cost of having to create them again later, if needed).
function World:Cleanup()
	if ecs.AutoDeleteEmptyArchetypes then return end
	local keyToArchetype = self.keyToArchetype
	for key, archetype in keyToArchetype do
		if archetype.count == 0 and key ~= "" then
			keyToArchetype[key] = nil
		end
	end
end

local Query = {}
Query.__index = Query
local function returnSelf(self) return self end
local function doNothing() end
local emptyQuery = table.freeze(setmetatable({
	With = returnSelf,
	Without = returnSelf,
	Custom = returnSelf,
	-- archetypes = emptyTable,
	-- components = emptyTable,
}, {
	__iter = function() return doNothing end
}))
function Query:__iter()
	-- Initialize
	local archetypes = self.archetypes
	local archetypeI = 0
	local archetype
	local entities = emptyTable
	-- Cache number of entities in each archetype so that we don't iterate multiple times over moved/added entities
	local i
	local entityCounts = table.create(#archetypes)
	for i, archetype in archetypes do
		entityCounts[i] = archetype.count
	end
	-- local function advance()
	-- 	local e = entities[i]
	-- 	while not e do
	-- 		archetypeI += 1
	-- 		archetype = archetypes[archetypeI]
	-- 		if not archetype then return end
	-- 		entities = archetype.entities
	-- 		i = entityCounts[archetypeI] -- use cached count (see above)
	-- 		e = entities[i]
	-- 	end
	-- 	i -= 1
	-- 	return e
	-- end
	local A, B, C, D, E = unpack(self.components)
	if not B then
		-- return function()
		-- 	local e = advance()
		-- 	if not e then return end
		-- 	return e, e[A]
		-- end
		return function()
			local e = entities[i]
			while not e do
				archetypeI += 1
				archetype = archetypes[archetypeI]
				if not archetype then return end
				entities = archetype.entities
				i = entityCounts[archetypeI] -- use cached count (see above)
				e = entities[i]
			end
			i -= 1
			return e, e[A]
		end
	elseif not C then
		return function()
			local e = entities[i]
			while not e do
				archetypeI += 1
				archetype = archetypes[archetypeI]
				if not archetype then return end
				entities = archetype.entities
				i = entityCounts[archetypeI] -- use cached count (see above)
				e = entities[i]
			end
			i -= 1
			return e, e[A], e[B]
		end
	elseif not D then
		return function()
			local e = entities[i]
			while not e do
				archetypeI += 1
				archetype = archetypes[archetypeI]
				if not archetype then return end
				entities = archetype.entities
				i = entityCounts[archetypeI] -- use cached count (see above)
				e = entities[i]
			end
			i -= 1
			return e, e[A], e[B], e[C]
		end
	elseif not E then
		return function()
			local e = entities[i]
			while not e do
				archetypeI += 1
				archetype = archetypes[archetypeI]
				if not archetype then return end
				entities = archetype.entities
				i = entityCounts[archetypeI] -- use cached count (see above)
				e = entities[i]
			end
			i -= 1
			return e, e[A], e[B], e[C], e[D]
		end
	else
		return function()
			local e = entities[i]
			while not e do
				archetypeI += 1
				archetype = archetypes[archetypeI]
				if not archetype then return end
				entities = archetype.entities
				i = entityCounts[archetypeI] -- use cached count (see above)
				e = entities[i]
			end
			i -= 1
			return e, e[A], e[B], e[C], e[D], e[E]
		end
	end
end
function Query:With(...)
	-- Filter archetypes (each must have the specified components)
	local archetypes = self.archetypes
	local count = #archetypes
	for argI = 1, select("#", ...) do
		local C = select(argI, ...)
		-- if any archetype doesn't have C, remove it
		for i = count, 1, -1 do
			if archetypes[i].HasComponent[C] then continue end
			if i == count then
				archetypes[i] = nil
			else
				archetypes[i] = archetypes[count]
				archetypes[count] = nil
			end
			count -= 1
			if count == 0 then return emptyQuery end
		end
	end
	return self
end
function Query:Without(...)
	-- Filter archetypes (each must *not* have the specified components)
	local archetypes = self.archetypes
	local count = #archetypes
	for argI = 1, select("#", ...) do
		local C = select(argI, ...)
		-- if any archetype doesn't have C, remove it
		for i = count, 1, -1 do
			if not archetypes[i].HasComponent[C] then continue end
			if i == count then
				archetypes[i] = nil
			else
				archetypes[i] = archetypes[count]
				archetypes[count] = nil
			end
			count -= 1
			if count == 0 then return emptyQuery end
		end
	end
	return self
end
--- Filters out any archetypes for which `keep(archetype)` returns false
function Query:Custom(keep)
	local archetypes = self.archetypes
	-- local has = archetypes.HasComponent
	local count = #archetypes
	for i = count, 1, -1 do
		if keep(archetypes[i].HasComponent) then continue end
		if i == count then
			archetypes[i] = nil
		else
			archetypes[i] = archetypes[count]
			archetypes[count] = nil
		end
		count -= 1
		if count == 0 then return emptyQuery end
	end
	return self
end

function World:Query(...)
	local components = {...}
	if not components[1] then error("Must specify at least one component to iterate over", 2) end
	if components[6] then error("May only iterate over 5 component values at once", 2) end
	-- find the component with the least number of archetypes
	local best
	local smallest = math.huge
	for i, C in components do
		local num = C.archetypesCount
		if num == 0 then
			return emptyQuery
		elseif num < smallest then
			smallest = num
			best = C
		end
	end
	local archetypes = {}
	local numArchetypes = 0
	-- Now filter each archetype in 'best': only accept archetypes that have all required components
	for _, archetype in best.archetypes do
		if archetype.count == 0 then continue end
		local invalid = false
		for i, C in components do
			if not archetype.HasComponent[C] then
				invalid = true
				break
			end
		end
		if invalid then continue end
		numArchetypes += 1
		archetypes[numArchetypes] = archetype
	end
	if numArchetypes == 0 then return emptyQuery end
	return setmetatable({
		archetypes = archetypes,
		components = components,
	}, Query)
end

local function override(t, key, fn)
	local base = t[key]
	if base then
		t[key] = function(...)
			base(...)
			fn(...)
		end
	else
		t[key] = fn
	end
end
function World:OnAdd(C, onAdd)
	override(C, "OnAdd", onAdd)
end
function World:OnChange(C, onChange)
	override(C, "OnChange", onChange)
end
function World:OnNewValue(C, onNewValue)
	override(C, "OnChange", function(e, value, prev)
		if value then
			onNewValue(e, value, prev)
		end
	end)
end
function World:OnRemove(C, onRemove)
	override(C, "OnRemove", onRemove)
end
function World:OnDelete(C, onDelete)
	override(C, "OnDelete", onDelete)
end

return ecs