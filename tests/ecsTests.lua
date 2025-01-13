return function(tests, t)


local ecs = require(game.ReplicatedStorage.ecs)
local new = ecs.World.new

local function verifyIntegrity(w)
	for id, e in w.idToEntity do
		t.truthy(e.archetype)
		t.equals(e.archetype.entities[e.entitiesIndex], e)
	end
	for _, arch in w.keyToArchetype do
		t.equals(arch.count, #arch.entities)
	end
end

function tests.AddRemoveFlag()
	local w = new()
	local e = w:Entity("e")
	local A = w:Component("A")
	w:Add(e, A)
	t.equals(w:Get(e, A), nil)
	t.equals(w:Has(e, A), true)
	w:Remove(e, A)
	t.falsy(w:Has(e, A))
	verifyIntegrity(w)
end
function tests.AddRemoveData1()
	local w = new()
	local e = w:Entity()
	local A = w:Component()
	w:Set(e, A, "a")
	t.equals(w:Get(e, A), "a")
	t.equals(w:Has(e, A), true)
	w:Remove(e, A)
	t.equals(w:Get(e, A), nil)
	verifyIntegrity(w)
end
function tests.AddData2()
	local w = new()
	local A = w:Component()
	local B = w:Component()
	local e1 = w:Entity()
	local e2 = w:Entity()
	w:Set(e1, A, "e1a")
	w:Set(e2, B, "e2b")
	w:Set(e2, A, "e2a")
	t.equals(w:Get(e1, A), "e1a")
	t.equals(w:Get(e2, A), "e2a")
	t.equals(w:Get(e2, B), "e2b")
	verifyIntegrity(w)
end
function tests.CreateEntity()
	local w = new()
	local A = w:Component()
	local B = w:Component()
	local C = w:Flag()
	local e1 = w:CreateEntity(function(add, set)
		set(A, "e1a")
		add(C)
	end)
	local e2 = w:CreateEntity(function(add, set)
		set(B, "e2b")
		set(A, "e2a")
	end)
	t.equals(w:Get(e1, A), "e1a")
	t.truthy(w:Has(e1, C), "e1 C")
	t.equals(w:Get(e2, A), "e2a")
	t.equals(w:Get(e2, B), "e2b")
	verifyIntegrity(w)
end

local function setupAB2()
	local w = new()
	local A = w:Component("A")
	local B = w:Component("B")
	local e1 = w:Entity("e1")
	w:Add(e1, A)
	local e2 = w:Entity("e2")
	w:Add(e2, A)
	w:Add(e2, B)
	return {
		w = w,
		A = A,
		B = B,
		e1 = e1,
		e2 = e2,
	}
end

function tests.Query()
	local x = setupAB2()
	local w = x.w
	local iter = {}
	for e in w:Query(x.A, x.B) do
		if iter[e] then error("already iterated over " + tostring(e)) end
		iter[e] = true
	end
	t.falsy(iter[x.e1])
	t.truthy(iter[x.e2])
	table.clear(iter)
	for e in w:Query(x.A) do
		if iter[e] then error("already iterated over " + tostring(e)) end
		iter[e] = true
	end
	t.truthy(iter[x.e1])
	t.truthy(iter[x.e2])
	verifyIntegrity(w)
end
function tests.QueryWith()
	local x = setupAB2()
	local w = x.w
	local iter = {}
	for e in w:Query(w.EntityFlag):With(x.A, x.B) do
		if iter[e] then error("already iterated over " + tostring(e)) end
		iter[e] = true
	end
	t.falsy(iter[x.e1])
	t.truthy(iter[x.e2])
	table.clear(iter)
	for e in w:Query(w.EntityFlag):With(x.A) do
		if iter[e] then error("already iterated over " + tostring(e)) end
		iter[e] = true
	end
	t.truthy(iter[x.e1])
	t.truthy(iter[x.e2])
	verifyIntegrity(w)
end
function tests.QueryWithout()
	local x = setupAB2()
	local w = x.w
	local iter = {[x.e1] = true}
	for e in w:Query(x.A):Without(x.B) do
		if not iter[e] then error("unexpected entity in iteration " .. tostring(e)) end
		iter[e] = nil
	end
	if next(iter) then error("failed to iterate over anything") end
	for e in w:Query(x.B):Without(x.A) do
		error("unexpected iteration - everything has A")
	end
	verifyIntegrity(w)
end
function tests.QueryCount()
	local w = new()
	local A = w:Flag("A")
	local B = w:Flag("B")
	local C = w:Flag("C")
	w:CreateEntity(function(add) add(A) end)
	for i = 1, 2 do w:CreateEntity(function(add) add(A) add(B) end) end
	for i = 1, 2 do w:CreateEntity(function(add) add(A) add(C) end) end
	w:CreateEntity(function(add) add(B) end)

	t.equals(w:Query(A):Count(), 5)
	t.equals(w:Query(A):Without(B):Count(), 3)
	t.equals(w:Query(B):Count(), 3)
	t.equals(w:Query():With(A, B):Count(), 2)

	verifyIntegrity(w)
end
function tests.IterComponents()
	local w = new()
	local A = w:Flag("A")
	local B = w:Flag("B")
	local iter = {[A] = true, [B] = true}
	for C in w:IterComponents(w:CreateEntity(function(add) add(A) add(B) end)) do
		if not iter[C] then error("unexpected component in iteration " .. tostring(C)) end
		iter[C] = nil
	end
	if next(iter) then error("failed to iterate over all desired components") end
	verifyIntegrity(w)
end
function tests.QueryComplex()
	-- With(A):Without(B):With(C) regardless of D and there are some entities that fit each possibility
	local w = new()
	local A, B, C, D = w:Flag("A"), w:Flag("B"), w:Flag("C"), w:Flag("D")
	local expected = {} -- [entity] = true/nil
	-- add an extra entity in A so that :With(C) will grab the smaller one
	local e = w:Entity("eA")
	w:Add(e, A)
	for a = 1, 2 do
		for b = 1, 2 do
			for c = 1, 2 do
				for d = 1, 2 do
					local e = w:Entity(string.format("e%d,%d,%d,%d", a, b, c, d))
					if a == 2 then w:Add(e, A) end
					if b == 2 then w:Add(e, B) end
					if c == 2 then w:Add(e, C) end
					if d == 2 then w:Add(e, D) end
					expected[e] = a == 2 and b == 1 and c == 2 or nil
				end
			end
		end
	end
	for e in w:Query(A):Without(B):With(C) do
		if not expected[e] then error("unexpected entity in iteration " .. e.Name) end
		expected[e] = nil
	end
	if next(expected) then error("failed to iterate over " .. next(expected).Name) end
	verifyIntegrity(w)
end
function tests.QueryAllEntityOrComponent()
	local w = new()
	local e1 = w:Entity()
	local A = w:Component()
	local found = false
	for e in w:Query(w.EntityFlag) do
		t.equals(e, e1)
		found = true
	end
	t.truthy(found, "found e1 via query ecs.Entity")
	found = false
	for e in w:Query(w.ComponentFlag) do
		if e == A then
			found = true
		elseif e == e1 then
			error("entity found in list of Component")
		end
	end
	t.truthy(found, "found A via query ecs.Component")
	verifyIntegrity(w)
end

local function archetypeToString(archetype)
	local t = {}
	for C in archetype.HasComponent do
		table.insert(t, C.Name or C.Id)
	end
	return table.concat(t, "_")
end
local function verifyNoEmptyArchetype(w, clearedC)
	for key, archetype in w.keyToArchetype do
		if archetype.count == 0 and archetype.key ~= "" then
			error(`Empty archetype {archetypeToString(archetype)} exists after ClearComponent`)
		elseif archetype.HasComponent[clearedC] then
			error(`Archetype {archetypeToString(archetype)} still exists with '{clearedC.Name}'`)
		end
	end
end

function tests.DeleteEntity()
	local w = new()
	local A = w:Component()
	local e = w:Entity()
	w:Set(e, A, 1)
	w:Delete(e)
	t.equals(w:Get(e, A), nil)
	for e in w:Query(A) do
		error("should not iter over deleted entity")
	end
	verifyIntegrity(w)
end
function tests.DeleteComponent()
	ecs.AutoDeleteEmptyArchetypes = true
	local w = new()
	local A = w:Component()
	local B = w:Component()
	local e = w:Entity()
	w:Set(e, A, 1)
	w:Set(e, B, 2)
	w:Delete(A)
	t.equals(w:Get(e, A), nil, "entity should not have data from deleted component")
	t.equals(w:Get(e, B), 2, "entity should not be deleted")
	verifyNoEmptyArchetype(w, A)
	verifyIntegrity(w)
end
tests.ClearComponent = {
	test = function(autoDelete)
		ecs.AutoDeleteEmptyArchetypes = autoDelete
		local w = new()
		local A, B, C = w:Flag("A"), w:Flag("B"), w:Flag("C")
		local expected = {} -- [entity] = set of components expected after operation
		local all = {A, B, C}
		local function make(name, exp, ...) -- exp: expected components after operation
			local set = {}
			for _, C in exp do set[C] = true end
			for n = 1, 2 do
				local e = w:Entity(name .. n)
				expected[e] = set
				for i = 1, select("#", ...) do
					local C = select(i, ...)
					w:Add(e, C)
				end
			end
		end
		make("A", {A}, A) -- must not mangle pre-existing
		make("B", {}, B)
		make("AB", {A}, A, B) -- must merge into pre-existing
		make("BC", {C}, B, C) -- handles case where C is not pre-existing
		w:ClearComponent(B)
		for e, set in expected do
			for C in set do
				t.truthy(w:Has(e, C), e.Name, "should have", C.Name)
			end
			for _, C in all do
				if not set[C] then
					t.falsy(w:Has(e, C), e.Name, "should not have", C.Name)
				end
			end
		end
		if autoDelete then
			verifyNoEmptyArchetype(w, B)
		end
		-- Verify that B doesn't have any archetypes (or at least that they don't have any entities in them) [note: this section caught errors not caught by verifyNoEmptyArchetype]
		for _, archetype in B.archetypes do
			if not archetype.HasComponent[B] then
				error("Archetype no longer has B, but B still has archetype")
			elseif archetype.count > 0 then
				error("B has an archetype with entities in it")
			end
		end
		verifyIntegrity(w)
	end,
	args = {true, false}
}
function tests.ClearComponent2()
	ecs.AutoDeleteEmptyArchetypes = false
	local world = ecs.World.new()
	local C1 = world:Component()
	local C2 = world:Component()
	local es = {}
	for i = 1, 5 do
		local e = world:Entity()
		es[i] = e
		world:Set(e, C1, i)
		world:Set(e, C2, i)
	end
	world:ClearComponent(C1)
	world:ClearComponent(C2)
	for i, e in es do
		world:Delete(e)
	end
	verifyIntegrity(world)
