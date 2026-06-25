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

type Iter<T extends readonly unknown[]> = IterableFunction<LuaTuple<[Entity, ...T]>>
export type Query<T extends readonly unknown[]> = Iter<T> & {
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
	/** The name associated with this entity (used with type checking). */
	Name: Name
}
/** The same as Entity, but for use with type checked queries. */
export type Entity_<Name extends string = string> = Reconstruct<Omit<Entity, "Name"> & Name_<Name>>
export type Component_<Name extends string = string, Data = any> = Reconstruct<Omit<Component<Data>, "Name"> & Name_<Name>>
export type Flag_<Name extends string = string> = Reconstruct<Omit<Flag, "Name"> & Name_<Name>>
export type ProtectedComponent_<Name extends string = string, Data = any> = Reconstruct<Omit<ProtectedComponent<Data>, "Name"> & Name_<Name>>
export type ProtectedFlag_<Name extends string = string> = Reconstruct<Omit<ProtectedFlag, "Name"> & Name_<Name>>

/** Represents an entity type description, for use in type checked queries.\
 * If you get an error while trying to create one of these, it's probably because one of the components/flags is unnamed - double check that you're using `world.Component_` / `world.Flag_` and that any type casts applied to the target component maintains the name. For instance, casting `as Component<Data>` will remove the name from the type; use `as Component_<"NameHere", Data>` instead. */
export type Components<T extends readonly Entity_[]> = {
	[K in T[number]["Name"]]: Extract<T[number], { Name: K }>
}

/** Validate that each component in Args belongs in Desc (ignoring unnamed components) */
type ValidateComponents<Desc, Args extends readonly unknown[]> = {
	[K in keyof Args]: Args[K] extends { Name: infer N extends string }
		? string extends N
			? Args[K]
			: N extends keyof Desc
				? Args[K]
				: never
		: Args[K]
}

/** Same as ValidateComponents but disallow components that belong to Desc */
type ValidateNotComponents<Desc, Args extends readonly unknown[]> = {
	[K in keyof Args]: Args[K] extends { Name: infer N extends string }
		? string extends N
			? Args[K]
			: N extends keyof Desc
				? never
				: Args[K]
		: Args[K]
}

type InferComponentValue<E> = E extends AnyComponent<infer T> ? T : undefined
type InferComponentValues<A extends readonly Entity[]> = {
	[K in keyof A]: InferComponentValue<A[K]>
}

/** A type checked query.
 * @type Desc - the set of components that a target entity may have (created using the `Components` type). */
export type Query_<Desc extends Components<any>, Args extends readonly Entity[]> = Iter<InferComponentValues<Args>> & {
	/** Require that entities have the specified components. Note that the value of these components will not be returned in the iteration. */
	With<Args2 extends readonly Entity[]>(...components: ValidateComponents<Desc, Args2>): Query_<Desc, Args>
	/** Require that entities *not* have the specified components (type checking will assert that `Desc` may have them; use `IsNot` if you're using the component to restrict entities to just `Desc`). */
	Without<Args2 extends readonly Entity[]>(...components: ValidateComponents<Desc, Args2>): Query_<Desc, Args>
	/** Require that entities *not* have the specified components (type checking will assert that `Desc` *does not* have them).\
	 * Use this to find just the entity type you're looking for.\
	 * Without vs IsNot example: say you're updating enemy health in response to poison, but players have separate health updating logic. Then you might use `world.Query_<Enemy_>()(Health, Poison).IsNot(Player).Without(PoisonInit)`. `IsNot` restricts to just the `Enemy_` description; `Without` specifies "Enemies can have this but I don't want it".\
	 * For unnamed components/flags (which won't error in either case) or other cases where this distinction seems meaningless, prefer to use `Without`. */
	IsNot<Args2 extends readonly Entity[]>(...components: ValidateNotComponents<Desc, Args2>): Query_<Desc, Args>
	/** Filters out any archetypes (sets of entities) for which `keep(has)` returns false\
	 * `has` is the set of components that the archetype has.\
	 * For example, if you wanted to iterate over entities that have component A or B:\
	 * `query:Custom(function(has) return has[A] or has[B] end)` */
	Custom(keep: (hasComponent: ReadonlySet<Entity>) => boolean): Query_<Desc, Args>
	/** Counts how many entities are in the query. (Faster than iterating over them yourself.) */
	Count(): number
	Clone(): Query_<Desc, Args>
	/** Returns true if Count would return 0. (Faster than using `Count() == 0`) */
	IsEmpty(): boolean
}

export class World {
	constructor()

	/** Added to anything created via Component or Flag */
	ComponentFlag: Flag
	/** Added to anything created via Entity */
	EntityFlag: Flag

