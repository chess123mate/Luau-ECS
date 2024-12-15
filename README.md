# Luau-ECS
Simple Luau-based ECS inspired by [JECS](https://github.com/Ukendio/jecs/) (with some archetype & query code derived from it).

Performance is somewhat better than JECS, at the cost of not supporting `pair`.

Usage Notes
-----------
- Entities are tables (with data inside the entity), not integers, but for replication/serialization you can use entity.Id
- You can modify entities during hooks in any way
- During iteration, you can modify the entity being iterated over in any way, but not any others (such as by accessing or querying other entities and adding/removing components to them)
