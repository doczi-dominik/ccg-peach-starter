package peach;

import peach.Component.ComponentSet;
import peach.Entity.EntityID;
import peach.Component.ComponentID;
import haxe.ds.IntMap;

typedef EventID = Int;

@:allow(peach.World)
abstract Components(IntMap<ComponentSet>) {
	function new() {
		this = new IntMap<ComponentSet>();
	}

	public inline function add(entityID: EntityID, ...components: Component) {
		final comps = this.get(entityID) ?? new IntMap<Component>();

		for (c in components) {
			final compID = c._peach_id;
			if (!comps.exists(compID)) {
				comps.set(compID, c);
			}
		}

		if (!this.exists(entityID)) {
			@:nullSafety(Off)
			this.set(entityID, comps);
		}
	}

	public inline function get(entityID: EntityID, componentID: ComponentID): Null<Component> {
		final comps = this.get(entityID);

		if (comps == null)
			return null;

		return comps.get(componentID);
	}

	public inline function remove(entityID: EntityID, ...componentIDs: ComponentID) {
		if (componentIDs.length == 0) {
			this.remove(entityID);
		}

		final comps = this.get(entityID);

		if (comps == null)
			return;

		for (id in componentIDs) {
			comps.remove(id);
		}
	}

	public inline function getMatching(componentIDs: Array<ComponentID>): Array<EntityID> {
		final matched = [];

		for (entityID => compMap in this.keyValueIterator()) {
			var hasAll = true;

			for (id in componentIDs) {
				if (!compMap.exists(id)) {
					hasAll = false;
					break;
				}
			}

			if (hasAll) {
				matched.push(entityID);
			}
		}

		return matched;
	}
}

class World {
	// ComponentID / EntityID / Component
	@:allow(peach.System)
	@:allow(peach.Entity)
	final comps = new Components();

	final systems: IntMap<Array<System>>;

	var lastEntityID = -1;

	public function new(systems: IntMap<Array<System>>) {
		this.systems = systems;
	}

	public function add(entity: Entity, ?entityID: EntityID) {
		final eid = entityID ?? lastEntityID--;

		entity._world = this;
		entity._entityID = eid;

		comps.add(eid, ...entity.comps);
	}

	public function run(id: EventID, ...args: Any) {
		final selected = systems.get(id);

		if (selected == null)
			return;

		for (sys in selected) {
			sys._world = this;
			sys.run(...args);
		}
	}
}
