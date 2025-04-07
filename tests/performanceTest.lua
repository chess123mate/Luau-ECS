return function(tests, t)


local ecs = require(game.ReplicatedStorage.ecs)
--[[
Note: numbers do not seem to be altered when running ECS with !native option; perhaps it isn't compiled when required by code in TestService?
ECS:
AddMany 0.0037
SpawnMany 0.0047
DeleteMany 0.00115
	if no ComponentFlag/EntityFlag, DeleteMany was a bit faster
DeleteManyWith2Data 0.0021
DeleteManyWith2DataB 0.0017 (uses ClearComponent)
Query 0.0024

JECS:
AddMany 0.019296499900519848 (5.2x)
SpawnMany 0.0019157999195158482 (0.4x)
DeleteMany 0.002738300012424588 (2.4x)
DeleteManyWith2Data 0.005780600011348724 (2.75x) (3.4x compared to B)
Query 0.0024 (1x)
]]

function tests.AddMany()
	local s = os.clock()
	local world = ecs.World.new()
	local C1 = world:Entity()
	local C2 = world:Entity()
	local C3 = world:Entity()
	local C4 = world:Entity()
	local C5 = world:Entity()
	local C6 = world:Entity()
	local C7 = world:Entity()
	local C8 = world:Entity()
	local e = world:Entity()
	for i = 1, 5000 do
		world:Set(e, C1, i)
		world:Set(e, C2, i)
		world:Set(e, C3, i)
		world:Set(e, C4, i)
		world:Set(e, C5, i)
		world:Set(e, C6, i)
		world:Set(e, C7, i)
		world:Set(e, C8, i)
	end
	print("AddMany", os.clock() - s)
end

function tests.SpawnMany()
	local s = os.clock()
	local world = ecs.World.new()
	for i = 1, 5000 do
		world:Entity()
	end
	print("SpawnMany", os.clock() - s)
end

function tests.DeleteMany()
	local world = ecs.World.new()
	local es = {}
	for i = 1, 5000 do
		es[i] = world:Entity()
	end
	local s = os.clock()
	for i, e in es do
		world:Delete(e)
	end
	print("DeleteMany", os.clock() - s)
end

function tests.DeleteManyWith2Data()
	local world = ecs.World.new()
	local C1 = world:Component()
	local C2 = world:Component()
	local es = {}
	for i = 1, 5000 do
		local e = world:Entity()
		es[i] = e
		world:Set(e, C1, i)
		world:Set(e, C2, i)
	end
	local s = os.clock()
	for i, e in es do
		world:Delete(e)
	end
	print("DeleteManyWith2Data", os.clock() - s)
end
function tests.DeleteManyWith2DataB()
	local world = ecs.World.new()
	local C1 = world:Component()
	local C2 = world:Component()
	local es = {}
	for i = 1, 5000 do
		local e = world:Entity()
		es[i] = e
		world:Set(e, C1, i)
		world:Set(e, C2, i)
	end
	local s = os.clock()
	world:ClearComponent(C1)
	world:ClearComponent(C2)
	for i, e in es do
		world:Delete(e)
	end
	print("DeleteManyWith2DataB", os.clock() - s)
end

function tests.Query()
	local numC = 4
	local n = 1000
	local rounds = 10
	local world = ecs.World.new()
	local Cs = {}
	for c = 1, numC do
		Cs[c] = world:Component()
	end
	local es = {}
	for i = 1, n do
		es[i] = world:Entity()
	end
	for c = 1, numC do
		local C = Cs[c]
		for i = 1, n, c do
			world:Add(es[i], C)
		end
	end
	local s = os.clock()
	for r = 1, rounds do
		for i = 1, numC do
			local query = world:Query(Cs[1])
			for j = 2, i do
				query:With(Cs[j])
			end
			for e in query do
			end
			for e in world:Query(Cs[i]) do
			end
		end
	end
	print("Query", os.clock() - s)
end


end -- function(tests, t)