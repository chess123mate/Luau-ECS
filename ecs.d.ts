/** Config that adjusts how all worlds operate */
export const Config: {
	/** Defaults to true. Set to false to disable entities from having their Name field be set to their Id field by default. */
	EntityNameDefault: boolean
}

export type Entity = {
	/** The id (unique across the entire world) */
	Id: number
	/** The debug name associated with this entity. If `EntityNameDefault` is true, this will equal `tostring(Id)` by default. */
	Name?: string
	/** Set to true on Flag entities.\
	 * If you are using an entity as a flag component, setting this to true has performance benefits. */
	IsFlag?: true
}

type ComponentHooks<Data> = {
	OnAdd?: (e: Entity, value: Data) => void
	OnChange?: (e: Entity, value: Data, prev: Data) => void
	OnRemove?: (e: Entity, prev: Data) => void
	OnDelete?: (e: Entity, prev: Data) => void
}
/** Any component (protected or not). Useful if you just want to receive a component for world.Get. */
export type AnyComponent<Data = any> = Reconstruct<Entity & { IsFlag: undefined; __data: Data }> & ComponentHooks<Data>
/** Cast an exported component as a ProtectedComponent to disallow world.Add, Set, and Remove.\
 * Use this when you want to enforce that other code modify the data in a particular way. */
export type ProtectedComponent<Data = any> = Reconstruct<Entity & { IsFlag: undefined; __data: Data; __protected: true }> & ComponentHooks<Data>
/** An unprotected component (i.e. you can use in world.Add, Set, and Remove). */
export type Component<Data = any> = Reconstruct<Entity & { IsFlag: undefined; __data: Data; __protected: never }> & ComponentHooks<Data>

type FlagHooks = {
	OnAdd?: (e: Entity) => void
	OnRemove?: (e: Entity) => void
	OnDelete?: (e: Entity) => void
}
/** Any component (protected or not). Useful if you just want to receive a flag for world.Has. */
export type AnyFlag = Reconstruct<Entity & { IsFlag: true }> & FlagHooks
/** Cast an exported flag as a ProtectedFlag to disallow world.Add and Remove.\
 * Use this when you want to enforce that other code only add/remove this flag in a particular way. */
export type ProtectedFlag = Reconstruct<Entity & { IsFlag: true; __protected: true }> & FlagHooks
/** An unprotected flag (i.e. you can use in world.Add and Remove). */
export type Flag = Reconstruct<Entity & { IsFlag: true; __protected: never }> & FlagHooks

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
	/** Counts how many entities are in the query. (Faster than iterating over them yourself.) */
	Count(): number
	Clone(): Query<T>
	/** Returns true if Count would return 0. (Faster than using `Count() == 0`) */
	IsEmpty(): boolean
}

type Name_<Name extends string> = {
	/** The name associated with this entity for use with type checking. */
	Name: Name
}
/** The same as Entity, but for use with type checked queries. */
export type Entity_<Name extends string = string> = Reconstruct<Omit<Entity, "Name"> & Name_<Name>>
export type Component_<Name extends string = string, Data = any> = Reconstruct<Omit<Component<Data>, "Name"> & Name_<Name>>
export type Flag_<Name extends string = string> = Reconstruct<Omit<Flag, "Name"> & Name_<Name>>

