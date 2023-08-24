package peach;

import peach.Component.ComponentID;
import haxe.macro.Type.ClassType;
import haxe.macro.Expr;
import haxe.macro.Expr.FunctionArg;
import haxe.macro.Expr.Field;
import haxe.macro.Context;

using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;

class Macros {
	static inline final PEACH_ID = "_peach_id";

	static var lastComponentID: ComponentID = 0;

	static function getFullName(ct: ClassType) {
		return '${ct.pack.join(".")}.${ct.name}';
	}

	public static function getComponentID(t: haxe.macro.Type): Null<ComponentID> {
		switch (t) {
			case TInst(t, _):
				final ct = t.get();
				final meta = ct.meta.extract(PEACH_ID)[0];

				if (meta != null) {
					final param = meta.params[0];

					switch (param.expr) {
						case EConst(CInt(v, _)):
							return Std.parseInt(v);
						default:
							return null;
					}
				}

				return null;
			default:
				return null;
		}
	}

	static function addCtor(pos: Position, exprs: Array<Expr>, ?args: Array<FunctionArg>): Field {
		return {
			name: "new",
			pos: pos,
			access: [APublic],
			kind: FFun({
				args: args ?? [],
				expr: macro $b{exprs},
				params: [],
				ret: null
			})
		}
	}

	public static macro function buildSystem(): Array<Field> {
		final buildFields = Context.getBuildFields();
		final pos = Context.currentPos();

		if (buildFields.length == 0) {
			Context.fatalError("Empty System", pos);
		}

		final ctorExprs: Array<Expr> = [];
		var hasUpdate = false;
		var hasAll = false;
		var hasInit = false;

		for (f in buildFields) {
			final declrPos = f.pos;

			// TODO: track unused instead
			switch (f.kind) {
				case FVar(_, e):
					f.meta.push({name: ":nullSafety", params: [macro Off], pos: declrPos});
				default:
			}

			if (f.name == "init") {
				switch (f.kind) {
					case FFun(f):
						if (f.args.length > 0) {
							Context.fatalError("init() cannot take arguments!", declrPos);
						}

						hasInit = true;
					default:
						Context.fatalError("init must be a function!", declrPos);
				}
			}
		}

		for (f in buildFields) {
			final declrPos = f.pos;

			if (f.name == "update") {
				switch (f.kind) {
					case FFun(f):
						hasUpdate = true;

						final argExprs = [for (i in 0...f.args.length) macro cast args[$v{i}]];

						var runExpr: Expr;

						if (hasInit) {
							runExpr = macro {
								if (!_initCalled) {
									init();
									_initCalled = true;
								}

								update($a{argExprs});
							}
						} else {
							runExpr = macro {
								update($a{argExprs});
							}
						}

						buildFields.push({
							name: "run",
							pos: pos,
							kind: FFun({
								args: [
									{
										name: "args",
										type: macro : haxe.Rest<Any>
									}
								],
								expr: runExpr
							})
						});
					default:
				}
			}

			if (f.name == "all") {
				hasAll = true;
				switch (f.kind) {
					case FFun(f):
						final compIDs = new Array<ComponentID>();
						final args = f.args;

						if (args.length == 0) {
							Context.fatalError("all() has zero parameters", declrPos);
						}

						var a: FunctionArg;

						var lastCompIndex = 0;

						while (lastCompIndex < args.length) {
							final a = args[lastCompIndex];
							final t = a.type.toType();
							final id = getComponentID(t);

							if (id == null) {
								break;
							}

							compIDs.push(id);

							lastCompIndex++;
						}

						if (compIDs.length == 0) {
							Context.fatalError("all() has no Component parameters!", pos);
						}

						final exprs = [];

						for (id in compIDs) {
							exprs.push(macro @:privateAccess cast _world.comps.get(entityID, $v{id}));
						}

						final remainingCount = args.length - lastCompIndex;
						for (i in 0...remainingCount) {
							exprs.push(macro cast args[$v{i}]);
						}

						var runExpr: Expr;

						if (hasInit) {
							runExpr = macro {
								@:privateAccess
								final matching = _world.comps.getMatching($v{compIDs});

								if (!_initCalled) {
									init();
									_initCalled = true;
								}

								for (entityID in matching) {
									this.entityID = entityID;

									all($a{exprs});
								}
							}
						} else {
							runExpr = macro {
								@:privateAccess
								final matching = _world.comps.getMatching($v{compIDs});

								for (entityID in matching) {
									this.entityID = entityID;

									all($a{exprs});
								}
							}
						}

						buildFields.push({
							name: "run",
							pos: pos,
							kind: FFun({
								args: [
									{
										name: "args",
										type: macro : haxe.Rest<Any>
									}
								],
								expr: runExpr
							})
						});

						ctorExprs.push(macro $p{["this", "allCompIDs"]} = $v{compIDs});
					default:
				}
			}
		}

		if (hasUpdate && hasAll) {
			Context.fatalError("A System cannot have both an update() and an all(..) function!", pos);
		}

		buildFields.push(addCtor(pos, ctorExprs));

		final ct = Context.getLocalClass().get();

		Context.onAfterTyping((modules) -> {
			for (m in modules) {
				switch (m) {
					case TClassDecl(c):
						final c = c.get();
					default:
				}
			}
		});

		return buildFields;
	}

