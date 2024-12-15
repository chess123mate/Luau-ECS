# Luau-ECS
Simple Luau-based ECS inspired by [JECS](https://github.com/Ukendio/jecs/) (with some archetype & query code derived from it).

Usage Notes
-----------
- It is not allowed to apply a `__tostring` metatable to any entity/component.
 - If this is required, entities and components would need a unique `id` to be used instead of where `tostring(C)` is currently used
- Entities are tables (with data inside the entity), not integers
- You can modify entities during hooks in any way
- During iteration, you can modify the entity being iterated over in any way, but not any others (such as by accessing or querying other entities and adding/removing components to them)
