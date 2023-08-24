package peach;

import haxe.ds.IntMap;

typedef ComponentID = Int;
typedef ComponentHash = Array<ComponentID>;
typedef ComponentSet = IntMap<Component>;

@:autoBuild(peach.Macros.buildComponent())
abstract class Component {
	@:allow(peach.World)
	@:allow(peach.Entity)
	@:allow(Example)
	@:nullSafety(Off)
	final _peach_id:ComponentID;
}
