package peach;

import peach.Component.ComponentHash;
import haxe.ds.Either;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.Var;
import peach.Entity.EntityID;
import peach.Component.ComponentID;

using haxe.macro.TypeTools;
using haxe.macro.ExprTools;

@:autoBuild(peach.Macros.buildSystem())
@:allow(peach.World)
abstract class System {
	final allCompIDs: Null<ComponentHash> = null;

	@:noCompletion
	@:nullSafety(Off)
	var _world: World;

	@:noCompletion
	var _initCalled = false;

	@:nullSafety(Off)
	var entityID: EntityID;

	abstract function run(...args: Any): Void;

	macro function get(...exprs: Expr): Expr {
		final vars = new Array<Var>();
		final pos = Context.currentPos();
		final isInUpdate = Context.getLocalMethod() == "update";

		var target: Expr = macro entityID;
		var reassignedTarget = false;

		for (e in exprs) {
			switch (e.expr) {
				case EConst(_) | EField(_, _, _):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity.\n\nPlease provide only 1 identifier as a target, or leave it off to target the current Entity of the system.",
							pos);
					}

					target = e;
					reassignedTarget = true;
				case EBinop(OpAssign, _.expr => EConst(CIdent(varname)), _.expr => EConst(CIdent(compName))):
					final type = Context.getType(compName);
					final id = Macros.getComponentID(type);

					if (id == null) {
						Context.fatalError('$compName is not a Component type', pos);
					}

					vars.push({
						name: varname,
						isStatic: false,
						isFinal: true,
						type: type.toComplexType(),
						expr: macro @:privateAccess cast _world.comps.get($target, $v{id})
					});

				case EBinop(OpNullCoal, _.expr => EConst(CIdent(varname)), _.expr => EConst(CIdent(compName))):
					final type = Context.getType(compName);
					final id = Macros.getComponentID(type);

					if (id == null) {
						Context.fatalError('$compName is not a Component type', pos);
					}

					vars.push({
						name: varname,
						isStatic: false,
						isFinal: true,
						type: TPath({
							pack: [],
							name: "Null",
							params: [TPType(type.toComplexType())]
						}),
						expr: macro @:privateAccess cast _world.comps.get($target, $v{id})
					});
				default:
			}
		}

		if (isInUpdate && !reassignedTarget) {
			Context.fatalError('Please provide a target EntityID as the first argument to get().\n\nupdate() runs standalone, not on a particular Entity, so there is no default target like in all() for example.',
				pos);
		}

		return {pos: pos, expr: EVars(vars)};
	}

	macro function add(...exprs: Expr): Expr {
		final args = new Array<Expr>();

		var target: Expr = macro entityID;
		var reassignedTarget = false;

		for (e in exprs) {
			switch (e.expr) {
				case EConst(CIdent(s)) if (reassignedTarget):
					args.push(e);
				case EConst(_):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity.\n\nPlease provide only 1 constant as a target, or leave it off to target the current Entity of the system.",
							Context.currentPos());
					}
					target = e;
					reassignedTarget = true;
				case ENew(_, _):
					args.push(e);
				default:
			}
		}

		return macro @:privateAccess _world.comps.add($target, ...$a{args});
	}

	macro function remove(...exprs: Expr) {
		final ids = new Array<ComponentID>();
		final pos = Context.currentPos();

		var target: Expr = macro entityID;
		var reassignedTarget = false;

		for (e in exprs) {
			switch (e.expr) {
				case EConst(CIdent(name)):
					try {
						final type = Context.getType(name);
						final id = Macros.getComponentID(type);

						if (id == null) {
							Context.fatalError('$name is not a Component type', pos);
						}

						ids.push(id);
					} catch (_) {
						if (reassignedTarget) {
							Context.fatalError("Cannot target more than 1 Entity.\n\nPlease provide only 1 identifier as a target, or leave it off to target the current Entity of the system.",
								pos);
						}

						target = macro cast ${e};
						reassignedTarget = true;
					}
				case EConst(_):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity.\n\nPlease provide only 1 constant as a target, or leave it off to target the current Entity of the system.",
							pos);
					}
					target = e;
					reassignedTarget = true;
				default:
			}
		}

		if (!reassignedTarget && ids.length == 0) {
			Context.fatalError("remove() has zero arguments.

Try one of the follwing parameter configs:
1. Provide Component class names to remove those Components from the current Entity
2. Pass an EntityID, then Component classes to remove Components from that specific Entity
3. Pass only an EntityID to remove the Entity from the World.", pos);

		}

		return macro @:privateAccess _world.comps.remove($target, ...$v{ids});
	}

	macro function swap(...exprs: Expr) {
		final pos = Context.currentPos();
		final toDel = new Array<ComponentID>();
		final toAdd = new Array<Expr>();

		var target: Expr = macro entityID;
		var reassignedTarget = false;
		var arrayCount = 0;

		for (e in exprs) {
			switch (e.expr) {
				case EArrayDecl(values):
					arrayCount++;

					if (arrayCount == 1) {
						for (e in values) {
							switch (e.expr) {
								case EConst(CIdent(name)):
									final type = Context.getType(name);
									final id = Macros.getComponentID(type);

									if (id == null) {
										Context.fatalError('$name is not a Component type (found in the Removal array)', pos);
									}

									toDel.push(id);
								default:
							}
						}

						continue;
					}

					if (arrayCount == 2) {
						for (e in values) {
							switch (e.expr) {
								case EConst(CIdent(name)):
									final type = Context.getType(name);
									final id = Macros.getComponentID(type);

									if (id == null) {
										Context.fatalError('$name is not a Component type (found in the Addition array)', pos);
									}

									toAdd.push(e);
								case ENew(t, _):
									final name = t.name;
									final type = Context.getType(name);
									final id = Macros.getComponentID(type);

									if (id == null) {
										Context.fatalError('$name is not a Component type (found in the Addition array)', pos);
									}

									toAdd.push(e);
								default:
							}
						}

						continue;
					}

					Context.fatalError("Cannot use more than 2 arrays. The first array is used for removal, the second for addition.", pos);
				case EConst(_):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity.\n\nPlease provide only 1 constant as a target, or leave it off to target the current Entity of the system.",
							pos);
					}
					target = e;
					reassignedTarget = true;
				default:
			}
		}

		if (toDel.length == 0) {
			Context.fatalError("Removal array cannot be empty!", pos);
		}

		if (toAdd.length == 0) {
			Context.fatalError("Addition array cannot be empty!", pos);
		}

		final e = macro {
			_world.comps.remove($target, ...$v{toDel});
			_world.comps.add($target, ...$a{toAdd});
		}

		return e;
	}
}
