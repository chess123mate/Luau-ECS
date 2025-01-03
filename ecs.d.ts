/** Config that adjusts how all worlds operate */
export const Config: {
	/** Defaults to false. Might make sense to set to `true` to save on memory if you have numerous combinations of components/flags that are often only used briefly. (For example, a scenario where you have 20 flags and an entity may randomly have none or all would create 2^20 archetypes.) Alternatively, occasionally call world:Clean(). Note that setting this to true in regular usage may harm performance if you are regularly emptying out and recreating archetypes. */
	AutoDeleteEmptyArchetypes: boolean
	/** Defaults to true. Set to false to disable entities from having their Name field be set to their Id field by default. */
	EntityNameDefault: boolean
}

export type Entity = {
	/** The id (unique across the entire world) */
	Id: number
	/** The debug name associated with this entity */
	Name?: string
	/** Set to true on Flag entities. */
	IsFlag?: true
}
type ComponentHooks<Data> = {
	OnAdd?: (e: Entity, value: Data) => void
	OnChange?: (e: Entity, value: Data, prev: Data) => void
	OnRemove?: (e: Entity, prev: Data) => void
	OnDelete?: (e: Entity, prev: Data) => void
}
/** Any component (protected or not). Useful if you just want to receive a component for world.Get. */
export type AnyComponent<Data = unknown> = Reconstruct<Entity & { __data: Data }> & ComponentHooks<Data>
/** Cast an exported component as a ProtectedComponent to disallow world.Add, Set, and Remove.\
 * Use this when you want to enforce that other code modify the data in a particular way. */
export type ProtectedComponent<Data = unknown> = Reconstruct<Entity & { __data: Data, __protected: true }> & ComponentHooks<Data>
/** An unprotected component (i.e. you can use in world.Add, Set, and Remove). */
export type Component<Data = unknown> = Reconstruct<Entity & { __data: Data, __protected: never }> & ComponentHooks<Data>

type FlagHooks = {
	OnAdd?: (e: Entity) => void
	OnRemove?: (e: Entity) => void
	OnDelete?: (e: Entity) => void
}
/** Any component (protected or not). Useful if you just want to receive a flag for world.Has. */
export type AnyFlag = Reconstruct<Entity & { IsFlag: true }> & FlagHooks
/** Cast an exported flag as a ProtectedFlag to disallow world.Add and Remove.\
 * Use this when you want to enforce that other code only add/remove this flag in a particular way. */
export type ProtectedFlag = Reconstruct<Entity & { IsFlag: true, __protected: true }> & FlagHooks
/** An unprotected flag (i.e. you can use in world.Add and Remove). */
export type Flag = Reconstruct<Entity & { IsFlag: true, __protected: never }> & FlagHooks

type Iter<T extends unknown[]> = IterableFunction<LuaTuple<[Entity, ...T]>>
export type Query<T extends unknown[]> = Iter<T> & {
	/** Require that entities have the specified components. Note that the value of these components will not be returned in the iteration. */
	With(...components: Entity[]): Query<T>
	/** Require that entities *not* have the specified components. */
	Without(...components: Entity[]): Query<T>
	/** Filters out any archetypes (sets of entities) for which `keep(has)` returns false\
	 * `has` is the set of components that the archetype has.\
	 * For example, if you wanted to iterate over entities that have component A or B:\
	 * `query:Custom(function(has) return has[A] or has[B] end)` */
	Custom(keep: (hasComponent: ReadonlySet<Entity>) => boolean): Query<T>
}

type InferComponentValue<E> = E extends AnyComponent<infer T> ? T : undefined
type InferComponentValues<A extends Entity[]> = {
	[K in keyof A]: InferComponentValue<A[K]>
}

export class World {
	constructor()

	/** Added to anything created via Component or Flag */
	ComponentFlag: Flag
	/** Added to anything created via Entity */
	EntityFlag: Flag

	/** Create a new entity.\
	 * If needed, you can use this as a Component or Flag (simply type-cast it). If you intend to use it as a Flag, set `entity.IsFlag` to `true`.\
	 * Unlike a Component or Flag, entities created this way have `EntityFlag` set.
	 * @param name Stored in entity.Name */
	Entity(name?: string): Entity
	/** Create a new Component entity. Unlike an Entity, it has `ComponentFlag` set.
	 * @param name Stored in entity.Name */
	Component<Data>(name?: string): Component<Data>
	/** Create a new Flag entity. Unlike an Entity, it has `ComponentFlag` set. Unlike Components, Flags never have data associated with them.
	 * @param name Stored in entity.Name */
	Flag(name?: string): Flag

