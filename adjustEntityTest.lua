-- This test run repeatedly with ecs library to test effectiveness of AdjustEntity and identify bugs
--[[It also used this in the ecs file:
function World:AdjustEntity2(e, adjustFn)
	adjustFn(
		function(C)
			self:Add(e, C)
		end,
		function(C, value)
			self:Set(e, C, value)
		end,
		function(C)
			self:Remove(C)
		end)
	return e
end
]]
local ecs = require(game.ReplicatedStorage.ecs:Clone())
ecs.AutoDeleteEmptyArchetypes = false
ecs.EntityNameDefault = false
print(".")
local world = ecs.World.new()
local C1 = world:Component()
local C2 = world:Component()
local n = 1000
local es = table.create(n)

local function time(dt)
	return string.format("%.2fμs", dt / n * 1e6)
end
local function result(dt, ...)
	print(time(dt), ...)
end
local s

s = os.clock()
while os.clock() - s < 0.1 do end -- warmup

s = os.clock()
for i = 1, n do
	es[i] = world:Entity()
end
result(os.clock() - s, "create")

s = os.clock()
for i, e in es do
	world:AdjustEntity(e, function() end)
end
result(os.clock() - s, "empty adjust")

s = os.clock()
for i, e in es do
	world:Add(e, C1)
end
local addc1 = os.clock() - s

s = os.clock()
for i, e in es do
	world:Remove(e, C1)
end
result(os.clock() - s, "remove C1")

s = os.clock()
for i, e in es do
	world:Add(e, C1)
	world:Add(e, C2)
end
local addc2 = os.clock() - s

s = os.clock()
for i, e in es do
	world:Remove(e, C1)
	world:Remove(e, C2)
end
result(os.clock() - s, "remove C1,C2")

local total = 0
s = os.clock()
for i, e in es do
	world:AdjustEntity(e, function(add, set)
		local a = os.clock()
		add(C1)
		total += os.clock() - a
	end)
end
local adj1 = os.clock() - s

s = os.clock()
world:ClearComponent(C1)
result(os.clock() - s, "Clear C1")

result(addc1, "add C1")
result(adj1, "adjust1", time(total))

local total = 0
s = os.clock()
for i, e in es do
	world:AdjustEntity2(e, function(add, set)
		local a = os.clock()
		add(C1)
		total += os.clock() - a
	end)
end
result(os.clock() - s, "adjust1b", time(total))

local total = 0
s = os.clock()
for i, e in es do
	world:AdjustEntity(e, function(add, set)
		local a = os.clock()
		add(C1)
		add(C2)
		total += os.clock() - a
	end)
end
local adj2 = os.clock() - s
result(addc2, "add C1,C2")
result(adj2, "adjust2", time(total))

world:ClearComponent(C1)
world:ClearComponent(C2)

local total = 0
s = os.clock()
for i, e in es do
	world:AdjustEntity2(e, function(add, set)
		local a = os.clock()
		add(C1)
		add(C2)
		total += os.clock() - a
	end)
end
result(os.clock() - s, "adjust2b", time(total))

local Cs = {}
for i = 1, 10 do
	Cs[i] = if i <= 5 then world:Component() else world:Flag()
end

s = os.clock()
for i, e in es do
	for c, C in Cs do
		if c <= 5 then
			world:Set(e, C, c)
		else
			world:Add(e, C)
		end
	end
end
result(os.clock() - s, "set/add10")

for c, C in Cs do
	world:ClearComponent(C)
end

s = os.clock()
for i, e in es do
	world:AdjustEntity(e, function(add, set)
		for c, C in Cs do
			if c <= 5 then
				set(C, c)
			else
				add(C)
			end
		end
	end)
end
result(os.clock() - s, "adjust10")

for c, C in Cs do
	world:ClearComponent(C)
end

s = os.clock()
for i, e in es do
	world:AdjustEntity2(e, function(add, set)
		for c, C in Cs do
			if c <= 5 then
				set(C, c)
			else
				add(C)
			end
		end
	end)
end
result(os.clock() - s, "adjust10b")

for c, C in Cs do
	world:ClearComponent(C)
end

--[[For 1k, per entity:
0.73μs create
0.31μs empty adjust
0.44μs remove C1
0.88μs remove C1,C2
0.04μs Clear C1
0.44μs add C1
0.97μs adjust1 0.21μs
0.83μs adjust1b 0.61μs
0.86μs add C1,C2
1.29μs adjust2 0.29μs
1.18μs adjust2b 0.97μs
6.54μs set/add10
5.76μs adjust10
7.62μs adjust10b
For adjust:
	Seems crazy that `total` (as seen in `adjust1`) can be ~50% of `add C1`
For adjust b compared to add/set method:
	0.18μs more (+/- 0.05)
	Implies creating each closure costs 0.06µs

Adjust cost notes (µs):
	0.18 = 0.06 * 3 closures
	0.12 = 0.04 * 3 tables (hasComponent + prevValue + changes)
	0.04 cost (tied with add) cloning table from archetype
	0.34 accounted for so far
	In comparison, just calling add/set only costs 0.42, so you already have tough competition just there
	Based on adjust10 - adjust1...
		(6.19 - 1.01) / 9 = 0.58
		1.01 - 0.58 = 0.44 base overhead (measured 0.32 but estimated 0.12 more when you have changes)
		Adjust = 0.44 + 0.58 * numChanges
		but if that's true, then why is it faster then 10 sets?
		1 add is .42, 2 add is .435, 10 add is .65
		maybe it has to do with memory allocation

For 1:
13.40μs create (NOTE: prior testing gave 2.50μs ??)
4.30μs empty adjust
4.10μs remove C1
4.20μs remove C1,C2
5.20μs Clear C1
4.00μs add C1
7.30μs adjust1 1.40μs
4.50μs adjust1b 2.80μs
5.40μs add C1,C2
6.10μs adjust2 1.20μs
3.60μs adjust2b 2.50μs
12.90μs set/add10
8.10μs adjust10
10.00μs adjust10b
]]