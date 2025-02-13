--!native
local ecs = {
	-- Global config
	--- Defaults to false. Might make sense to set to `true` to save on memory if you have numerous combinations of components/flags that are often only used briefly. (For example, a scenario where you have 20 flags and an entity may randomly have none or all would create 2^20 archetypes.) Alternatively, occasionally call world:Clean(). Note that setting this to true in regular usage may harm performance if you are regularly emptying out and recreating archetypes.
	AutoDeleteEmptyArchetypes = false,
	--- Set to false to disable entities from having their Name field be set to their Id field by default.
	EntityNameDefault = true,
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
	archetypes: List<Archetype> that the entity (as a component) is in
	archetypesCount: #archetypes
}
Components can be used interchangeably with entities (they are identical internally).
Archetype = {
	entities = List<Entity>
	count (of entities)
	components = List<tostring(Component.Id)>
	HasComponent = Set<Component>
	key = table.concat(tostring(Component.Id), "_")
	-- The following cache adjacent archetypes
	addComponent = {[Component] = archetype}
	removeComponent = {[Component] = archetype}
}
]]

local protectedArchetypes = {
	-- Even with AutoDelete, these commonly used archetypes will never be deleted
	[""] = true,
	["0"] = true,
	["1"] = true,
}
ecs._protectedArchetypes = protectedArchetypes -- for testing only

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
			archetypes[i], archetypes[count] = archetypes[count], nil
		end
		C.archetypesCount = count - 1
	end
end
local function Archetype_disassociateShortcuts(archetype)
	for C, other in archetype.addComponent do
		other.removeComponent[C] = nil
	end
	for C, other in archetype.removeComponent do
		other.addComponent[C] = nil
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
local function World_newEntityNoArchetype(self, name)
	local nextId = self.nextId
	self.nextId = nextId + 1
	local e = {
		Id = nextId,
		Name = name or if ecs.EntityNameDefault then tostring(nextId) else nil,
		archetypes = {}, -- list of archetypes that the entity (as a component) is in
		archetypesCount = 0,
	}
	self.idToEntity[nextId] = e
	return e
end
local function World_newEntity(self, name)
	local e = World_newEntityNoArchetype(self, name)
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
		addComponent = {},
		removeComponent = {},
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
		addComponent = {},
		removeComponent = {},
	}
	self.keyToArchetype[key] = archetype
	e.archetype = archetype
	e.entitiesIndex = 1
	Archetype_associateComponents(archetype)
	return archetype
end

--- Removes the entity from its currently assigned archetype. Its archetype and entitiesIndex properties should be cleared/changed after calling this.
--- Returns true if the current operation should be cancelled because the entity is being deleted
--- Returns false if the archetype is deleted
local function World_removeEntityFromCurrentArchetype(self, e)
	local archetype = e.archetype
	if archetype == deletingArchetype then return true end -- do not perform this operation
	Archetype_removeEntity(archetype, e)
	if archetype.count == 0 and ecs.AutoDeleteEmptyArchetypes and not protectedArchetypes[archetype.key] then
		-- World_deleteArchetype:
		self.keyToArchetype[archetype.key] = nil
		Archetype_disassociateComponents(archetype)
		Archetype_disassociateShortcuts(archetype)
		return false
	end
end

--- Add "C" to e's archetype
--- assumes !e.archetype.HasComponent[C]; does not handle hooks nor value
--- Returns true if 'e' is being deleted
local function World_addComponentToEntityArchetype(self, e, C)
	local result = World_removeEntityFromCurrentArchetype(self, e)
	if result then return true end
	local prevArchetype = e.archetype
	-- Try shortcut
	local archetype = prevArchetype.addComponent[C]
	if archetype then
		Archetype_addEntity(archetype, e)
		return
	end
	local key, components = Archetype_addGetKey(prevArchetype, C)
	archetype = self.keyToArchetype[key]
	if archetype then
		Archetype_addEntity(archetype, e)
	else
		local hasComponent = table.clone(prevArchetype.HasComponent)
		hasComponent[C] = true
		archetype = World_newArchetypeFor(self, e, key, components, hasComponent)
	end
	if result ~= false then -- Setup shortcut
		prevArchetype.addComponent[C] = archetype
		archetype.removeComponent[C] = prevArchetype
	end
