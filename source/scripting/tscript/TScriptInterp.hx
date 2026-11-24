package scripting.tscript;

import scripting.tscript.TScriptAst;

/** Result of executing a statement: normal flow, loop control, or a return value. */
enum Signal {
	SNormal;
	SBreak;
	SContinue;
	SReturn(value:Dynamic);
}

/** A lexical scope. Lookups walk up through the parents. */
class Env {
	public final vars:Map<String, Dynamic> = new Map();
	public final parent:Null<Env>;

	public function new(?parent:Env) {
		this.parent = parent;
	}

	public function has(name:String):Bool {
		var e:Null<Env> = this;
		while (e != null) {
			if (e.vars.exists(name))
				return true;
			e = e.parent;
		}
		return false;
	}

	public function get(name:String):Dynamic {
		var e:Null<Env> = this;
		while (e != null) {
			if (e.vars.exists(name))
				return e.vars.get(name);
			e = e.parent;
		}
		throw 'TScript: undefined variable "$name"';
	}

	public function set(name:String, value:Dynamic):Void {
		var e:Null<Env> = this;
		while (e != null) {
			if (e.vars.exists(name)) {
				e.vars.set(name, value);
				return;
			}
			e = e.parent;
		}
		throw 'TScript: assignment to undefined variable "$name"';
	}
}

/** A user-defined function value. */
class TScriptFunction {
	public final name:String;
	public final params:Array<String>;
	public final body:Stmt;
	public final closure:Env;

	public function new(name:String, params:Array<String>, body:Stmt, closure:Env) {
		this.name = name;
		this.params = params;
		this.body = body;
		this.closure = closure;
	}
}

/** A host (engine-provided) function value. Called with the argument array as-is. */
class TScriptHostFunction {
	public final name:String;
	public final fn:Array<Dynamic>->Dynamic;

	public function new(name:String, fn:Array<Dynamic>->Dynamic) {
		this.name = name;
		this.fn = fn;
	}
}

/**
 * Tree-walking interpreter for the TScript subset.
 *
 * Host integration: register functions with `define`. They are available
 * to scripts by name, e.g. `define("setX", args -> ...)`.
 */
class TScriptInterp {
	public final globals:Env = new Env();
	final hostFunctions:Map<String, TScriptHostFunction> = new Map();

	public function new(?print:String->Void) {
		var out = print != null ? print : defaultPrint;
		define("print", function(args:Array<Dynamic>) {
			var parts:Array<String> = [];
			for (a in args)
				parts.push(stringify(a));
			out(parts.join(" "));
			return null;
		});
	}

	static function defaultPrint(s:String):Void {
		#if sys
		Sys.println(s);
		#else
		trace(s);
		#end
	}

	/** Register a host function callable from scripts. */
	public function define(name:String, fn:Array<Dynamic>->Dynamic):Void {
		hostFunctions.set(name, new TScriptHostFunction(name, fn));
	}

	public function run(stmts:Array<Stmt>):Void {
		for (s in stmts) {
			var sig = exec(s, globals);
			if (sig != SNormal)
				throw 'TScript: "break", "continue" or "return" outside of a loop or function';
		}
	}

	// ----- statements -----

	function exec(s:Stmt, env:Env):Signal {
		switch (s) {
			case VarDecl(name, init):
				env.vars.set(name, init == null ? null : evalExpr(init, env));
				return SNormal;

			case ExprStmt(expr):
				evalExpr(expr, env);
				return SNormal;

			case If(cond, thenBranch, elseBranch):
				if (truthy(evalExpr(cond, env)))
					return exec(thenBranch, env);
				if (elseBranch != null)
					return exec(elseBranch, env);
				return SNormal;

			case While(cond, body):
				while (truthy(evalExpr(cond, env))) {
					var sig = exec(body, env);
					switch (sig) {
						case SBreak: break;
						case SReturn(_): return sig;
						case _:
					}
				}
				return SNormal;

			case ForRange(name, from, to, body):
				var start = toInt(evalExpr(from, env), "range start");
				var end = toInt(evalExpr(to, env), "range end");
				var i = start;
				while (i < end) {
					var loopEnv = new Env(env);
					loopEnv.vars.set(name, i);
					var sig = exec(body, loopEnv);
					switch (sig) {
						case SBreak: break;
						case SReturn(_): return sig;
						case _:
					}
					i++;
				}
				return SNormal;

			case Return(value):
				return SReturn(value == null ? null : evalExpr(value, env));

			case Break:
				return SBreak;

			case Continue:
				return SContinue;

			case Block(stmts):
				var inner = new Env(env);
				for (st in stmts) {
					var sig = exec(st, inner);
					if (sig != SNormal)
						return sig;
				}
				return SNormal;

			case FuncDecl(name, params, body):
				env.vars.set(name, new TScriptFunction(name, params, body, env));
				return SNormal;
		}
	}

