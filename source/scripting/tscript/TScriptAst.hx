package scripting.tscript;

enum Expr {
	Lit(value:Dynamic);
	Ident(name:String);
	ArrayLit(items:Array<Expr>);
	Unary(op:String, operand:Expr);
	Binary(op:String, left:Expr, right:Expr);
	Assign(target:Expr, op:String, value:Expr);
	Call(callee:Expr, args:Array<Expr>);
	Index(obj:Expr, index:Expr);
	Member(obj:Expr, name:String);
}

enum Stmt {
	VarDecl(name:String, init:Null<Expr>);
	ExprStmt(expr:Expr);
	If(cond:Expr, thenBranch:Stmt, elseBranch:Null<Stmt>);
	While(cond:Expr, body:Stmt);
	ForRange(name:String, from:Expr, to:Expr, body:Stmt);
	Return(value:Null<Expr>);
	Break;
	Continue;
	Block(stmts:Array<Stmt>);
	FuncDecl(name:String, params:Array<String>, body:Stmt);
}
