%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
% This module handles code generation for "simple" unifications,
% i.e. those unifications which are simple enough for us to generate
% inline code.
%
% For "complicated" unifications, we generate a call to an out-of-line
% unification predicate (the call is handled in call_gen.nl) - and then
% eventually generate the out-of-line code (unify_proc.nl).
%
%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- module unify_gen.

:- interface.

:- import_module list, hlds, llds, code_info, code_util.

	% Generate code for an assignment unification.
	% (currently implemented as a cached assignment).
:- pred unify_gen__generate_assignment(var, var, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_assignment(in, in, out, in, out) is det.

	% Generate a construction unification
:- pred unify_gen__generate_construction(var, cons_id,
				list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_construction(in, in, in, in, out, in, out) is det.

:- pred unify_gen__generate_det_deconstruction(var, cons_id,
				list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_det_deconstruction(in, in, in, in, out,
							in, out) is det.

:- pred unify_gen__generate_semi_deconstruction(var, cons_id,
				list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_deconstruction(in, in, in, in, out,
							in, out) is det.

:- pred unify_gen__generate_test(var, var, code_tree, code_info, code_info).
:- mode unify_gen__generate_test(in, in, out, in, out) is det.

:- pred unify_gen__generate_tag_test(var, cons_id, code_tree,
						code_info, code_info).
:- mode unify_gen__generate_tag_test(in, in, out, in, out) is det.

:- pred unify_gen__generate_tag_rval(var, cons_id, rval, code_tree,
						code_info, code_info).
:- mode unify_gen__generate_tag_rval(in, in, out, out, in, out) is det.

%---------------------------------------------------------------------------%
:- implementation.

:- import_module string, tree, int, map, require, std_util.
:- import_module prog_io, mode_util, hlds_out.

:- type uni_val		--->	ref(var)
			;	lval(lval).

%---------------------------------------------------------------------------%

	% assignment unifications are generated by simply caching the
	% bound variable as the expression that generates the free
	% variable. No immediate code is generated.

unify_gen__generate_assignment(VarA, VarB, empty) -->
	(
		code_info__variable_is_live(VarA)
	->
		code_info__cache_expression(VarA, var(VarB))
	;
		% For free-free unifications, the mode analysis reports
		% them as assignment to the dead variable.  For such
		% unifications we of course don't generate any code
		{ true }
	).

%---------------------------------------------------------------------------%

	% A [simple] test unification is generated by flushing both
	% variables from the cache, and producing code that branches
	% to the fall-through point if the two values are not the same.
	% Simple tests are in-in unifications on enumerations, integers,
	% strings and floats. XXX handle floats.

unify_gen__generate_test(VarA, VarB, Code) -->
	code_info__produce_variable(VarA, Code0, ValA),
	code_info__produce_variable(VarB, Code1, ValB),
	{ CodeA = tree(Code0, Code1) },
	code_info__generate_test_and_fail(
			binop(eq, ValA, ValB), FailCode),
	{ Code = tree(CodeA, FailCode) }.

%---------------------------------------------------------------------------%

unify_gen__generate_tag_test(Var, ConsId, Code) -->
	code_info__produce_variable(Var, VarCode, Rval),
	code_info__variable_to_string(Var, VarName),
	{ hlds_out__cons_id_to_string(ConsId, ConsIdName) },
	{ string__append_list(["checking that ", VarName,
			" has functor ", ConsIdName], Comment) },
	{ CommentCode = node([comment(Comment) - ""]) },
	code_info__cons_id_to_tag(Var, ConsId, Tag),
	{ unify_gen__generate_tag_rval_2(Tag, Rval, TestRval) },
	code_info__generate_test_and_fail(TestRval, TestCode),
	{ Code = tree(VarCode, tree(CommentCode, TestCode)) }.

%---------------------------------------------------------------------------%

unify_gen__generate_tag_rval(Var, ConsId, TestRval, Code) -->
        code_info__produce_variable(Var, Code, Rval),
	code_info__cons_id_to_tag(Var, ConsId, Tag),
	{ unify_gen__generate_tag_rval_2(Tag, Rval, TestRval) }.

:- pred unify_gen__generate_tag_rval_2(cons_tag, rval, rval).
:- mode unify_gen__generate_tag_rval_2(in, in, out) is det.

unify_gen__generate_tag_rval_2(string_constant(String), Rval, TestRval) :-
	TestRval = binop(str_eq, Rval, const(string_const(String))).
unify_gen__generate_tag_rval_2(float_constant(_String), _, _) :-
	error("Sorry, float tests not implemented").
unify_gen__generate_tag_rval_2(int_constant(Int), Rval, TestRval) :-
	TestRval = binop(eq, Rval, const(int_const(Int))).
unify_gen__generate_tag_rval_2(pred_constant(_, _), _Rval, _TestRval) :-
	% XXX We should report a proper error message rather than just aborting
	error("Attempted higher-order unification").
unify_gen__generate_tag_rval_2(simple_tag(SimpleTag), Rval, TestRval) :-
	TestRval = binop(eq,	unop(tag, Rval),
				unop(mktag, const(int_const(SimpleTag)))).
unify_gen__generate_tag_rval_2(complicated_tag(Bits, Num), Rval, TestRval) :-
	TestRval = binop(and,
			binop(eq,	unop(tag, Rval),
					unop(mktag, const(int_const(Bits)))), 
			binop(eq,	lval(field(Bits, Rval,
						const(int_const(0)))),
					const(int_const(Num)))).
unify_gen__generate_tag_rval_2(complicated_constant_tag(Bits, Num), Rval,
		TestRval) :-
	TestRval = binop(eq,	Rval,
			mkword(Bits, unop(mkbody, const(int_const(Num))))).

%---------------------------------------------------------------------------%

	% A construction unification consists of a heap-increment to
	% create a term, and a series of [optional] assignments to
	% instantiate the arguments of that term.

	% The current implementation generates the construction
	% in an eager manner.

unify_gen__generate_construction(Var, Cons, Args, Modes, Code) -->
	code_info__cons_id_to_tag(Var, Cons, Tag),
	unify_gen__generate_construction_2(Tag, Var, Args, Modes, Code).

:- pred unify_gen__generate_construction_2(cons_tag, var, 
					list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_construction_2(in, in, in, in, out,
					in, out) is det.

unify_gen__generate_construction_2(string_constant(String),
		Var, _Args, _Modes, Code) -->
	{ Code = empty },
	code_info__cache_expression(Var, const(string_const(String))).
unify_gen__generate_construction_2(int_constant(Int),
		Var, _Args, _Modes, Code) -->
	{ Code = empty },
	code_info__cache_expression(Var, const(int_const(Int))).
unify_gen__generate_construction_2(float_constant(_Float),
		_Var, _Args, _Modes, _Code) -->
	{ error("Float constructions unimplemented") }.
unify_gen__generate_construction_2(simple_tag(SimpleTag),
		Var, Args, Modes, Code) -->
	code_info__get_module_info(ModuleInfo),
	code_info__get_next_label_number(LabelCount),
	{ unify_gen__generate_cons_args(Args, ModuleInfo, Modes, RVals) },
	code_info__cache_expression(Var, create(SimpleTag, RVals, LabelCount)),
		% we need to flush the expression immediately,
		% since the expression cache doesn't handle the
		% dependencies in create expressions
	code_info__produce_variable(Var, Code, _).
unify_gen__generate_construction_2(complicated_tag(Bits0, Num0),
		Var, Args, Modes, Code) -->
	code_info__get_module_info(ModuleInfo),
	code_info__get_next_label_number(LabelCount),
	{ unify_gen__generate_cons_args(Args, ModuleInfo, Modes, RVals0) },
		% the first field holds the secondary tag
	{ RVals = [yes(const(int_const(Num0))) | RVals0] },
	code_info__cache_expression(Var, create(Bits0, RVals, LabelCount)),
		% we need to flush the expression immediately,
		% since the expression cache doesn't handle the
		% dependencies in create expressions
	code_info__produce_variable(Var, Code, _).
unify_gen__generate_construction_2(complicated_constant_tag(Bits1, Num1),
		Var, _Args, _Modes, Code) -->
	{ Code = empty },
	code_info__cache_expression(Var,
		mkword(Bits1, unop(mkbody, const(int_const(Num1))))).
unify_gen__generate_construction_2(pred_constant(PredId, ProcId),
		Var, Args, _Modes, Code) -->
	code_info__get_module_info(ModuleInfo),
	{ module_info_preds(ModuleInfo, Preds) },
	{ map__lookup(Preds, PredId, PredInfo) },
	{ list__length(Args, NumArgs) },
	{ pred_info_name(PredInfo, PredName) },
	( { PredName = "call", Args = [CallPred | CallArgs] } ->
		%
		% We need to handle
		%	P = call(P0, ...)
		% as a special case.
		%
		code_info__get_next_label(LoopEnd),
		code_info__get_next_label(LoopStart),
		code_info__get_free_register(LoopCounter),
		code_info__get_free_register(NumOldArgs),
		code_info__get_free_register(NewClosure),
		{ NumOldArgsReg = reg(NumOldArgs) },
		{ LoopCounterReg = reg(LoopCounter) },
		{ NewClosureReg = reg(NewClosure) },
		{ Zero = const(int_const(0)) },
		{ One = const(int_const(1)) },
		{ list__length(CallArgs, NumNewArgs) },
		{ NumNewArgs_Rval = const(int_const(NumNewArgs)) },
		{ NumNewArgsPlusTwo is NumNewArgs + 2 },
		{ NumNewArgsPlusTwo_Rval =
			const(int_const(NumNewArgsPlusTwo)) },
		code_info__produce_variable(CallPred, Code1, OldClosure),
		{ Code2 = node([
			comment("build new closure from old closure") - "",
			assign(NumOldArgsReg,
				lval(field(0, OldClosure, Zero)))
				- "get number of arguments",
			assign(NewClosureReg, heap_alloc(
				binop(+, OldClosure,
				NumNewArgsPlusTwo_Rval)))
				- "allocate new closure",
			assign(field(0, lval(NewClosureReg), Zero),
				binop(+, lval(NumOldArgsReg), NumNewArgs_Rval))
				- "set new number of arguments",
			assign(LoopCounterReg, Zero)
				- "initialize loop counter",
			label(LoopStart) - "start of loop",
			assign(LoopCounterReg,
				binop(+, lval(LoopCounterReg), One))
				- "increment loop counter",
			assign(field(0, lval(NewClosureReg),
					lval(LoopCounterReg)),
				lval(field(0, OldClosure,
					lval(LoopCounterReg))))
				- "copy old field",
			if_val(binop(<, lval(LoopCounterReg),
				lval(NumOldArgsReg)), label(LoopStart))
				- "repeat the loop?",
			label(LoopEnd) - "end of loop"
		]) },
		{ unify_gen__generate_extra_closure_args(CallArgs,
			LoopCounterReg, NewClosureReg, Code3) },
		{ Code = tree(Code1, tree(Code2, Code3)) },
		{ Value = lval(NewClosureReg) }
	;
		{ Code = empty },
		{ pred_info_procedures(PredInfo, Procs) },
		{ map__lookup(Procs, ProcId, ProcInfo) },
		{ proc_info_arg_info(ProcInfo, ArgInfo) },
		{ code_util__make_entry_label(ModuleInfo, PredId, ProcId,
				CodeAddress) },
		code_info__get_next_label_number(LabelCount),
		{ unify_gen__generate_pred_args(Args, ArgInfo, PredArgs) },
		{ Vector = [yes(const(int_const(NumArgs))),
				yes(const(pred_const(CodeAddress))) | PredArgs] },
		{ Value = create(0, Vector, LabelCount) }
	),
	code_info__cache_expression(Var, Value).

:- pred unify_gen__generate_extra_closure_args(list(var), lval, lval, code_tree).
:- mode unify_gen__generate_extra_closure_args(in, in, in, out) is det.

unify_gen__generate_extra_closure_args([], _, _, empty).
unify_gen__generate_extra_closure_args([Var | Vars], LoopCounterReg,
				NewClosureReg, tree(Code1, Code2)) :-
	One = const(int_const(1)),
	Code1 = node([
		assign(LoopCounterReg,
			binop(+, lval(LoopCounterReg), One))
			- "increment argument counter",
		assign(field(0, lval(NewClosureReg), lval(LoopCounterReg)),
			var(Var))
			- "set new argument field"
	]),
	unify_gen__generate_extra_closure_args(Vars, LoopCounterReg,
		NewClosureReg, Code2).

:- pred unify_gen__generate_pred_args(list(var), list(arg_info),
					list(maybe(rval))).
:- mode unify_gen__generate_pred_args(in, in, out) is det.

unify_gen__generate_pred_args([], _, []).
unify_gen__generate_pred_args([_|_], [], _) :-
	error("unify_gen__generate_pred_args: insufficient args").
unify_gen__generate_pred_args([Var|Vars], [ArgInfo|ArgInfos], [Rval|Rvals]) :-
	ArgInfo = arg_info(_, ArgMode),
	( ArgMode = top_in ->
		Rval = yes(var(Var))
	;
		Rval = no
	),
	unify_gen__generate_pred_args(Vars, ArgInfos, Rvals).

:- pred unify_gen__generate_cons_args(list(var), module_info, list(uni_mode),
					list(maybe(rval))).
:- mode unify_gen__generate_cons_args(in, in, in, out) is det.

unify_gen__generate_cons_args(Vars, ModuleInfo, Modes, Args) :-
	( unify_gen__generate_cons_args_2(Vars, ModuleInfo, Modes, Args0) ->
		Args = Args0
	;
		error("unify_gen__generate_cons_args: length mismatch")
	).
		
	% Create a list of maybe(rval) for the arguments
	% for a construction unification.  For each argument which
	% is input to the construction unification, we produce `yes(var(Var))',
	% but if the argument is free, we just produce `no', meaning don't
	% generate an assignment to that field.

:- pred unify_gen__generate_cons_args_2(list(var), module_info, list(uni_mode),
					list(maybe(rval))).
:- mode unify_gen__generate_cons_args_2(in, in, in, out) is semidet.

unify_gen__generate_cons_args_2([], _, [], []).
unify_gen__generate_cons_args_2([Var|Vars], ModuleInfo, [UniMode | UniModes],
			[Arg|RVals]) :-
	UniMode = ((_LI - RI) -> (_LF - RF)),
	( mode_is_input(ModuleInfo, (RI -> RF)) ->
		Arg = yes(var(Var))
	;
		Arg = no
	),
	unify_gen__generate_cons_args_2(Vars, ModuleInfo, UniModes, RVals).

%---------------------------------------------------------------------------%

:- pred unify_gen__make_fields_and_argvars(list(var), lval, int, int,
						list(uni_val), list(uni_val)).
:- mode unify_gen__make_fields_and_argvars(in, in, in, in, out, out) is det.

	% Construct a pair of lists that associates the fields of
	% a term with variables.

unify_gen__make_fields_and_argvars([], _, _, _, [], []).
unify_gen__make_fields_and_argvars([Var|Vars], Lval, Field0, TagNum,
							[F|Fs], [A|As]) :-
	F = lval(field(TagNum, lval(Lval), const(int_const(Field0)))),
	A = ref(Var),
	Field1 is Field0 + 1,
	unify_gen__make_fields_and_argvars(Vars, Lval, Field1, TagNum, Fs, As).

%---------------------------------------------------------------------------%

	% Generate a deterministic deconstruction. In a deterministic
	% deconstruction, we know the value of the tag, so we don't
	% need to generate a test.

	% Deconstructions are generated semi-eagerly. Any test sub-
	% unifications are generate eagerly (they _must_ be), but
	% assignment unifications are cached.

unify_gen__generate_det_deconstruction(Var, Cons, Args, Modes, Code) -->
	code_info__cons_id_to_tag(Var, Cons, Tag),
	% For constants, if the deconstruction is det, then we already know
	% the value of the constant, so Code = empty.
	(
		{ Tag = string_constant(_String) }
	->
		{ Code = empty }
	;
		{ Tag = int_constant(_Int) }
	->
		{ Code = empty }
	;
		{ Tag = float_constant(_Float) }
	->
		{ Code = empty }
	;
		{ Tag = pred_constant(_, _) }
	->
		{ Code = empty }
	;
		{ Tag = simple_tag(SimpleTag) }
	->
		code_info__flush_variable(Var, CodeA),
		code_info__get_variable_register(Var, Lval),
		{ unify_gen__make_fields_and_argvars(Args, Lval, 0,
						SimpleTag, Fields, ArgVars) },
		unify_gen__generate_det_unify_args(Fields, ArgVars,
								Modes, CodeB),
		{ Code = tree(CodeA, CodeB) }
	;
		{ Tag = complicated_tag(Bits0, _Num0) }
	->
		code_info__flush_variable(Var, CodeA),
		code_info__get_variable_register(Var, Lval),
		{ unify_gen__make_fields_and_argvars(Args, Lval, 1,
						Bits0, Fields, ArgVars) },
		unify_gen__generate_det_unify_args(Fields, ArgVars,
								Modes, CodeB),
		{ Code = tree(CodeA, CodeB) }
	;
		{ Tag = complicated_constant_tag(_Bits1, _Num1) }
	->
		{ Code = empty } % if this is det, then nothing happens
	;
		{ error("Unrecognised tag in deconstruction") }
	).

%---------------------------------------------------------------------------%

	% Generate a semideterministic deconstruction.
	% A semideterministic deconstruction unification is tag-test
	% followed by a deterministic deconstruction.

unify_gen__generate_semi_deconstruction(Var, Tag, Args, Modes, Code) -->
	unify_gen__generate_tag_test(Var, Tag, CodeA),
	unify_gen__generate_det_deconstruction(Var, Tag, Args, Modes, CodeB),
	{ Code = tree(CodeA, CodeB) }.

%---------------------------------------------------------------------------%

	% Generate code to perform a list of deterministic subunifications
	% for the arguments of a construction.

:- pred unify_gen__generate_det_unify_args(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_det_unify_args(in, in, in, out, in, out) is det.

unify_gen__generate_det_unify_args(Ls, Rs, Ms, Code) -->
	( unify_gen__generate_det_unify_args_2(Ls, Rs, Ms, Code0) ->
		{ Code = Code0 }
	;
		{ error("unify_gen__generate_det_unify_args: length mismatch") }
	).

:- pred unify_gen__generate_det_unify_args_2(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_det_unify_args_2(in, in, in, out, in, out)
	is semidet.

unify_gen__generate_det_unify_args_2([], [], [], empty) --> [].
unify_gen__generate_det_unify_args_2([L|Ls], [R|Rs], [M|Ms], Code) -->
	unify_gen__generate_det_sub_unify(L, R, M, CodeA),
	unify_gen__generate_det_unify_args_2(Ls, Rs, Ms, CodeB),
	{ Code = tree(CodeA, CodeB) }.

%---------------------------------------------------------------------------%

	% Generate code to perform a list of semideterministic sub-
	% unifications for the arguments of a [de]construction.
:- pred unify_gen__generate_semi_unify_args(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_unify_args(in, in, in, out, in, out) is det.

unify_gen__generate_semi_unify_args(Ls, Rs, Ms, Code) -->
	( unify_gen__generate_semi_unify_args_2(Ls, Rs, Ms, Code0) ->
	    { Code = Code0 }
	;
	    { error("unify_gen__generate_semi_unify_args: length mismatch") }
	).

:- pred unify_gen__generate_semi_unify_args_2(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_unify_args_2(in, in, in, out, in, out)
	is semidet.

unify_gen__generate_semi_unify_args_2([], [], [], empty) --> [].
unify_gen__generate_semi_unify_args_2([L|Ls], [R|Rs], [M|Ms], Code) -->
	unify_gen__generate_semi_sub_unify(L, R, M, CodeA),
	unify_gen__generate_semi_unify_args_2(Ls, Rs, Ms, CodeB),
	{ Code = tree(CodeA, CodeB) }.

%---------------------------------------------------------------------------%

	% Generate a subunification between two [field|variable].

:- pred unify_gen__generate_det_sub_unify(uni_val, uni_val, uni_mode, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_det_sub_unify(in, in, in, out, in, out) is det.

unify_gen__generate_det_sub_unify(L, R, M, Code) -->
	{ M = ((LI - RI) -> (LF - RF)) },
	code_info__get_module_info(ModuleInfo),
	(
			% Input - input == test unification
			% == not allowed in det code.
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		{ error("Det unifications may not contain tests") }
		% XXX We should perhaps just emit empty code here,
		% since the unification must be something like `1 = 1'?
		% { Code = node([ c_code("abort();") -
		% 	"Error - det argument sub-unify is a test???" ]) }
	;
			% Input - Output== assignment ->
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(R, L, Code)
	;
			% Input - Output== assignment <-
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(L, R, Code)
	;
			% Bizzare!
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		{ error("Some strange unify") }
	;
		{ Code = empty } % free-free - ignore
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_semi_sub_unify(uni_val, uni_val, uni_mode,
					code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_sub_unify(in, in, in, out, in, out) is det.

unify_gen__generate_semi_sub_unify(L, R, M, Code) -->
	{ M = ((LI - RI) -> (LF - RF)) },
	code_info__get_module_info(ModuleInfo),
	(
			% Input - input == test unification
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		% This shouldn't happen, since the transformation to
		% super-homogeneous form should avoid tests in the arguments
		% of a construction or deconstruction unification.
		{ error("test in arg of [de]construction - tell fjh to fix that bug in make_hlds.nl") },
		unify_gen__generate_sub_test(L, R, Code)
	;
			% Input - Output== assignment ->
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(R, L, Code)
	;
			% Input - Output== assignment <-
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(L, R, Code)
	;
			% Weird! [and you thought I was cutting and pasting]
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		{ error("Some strange unify") }
	;
		{ Code = empty } % free-free - ignore
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_sub_assign(uni_val, uni_val, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_sub_assign(in, in, out, in, out) is det.

	% Assignment between to lvalues - cannot cache [yet]
	% so generate immediate code
unify_gen__generate_sub_assign(lval(Lval), lval(Rval), Code) -->
	{ Code = node([
		assign(Lval, lval(Rval)) - "Copy field"
	]) }.
	% assignment from a variable to an lvalue - cannot cache
	% so generate immediately
unify_gen__generate_sub_assign(lval(Lval), ref(Var), Code) -->
	code_info__produce_variable(Var, Code0, Source),
	{ Code = tree(
		Code0,
		node([
			assign(Lval, Source) - "Copy value"
		])
	) }.
	% assignment to a variable, so cache it.
unify_gen__generate_sub_assign(ref(Var), lval(Rval), empty) -->
	(
		code_info__variable_is_live(Var)
	->
		code_info__cache_expression(Var, lval(Rval))
	;
		{ true }
	).
	% assignment to a variable, so cache it.
unify_gen__generate_sub_assign(ref(Lvar), ref(Rvar), empty) -->
	(
		code_info__variable_is_live(Lvar)
	->
		code_info__cache_expression(Lvar, var(Rvar))
	;
		{ true }
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_sub_test(uni_val, uni_val, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_sub_test(in, in, out, in, out) is det.

	% Generate code to evaluate the two arguments of a sub-test
	% and compare them. XXX strings?
unify_gen__generate_sub_test(UnivalX, UnivalY, Code) -->
	unify_gen__evaluate_uni_val(UnivalX, RvalX, CodeX),
	unify_gen__evaluate_uni_val(UnivalY, RvalY, CodeY),
	code_info__generate_test_and_fail(
		binop(eq, RvalX, RvalY), TestCode),
	{ Code = tree(tree(CodeX, CodeY), TestCode) }.

:- pred unify_gen__evaluate_uni_val(uni_val, rval, code_tree,
					code_info, code_info).
:- mode unify_gen__evaluate_uni_val(in, out, out, in, out) is det.

	% Lvalue - do nothing
unify_gen__evaluate_uni_val(lval(Lval), lval(Lval), empty) --> [].
	% Var - cached, so flush it.
unify_gen__evaluate_uni_val(ref(Var), Rval, Code) -->
	code_info__produce_variable(Var, Code, Rval).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