	// ----- expressions -----

	function evalExpr(e:Expr, env:Env):Dynamic {
		switch (e) {
			case Lit(value):
				return value;

			case Ident(name):
				if (env.has(name))
					return env.get(name);
				if (hostFunctions.exists(name))
					return hostFunctions.get(name);
				throw 'TScript: undefined name "$name"';

			case ArrayLit(items):
				var arr:Array<Dynamic> = [];
				for (item in items)
					arr.push(evalExpr(item, env));
				return arr;

			case Unary(op, operand):
				var v = evalExpr(operand, env);
				return switch (op) {
					case "-": negate(v);
					case "not": !truthy(v);
					case _: throw 'TScript: unknown unary "$op"';
				}

			case Binary(op, left, right):
				// Short-circuit logical operators
				if (op == "and") {
					var l = evalExpr(left, env);
					return truthy(l) ? evalExpr(right, env) : l;
				}
				if (op == "or") {
					var l = evalExpr(left, env);
					return truthy(l) ? l : evalExpr(right, env);
				}
				return binary(op, evalExpr(left, env), evalExpr(right, env));

			case Assign(target, op, value):
				var rhs = evalExpr(value, env);
				var result = op == "=" ? rhs : binary(op.substr(0, 1), evalExpr(target, env), rhs);
				assignTo(target, result, env);
				return result;

			case Call(callee, args):
				return evalCall(callee, args, env);

			case Index(obj, idx):
				var container = evalExpr(obj, env);
				var key = evalExpr(idx, env);
				if (Std.isOfType(container, Array)) {
					var arr:Array<Dynamic> = cast container;
					var i = toInt(key, "array index");
					if (i < 0 || i >= arr.length)
						throw 'TScript: index $i out of range';
					return arr[i];
				}
				throw 'TScript: value cannot be indexed';

			case Member(obj, name):
				var target = evalExpr(obj, env);
				if (name == "length") {
					if (Std.isOfType(target, Array))
						return (cast target : Array<Dynamic>).length;
					if (Std.isOfType(target, String))
						return (cast target : String).length;
				}
				throw 'TScript: no member "$name"';
		}
	}

	function evalCall(callee:Expr, args:Array<Expr>, env:Env):Dynamic {
		// Method calls on arrays
		switch (callee) {
			case Member(obj, method):
				var target = evalExpr(obj, env);
				if (Std.isOfType(target, Array)) {
					var arr:Array<Dynamic> = cast target;
					var argValues = [for (a in args) evalExpr(a, env)];
					switch (method) {
						case "push":
							for (v in argValues)
								arr.push(v);
							return arr.length;
						case "pop":
							if (arr.length == 0)
								throw 'TScript: pop from empty array';
							return arr.pop();
						case _:
							throw 'TScript: array has no method "$method"';
					}
				}
				throw 'TScript: value has no method "$method"';
			case _:
		}

		var fn = evalExpr(callee, env);
		var argValues = [for (a in args) evalExpr(a, env)];
		return callValue(fn, argValues);
	}

	public function callValue(fn:Dynamic, argValues:Array<Dynamic>):Dynamic {
		if (Std.isOfType(fn, TScriptFunction)) {
			var f:TScriptFunction = cast fn;
			if (argValues.length != f.params.length)
				throw 'TScript: function "${f.name}" expects ${f.params.length} argument(s), got ${argValues.length}';
			var callEnv = new Env(f.closure);
			for (i in 0...f.params.length)
				callEnv.vars.set(f.params[i], argValues[i]);
			return switch (exec(f.body, callEnv)) {
				case SReturn(v): v;
				case _: null;
			}
		}
		if (Std.isOfType(fn, TScriptHostFunction)) {
			var h:TScriptHostFunction = cast fn;
			return h.fn(argValues);
		}
		throw 'TScript: value is not callable';
	}