end

--- Remove "C" from e's archetype
--- assumes e.archetype.HasComponent[C]; does not handle hooks nor value
--- Returns true if 'e' is being deleted
local function World_removeComponentFromEntityArchetype(self, e, C)
	local result = World_removeEntityFromCurrentArchetype(self, e)
	if result then return true end
	local prevArchetype = e.archetype
	-- Try shortcut
	local archetype = prevArchetype.removeComponent[C]
	if archetype then
		Archetype_addEntity(archetype, e)
		return
	end
	local key, components = Archetype_removeGetKey(prevArchetype, C)
	archetype = self.keyToArchetype[key]
	if archetype then
		Archetype_addEntity(archetype, e)
	else
		local hasComponent = table.clone(prevArchetype.HasComponent)
		hasComponent[C] = nil
		archetype = World_newArchetypeFor(self, e, key, components, hasComponent)
	end
	if result ~= false then -- Setup shortcut
		prevArchetype.removeComponent[C] = archetype
		archetype.addComponent[C] = prevArchetype
	end
end

--- Efficiently create an entity with tags/components.
--- initFn : function(add, set) is expected to add any flags and set any components that the entity should have.
--- Hooks will be invoked all at once *after* the entity has all the specified flags and components.
--- This method can be vastly more efficient if AutoDeleteEmptyArchetypes is on; otherwise it still runs in 75% - 90% the time of using `Entity`, depending on the number of components/flags you add.)
function World:CreateEntity(name, initFn)
	if not initFn then initFn = name; name = nil end -- shift arguments

	local e = World_newEntityNoArchetype(self, name)
	local EntityFlag = self.EntityFlag
	local components = {tostring(EntityFlag.Id)}
	local hasComponent = {[EntityFlag] = true}
	local componentList = {EntityFlag}
	local n = 1
	local function add(Flag)
		if hasComponent[Flag] then return end
		hasComponent[validateComponent(Flag)] = true
		local s = tostring(Flag.Id)
		table.insert(components, findInsertIndex(components, s), s)
		n += 1
		componentList[n] = Flag
	end
	local function set(C, value)
		e[C] = value
		if hasComponent[C] then return end
		hasComponent[validateComponent(C)] = true
		local s = tostring(C.Id)
		table.insert(components, findInsertIndex(components, s), s)
		n += 1
		componentList[n] = C
	end
	initFn(add, set)

	-- Add to correct archetype
	local key = table.concat(components, "_")
	local archetype = self.keyToArchetype[key]
	if not archetype then
		World_newArchetypeFor(self, e, key, components, hasComponent)
	else
		Archetype_addEntity(archetype, e)
	end

	-- Run hooks
	for _, C in componentList do
		local value = e[C]
		local onAdd = C.OnAdd
		if onAdd then onAdd(e, value) end
		local onChange = C.OnChange
		if onChange and value ~= nil then onChange(e, value) end
	end
	return e
