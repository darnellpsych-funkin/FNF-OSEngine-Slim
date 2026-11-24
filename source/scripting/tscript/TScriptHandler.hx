package scripting.tscript;

import scripting.tscript.TScriptAst;
import scripting.tscript.TScriptInterp;
import scripting.tscript.TScriptParser;

/**
 * One loaded .tscript file. Errors are contained here: a script that fails
 * to load or throws at runtime is logged once and then ignored, so it can
 * never crash the game.
 */
class TScriptHandler {
	public final path:String;
	public final interp:TScriptInterp;
	var failed:Bool = false;

	function new(path:String, interp:TScriptInterp) {
		this.path = path;
		this.interp = interp;
	}

	/** Parse and run a script's top level. Returns null if loading fails. */
	public static function load(path:String, source:String, bind:TScriptInterp->Void):Null<TScriptHandler> {
		var interp = new TScriptInterp();
		bind(interp);
		var handler = new TScriptHandler(path, interp);
		try {
			interp.run(TScriptParser.parseSource(source));
		} catch (e:Dynamic) {
			handler.fail(Std.string(e));
			return null;
		}
		return handler;
	}

	/** Call a function defined by the script, if it exists. Extra arguments are dropped, missing ones are null. */
	public function call(func:String, args:Array<Dynamic>):Void {
		if (failed || !interp.globals.has(func))
			return;
		var fn:Dynamic = interp.globals.get(func);
		var callArgs = args;
		if (Std.isOfType(fn, TScriptFunction)) {
			var def:TScriptFunction = cast fn;
			callArgs = [for (i in 0...def.params.length) i < args.length ? args[i] : null];
		}
		try {
			interp.callValue(fn, callArgs);
		} catch (e:Dynamic) {
			fail(Std.string(e));
		}
	}

	function fail(message:String):Void {
		if (failed)
			return;
		failed = true;
		trace('TScript error in $path: $message');
	}
}
