package;

import scripting.tscript.TScriptInterp;
import scripting.tscript.TScriptParser;

/**
 * Standalone tests for the TScript subset.
 * Run: haxe -cp source -cp tests/tscript -main TScriptTest --interp
 */
class TScriptTest {
	static var failures = 0;
	static var passes = 0;

	static function runScript(src:String, ?host:TScriptInterp->Void):Array<String> {
		var lines:Array<String> = [];
		var interp = new TScriptInterp(function(s) lines.push(s));
		if (host != null)
			host(interp);
		interp.run(TScriptParser.parseSource(src));
		return lines;
	}

	static function check(name:String, expected:String, src:String, ?host:TScriptInterp->Void):Void {
		var got:String;
		try {
			got = runScript(src, host).join("\n");
		} catch (e:Dynamic) {
			got = "ERROR: " + Std.string(e);
		}
		if (got == expected) {
			passes++;
		} else {
			failures++;
			Sys.println('FAIL $name\n  expected: ${expected}\n  got:      ${got}');
		}
	}

	static function main() {
		// Arithmetic and printing
		check("arith", "7\n2.5\n-3", "print(1 + 2 * 3);\nprint(5 / 2);\nprint(-(1 + 2));");
		check("int preserved", "3\ntrue", "print(7 % 4);\nprint(2 * 3 == 6);");
		check("string concat", "a1true", "print(\"a\" + 1 + true);");

		// Variables and assignment
		check("vars", "5\n8", "var x = 3;\nx += 2;\nprint(x);\nx *= 2;\nx -= 2;\nprint(x);");

		// If / else
		check("if-else", "yes\nno", "if 2 > 1 then print(\"yes\"); else print(\"no\");\nif 1 > 2 print(\"yes\"); else print(\"no\");");

		// Ranges (half-open) and for loops
		check("range", "0\n1\n2", "for var i in 0:3 do print(i);");
		check("empty range", "", "for var i in 3:3 do print(i);");

		// While with break and continue
		check("while break", "0\n1", "var i = 0;\nwhile i < 10 do { if i == 2 then break; print(i); i += 1; }");
		check("for continue", "0\n2", "for var i in 0:3 do { if i == 1 then continue; print(i); }");

		// Functions, return and closures
		check("function", "7", "function add(a, b) { return a + b; }\nprint(add(3, 4));");
		check("recursion", "120", "function fact(n) { if n <= 1 then return 1; return n * fact(n - 1); }\nprint(fact(5));");
		check("closure", "11", "var base = 10;\nfunction addBase(x) { return x + base; }\nprint(addBase(1));");

		// Arrays
		check("array ops", "3\n[1, 2, 3]\n3", "var a = [];\na.push(1);\na.push(2);\na.push(3);\nprint(a.length);\nprint(a);\nprint(a[2]);");
		check("array index assign", "[9, 2]", "var a = [1, 2];\na[0] = 9;\nprint(a);");

		// Logic and comparison
		check("logic", "true\nfalse", "print(not false and 1 < 2);\nprint(false or false);");

		// Host functions
		check("host fn", "42", "print(answer());", function(i) i.define("answer", function(_) return 42));

		// Errors
		check("undefined var", "ERROR: TScript: undefined name \"nope\"", "print(nope);");
		check("parse error", "ERROR: TScript line 1: expected \";\" but found \"\"", "print(1)");
		check("unterminated string", "ERROR: TScript line 1: unterminated string", "print(\"abc);");

		// Comments
		check("comments", "1", "# hash comment\n// line comment\n/* block\ncomment */ print(1);");

		Sys.println('TScript tests: $passes passed, $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
