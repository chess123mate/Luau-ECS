# Luau-ECS
Simple Luau-based ECS inspired by [JECS](https://github.com/Ukendio/jecs/) (with some archetype & query code derived from it).

Performance is somewhat better than JECS, at the cost of not supporting `pair`.

Usage Notes
-----------
- Entities are tables (with data inside the entity), not integers, but for replication/serialization you can use entity.Id
- You can modify entities during hooks in any way
- During iteration, you can modify the entity being iterated over in any way, but not any others (such as by accessing or querying other entities and adding/removing components to them)
- During deletion of an entity, any attempt to add/modify components & values will silently fail
- In typescript, to control how a component or flag is added, removed, or set on an entity, you can use the various Readonly and Protected functions/types to export a component that cannot be used in world.Add/Set/Remove (Readonly disables Set; Protected disables all three).

Using in Roblox-TS projects
---------------------------
- Add `"@rbxts/luau-ecs": "github:chess123mate/Luau-ECS",` to your `package.json`'s `dependencies`
- To update to the latest version, if you're using pnpm, you can run `pnpm update @rbxts/luau-ecs`


Setting up for development
--------------------------
- To run tests, you'll need <https://github.com/chess123mate/TestRunnerPlugin>
