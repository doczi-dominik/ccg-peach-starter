package peach;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.Rest;
import haxe.ds.IntMap;
import peach.Component;

using haxe.macro.TypeTools;

typedef EntityID = Int;

@:autoBuild(peach.Macros.buildEntity())
class Entity {
	@:allow(peach.World)
	final comps: Array<Component>;

	@:nullSafety(Off)
	@:noCompletion
	@:allow(peach.World)
	var _world: World;

	@:nullSafety(Off)
	@:noCompletion
	@:allow(peach.World)
	var _entityID: EntityID;

	function new(...components: Component) {
		comps = components;
	}

	final function add(...components: Component) {
		_world.comps.add(_entityID, ...components);
	}

	final macro function get(...exprs: Expr): Expr {
		final vars = new Array<Var>();
		final pos = Context.currentPos();

		for (e in exprs) {
			switch (e.expr) {
				case EBinop(op, _.expr => EConst(CIdent(varname)), _.expr => EConst(CIdent(compName))):
					final type = Context.getType(compName);
					final id = Macros.getComponentID(type);

					if (id == null) {
						Context.fatalError('$compName is not a Component type!', pos);
					}

					var t: Null<ComplexType>;

					t = switch (op) {
						case OpAssign:
							type.toComplexType();
						case OpNullCoal:
							TPath({
								pack: [],
								name: "Null",
								params: [TPType(type.toComplexType())]
							});
						default:
							null;
					}

					vars.push({
						name: varname,
						isStatic: false,
						isFinal: true,
						type: t,
						expr: macro @:privateAccess cast _world.comps.get(_entityID, $v{id})
					});
				default:
			}
		}

		return {pos: pos, expr: EVars(vars)};
	}
}
