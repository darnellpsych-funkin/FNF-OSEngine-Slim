package scripting.tscript;

import scripting.tscript.TScriptAst;
import scripting.tscript.TScriptLexer;

/**
 * Recursive-descent parser for the TScript subset.
 *
 * Precedence (low to high): or, and, equality, comparison, additive,
 * multiplicative, unary (-, not), postfix (call, index, member), primary.
 */
class TScriptParser {
	var toks:Array<Tok>;
	var pos:Int = 0;

	public function new(toks:Array<Tok>) {
		this.toks = toks;
	}

	public static function parseSource(src:String):Array<Stmt> {
		var parser = new TScriptParser(TScriptLexer.tokenize(src));
		return parser.parseProgram();
	}

	public function parseProgram():Array<Stmt> {
		var stmts:Array<Stmt> = [];
		while (peek().kind != Eof)
			stmts.push(parseStatement());
		return stmts;
	}

	// ----- token helpers -----

	inline function peek():Tok
		return toks[pos];

	function advance():Tok {
		var t = toks[pos];
		if (t.kind != Eof)
			pos++;
		return t;
	}

	function isOp(text:String):Bool
		return peek().kind == Op && peek().text == text;

	function isWord(text:String):Bool
		return peek().kind == Id && peek().text == text;

	function expectOp(text:String):Void {
		if (!isOp(text))
			fail('expected "$text" but found "${peek().text}"');
		advance();
	}

	function expectId():String {
		if (peek().kind != Id)
			fail('expected identifier but found "${peek().text}"');
		return advance().text;
	}

	function fail(msg:String):Dynamic
		throw 'TScript line ${peek().line}: $msg';

	// ----- statements -----

	function parseStatement():Stmt {
		if (isWord("var")) {
			advance();
			var name = expectId();
			var init:Null<Expr> = null;
			if (isOp("=")) {
				advance();
				init = parseExpr();
			}
			expectOp(";");
			return VarDecl(name, init);
		}

		if (isWord("function")) {
			advance();
			var name = expectId();
			var params = parseParamList();
			var body = parseBlock();
			return FuncDecl(name, params, body);
		}

		if (isWord("if")) {
			advance();
			var cond = parseExpr();
			if (isWord("then"))
				advance();
			var thenBranch = parseStatement();
			var elseBranch:Null<Stmt> = null;
			if (isWord("else")) {
				advance();
				elseBranch = parseStatement();
			}
			return If(cond, thenBranch, elseBranch);
		}

		if (isWord("while")) {
			advance();
			var cond = parseExpr();
			if (isWord("do"))
				advance();
			return While(cond, parseStatement());
		}

		if (isWord("for")) {
			advance();
			if (isWord("var"))
				advance();
			var name = expectId();
			if (!isWord("in"))
				fail('expected "in" after loop variable');
			advance();
			var from = parseExpr();
			expectOp(":");
			var to = parseExpr();
			if (isWord("do"))
				advance();
			return ForRange(name, from, to, parseStatement());
		}

		if (isWord("return")) {
			advance();
			var value:Null<Expr> = null;
			if (!isOp(";"))
				value = parseExpr();
			expectOp(";");
			return Return(value);
		}

		if (isWord("break")) {
			advance();
			expectOp(";");
			return Break;
		}

		if (isWord("continue")) {
			advance();
			expectOp(";");
			return Continue;
		}

		if (isOp("{"))
			return parseBlock();

		// Expression or assignment statement
		var expr = parseExpr();
		if (isAssignOp()) {
			var op = advance().text;
			var value = parseExpr();
			expr = Assign(expr, op, value);
		}
		expectOp(";");
		return ExprStmt(expr);
	}

	function isAssignOp():Bool
		return peek().kind == Op && (peek().text == "=" || peek().text == "+=" || peek().text == "-=" || peek().text == "*=" || peek().text == "/=");

	function parseBlock():Stmt {
		expectOp("{");
		var stmts:Array<Stmt> = [];
		while (!isOp("}")) {
			if (peek().kind == Eof)
				fail('unterminated block');
			stmts.push(parseStatement());
		}
		advance();
		return Block(stmts);
	}

	function parseParamList():Array<String> {
		expectOp("(");
		var params:Array<String> = [];
		if (!isOp(")")) {
			params.push(expectId());
			while (isOp(",")) {
				advance();
				params.push(expectId());
			}
		}
		expectOp(")");
		return params;
	}

	// ----- expressions -----

	public function parseExpr():Expr
		return parseOr();

	function parseOr():Expr {
		var left = parseAnd();
		while (isWord("or")) {
			advance();
			left = Binary("or", left, parseAnd());
		}
		return left;
	}

	function parseAnd():Expr {
		var left = parseEquality();
		while (isWord("and")) {
			advance();
			left = Binary("and", left, parseEquality());
		}
		return left;
	}

	function parseEquality():Expr {
		var left = parseComparison();
		while (isOp("==") || isOp("!=")) {
			var op = advance().text;
			left = Binary(op, left, parseComparison());
		}
		return left;
	}

	function parseComparison():Expr {
		var left = parseAdditive();
		while (isOp("<") || isOp(">") || isOp("<=") || isOp(">=")) {
			var op = advance().text;
			left = Binary(op, left, parseAdditive());
		}
		return left;
	}

	function parseAdditive():Expr {
		var left = parseMultiplicative();
		while (isOp("+") || isOp("-")) {
			var op = advance().text;
			left = Binary(op, left, parseMultiplicative());
		}
		return left;
	}

	function parseMultiplicative():Expr {
		var left = parseUnary();
		while (isOp("*") || isOp("/") || isOp("%")) {
			var op = advance().text;
			left = Binary(op, left, parseUnary());
		}
		return left;
	}

	function parseUnary():Expr {
		if (isOp("-")) {
			advance();
			return Unary("-", parseUnary());
		}
		if (isWord("not")) {
			advance();
			return Unary("not", parseUnary());
		}
		return parsePostfix();
	}

	function parsePostfix():Expr {
		var expr = parsePrimary();
		while (true) {
			if (isOp("(")) {
				advance();
				var args:Array<Expr> = [];
				if (!isOp(")")) {
					args.push(parseExpr());
					while (isOp(",")) {
						advance();
						args.push(parseExpr());
					}
				}
				expectOp(")");
				expr = Call(expr, args);
			} else if (isOp("[")) {
				advance();
				var index = parseExpr();
				expectOp("]");
				expr = Index(expr, index);
			} else if (isOp(".")) {
				advance();
				expr = Member(expr, expectId());
			} else {
				break;
			}
		}
		return expr;
	}

	function parsePrimary():Expr {
		var t = peek();
		switch (t.kind) {
			case Num:
				advance();
				return Lit(t.isInt ? Std.int(t.num) : t.num);
			case Str:
				advance();
				return Lit(t.text);
			case Id:
				advance();
				return switch (t.text) {
					case "true": Lit(true);
					case "false": Lit(false);
					case "null": Lit(null);
					case _: Ident(t.text);
				}
			case Op:
				if (t.text == "(") {
					advance();
					var inner = parseExpr();
					expectOp(")");
					return inner;
				}
				if (t.text == "[") {
					advance();
					var items:Array<Expr> = [];
					if (!isOp("]")) {
						items.push(parseExpr());
						while (isOp(",")) {
							advance();
							items.push(parseExpr());
						}
					}
					expectOp("]");
					return ArrayLit(items);
				}
				return fail('unexpected "${t.text}"');
			case Eof:
				return fail('unexpected end of input');
		}
	}
}
