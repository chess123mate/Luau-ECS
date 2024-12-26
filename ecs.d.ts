/** Config that adjusts how all worlds operate */
export const Config: {
	/** Defaults to false. Might make sense to set to `true` to save on memory if you have numerous combinations of components/flags that are often only used briefly. (For example, a scenario where you have 20 flags and an entity may randomly have none or all would create 2^20 archetypes.) Alternatively, occasionally call world:Clean(). Note that setting this to true in regular usage may harm performance if you are regularly emptying out and recreating archetypes. */
	AutoDeleteEmptyArchetypes: boolean
}

/** Represents a unique set of components */
export type Archetype = {
	HasComponent: Set<Entity>
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
export type Component<Data = unknown> = Reconstruct<Entity & { __data: Data }> & ComponentHooks<Data>
/** Cast an exported component as a ReadonlyComponent to disallow world.Set */
export type ReadonlyComponent<Data = unknown> = Component<Data> & { __readonly: true }
/** Cast an exported component as a ProtectedComponent to disallow world.Add, Set, and Remove */
export type ProtectedComponent<Data = unknown> = Component<Data> & { __protected: true }
export type ProtectedFlag = Flag & { __protected: true }

type FlagHooks = {
	OnAdd?: (e: Entity) => void
	OnRemove?: (e: Entity) => void
	OnDelete?: (e: Entity) => void
}
export type Flag = Reconstruct<Entity & { IsFlag: true }> & FlagHooks

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

type InferComponentValue<E> = E extends Component<infer T> ? T : undefined
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
	/** Create a new Flag entity. Unlike an Entity, it has `ComponentFlag`
	 * @param name Stored in entity.Name */
	Flag(name?: string): Flag

	Add(e: Entity, C: Flag & { __protected?: never }): void
	Has(e: Entity, C: Entity): boolean
	/** Combination of World:Add and associating a value between the entity and component. (Note that an entity can have a component even if its value is undefined, so `value = undefined` is valid.) */
	Set<Data>(e: Entity, C: Component<Data> & { __readonly?: never, __protected?: never }, value: Data): void
	/** You can also get the data directly via e[C], so long as you treat it as read-only. */
	Get<C extends Component<any> | Flag>(e: Entity, C: C): C extends Component<infer Data> ? Data | undefined : undefined

	/** Removes a component from the entity
	 * Does nothing if the entity doesn't have the component */
	Remove<C extends (Component<any> | Flag) & { __protected?: never }>(e: Entity, C: C): void

	/** Deletes all data from the entity, removes the entity from the world, and - treating `e` like a component - removes any data associated with `e` from all other entities.\
	 * Of course, if you have references to entities in any of your data, this cannot be deleted automatically - use OnDelete hooks for such components.\
	 * Note that archetypes referencing `e` will be deleted regardless of `ecs.AutoDeleteEmptyArchetypes` */
	Delete(e: Entity): void
	/** Returns true while the world is deleting 'e'. */
	IsDeleting(e: Entity): boolean
	/** Removes `C` (and clears any data associated with it) from all other entities.\
	 * Unlike Delete, `C` itself is not modified and remains usable after the operation.\
	 * Useful to clear temporary flags/data efficiently; should be used instead of `for e in world:Query(C) do world:Remove(e, C) end` */
	ClearComponent(C: Component<any> | Flag): void

	/** Iterate over all entities that have the specified components.\
	 * Note: you may change the entity under iteration in any way you wish, but changing *other* entities results in undefined behaviour. */

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
	OnAdd(C: Flag, onAdd: (e: Entity) => void): void
	OnAdd<Data>(C: Component<Data>, onAdd: (e: Entity, value: Data) => void): void

	/** Extends any OnChange behaviour defined for `C`.\
	 * Triggered whenever the value associated with C is changed on some entity.
	 * @param onChange `value` and `prev` are guaranteed to be different. Either could be `nil`, as OnChange will trigger along with OnAdd and OnRemove. */
	OnChange<Data>(C: Component<Data>, onChange: (e: Entity, value: Data | undefined, prev: Data | undefined) => void): void
	/** Same as OnChange, but only triggers when `value` is not undefined. */
	OnNewValue<Data>(C: Component<Data>, onNewValue: (e: Entity, value: Data, prev: Data | undefined) => void): void

	/** Extends any OnRemove behaviour defined for `C`.\
	 * Triggered when C is removed from an entity. */
	OnRemove(C: Flag, onRemove: (e: Entity) => void): void
	OnRemove<Data>(C: Component<Data>, onRemove: (e: Entity, prev: Data) => void): void

	/** Extends any OnDelete behaviour defined for `C`.\
	 * OnDelete is triggered after OnRemove if the OnRemove was triggered by world:Delete */
	OnDelete(C: Flag, onDelete: (e: Entity) => void): void
	/** Extends any OnDelete behaviour defined for `C`.\
	 * Triggered after OnRemove if the OnRemove was triggered by world:Delete
	 * @param onDelete `prev` refers to the value of e[C] *before* the world:Delete call */
	OnDelete<Data>(C: Component<Data>, onDelete: (e: Entity, prev: Data) => void): void

	/** Casts the component as Readonly, disallowing world.Set */
	Readonly: <Data>(C: Component<Data>) => ReadonlyComponent<Data>

	/** Casts the component as Protected, disallowing world.Add, Set, and Remove */
	Protected: <C extends Component<any> | Flag>(C: C) => C & { __protected: true }
}

/** Returns true if it's an entity/component/flag that hasn't been deleted */
export function IsLiveEntity(e: unknown): e is Entity