	function assignTo(target:Expr, value:Dynamic, env:Env):Void {
		switch (target) {
			case Ident(name):
				env.set(name, value);
			case Index(obj, idx):
				var container = evalExpr(obj, env);
				var key = evalExpr(idx, env);
				if (Std.isOfType(container, Array)) {
					var arr:Array<Dynamic> = cast container;
					var i = toInt(key, "array index");
					if (i < 0 || i >= arr.length)
						throw 'TScript: index $i out of range';
					arr[i] = value;
				} else {
					throw 'TScript: value cannot be assigned by index';
				}
			case _:
				throw 'TScript: invalid assignment target';
		}
	}

	// ----- helpers -----

	static function truthy(v:Dynamic):Bool {
		if (v == null)
			return false;
		if (Std.isOfType(v, Bool))
			return v;
		throw 'TScript: condition must be a boolean';
	}

	static function negate(v:Dynamic):Dynamic {
		if (isNumber(v))
			return -v;
		throw 'TScript: cannot negate a non-number';
	}

	static function binary(op:String, a:Dynamic, b:Dynamic):Dynamic {
		switch (op) {
			case "+":
				if (Std.isOfType(a, String) || Std.isOfType(b, String))
					return stringify(a) + stringify(b);
				return numeric(op, a, b);
			case "-", "*", "%":
				return numeric(op, a, b);
			case "/":
				// Division always yields a real number
				requireNumbers(op, a, b);
				return (a : Float) / (b : Float);
			case "==":
				return equal(a, b);
			case "!=":
				return !equal(a, b);
			case "<", ">", "<=", ">=":
				return compare(op, a, b);
			case _:
				throw 'TScript: unknown operator "$op"';
		}
	}

	static function numeric(op:String, a:Dynamic, b:Dynamic):Dynamic {
		requireNumbers(op, a, b);
		var bothInt = Std.isOfType(a, Int) && Std.isOfType(b, Int);
		var x:Float = a;
		var y:Float = b;
		var r:Float = switch (op) {
			case "+": x + y;
			case "-": x - y;
			case "*": x * y;
			case "%": x % y;
			case _: throw 'TScript: unknown operator "$op"';
		}
		return bothInt ? Std.int(r) : r;
	}

	static function compare(op:String, a:Dynamic, b:Dynamic):Bool {
		if (isNumber(a) && isNumber(b)) {
			var x:Float = a;
			var y:Float = b;
			return switch (op) {
				case "<": x < y;
				case ">": x > y;
				case "<=": x <= y;
				case _: x >= y;
			}
		}
		if (Std.isOfType(a, String) && Std.isOfType(b, String)) {
			var x:String = a;
			var y:String = b;
			return switch (op) {
				case "<": x < y;
				case ">": x > y;
				case "<=": x <= y;
				case _: x >= y;
			}
		}
		throw 'TScript: cannot compare these values with "$op"';
	}

	static function equal(a:Dynamic, b:Dynamic):Bool {
		if (isNumber(a) && isNumber(b))
			return (a : Float) == (b : Float);
		return a == b;
	}

	static function requireNumbers(op:String, a:Dynamic, b:Dynamic):Void {
		if (!isNumber(a) || !isNumber(b))
			throw 'TScript: operator "$op" needs numbers';
	}

	static inline function isNumber(v:Dynamic):Bool
		return Std.isOfType(v, Int) || Std.isOfType(v, Float);

	static function toInt(v:Dynamic, what:String):Int {
		if (Std.isOfType(v, Int))
			return v;
		if (Std.isOfType(v, Float) && Math.floor(v) == v)
			return Std.int(v);
		throw 'TScript: $what must be an integer';
	}

	public static function stringify(v:Dynamic):String {
		if (v == null)
			return "null";
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = cast v;
			return "[" + [for (x in arr) stringify(x)].join(", ") + "]";
		}
		if (Std.isOfType(v, Bool))
			return v ? "true" : "false";
		return Std.string(v);
	}
}
