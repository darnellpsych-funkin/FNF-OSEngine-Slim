package scripting.tscript;

enum TokKind {
	Num;
	Str;
	Id;
	Op;
	Eof;
}

typedef Tok = {
	var kind:TokKind;
	var text:String;
	var num:Float;
	var isInt:Bool;
	var line:Int;
}

/**
 * Tokenizer for the TScript subset supported by the engine.
 *
 * Comments: `#`, `//` and `/* ... *\/`.
 * Strings: double quoted with \n \t \" \\ escapes.
 * Operators are listed in TWO_CHAR_OPS and ONE_CHAR_OPS.
 */
class TScriptLexer {
	static final TWO_CHAR_OPS:Array<String> = ["==", "!=", "<=", ">=", "+=", "-=", "*=", "/="];
	static final ONE_CHAR_OPS:String = "+-*/%<>=()[]{},;.:";

	public static function tokenize(src:String):Array<Tok> {
		var toks:Array<Tok> = [];
		var i = 0;
		var line = 1;
		var n = src.length;

		inline function at(k:Int):String
			return k < n ? src.charAt(k) : "";

		while (i < n) {
			var c = src.charAt(i);

			if (c == "\n") {
				line++;
				i++;
				continue;
			}
			if (c == " " || c == "\t" || c == "\r") {
				i++;
				continue;
			}

			// Comments
			if (c == "#" || (c == "/" && at(i + 1) == "/")) {
				while (i < n && src.charAt(i) != "\n")
					i++;
				continue;
			}
			if (c == "/" && at(i + 1) == "*") {
				i += 2;
				while (i < n && !(src.charAt(i) == "*" && at(i + 1) == "/")) {
					if (src.charAt(i) == "\n")
						line++;
					i++;
				}
				if (i >= n)
					throw 'TScript line $line: unterminated comment';
				i += 2;
				continue;
			}

			// Identifiers and keywords (keywords are plain Id tokens; the parser checks them)
			if (isAlpha(c)) {
				var start = i;
				while (i < n && isAlnum(src.charAt(i)))
					i++;
				toks.push({kind: Id, text: src.substring(start, i), num: 0, isInt: false, line: line});
				continue;
			}

			// Numbers: integers and reals
			if (isDigit(c)) {
				var start = i;
				while (i < n && isDigit(src.charAt(i)))
					i++;
				var isInt = true;
				if (at(i) == "." && isDigit(at(i + 1))) {
					isInt = false;
					i++;
					while (i < n && isDigit(src.charAt(i)))
						i++;
				}
				var text = src.substring(start, i);
				var value = Std.parseFloat(text);
				toks.push({kind: Num, text: text, num: value, isInt: isInt, line: line});
				continue;
			}

			// Strings
			if (c == "\"") {
				var buf = new StringBuf();
				i++;
				while (true) {
					if (i >= n)
						throw 'TScript line $line: unterminated string';
					var d = src.charAt(i);
					if (d == "\"") {
						i++;
						break;
					}
					if (d == "\n")
						throw 'TScript line $line: newline in string';
					if (d == "\\") {
						var e = at(i + 1);
						switch (e) {
							case "n": buf.add("\n");
							case "t": buf.add("\t");
							case "\"": buf.add("\"");
							case "\\": buf.add("\\");
							default: throw 'TScript line $line: bad escape \\$e';
						}
						i += 2;
					} else {
						buf.add(d);
						i++;
					}
				}
				toks.push({kind: Str, text: buf.toString(), num: 0, isInt: false, line: line});
				continue;
			}

			// Two-character operators
			var two = c + at(i + 1);
			if (TWO_CHAR_OPS.indexOf(two) >= 0) {
				toks.push({kind: Op, text: two, num: 0, isInt: false, line: line});
				i += 2;
				continue;
			}

			// One-character operators, groupings and delimiters
			if (ONE_CHAR_OPS.indexOf(c) >= 0) {
				toks.push({kind: Op, text: c, num: 0, isInt: false, line: line});
				i++;
				continue;
			}

			throw 'TScript line $line: unexpected character \'$c\'';
		}

		toks.push({kind: Eof, text: "", num: 0, isInt: false, line: line});
		return toks;
	}

	static inline function isAlpha(c:String):Bool
		return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";

	static inline function isDigit(c:String):Bool
		return c >= "0" && c <= "9";

	static inline function isAlnum(c:String):Bool
		return isAlpha(c) || isDigit(c);
}