end
--- Same as CreateEntity for existing entities.
--- adjustFn : function(add, set, remove)
--- Note: For hooks, only the archetype from the starting state into the final state will be run. Thus, removing a flag and then adding it again (in the same AdjustEntity call) will not trigger any hooks.
--- Performance-wise, this function is only superior when you have more than 4 changes to make at a time.
--- Returns the entity.
function World:AdjustEntity(e, adjustFn)
	-- TODO If world has archetype transitions defined, we can use that here and we may not need to clone hasComponent if we can just trace the archetype as changes are made
	local archetype = (e or error("Missing entity argument in World:AdjustEntity", 2)).archetype or error("Argument #1 is not an entity or was already deleted", 2)
	if archetype == deletingArchetype then return end
	local components = table.clone(archetype.components)
	local hadComponent = archetype.HasComponent
	local hasComponent = table.clone(hadComponent)
	local prevValue = {} -- [C] = value, using the 'prevValue' table itself as a nil value placeholder
	local function add(Flag)
		if hasComponent[Flag] then return end
		if prevValue[Flag] == nil then
			validateComponent(Flag)
			prevValue[Flag] = prevValue
		end
		hasComponent[Flag] = true
	end
	local function set(C, value)
		local v = e[C]
		if v == value then return end -- no change
		if prevValue[C] == nil then
			validateComponent(C)
			prevValue[C] = if v == nil then prevValue else e[C]
		end
		e[C] = value
		hasComponent[C] = true
	end
	local function remove(C)
		if not hasComponent[C] then return end
		if prevValue[C] == nil then
			validateComponent(C)
			local v = e[C]
			prevValue[C] = if v == nil then prevValue else e[C]
		end
		hasComponent[C] = nil
	end
	adjustFn(add, set, remove)

	for C in prevValue do
		if hasComponent[C] then
			if hadComponent[C] then
				-- check if value is the same as it was before
				local prev = prevValue[C]
				if e[C] == (if prev == prevValue then nil else prev) then
					prevValue[C] = nil
				end
			else
				local s = tostring(C.Id)
				table.insert(components, findInsertIndex(components, s), s)
			end
		elseif hadComponent[C] then
			local s = tostring(C.Id)
			table.remove(components, table.find(components, s))
		else -- didn't have component and still don't
			prevValue[C] = nil
		end
	end

	if not next(prevValue) then return e end

	-- Remove from previous archetype
	World_removeEntityFromCurrentArchetype(self, e)

	-- Add to correct archetype
	local key = table.concat(components, "_")
	local archetype = self.keyToArchetype[key]
	if not archetype then
		World_newArchetypeFor(self, e, key, components, hasComponent)
	else
		Archetype_addEntity(archetype, e)
	end

	-- Run hooks
	for C, prev in prevValue do
		if C.IsFlag then
			if hasComponent[C] then
				local onAdd = C.OnAdd
				if onAdd then onAdd(e) end
			else
				local onRemove = C.OnRemove
				if onRemove then onRemove(e) end
			end
		else
			local value = e[C]
			if prev == prevValue then prev = nil end
			if hasComponent[C] and not hadComponent[C] then
				local onAdd = C.OnAdd
				if onAdd then onAdd(e, value) end
			end
			if value ~= prev then
				local onChange = C.OnChange
				if onChange then onChange(e, value, prev) end
			end
			if not hasComponent[C] and hadComponent[C] then
				local onRemove = C.OnRemove
				if onRemove then onRemove(e, prev) end
			end
		end
	end
	return e
end
function World:Add(e, C)
	local archetype = (e or error("Missing entity argument in World:Add", 2)).archetype or error("Argument #1 is not an entity or was already deleted", 2)
	if archetype.HasComponent[C] then return end -- already added
	-- Archetype
	if World_addComponentToEntityArchetype(self, e, validateComponent(C)) then return end -- entity being deleted
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
	local prev = (e or error("Missing entity argument in World:Set", 2))[C]
	if prev == value then return end -- already have this component with the specified value
	local archetype = e.archetype or error("Argument #1 is not an entity or was already deleted", 2)
	local onAdd
	if not archetype.HasComponent[C] then
		if World_addComponentToEntityArchetype(self, e, validateComponent(C)) then return end -- entity being deleted
		onAdd = C.OnAdd
	end
	-- Update value
	e[C] = value
	-- Hooks
	if onAdd then onAdd(e, value) end
	local onChange = C.OnChange
	if onChange then onChange(e, value, prev) end
end

