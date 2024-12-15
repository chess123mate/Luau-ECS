return function(tests, t)


local ecs = require(game.ReplicatedStorage.ecs)
local new = ecs.World.new

function tests.AddRemoveFlag()
	local w = new()
	local e = w:Entity("e")
	local A = w:Component("A")
	w:Add(e, A)
	t.equals(w:Get(e, A), nil)
	t.equals(w:Has(e, A), true)
	w:Remove(e, A)
	t.falsy(w:Has(e, A))
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
	local iter = {}
	for e in x.w:Query(x.A, x.B) do
		if iter[e] then error("already iterated over " + tostring(e)) end
		iter[e] = true
	end
	t.falsy(iter[x.e1])
	t.truthy(iter[x.e2])
	table.clear(iter)
	for e in x.w:Query(x.A) do
		if iter[e] then error("already iterated over " + tostring(e)) end
		iter[e] = true
	end
	t.truthy(iter[x.e1])
	t.truthy(iter[x.e2])
end
function tests.QueryWithout()
	local x = setupAB2()
	local iter = {[x.e1] = true}
	for e in x.w:Query(x.A):Without(x.B) do
		if not iter[e] then error("unexpected entity in iteration " .. tostring(e)) end
		iter[e] = nil
	end
	if next(iter) then error("failed to iterate over anything") end
	for e in x.w:Query(x.B):Without(x.A) do
		error("unexpected iteration - everything has A")
	end
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
end
function tests.DeleteComponent()
	local w = new()
	local A = w:Component()
	local B = w:Component()
	local e = w:Entity()
	w:Set(e, A, 1)
	w:Set(e, B, 2)
	w:Delete(A)
	t.equals(w:Get(e, A), nil, "entity should not have data from deleted component")
	t.equals(w:Get(e, B), 2, "entity should not be deleted")
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
	}
}


end -- function(tests, t)