	public static macro function buildComponent(): Array<Field> {
		final t = Context.getLocalType();
		final buildFields = Context.getBuildFields();
		final pos = Context.currentPos();

		var ctor: Null<Field>;
		var onlyPrivate = buildFields.length > 0;

		for (f in buildFields) {
			if (f.access.contains(APublic)) {
				onlyPrivate = false;
			}

			if (f.name == "new") {
				ctor = f;
			}
		}

		if (ctor == null) {
			final args: Array<FunctionArg> = [];

			final assignments = [macro $p{["this", PEACH_ID]} = $v{lastComponentID}];

			for (f in buildFields) {
				final name = f.name;

				switch (f.kind) {
					case FVar(t, e) | FProp(_, _, t, e):
						args.push({
							name: name,
							type: t,
							opt: e != null && !f.access.contains(AFinal),
							value: e
						});
						assignments.push(macro $p{["this", name]} = cast $i{name});
					default:
				}
			}

			buildFields.push(addCtor(Context.currentPos(), assignments, args));
		} else {
			switch (ctor.kind) {
				case FFun(f):
					switch (f.expr.expr) {
						case EBlock(exprs):
							exprs.push(macro $p{["this", PEACH_ID]} = $v{lastComponentID});
						default:
					}
				default:
			}
		}

		var noForcedAccess = true;
		var name: String;

		switch (t) {
			case TInst(t, _):
				final ct = t.get();

				name = ct.name;
				noForcedAccess = !ct.meta.has("pForcedAccess");

				ct.meta.add(PEACH_ID, [macro $v{lastComponentID}], ct.pos);
			default:
		}

		if (noForcedAccess && onlyPrivate) {
			Context.fatalError('Component only contains private fields!\n\nIf this is intentional (e.g.: for Access Control usage), please add the @pForcedAccess metadata above the class:\n\n@pForcedAccess\nclass $name extends Component {',
				pos);
		}
		lastComponentID++;
		return buildFields;
	}

	public static macro function buildEntity(): Array<Field> {
		final buildFields = Context.getBuildFields();
		var ctor: Null<Field>;

		for (f in buildFields) {
			if (f.name == "new") {
				ctor = f;
				break;
			}
		}

		if (ctor == null) {
			Context.fatalError("Missing constructor.\n\nFor an empty entity, try adding\npublic function new() { super(); }", Context.currentPos());
		}

		final componentIDs = new Array<ComponentID>();
		var ctorBlock: Array<Expr>;

		switch (ctor.kind) {
			case FFun(f):
				final types = f.args.map(a -> a.type.toType());

				for (t in types) {
					final id = getComponentID(t);

					if (id != null) {
						componentIDs.push(id);
					}
				}

				switch (f.expr.expr) {
					case EBlock(exprs):
						ctorBlock = exprs;
					default:
				}
			default:
		}

		for (e in ctorBlock) {
			switch (e.expr) {
				case ECall(e, params):

				default:
			}
		}

		return buildFields;
	}
}
