-- This test run repeatedly with ecs library to test effectiveness of CreateEntity
local ecs = require(game.ReplicatedStorage.ecs)
ecs.AutoDeleteEmptyArchetypes = true
local world = ecs.World.new()
local Cs = {}
for i = 1, 10 do
	Cs[i] = if i <= 5 then world:Component() else world:Flag()
end

local total = 0
local rounds = 30
for r = 1, rounds do
	task.wait()
	-- add a bunch of entities
	local s = os.clock()

	-- local es = {}
	-- for i = 1, 1000 do
	-- 	local e = world:Entity()
	-- 	es[i] = e
	-- end
	-- -- form 2^10 new archetypes
	-- for i, e in es do
	-- 	for c = 1, 10 do
	-- 		if i % (c + 1) == 0 then
	-- 			if c <= 5 then
	-- 				world:Set(e, Cs[c], i)
	-- 			else
	-- 				world:Add(e, Cs[c])
	-- 			end
	-- 		end
	-- 	end
	-- end

	-- local es = {}
	-- for i = 1, 1000 do
	-- 	local e = world:CreateEntity(function(add, set)
	-- 		for c = 1, 10 do
	-- 			if i % (c + 1) == 0 then
	-- 				if c <= 5 then
	-- 					set(Cs[c], i)
	-- 				else
	-- 					add(Cs[c])
	-- 				end
	-- 			end
	-- 		end
	-- 	end)
	-- 	es[i] = e
	-- end

	-- local es = {}
	-- for i = 1, 1000 do
	-- 	local e = world:Entity()
	-- 	es[i] = e
	-- end
	-- -- put them all in the same archetypes
	-- for i, e in es do
	-- 	for c = 1, 10 do
	-- 		if c <= 5 then
	-- 			world:Set(e, Cs[c], i)
	-- 		else
	-- 			world:Add(e, Cs[c])
	-- 		end
	-- 	end
	-- end

	local es = {}
	for i = 1, 1000 do
		local e = world:CreateEntity(function(add, set)
			for c = 1, 10 do
				if c <= 5 then
					set(Cs[c], i)
				else
					add(Cs[c])
				end
			end
		end)
		es[i] = e
	end

	dt = os.clock() - s
	-- Cleanup
	for _, C in Cs do
		world:ClearComponent(C)
	end
	for _, e in es do
		world:Delete(e)
	end
	local dt = os.clock() - s
	print(dt)
	total += dt
end
print("Avg:", total / rounds)
-- For the 1k archetypes:
-- 0.0040 for regular
-- 0.0030 for CreateEntity
-- For 1 archetype (10 components):
-- 0.0166 for regular
-- 0.0056 for CreateEntity