--- Removes a component from the entity
--- Does nothing if the entity doesn't have the component
function World:Remove(e, C)
	local archetype = (e or error("Missing entity argument in World:Set", 2)).archetype or error("Argument #1 is not an entity or was already deleted", 2)
	if not archetype.HasComponent[C or error("Missing component argument in World:Remove", 2)] then return end -- already removed
	if World_removeComponentFromEntityArchetype(self, e, C) then return end -- entity being deleted
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
--- Note that archetypes referencing `e` will be deleted regardless of `ecs.AutoDeleteEmptyArchetypes`
function World:Delete(e)
	local archetype = (e or error("Missing entity argument in World:Delete", 2)).archetype
	if not archetype then return end -- already deleted
	-- Remove everything from 'e'
	-- Note: if this next line returns, we're already deleting 'e'
	if World_removeEntityFromCurrentArchetype(self, e) then return end -- doesn't clear e.archetype
	local components = archetype.HasComponent
	e.archetype = deletingArchetype -- in addition to preventing us from trying to delete 'e' a 2nd time, prevents components from being added to/removed from it
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
	-- Since we're deleting 'e', we specify 'true' for the _deleting parameter of ClearComponent, since any archetypes that continue to reference C can never be re-used.
	self:ClearComponent(e, true)

	self.idToEntity[e.Id] = nil
	e.archetype = nil
end

--- Returns true while the world is deleting 'e'.
function World:IsDeleting(e)
	return deletingArchetype == (e or error("Missing entity argument in World:IsDeleting", 2)).archetype
end

--- Returns true if 'e' has been deleted.
--- Ideally you shouldn't need this, aside from its use in debugging. Typically, if you have a reference to an entity (that could have been deleted) in a component, you should use an OnDelete hook to clean it up.
function World:IsDeleted(e)
	return not (e or error("Missing entity argument in World:IsDeleted", 2)).archetype
end