	/** Create a new entity.\
	 * Technically you can use this as a component/flag (but if you intend to use it as a Flag, set `entity.IsFlag` to `true`).\
	 * Note: unlike a Component or Flag, entities created this way have `world.EntityFlag` added (instead of `world.ComponentFlag`).
	 * @param name Stored in entity.Name */
	Entity(name?: string): Entity
	/** Create a new Component entity. Unlike an Entity, it has `ComponentFlag` added.
	 * @param name Stored in entity.Name. If you want to use this component in type checked queries, use Component_ instead. */
	Component<Data>(name?: string): Component<Data>
	/** Same as Component, but for use with type checked queries. */
	Component_<Data>(): <Name extends string>(name: Name) => Component_<Name, Data>
	/** Create a new Flag entity. Unlike an Entity, it has `ComponentFlag` added. Unlike Components, Flags never have data associated with them.
	 * @param name Stored in entity.Name */
	Flag(name?: string): Flag
	/** Same as Flag, but for use with type checked queries.
	 * @param name Stored in entity.Name */
	Flag_<Name extends string>(name: Name): Flag_<Name>

	/** Triggers:
	 * - OnAdd (unless the entity already had the flag)
	 *
	 * For components, use Set. */
	Add(e: Entity, C: Flag): void
	Has(e: Entity, C: Entity): boolean
	/** Adds the component to the entity with the specified value. (Note that an entity can have a component even if its value is undefined, so `value = undefined` is valid and `Has(entity, component)` will still return true.)\
	 * Triggers:
	 * - OnAdd (if the entity didn't have the component before)
	 * - OnChange (if the new value is different). */
	Set<Data>(e: Entity, C: Component<Data>, value: Data): void
	/** Get the value associated with a component.\
	 * You are technically allowed to call Get(e, flag), but since this will always return `undefined` it is usually a bug (you usually want to check if `Has`, not `Get`).\
	 * (You can also get the data directly via e[C], so long as you treat it as read-only.) */
	Get<Data>(e: Entity, C: AnyComponent<Data>): Data | undefined

	/** Removes a component or flag from the entity, doing nothing if the entity already didn't have the component/flag.\
	 * Triggers:
	 * - OnChange (if C is a component with a non-undefined value)
	 * - OnRemove */
	Remove<C extends Component<any> | Flag>(e: Entity, C: C): void

	/** Deletes all data from the entity, removes the entity from the world, and - treating `e` like a component - removes any data associated with `e` from all other entities.\
	 * Of course, if you have references to entities in any of your data, this cannot be deleted automatically - use OnDelete hooks for such components.\
	 * If the entity is already deleted, does nothing.\
	 * It is safe to continue to use `e` while it is being deleted (in OnChange/OnRemove hooks), but operations that add/remove components will silently do nothing. (`Set` will update the value only if the entity already had the component.)\
	 * After Delete returns, `e` is no longer an entity and cannot be used in any function except `IsDeleted`.\
	 * Triggers:
	 * - OnChange (for each component that had a value)
	 * - OnRemove (for all components/flags)
	 * - OnDelete (for all components/flags) */
	Delete(e: Entity): void
	/** Returns true while the world is deleting 'e' (but false if it's already been deleted; you should only use this in OnRemove/OnChange hooks). */
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
	 * Systems can save & reuse queries (though this is only a tiny performance benefit as most of the work is done when you start iteration). */
	Query<T extends readonly Entity[]>(...components: T): Query<InferComponentValues<T>>
	/** Same as Query, but returns a type checked query, to notify you if you attempt to query for a component that a particular type of entity doesn't have. Note that components/entities that do not have a Name are always allowed.
	 * @type Desc - the set of components you expect an entity (of the type you are querying for) to potentially have
	 * @example
	 * ```
	 * // Step 1: define your component sets using defined components/flags:
	 * type Character_ = Components<[typeof Model, typeof Health]>
	 * type Effects_ = Components<[typeof Healing, typeof Poisoned]>
	 * // Step 2: use the component sets in the query (& them together if you need more than one, especially if you have a flag that is specific to a particular system)
	 * for (const [e, health, healing] of world.Query_<Character_ & Effects_>()(Health, Healing)) {
	 * 	// ...
	 * }
	 * ```
	 * You will get an (unfortunately obfuscated) error message if you attempt to use a component not in `Desc` (the first few words are `Argument of type`). */
	Query_<Desc extends Components<any> = {}>(): <Args extends readonly Entity[]>(...components: ValidateComponents<Desc, Args>) => Query_<Desc, Args>

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
	Protected: <C extends Component<any> | Flag>(C: C) =>
		C extends Component_<infer Name, infer Data> ? ProtectedComponent_<Name, Data>
		: C extends Component<infer Data> ? ProtectedComponent<Data>
		: C extends Flag_<infer Name> ? ProtectedFlag_<Name>
		: ProtectedFlag
}

/** Returns true if it's an entity/component/flag that hasn't been deleted */
export function IsLiveEntity(e: unknown): e is Entity
