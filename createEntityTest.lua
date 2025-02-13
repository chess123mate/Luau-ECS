-- This test run repeatedly with ecs library to test effectiveness of CreateEntity
local ecs = require(game.ReplicatedStorage.ecs:Clone())
ecs.AutoDeleteEmptyArchetypes = false
ecs.EntityNameDefault = false
local rounds = 30
local n = 1000
print("----")
for z = 1, 6 do
	local world = ecs.World.new()
	local Cs = {}
	for i = 1, 10 do
		Cs[i] = if i <= 5 then world:Component() else world:Flag()
	end
	local REGULAR = z == 1 or z == 4
	local CREATE = z == 2 or z == 5
	local MULTI_ARCHETYPE = z <= 3
	local total = 0
	for r = 1, rounds do
		local s = os.clock()
		local es = {}

		if MULTI_ARCHETYPE then
			if REGULAR then
				for i = 1, n do
					local e = world:Entity()
					for c = 1, 10 do
						if i % (c + 1) == 0 then
							if c <= 5 then
								world:Set(e, Cs[c], i)
							else
								world:Add(e, Cs[c])
							end
						end
					end
					es[i] = e
				end
			elseif CREATE then
				for i = 1, n do
					local e = world:CreateEntity(function(add, set)
						for c = 1, 10 do
							if i % (c + 1) == 0 then
								if c <= 5 then
									set(Cs[c], i)
								else
									add(Cs[c])
								end
							end
						end
					end)
					es[i] = e
				end
			else
				for i = 1, n do
					local e = world:AdjustEntity(world:Entity(), function(add, set, remove)
						for c = 1, 10 do
							if i % (c + 1) == 0 then
								if c <= 5 then
									set(Cs[c], i)
								else
									add(Cs[c])
								end
							end
						end
					end)
					es[i] = e
				end
			end
		else
			-- put all entities in the same archetypes
			if REGULAR then
				for i = 1, n do
					local e = world:Entity()
					for c = 1, 10 do
						if c <= 5 then
							world:Set(e, Cs[c], i)
						else
							world:Add(e, Cs[c])
						end
					end
					es[i] = e
				end
			elseif CREATE then
				for i = 1, n do
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
			else
				for i = 1, n do
					local e = world:AdjustEntity(world:Entity(), function(add, set)
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
			end
		end

		local dt = os.clock() - s
		total += dt
		-- Cleanup
		for _, C in Cs do
			world:ClearComponent(C)
		end
		for _, e in es do
			world:Delete(e)
		end
	end
	print(if MULTI_ARCHETYPE then "1k" else "1 ",
		if REGULAR then "regulr" elseif CREATE then "create" else "adjust",
		"Avg:", string.format("%.2fµs", total / rounds / n * 1e6))
end
--[[Results with transitions:
"1k" is the 1k archetypes case; "1" is the 1 archetype (10 components) case
  1k regulr Avg: 1.42µs
  1k create Avg: 2.45µs
  1k adjust Avg: 2.94µs
  1  regulr Avg: 2.93µs
  1  create Avg: 5.04µs
  1  adjust Avg: 6.66µs

Create tests are a bit faster without verifying components at each step and with sorting occurring at the end, but it's still substantially slower than the regular method
]]
-- Original tests for 1-archetype-CreateEntity took less than half the time but despite getting that earlier today I can't recreate it anymore (despite no major background tasks and using the original files)

-- Note that, for the 1 archetype case with AutoDeleteEmptyArchetypes true, the 'regular' case takes ~2.4x as long (presumably because of all the intermediary archetypes being repeatedly reconstructed)