local spareTable = {}
--- Removes `C` (and clears any data associated with it) from all other entities.
--- Unlike Delete, `C` itself is not modified and remains usable after the operation.
--- Useful to clear temporary flags/data efficiently; should be used instead of `for e in world:Query(C) do world:Remove(e, C) end`
function World:ClearComponent(C, _deleting)
	-- Remove the entire archetype (for each archetype C is in) rather than removing each entity individually
	local numArchetypesCount = (C or error("Missing Component argument in World:ClearComponent", 2)).archetypesCount
	if numArchetypesCount == 0 then return end
	local onChange = C.OnChange
	local onRemove = C.OnRemove
	local onDelete = C.OnDelete
	local keyToArchetype = self.keyToArchetype
	local autoDelete = _deleting or ecs.AutoDeleteEmptyArchetypes
	local entitiesRemoved -- a list of List<entity> to run hooks on after the loop is done (and to delete values for)
	if onChange or onRemove or onDelete then
		entitiesRemoved = spareTable or {}
		spareTable = nil
	end
	local archetypes = C.archetypes
	for i = numArchetypesCount, 1, -1 do -- must iterate in reverse order due to Archetype_disassociateComponents
		local archetype = archetypes[i]
		local archCount = archetype.count
		local entities
		if archetype.count > 0 then
			entities = archetype.entities
			if entitiesRemoved then
				table.insert(entitiesRemoved, entities)
			elseif not C.IsFlag then
				-- Remove all values from entities (normally we do that in the hook section below, but no hooks)
				for _, entity in entities do
					entity[C] = nil
				end
			end
		end
		-- We want to remove C from archetype
		local targetArchetype = archetype.removeComponent[C]
		local key, components
		if not targetArchetype then
			key, components = Archetype_removeGetKey(archetype, C)
			targetArchetype = keyToArchetype[key]
		end
		if targetArchetype then
			if archCount > 0 then
				if targetArchetype.count == 0 then
					-- Switch entities & count around
					targetArchetype.entities, archetype.entities = entities, targetArchetype.entities
					targetArchetype.count = archetype.count -- archetype.count is set to 0 below (if it isn't being deleted)
					for i, e in entities do
						e.archetype = targetArchetype
						-- entitiesIndex stays the same
					end
					-- in one of the cleanup cases below, entities must refer to the empty archetype's entities
					entities = archetype.entities
				else
					-- Copy entities into targetArchetype
					local targetEntities = targetArchetype.entities
					local numEntities = #entities
					local numTarget = #targetEntities
					table.move(entities, 1, numEntities, numTarget + 1, targetEntities)
					targetArchetype.count += numEntities
					for i, e in entities do
						e.archetype = targetArchetype
						e.entitiesIndex = numTarget + i
					end
					-- Don't need to table.clear(entities) as this is handled below: archetype is either deleted or cleared of entities
				end
			end -- else no entities to move anywhere
			if autoDelete then
				-- World_deleteArchetype:
				keyToArchetype[archetype.key] = nil
				Archetype_disassociateComponents(archetype)
				Archetype_disassociateShortcuts(archetype)
			elseif archCount > 0 then
				archetype.count = 0
				if entitiesRemoved then
					archetype.entities = {} -- cannot use table.clear since table is needed in entitiesRemoved
				else
					table.clear(entities)
				end
			end
		else
			-- Convert archetype into target
			-- Note: we won't need to disassociateComponents (nor associate them) since it'll be the same archetype, with the exception of the component-to-be-cleared
			-- Must update components, HasComponent, and key
			keyToArchetype[archetype.key] = nil
			keyToArchetype[key] = archetype
			archetype.components = components
			archetype.HasComponent[C] = nil
			archetype.key = key
			if not autoDelete then -- the "if autoDelete" case handled below with table.clear(C.archetypes)
				-- (copied from disassociateComponents and adjusted to use local variables), remove archetype from C:
				local i = table.find(archetypes, archetype)
				if i == numArchetypesCount then
					archetypes[i] = nil
				else
					archetypes[i], archetypes[numArchetypesCount] = archetypes[numArchetypesCount], nil
				end
				numArchetypesCount -= 1
				C.archetypesCount = numArchetypesCount
			end
			-- Clear shortcuts (they're all invalid now):
			Archetype_disassociateShortcuts(archetype)
			table.clear(archetype.addComponent)
			table.clear(archetype.removeComponent)
		end
	end
	if autoDelete --[[and not _deleting]] then -- TODO UNCERTAIN if we're deleting C, we don't need its archetypes table to be up-to-date
		table.clear(C.archetypes)
		C.archetypesCount = 0
	end -- else, in the case of targetArchetype above, there will be valid archetypes that C should still refer to (though they'll have no entities at the moment)
	if entitiesRemoved then
		if C.IsFlag then
			for _, list in entitiesRemoved do
				for _, e in list do
					if onRemove then onRemove(e) end
					if onDelete then onDelete(e) end
				end
			end
		else
			for _, list in entitiesRemoved do
				for _, e in list do
					local prevValue = e[C]
					e[C] = nil
					if onChange then onChange(e, nil, prevValue) end
					if onRemove then onRemove(e, prevValue) end
					if onDelete then onDelete(e, prevValue) end
				end
			end
		end
		if not spareTable then
			table.clear(entitiesRemoved)
			spareTable = entitiesRemoved
		end
	end
	--[[Original algorithm (which takes 2x longer in a small case (2 entities in a few archetypes) and 20x longer in larger cases (200 entities in those same archetypes):
	-- Remove 'C' from everything
	for e2 in self:Query(C) do
		World_removeComponentFromEntityArchetype(self, e2, C)
		-- Update value
		local prevValue = e2[C]
		e2[C] = nil
		-- Hooks
		if onChange and prevValue ~= nil then onChange(e2, nil, prevValue) end
		if onRemove then onRemove(e2, prevValue) end
		if onDelete then onDelete(e2, prevValue) end
	end
	]]
end

local noArchetype = {
	HasComponent = emptyTable
}

--- Iterates over all components that an entity has.
--- Recommended mainly for debugging and entity serialization.
--- For example: `for C in world:IterComponents(e) do`
function World:IterComponents(e)
	return (e.archetype or noArchetype).HasComponent
end

--- Remove empty archetypes (good for memory and query performance, but at the cost of having to create them again later, if needed).
--- Not needed if Config.AutoDeleteEmptyArchetypes is true.
--- Note that archetypes with deleted components are automatically cleaned up in `Delete`.
function World:Cleanup()
	if ecs.AutoDeleteEmptyArchetypes then return end
	local keyToArchetype = self.keyToArchetype
	for key, archetype in keyToArchetype do
		if archetype.count == 0 and not protectedArchetypes[key] then
			keyToArchetype[key] = nil
		end
	end
end

local Query = {}
Query.__index = Query
local function Query_new(with)
	return setmetatable({
		numComponents = #with,
		with = with, -- List<Component>
		-- without = nil or List<Component>
		-- custom = nil or List<fn>
	}, Query)
end
local function extend(list, ...)
	local n = #list
	for i = 1, select("#", ...) do
		list[n + i] = select(i, ...)
	end
end
--- Require that entities have the specified components. Note that the value of these components will not be returned in the iteration.
function Query:With(...)
	extend(self.with, ...)
	return self
end
--- Require that entities *not* have the specified components.
function Query:Without(...)
	local without = self.without
	if without then
		extend(without, ...)
	else
		self.without = {...}
	end
	return self
end
--- Filters out any archetypes (sets of entities) for which `keep(has)` returns false
--- `has` is the set of components that the archetype has. (Do not modify this value!)
--- For example, if you wanted to iterate over entities that have component A or B:
--- `query:Custom(function(has) return has[A] or has[B] end)`
function Query:Custom(keep)
	local custom = self.custom
	if custom then
		table.insert(custom, keep)
	else
		self.custom = {keep}
	end
	return self
end
local function Query_getArchetypes(self) -- returns count, archetypes
	local with = self.with
	local without = self.without
	local custom = self.custom
	local best
	local smallest = math.huge
	for i, C in with do
		local num = C.archetypesCount
		if num == 0 then
			return 0, emptyTable
		elseif num < smallest then
			smallest = num
			best = C
		end
	end
	local archetypes = table.create(smallest)
	local count = 0 -- # of archetypes
	-- Now add each potential archetype if it meets all requirements
	for _, archetype in best.archetypes do
		if archetype.count == 0 then continue end
		local invalid = false
		local has = archetype.HasComponent
		for _, C in with do
			if not has[C] then
				invalid = true
				break
			end
		end
		if invalid then continue end
		if without then
			for _, C in without do
				if has[C] then
					invalid = true
					break
				end
			end
			if invalid then continue end
		end
		if custom then
			for _, keep in custom do
				if not keep(has) then
					invalid = true
					break
				end
			end
			if invalid then continue end
		end
		count += 1
		archetypes[count] = archetype
	end
	return count, archetypes
end

--- Counts how many entities are in the query. (Faster than iterating over them yourself.)
function Query:Count()
	local num, archetypes = Query_getArchetypes(self)
	if num == 0 then return 0 end
	local count = 0
	for i, archetype in archetypes do
		count += archetype.count
	end
	return count
end
local function doNothing() end
function Query:__iter()
	local count, archetypes = Query_getArchetypes(self)
	if count == 0 then return doNothing end

	-- Initialize iteration
	local archetypeI = 0
	local archetype
	local entities = emptyTable
	-- Cache number of entities in each archetype so that we don't iterate multiple times over moved/added entities
	local i
	local entityCounts = table.create(count)
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
	local A, B, C, D, E = unpack(self.with, 1, self.numComponents)
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

--- Query which components have all the specified components for iteration. You can further modify the query using :With(...), :Without(...), or :Custom(keep) -- see Query function documentation for more.
--- Iterate over a query using `for entity, health in world:Query(Health) do`
--- During iteration, you are allowed to modify the current entity (by adding/removing/changing values or even deleting the entity), but not others (such as by running a query inside of a query).
--- If a system saves a query, you can iterate over it repeatedly (though this is a tiny performance benefit as most of the work is done when you start iteration).
function World:Query(...)
	return Query_new({...})
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
		if value ~= nil then
			onNewValue(e, value, prev)
		end
	end)
end
function World:OnRemove(C, onRemove)
	override(C, "OnRemove", onRemove)
end
function World:OnAddRemove(C, onAddRemove)
	override(C, "OnAdd", function(e)
		onAddRemove(e, true)
	end)
	override(C, "OnRemove", function(e)
		onAddRemove(e, false)
	end)
end
function World:OnDelete(C, onDelete)
	override(C, "OnDelete", onDelete)
end

-- Typescript conveniences:
function World.Readonly(C) return C end
World.Protected = World.Readonly

return ecs