/** Represents a collection of entities for use in type checked queries. */
export type Components<T extends Entity_[]> = {
	[K in T[number]["Name"]]: Extract<T[number], { Name: K }>
}
/** A type checked query. */
export type Query_<A extends Components<any>, T extends A[keyof A][]> = Iter<InferComponentValues<T>> & {
	/** Require that entities have the specified components. Note that the value of these components will not be returned in the iteration. */
	With(...components: A[keyof A][]): Query_<A, T>
	/** Require that entities *not* have the specified components. */
	Without(...components: A[keyof A][]): Query_<A, T>
	/** Filters out any archetypes (sets of entities) for which `keep(has)` returns false\
	 * `has` is the set of components that the archetype has.\
	 * For example, if you wanted to iterate over entities that have component A or B:\
	 * `query:Custom(function(has) return has[A] or has[B] end)` */
	Custom(keep: (hasComponent: ReadonlySet<Entity>) => boolean): Query_<A, T>
	/** Counts how many entities are in the query. (Faster than iterating over them yourself.) */
	Count(): number
	Clone(): Query_<A, T>
	/** Returns true if Count would return 0. (Faster than using `Count() == 0`) */
	IsEmpty(): boolean
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
	Entity(): Entity
	Entity<Name extends string>(name: Name): Entity_<Name>
	/** Create a new Component entity. Unlike an Entity, it has `ComponentFlag` set.
	 * @param name Stored in entity.Name. If you want to use this component in type checked queries, use Component_ instead. */
	Component<Data>(name?: string): Component<Data>
	Component_<Data>(): <Name extends string>(name: Name) => Component_<Name, Data>
	/** Create a new Flag entity. Unlike an Entity, it has `ComponentFlag` set. Unlike Components, Flags never have data associated with them.
	 * @param name Stored in entity.Name */
	Flag(): Flag
	Flag<Name extends string>(name: Name): Flag_<Name>

	Add(e: Entity, C: Flag): void
	Has(e: Entity, C: Entity): boolean
	/** Combination of World:Add and associating a value between the entity and component. (Note that an entity can have a component even if its value is undefined, so `value = undefined` is valid.) */
	Set<Data>(e: Entity, C: Component<Data>, value: Data): void
	/** Get the value associated with a component.\
	 * You are allowed to call Get(e, flag), but since this will always return `undefined` it is usually a bug (you usually want to check if `Has`, not `Get`).\
	 * You can also get the data directly via e[C], so long as you treat it as read-only. */
	Get<Data>(e: Entity, C: AnyComponent<Data>): Data | undefined

	/** Removes a component from the entity\
	 * Does nothing if the entity doesn't have the component */
	Remove<C extends Component<any> | Flag>(e: Entity, C: C): void

	/** Deletes all data from the entity, removes the entity from the world, and - treating `e` like a component - removes any data associated with `e` from all other entities.\
	 * Of course, if you have references to entities in any of your data, this cannot be deleted automatically - use OnDelete hooks for such components.\
	 * If the entity is already deleted, does nothing. */
	Delete(e: Entity): void
	/** Returns true while the world is deleting 'e'. */
	IsDeleting(e: Entity): boolean
	/** Returns true if 'e' has been deleted.\
	Ideally you shouldn't need this, aside from its use in debugging. Typically, if you have a reference to an entity (that could have been deleted) in a component, you should use an OnDelete hook to clean it up. */
	IsDeleted(e: Entity): boolean
	/** Removes `C` (and clears any data associated with it) from all other entities.\
	 * Unlike Delete, `C` itself is not modified and remains usable after the operation.\
	 * Useful to clear temporary flags/data efficiently; should be used instead of `for e in world:Query(C) do world:Remove(e, C) end` */
	ClearComponent(C: AnyComponent<any> | AnyFlag): void

	/** Iterates over all components that an entity has.\
	 * Recommended mainly for debugging and entity serialization.\
	 * @example ```
	 * for (const C of world.IterComponents(e)) {}
	 * ```
	 * Note: Do not rely on the return type being a ReadonlySet - this is only meant for iteration */
	IterComponents(e: Entity): ReadonlySet<Component<unknown> | Flag>

	/** Query which components have all the specified components for iteration.\
	 * You can further modify the query using :With(...), :Without(...), or :Custom(keep)\
	 * Iterate over a query using `for entity, health in world:Query(Health) do`\
	 * During iteration, you are allowed to modify the current entity (by adding/removing/changing values or even deleting the entity), but not others (such as by running a query inside of a query).\
	 * If a system saves a query, you can iterate over it repeatedly (though this is only a tiny performance benefit as most of the work is done when you start iteration). */
	Query<T extends Entity[]>(...components: T): Query<InferComponentValues<T>>
	/** Same as Query, but returns a type checked query, to notify you if you attempt to query for a component that a particular type of entity doesn't have.
	 * @example
	 * ```
	 * // Step 1: define your component sets:
	 * type Character = Components<[typeof Model, typeof Health]>
	 * type Effects = Components<[typeof Healing, typeof Poisoned]>
	 * // Step 2: use the component sets in the query (& them together if you need more than one, especially if you have a flag that is specific to a particular system)
	 * for (const [e, health, healing] of world.Query_<Character & Effects>()(Health, Healing)) {
	 * 	// ...
	 * }
	 * ```
	 * You will get an (unfortunately cryptic) error message if you attempt to use a component not in the component sets. */
	Query_<A extends Components<any>>(): <T extends A[keyof A][]>(...components: T) => Query_<A, T>

	/** Remove empty archetypes (good for memory and query performance, but at the cost of having to create them again later, if needed).\
	 * Note that archetypes with deleted components are automatically cleaned up in `Delete`.\
	 * Thus, it only makes sense to run this if you've created a large number of components/archetypes that you're no longer using but haven't deleted, especially if you will be doing a lot of queries but not creating more entities. */
	Cleanup(): void
	IdToEntity(id: number): Entity | undefined

	/** Extends any OnAdd behaviour defined for `C`.\
	 * Triggered when C is added to an entity. */
	OnAdd(C: AnyFlag, onAdd: (e: Entity) => void): void
	/** Extends any OnAdd behaviour defined for `C`.\
	 * Triggered when C is added to an entity. Called before OnChange. */
	OnAdd<Data>(C: AnyComponent<Data>, onAdd: (e: Entity, value: Data) => void): void

	/** Extends any OnChange behaviour defined for `C`.\
	 * Triggered whenever the value associated with C is changed on some entity.
	 * @param onChange `value` and `prev` are guaranteed to be different. Either could be `nil`, as OnChange will trigger along with OnAdd and OnRemove. */
	OnChange<Data>(C: AnyComponent<Data>, onChange: (e: Entity, value: Data | undefined, prev: Data | undefined) => void): void
	/** Same as OnChange, but only triggers when `value` is not undefined. */
	OnNewValue<Data>(C: AnyComponent<Data>, onNewValue: (e: Entity, value: Data, prev: Data | undefined) => void): void

	/** Extends any OnRemove behaviour defined for `C`.\
	 * Triggered when C is removed from an entity (after OnChange). */
	OnRemove(C: AnyFlag, onRemove: (e: Entity) => void): void
	OnRemove<Data>(C: AnyComponent<Data>, onRemove: (e: Entity, prev: Data) => void): void

	/** Extends both OnAdd and OnRemove behaviour for `C`.
	 * @param added `true` when called from OnAdd, `false` when called from OnRemove */
	OnAddRemove(C: AnyFlag | AnyComponent<any>, onAddRemove: (e: Entity, added: boolean) => void): void

	/** Extends any OnDelete behaviour defined for `C`.\
	 * Note: OnRemove is called before OnDelete. */
	OnDelete(C: AnyFlag, onDelete: (e: Entity) => void): void
	/** Extends any OnDelete behaviour defined for `C`.\
	 * Note: OnRemove is called before OnDelete.
	 * @param onDelete `prev` refers to the value of e[C] *before* the world:Delete call */
	OnDelete<Data>(C: AnyComponent<Data>, onDelete: (e: Entity, prev: Data) => void): void

	/** Casts the component as Protected, disallowing world.Add, Set, and Remove */
	Protected: <C extends Component<any> | Flag>(C: C) => C extends Component<infer Data> ? ProtectedComponent<Data> : ProtectedFlag
}

/** Returns true if it's an entity/component/flag that hasn't been deleted */
export function IsLiveEntity(e: unknown): e is Entity