end

function tests.Hooks()
	local w = new()
	local A = w:Component()
	local e1 = w:Entity()
	local added, changed, removed, deleted = 0, 0, 0, 0
	local expectedValue, expectedPrev
	local function update(value)
		expectedPrev = expectedValue
		expectedValue = value
	end
	local function set(value)
		update(value)
		w:Set(e1, A, value)
	end
	w:OnAdd(A, function(e, value)
		added += 1
		t.equals(e, e1)
		t.equals(value, expectedValue)
	end)
	w:OnChange(A, function(e, value, prev)
		changed += 1
		t.equals(e, e1)
		t.equals(value, expectedValue)
		t.equals(prev, expectedPrev)
	end)
	w:OnRemove(A, function(e, prev)
		removed += 1
		t.equals(e, e1)
		t.equals(prev, expectedPrev)
	end)
	w:OnDelete(A, function(e, prev) -- TODO doc that this isn't "when the component A is deleted", but "when an entity is deleted and it has an A"
		deleted += 1
		t.equals(e, e1)
		t.equals(prev, expectedPrev)
	end)
	set(1)
	set(2)
	update(nil)
	w:Set(e1, A, nil)
	t.equals(removed, 0, "component set to nil, don't call OnRemove yet")
	update(nil)
	t.equals(changed, 3)
	w:Delete(e1)
	w:Delete(e1) -- todo: delete this line if this is an error (but point is to make sure OnRemove won't be called multiple times)
	t.equals(added, 1)
	t.equals(removed, 1, "removed should only trigger once, when component removed entirely")
	t.equals(changed, 3, "changed should not trigger for deletion when value was nil")
	t.equals(deleted, 1)
	verifyIntegrity(w)
end
function tests.EditInHooks()
	local w = new()
	local A = w:Component("A")
	local B = w:Component("B")
	local e = w:Entity()
	local onAdd = w:Component("onAdd")
	local onChange = w:Component("onChange")
	local onRemove = w:Component("onRemove")
	local function inc(e, C)
		w:Set(e, C, (w:Get(e, C) or 0) + 1)
	end
	w:OnAdd(A, function(e)
		inc(e, onAdd)
	end)
	w:OnChange(A, function(e)
		inc(e, onChange)
	end)
	w:OnRemove(A, function(e)
		inc(e, onRemove)
	end)
	w:Set(e, A, 3)
	w:Set(e, A, 2)
	w:Remove(e, A)
	t.equals(w:Get(e, onAdd), 1)
	t.equals(w:Get(e, onChange), 3)
	t.equals(w:Get(e, onRemove), 1)
	verifyIntegrity(w)
end
function tests.EditInQuery()
	local w = new()
	local A = w:Component()
	local B = w:Component()
	local shouldSee = {}
	-- most use archetype A_B, but i == 0 will have just A
	for i = 1, 3 do
		local e = w:Entity()
		shouldSee[e] = true
		w:Set(e, A, i)
		if i ~= 1 then
			w:Add(e, B)
		end
	end
	for e, a in w:Query(A) do
		if shouldSee[e] then
			shouldSee[e] = nil
		else
			error("repeated iteration")
		end
		if w:Has(e, B) then
			w:Remove(e, B)
		else
			w:Add(e, B)
		end
	end
	t.falsy(next(shouldSee), "failed to iterate over something")
	verifyIntegrity(w)
end
local function ensureEntityNotInArchetypes(w, e)
	for key, archetype in w.keyToArchetype do
		for _, entity in archetype.entities do
			if entity == e then
				error("Deleted entity " .. (e.Name or e.Id) .. " found in archetype")
			end
		end
	end
end
function tests.RemoveWhileDeleting()
	local w = new()
	local Health = w:Component()
	local IsDead = w:Flag()
	w:OnChange(Health, function(e, h)
		if h and h <= 0 then
			w:Add(e, IsDead)
		else
			w:Remove(e, IsDead)
		end
	end)
	local e = w:Entity()
	w:Set(e, Health, 0)
	w:Delete(e)
	ensureEntityNotInArchetypes(w, e)
	verifyIntegrity(w)
end
function tests.AddWhileDeleting_And_IsDeleting()
	local w = new()
	local Health = w:Component("Health")
	local IsNotAlive = w:Flag("IsNotAlive")
	local isDeleting = false
	w:OnChange(Health, function(e, h)
		t.truthyEquals(w:IsDeleting(e), isDeleting, "IsDeleting")
		if not h or h <= 0 then
			w:Add(e, IsNotAlive)
		else
			w:Remove(e, IsNotAlive)
		end
	end)
	local e = w:Entity("e")
	w:Set(e, Health, 0)
	isDeleting = true
	w:Delete(e)
	t.falsy(w:IsDeleting(e), "IsDeleting after Delete")
	ensureEntityNotInArchetypes(w, e)
	verifyIntegrity(w)
end

tests.errors = {
	setup = setupAB2,
	test = function(x, fn, msg)
		t.errorsWith(msg, fn, x)
	end,
	argsLists = {
		{name="setNoEntity", function(x)
			x.w:Set(nil, x.A, 1)
		end, "Missing"},
		{name="setNoComponent", function(x)
			x.w:Set(x.e1, nil, 1)
		end, "Missing"},
		{name="addNoEntity", function(x)
			x.w:Add(nil, x.A)
		end, "Missing"},
		{name="addNoComponent", function(x)
			x.w:Add(x.e1, nil)
		end, "Missing"},
		{name="removeNoEntity", function(x)
			x.w:Remove(nil, x.A)
		end, "Missing"},
		{name="removeNoComponent", function(x)
			x.w:Remove(x.e1, nil)
		end, "Missing"},
		{name="deleteNoEntity", function(x)
			x.w:Delete(nil)
		end, "Missing"},
		{name="removeDeletedEntity", function(x)
			x.w:Delete(x.e1)
			x.w:Remove(x.e1)
		end, "deleted"}
	}
}


end -- function(tests, t)