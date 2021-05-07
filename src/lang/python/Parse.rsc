module lang::python::Parse

extend lang::python::AST;
import util::ShellExec;
import util::SystemAPI;
import lang::json::IO;
import IO;
import Type;

@synopsis="Installs the ast2json Python library using pip3"
public void installRequirements() {
    println(exec("pip3", args=["install", "ast2json"]));
}

@synopsis="parses a python expression producing an AST of type Expression"
public Expression parsePythonExpression(str input, loc src) {
    json = importAST(input);
    return convertExp(json, src);
}

@synopsis="parses a python statement producing an AST of type Expression"
public Statement parsePythonStatement(str input, loc src) {
    json = importAST(input);
    return convertStat(json, src);
}

@synopsis="parses a python statement producing an AST of type Expression"
public Module parsePythonModule(str input, loc src) {
    json = importAST(input);
    return convertModule(json, src);
}

@synopsis="wraps the python ast library as an external system process"
@description{
    This function starts the python3 interpreter to have access
    to the ast.parse function from Python's standard library.
    The output of the parser is mapped to JSON and then imported
    into a rascal data-structure that can be converted later.

    This function should not be used by clients, but it can
    be called for debugging purposes since it reflects an 
    intermediate stage.
}
node importAST(str input) {
    tempDir = |file:///| + getSystemProperty("java.io.tmpdir");

    pythonParserFile = tempDir + "parsePython.py";
    pythonInputFile = tempDir + "pythonInputFile.py";

    if (!exists(pythonParserFile))
        writeFile(pythonParserFile, pythonParserCode());
    
    writeFile(pythonInputFile, input);

    output = exec("python3", args=[pythonParserFile.path, pythonInputFile.path]);
    
    return parseJSON(#node, output);
}

Module convertModule("object"(_type="Module", body=list[node] body, type_ignores=list[node] type_ignores), loc src) 
    = \module([convertStat(s, src) | s <- body], [convertTypeIgnore(i, src) | i <- type_ignores]);

Module convertModule("object"(_type="Expression", expr=node body), loc src) 
    = \expression(convertExp(body, src));    

Module convertModule("object"(_type="Interactive", body=list[node] body), loc src) 
    = \interactive([convertStat(s, src) | s <- body]);    

Module convertModule("object"(_type="FunctionType", argtypes=list[node] argtypes, expr=node returns), loc src) 
    = \functionType([convertExp(e, src) | e <- argtypes], convertExp(returns, src));

Statement convertStat(node obj:"object"(_type=str typ), loc src) 
    = convertStat(typ, obj, src)
        [src=obj has lineno 
            ? src(0,1,<\int(obj.lineno), \int(obj.col_offset)>,<\int(obj.end_lineno), \int(obj.end_col_offset)>) 
            : src];

Statement convertStat("Expression", node obj, loc src)
    = expr(convertExp(obj, src));

Statement convertStat("FunctionDef",
    node obj:"object"(
        name=str name,
        args=node formals,
        body=list[node] body,
        decorators=list[node] decorators
    ),
    loc src)
    = functionDef(
        id(name), 
        convertArgs(formals, src), 
        [convertStat(s, src) | s <- body], 
        [convertExp(e, src) | e <- decorators], 
        obj.returns? ? just(convertExp(obj.returns, src)) : nothing(),
        obj.typeComment? ? just(obj.typeComment) : nothing()
    );

Expression convertExp(node obj:"object"(_type=str typ), loc src) 
    = convertExp(typ, obj, src)
        [src=obj has lineno 
            ? src(0,1,<\int(obj.lineno), \int(obj.col_offset)>,<\int(obj.end_lineno), \int(obj.end_col_offset)>) 
            : src];

Expression convertExp("Expression", node obj, loc src) = convertExp(obj.body, src);

Expression convertExp("Lambda", "object"(args=node args, body=node body), loc src) 
    = lambda(convertArgs(args, src), convertExp(body, src));

Expression convertExp("BinOp", "object"(op=node op, \left=node lhs, \right=node rhs), loc src) 
    = convertOp(op._type, convertExp(lhs, src), convertExp(rhs, src));

Expression convertExp("UnaryOp", "object"(op=node op, operand=node arg), loc src) 
    = convertOp(op._type, convertExp(arg, src));    

Expression convertExp("Name", "object"(ctx=node c, id=str n), loc src) = name(id(n), convertCtx(c));

Expression convertExp("Call", "object"(func=node f, args=list[node] as, keywords=list[node] kws), loc src) 
    = call(
        convertExp(f, src), 
        [convertExp(a, src) | a <- as], 
        [convertKeyword(kw, src) | kw <- kws] 
    );

Expression convertExp("List", "object"(elts=list[node] elts, ctx=node ctx), loc src) 
    = \list([convertExp(e, src) | e <- elts], convertCtx(ctx));

Expression convertExp("Set", "object"(elts=list[node] elts), loc src) 
    = \set([convertExp(e, src) | e <- elts]);

Expression convertExp("Dict",  "object"(keys=list[node] keys, values=list[node] values), loc src) 
    = \dict([convertExp(e, src) | e <- keys], [convertExp(e, src) | e <- values]);    

Expression convertExp("BoolOp", "object"(op="object"(_type="And"), values=list[node] vs), loc src)
    = and([convertExp(v, src) | v <- vs]);

Expression convertExp("BoolOp", "object"(op="object"(_type="Or"), values=list[node] vs), loc src)
    = and([convertExp(v, src) | v <- vs]);    

Expression convertExp("Constant", "object"(\value=num v), loc src) = constant(number(v), nothing());

Expression convertExp("Constant", "object"(\value=str s), loc src) = constant(string(s), nothing());

Keyword convertKeyword("object"(arg=str i, \value=node v), loc src) = \keyword(id(i), convertExp(v, src));

Expression convertOp("Add", Expression l, Expression r) = add(l, r);
Expression convertOp("Sub", Expression l, Expression r) = sub(l, r);
Expression convertOp("Mult", Expression l, Expression r) = mult(l, r);
Expression convertOp("MatMult", Expression l, Expression r) = matmult(l, r);
Expression convertOp("Mod", Expression l, Expression r) = \mod(l, r);
Expression convertOp("Pow", Expression l, Expression r) = pow(l, r);
Expression convertOp("Div", Expression l, Expression r) = \div(l, r);
Expression convertOp("LShift", Expression l, Expression r) = lshift(l, r);
Expression convertOp("RShift", Expression l, Expression r) = rshift(l, r);
Expression convertOp("BitOr", Expression l, Expression r) = bitor(l, r);
Expression convertOp("BitXor", Expression l, Expression r) = bitxor(l, r);
Expression convertOp("BitAnd", Expression l, Expression r) = bitand(l, r);
Expression convertOp("FloorDiv", Expression l, Expression r) = floordiv(l, r);

Expression convertOp("Invert", Expression a) = invert(a);
Expression convertOp("Not", Expression a) = \not(a);
Expression convertOp("UAdd", Expression a) = uadd(a);
Expression convertOp("USub", Expression a) = usub(a);

ExprContext convertCtx("object"(_type="Load")) = load();

Arguments convertArgs(
    node obj:"object"(
        _type="arguments", 
        posonlyargs=list[node] posonlyargs,
        kwonlyargs=list[node] kwonlyargs,
        args=list[node] args
    ),
    loc src)
    = arguments(
        [convertArg(a, src) | a <- posonlyargs], 
        [convertArg(a, src) | a <- args], 
        obj.vararg? ? just(convertArg(obj.vararg, src)) : nothing(), 
        [convertArg(a, src) | a <- kwonlyargs], 
        obj.kw_defaults? ? [convertExp(e, src) | e <- nodes(obj.kw_defaults)] : [],
        obj.kwarg? ? just(convertArg(obj.kwarg, src)) : nothing(),
        obj.defaults? ? [convertExp(e, src) | e <- nodes(obj.defaults)] : []
    );

Arg convertArg(
    node obj:"object"(
        arg=str a
    ),
    loc src)
    = arg(
        id(a), 
        obj.annotation? ? just(convertExp(obj.annotation, src)) : nothing(),
        obj.type_comment ? just(obj.typeComment) : nothing() 
    )[src=obj has lineno 
            ? src(0,1,<\int(obj.lineno), \int(obj.col_offset)>,<\int(obj.end_lineno), \int(obj.end_col_offset)>) 
            : src];

TypeIgnore convertTypeIgnore("object"(_type="TypeIgnore", lineno=int l, \tag=str t), loc _ /*src*/)
    = typeIgnore(l, t);

private str pythonParserCode()
    = "import io
      'import os
      'import ast
      'import sys
      'from ast2json import ast2json
      'import json
      '
      'with open (sys.argv[1], \"r\") as aFile:
      '   data=aFile.read()
      '
      'theAst = ast.parse(data, mode=\"eval\")
      'theAstAsJson = ast2json(theAst)
      'theJsonAstAsString = json.dumps(theAstAsJson)
      '
      'print(theJsonAstAsString)
      ";

private int \int(value v) = typeCast(#int, v);
private list[node] nodes(value v) = typeCast(#list[nodes], v);