	Add(e: Entity, C: Flag): void
	Has(e: Entity, C: Entity): boolean
	/** Combination of World:Add and associating a value between the entity and component. (Note that an entity can have a component even if its value is undefined, so `value = undefined` is valid.) */
	Set<Data>(e: Entity, C: Component<Data>, value: Data): void
	/** You can also get the data directly via e[C], so long as you treat it as read-only. */
	Get<C extends AnyComponent<any> | Flag>(e: Entity, C: C): C extends AnyComponent<infer Data> ? Data | undefined : undefined

	/** Removes a component from the entity
	 * Does nothing if the entity doesn't have the component */
	Remove<C extends (Component<any> | Flag)>(e: Entity, C: C): void

	/** Deletes all data from the entity, removes the entity from the world, and - treating `e` like a component - removes any data associated with `e` from all other entities.\
	 * Of course, if you have references to entities in any of your data, this cannot be deleted automatically - use OnDelete hooks for such components.\
	 * Note that archetypes referencing `e` will be deleted regardless of `ecs.AutoDeleteEmptyArchetypes` */
	Delete(e: Entity): void
	/** Returns true while the world is deleting 'e'. */
	IsDeleting(e: Entity): boolean
	/** Removes `C` (and clears any data associated with it) from all other entities.\
	 * Unlike Delete, `C` itself is not modified and remains usable after the operation.\
	 * Useful to clear temporary flags/data efficiently; should be used instead of `for e in world:Query(C) do world:Remove(e, C) end` */
	ClearComponent(C: AnyComponent<any> | AnyFlag): void

	/** Query which components have all the specified components for iteration.\
	 * You can further modify the query using :With(...), :Without(...), or :Custom(keep)\
	 * Iterate over a query using `for entity, health in world:Query(Health) do`\
	 * During iteration, you are allowed to modify the current entity (by adding/removing/changing values or even deleting the entity), but not others (such as by running a query inside of a query).\
	 * If a system saves a query, you can iterate over it repeatedly (though this is only a tiny performance benefit as most of the work is done when you start iteration). */
	Query<T extends Entity[]>(...components: T): Query<InferComponentValues<T>>

	/** Remove empty archetypes (good for memory and query performance, but at the cost of having to create them again later, if needed).\
	 * Not needed if Config.AutoDeleteEmptyArchetypes is true.\
	 * Note that archetypes with deleted components are automatically cleaned up in `Delete`. */
	Cleanup(): void
	IdToEntity(id: number): Entity | undefined

	/** Extends any OnAdd behaviour defined for `C`.\
	 * Triggered when C is added to an entity. */
	OnAdd(C: AnyFlag, onAdd: (e: Entity) => void): void
	OnAdd<Data>(C: AnyComponent<Data>, onAdd: (e: Entity, value: Data) => void): void

	/** Extends any OnChange behaviour defined for `C`.\
	 * Triggered whenever the value associated with C is changed on some entity.
	 * @param onChange `value` and `prev` are guaranteed to be different. Either could be `nil`, as OnChange will trigger along with OnAdd and OnRemove. */
	OnChange<Data>(C: AnyComponent<Data>, onChange: (e: Entity, value: Data | undefined, prev: Data | undefined) => void): void
	/** Same as OnChange, but only triggers when `value` is not undefined. */
	OnNewValue<Data>(C: AnyComponent<Data>, onNewValue: (e: Entity, value: Data, prev: Data | undefined) => void): void

	/** Extends any OnRemove behaviour defined for `C`.\
	 * Triggered when C is removed from an entity. */
	OnRemove(C: AnyFlag, onRemove: (e: Entity) => void): void
	OnRemove<Data>(C: AnyComponent<Data>, onRemove: (e: Entity, prev: Data) => void): void

	/** Extends any OnDelete behaviour defined for `C`.\
	 * OnDelete is triggered after OnRemove if the OnRemove was triggered by world:Delete */
	OnDelete(C: AnyFlag, onDelete: (e: Entity) => void): void
	/** Extends any OnDelete behaviour defined for `C`.\
	 * Triggered after OnRemove if the OnRemove was triggered by world:Delete
	 * @param onDelete `prev` refers to the value of e[C] *before* the world:Delete call */
	OnDelete<Data>(C: AnyComponent<Data>, onDelete: (e: Entity, prev: Data) => void): void

	/** Casts the component as Protected, disallowing world.Add, Set, and Remove */
	Protected: <C extends Component<any> | Flag>(C: C) => C extends Component<infer Data> ? ProtectedComponent<Data> : ProtectedFlag
}

/** Returns true if it's an entity/component/flag that hasn't been deleted */
export function IsLiveEntity(e: unknown): e is Entity
