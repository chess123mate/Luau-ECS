/** Config that adjusts how all worlds operate */
export const Config: {
	/** Defaults to true. If you are regularly emptying out and recreating archetypes, consider disabling this (and then consider calling world:Clean() on occasion.) */
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
}
type ComponentHooks<Data> = {
	OnAdd?: (e: Entity, value: Data) => void
	OnChange?: (e: Entity, value: Data, prev: Data) => void
	OnRemove?: (e: Entity, prev: Data) => void
	OnDelete?: (e: Entity, prev: Data) => void
}
export type Component<Data = unknown> = Reconstruct<Entity & { __data: Data }> & ComponentHooks<Data>

type FlagHooks = {
	OnAdd?: (e: Entity) => void
	OnRemove?: (e: Entity) => void
	OnDelete?: (e: Entity) => void
}
export type Flag = Reconstruct<Entity & { IsFlag: true }> & FlagHooks

type Iter<T extends unknown[]> = IterableFunction<LuaTuple<[Entity, ...T]>>
export type Query<T extends unknown[]> = Iter<T> & {
	/** Only iterate over entities that have the specified components */
	With(...components: Entity[]): Query<T>
	/** Only iterate over entities that do *not* have the specified components */
	Without(...components: Entity[]): Query<T>
	/** Only iterate over entities in archetypes for which `keep(archetype)` returns true */
	Custom(keep: (hasComponent: Set<Entity>) => boolean): Query<T>
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

	Entity(name?: string): Entity
	Component<Data>(name?: string): Component<Data>
	Flag(name?: string): Flag

	Add(e: Entity, C: Flag): void
	Has(e: Entity, C: Entity): boolean
	/** Combination of World:Add and associating a value between the entity and component. (Note that an entity can have a component even if its value is undefined, so `value = undefined` is valid.) */
	Set<Data>(e: Entity, C: Component<Data>, value: Data): void
	/** You can also get the data directly via e[C], so long as you treat it as read-only. */
	Get<C extends Component<any> | Flag>(e: Entity, C: C): C extends Component<infer Data> ? Data | undefined : undefined
	Remove<C extends Component<any> | Flag>(e: Entity, C: C): void
	/** Removes 'e' from the world, deleting all information off of 'e' and treating it like a component and removing all information associated with it from all entities. */
	Delete(e: Entity): void

	/** Iterate over all entities that have the specified components.\
	 * Note: you may change the entity under iteration in any way you wish, but changing *other* entities results in undefined behaviour.
	 */
	Query<T extends Entity[]>(...components: T): Query<InferComponentValues<T>>

	/** Remove empty archetypes (good for memory and query performance, but at the cost of having to create them again later, if needed).\
	 * Not needed if Config.AutoDeleteEmptyArchetypes is true.
	 */
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
	 * @param onDelete `prev` refers to the value of e[C] *before* the world:Delete call
	 */
	OnDelete<Data>(C: Component<Data>, onDelete: (e: Entity, prev: Data) => void): void
}

/** Returns true if it's an entity/component/flag that hasn't been deleted */
export function IsLiveEntity(e: unknown): e is Entity
