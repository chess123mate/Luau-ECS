-- This test run repeatedly with ecs library using !native vs not
local ecs = require(game.ReplicatedStorage.ecs)
ecs.AutoDeleteEmptyArchetypes = true
local world = ecs.World.new()

local total = 0
local rounds = 30
for r = 1, rounds do
	task.wait()
	local s = os.clock()
	local Cs = {}
	for i = 1, 10 do
		Cs[i] = if i <= 5 then world:Component() else world:Flag()
	end
	-- add a bunch of entities
	local es = {}
	for i = 1, 1000 do
		local e = world:Entity()
		es[i] = e
	end
	-- form 2^10 new archetypes
	for i, e in es do
		for c = 1, 10 do
			if i % (c + 1) == 0 then
				if c <= 5 then
					world:Set(e, Cs[c], i)
				else
					world:Add(e, Cs[c])
				end
			end
		end
	end
	-- Query a variety of them
	local n = 0
	for x = 1, 50 do
		for q in world:Query(Cs[(x + 1) % 10 + 1], Cs[(x + 2) % 10 + 1], Cs[(x + 6) % 10 + 1]) do
			n += 1
		end
		for q in world:Query(Cs[(x + 4) % 10 + 1], Cs[(x + 5) % 10 + 1], Cs[(x + 9) % 10 + 1]) do
			n += 1
		end
		for q in world:Query(Cs[(x + 3) % 10 + 1]):Without(Cs[(x + 4) % 10 + 1]):With(Cs[(x + 8) % 10 + 1]) do
			n += 1
		end
	end
	-- Cleanup
	for _, C in Cs do
		world:Delete(C)
	end
	for _, e in es do
		world:Delete(e)
	end
	first = false
	local dt = os.clock() - s
	print(dt)
	total += dt
end
print("Avg:", total / rounds)
-- native memory cost: 144KB out of 64MB max
-- Note: according to microprofiler, vast portion of the time is spent in world:Delete(C)

-- no auto-delete:
-- native, server only: .0048 (median of 3 runs)
-- native, play solo: .0056
-- non-native, server only: .0060
-- non-native, play solo: .0066

-- with auto-delete:
-- native, server only: .0054
-- native, play solo: .0064

-- Conclusions: auto-delete is slower in this scenario and using native really does help substantially