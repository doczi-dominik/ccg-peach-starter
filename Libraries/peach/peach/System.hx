package peach;

import haxe.macro.Context;
import haxe.macro.Expr;
import peach.Component.ComponentHash;
import peach.Component.ComponentID;
import peach.Entity.EntityID;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

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
						Context.fatalError("Cannot target more than 1 Entity!\n\nPlease provide only 1 identifier as a target, or leave it off to target the current Entity of the system.",
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
				case EMeta(_, _):
				default:
					Context.fatalError("Invalid get() expression!\n\nPlease use 'varName = ComponentName' if you are sure the Component exists and is always available and `varName ?? ComponentName` if it may be null.",
						pos);
			}
		}

		if (isInUpdate && !reassignedTarget) {
			Context.fatalError('Please provide a target EntityID as the first argument to get().\n\nupdate() runs standalone, not on a particular Entity, so there is no default target like in all() for example.',
				pos);
		}

		return {pos: pos, expr: EVars(vars)};
	}

	macro function add(...exprs: Expr): Expr {
		final pos = Context.currentPos();
		final args = new Array<Expr>();

		var target: Expr = macro entityID;
		var reassignedTarget = false;

		for (e in exprs) {
			switch (e.expr) {
				case EConst(CIdent(s)) if (reassignedTarget):
					args.push(e);
				case EConst(_):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity!\n\nPlease provide only 1 constant as a target, or leave it off to target the current Entity of the system.",
							Context.currentPos());
					}
					target = e;
					reassignedTarget = true;
				case ENew(_, _):
					args.push(e);
				case EMeta(_, _):
				default:
					Context.fatalError("Invalid add() expression!\n\nPlease construct a Component using 'new' or use one stored in a variable", pos);
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
							Context.fatalError("Cannot target more than 1 Entity!\n\nPlease provide only 1 identifier as a target, or leave it off to target the current Entity of the system.",
								pos);
						}

						target = macro cast ${e};
						reassignedTarget = true;
					}
				case EConst(_):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity!\n\nPlease provide only 1 constant as a target, or leave it off to target the current Entity of the system.",
							pos);
					}
					target = e;
					reassignedTarget = true;
				case EMeta(_, _):
				default:
					Context.fatalError("Invalid remove() expression!\n\nRemove a component by specifying its type name.", pos);
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
									Context.fatalError("Invalid expression in the Removal array!\n\nPlease only use Component class names.", pos);
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
									Context.fatalError("Invalid expression in the Removal array!\n\nConstruct a Component using 'new' or reuse an existing Component variable.",
										pos);
							}
						}

						continue;
					}

					Context.fatalError("Cannot use more than 2 arrays!\n\nThe first array is used for removal, the second for addition.", pos);
				case EConst(_):
					if (reassignedTarget) {
						Context.fatalError("Cannot target more than 1 Entity!\n\nPlease provide only 1 constant as a target, or leave it off to target the current Entity of the system.",
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
