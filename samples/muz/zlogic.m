%-----------------------------------------------------------------------------%
% Copyright (C) 1995-1999 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% file: zlogic.m
% main author: philip

:- module zlogic.

:- interface.
:- import_module io, list, std_util, zabstract, dict, ztype, word, repository.

% :- type typed_par ---> triple(par, subst, ptypes).
:- type gen_list == list(pair(triple(par, subst, ptypes), flag)).

:- pred generate_logic(
	dict::in,
	list(ident)::in,
	gen_list::in,
	repository::out,
	io__state::di,
	io__state::uo
	) is det.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
:- implementation.
:- import_module higher_order, map, set, string,
			assoc_list, require, int,
			char, ztype_op, unsafe.

:- type schema_vars == assoc_list(ident, cvar).		% sorted by ident

:- type cvar == var.

% If no predicate, identifier will be handled normally, ie. propagated out 
% until quantified or made an argument of the enclosing clause.
% If there is a predicate, var is assumed to be generated locally by the pred.

:- type value ---> value(var, maybe(formula)).

% :- type value_source
% 	--->	global			% to be passed in as an argument
% 	;	local(predicate)	% to be generated by a predicate
% 					% 	(predicate will be true
% 					%	for Z locals identifiers)
% 	.

:- type logic_rep_table ==
	pair(	map(ident, value),	% Z ident -> constraint variables
		map(ident, pair(string, set(ident)))).
	    				 % Z schema ident -> pred name + globals

:- type logstate ---> log(
	dict,				% global identifiers with types
	pair(ptypes, gentypes),		% identifier ref parameter type bindings
	logic_rep_table,
	varset,				% term variables and names
	list(formula),
	repository
).

:- type variable == cvar.

% :- type clause ---> clause(
% 	zcontext,		% From which part of the Z source?
% 	source,			% From what kind of source construct
% 	string,			% Predicate/clause name
% 	list(ztype),		% Z base types
% 	list(variable),		% Head variables
% 	predicate		% Body
% 	).

:- type global_vars == list(variable).

:- type comp_type ---> zsetcomp ; zlambda ; zmu.

:- type ref_ids == set(ident).	% identifiers referenced within a Z construct

:- func universe = ident.
universe = id(no, "_U", []).

:- pred mark(logic_rep_table::out, logstate::in, logstate::out) is det.
mark(VM, Log, Log) :- Log = log(_, _, VM, _, _, _).

:- pred restore(logic_rep_table::in, logstate::in, logstate::out) is det.
restore(VM, log(D, PM, _, VS, CL, Rep), log(D, PM, VM, VS, CL, Rep)).

% :- func varmap(logstate) = map(ident, cvar).
% varmap(log(_, _, VM, _, _, _)) = VM.

:- pred overlayV(assoc_list(ident, value), logstate, logstate).
:- mode overlayV(in, in, out) is det.
overlayV(AL, log(D, PM, VM0-SM, VS, CL, Rep), log(D, PM, VM-SM, VS, CL, Rep)) :-
	map__from_assoc_list(AL, M), map__overlay(VM0, M, VM).

:- pred overlayI(zcontext, assoc_list(ident, cvar), logstate, logstate).
:- mode overlayI(in, in, in, out) is det.
overlayI(ZC, IVL, CS, log(D, PM, VM-SM, VS, CL, Rep)) :-
	CS = log(D, PM, VM0-SM, VS, CL, Rep),
	lookupV(CS, universe, UV),
	P = (pred(I-V::in, I-value(V, yes(G))::out) is det :-
		G = put_zc(make_makeget(identPortray(I), UV,V), ZC)),
	list__map(P, IVL, AL),
	map__from_assoc_list(AL, M), map__overlay(VM0, M, VM).

:- pred overlay(assoc_list(ident, cvar), logstate, logstate).
:- mode overlay(in, in, out) is det.
overlay(AL, log(D, PM, VM0-SM, VS, CL, Rep), log(D, PM, VM-SM, VS, CL, Rep)) :-
	list__map(pred(I-V::in, I-value(V, no)::out) is det, AL, AL1),
	map__from_assoc_list(AL1, M), map__overlay(VM0, M, VM).

:- pred lookupV(logstate::in, ident::in, cvar::out,
					maybe(formula)::out) is det.
lookupV(log(_, _, VM-_, _, _, _), Id, V, P) :-
	( map__search(VM, Id, V0) ->
		V0 = value(V, P)
	;	string__append_list(
			["zlogic:lookupV: ident not found---", identPortray(Id)],
			Mesg),
		error(Mesg)
	).

:- pred lookupV(logstate::in, ident::in, cvar::out) is det.
lookupV(CS, Id, V) :-
	lookupV(CS, Id, V, P). % ,
%	( P = no ->
%		true
%	;	string__append_list(
%			["zlogic:lookupV/3: predicate exists for ",
%						identPortray(Id)], Mesg),
%		error(Mesg)
%	).

:- pred identsToVars(set(ident)::in, list(cvar)::out,
					logstate::in, logstate::out) is det.
identsToVars(IS, VL) -->
	{set__to_sorted_list(IS, IL)},
	=(CS),
	{list__map(lookupV(CS), IL, VL)}.

:- pred identsToFormula(set(ident)::in, formula::out, list(cvar)::out,
					logstate::in, logstate::out) is det.
identsToFormula(Is, F, VL) -->
	{set__to_sorted_list(Is, IL)},
	=(CS),
	{Pred = (pred(I::in, V-FI::out) is semidet :-
						lookupV(CS, I, V, yes(FI)))},
	{list__filter_map(Pred, IL, GVFL, Free)},
	( {Free = []},
		{split_pairs(GVFL, VL, FL)},
		{F = make_conj(FL)}
	; {Free = [_|_],
		string__append("identsToFormula/4--free vars: ",
			string_portray_list(identPortray, "", ", ", ": ", Free),
			Error),
		error(Error)}
	).

:- pred addSchema(ident::in, string::in, set(ident)::in,
					logstate::in, logstate::out) is det.
addSchema(Id, Name, Globals,
		log(D, PM, VM-SM0, VS, CL, Rep),
		log(D, PM, VM-SM, VS, CL, Rep)) :-
	map__det_insert(SM0, Id, Name-Globals, SM).

:- pred lookupS(logstate::in, ident::in, string::out, set(ident)::out) is det.
lookupS(log(_, _, _-SM, _, _, _), Id, Name, Globals) :-
	( map__search(SM, Id, Info) ->
		Name-Globals = Info
	;	string__append_list(
			["zlogic:lookupS: ident not found---", identPortray(Id)],
			Mesg),
		error(Mesg)
	).

:- pred lookupSExpr(ref::in, logstate::in, slist::out) is det.
lookupSExpr(Ref, log(_, PM-_, _, _, _, _), SL) :- find_sexpr_type(Ref, SL, PM).

:- pragma promise_pure(lookupRef/3).
:- pred lookupRef(ref::in, logstate::in, maybe(list(expr))::out) is det.
lookupRef(Ref, log(_, _-GenTypes, _, _, _, _), Ps) :-
	getGenType(GenTypes, Ref, Ps),
% map__to_assoc_list(GenTypes, AL),
impure unsafe_perform_io(io__print(Ref)),
impure unsafe_perform_io(io__nl),
impure unsafe_perform_io(io__print(Ps)),
% impure unsafe_perform_io(io__nl),
% impure unsafe_perform_io(io__print(AL)),
impure unsafe_perform_io(io__nl).

:- pred setPtypes(ptypes, logstate, logstate).
:- mode setPtypes(in, in, out) is det.
setPtypes(Ptypes,
	log(D,      _-GenTypes, M, VS, CL, Rep),
	log(D, Ptypes-GenTypes, M, VS, CL, Rep)).

:- pred setGenTypes(gentypes, logstate, logstate).
:- mode setGenTypes(in, in, out) is det.
setGenTypes(GenTypes,
	log(D, PM-_, M, VS, CL, Rep),
	log(D, PM-GenTypes, M, VS, CL, Rep)).

:- pred lookupId(logstate::in, ident::in, ztype::out) is det.
lookupId(log(D, _, _, _, _, _), Id, T) :-
	( dict__search(Id, e(_, T0), D) ->
		T = T0
	;	string__append_list(
			["zlogic:lookupId: ident not found---", identPortray(Id)],
			Mesg),
		error(Mesg)
	).

:- func conjoin(zcontext, list(formula)) = formula.
conjoin(ZC, FL) = put_zc(make_conj(FL), ZC).

:- func make_true = formula.
make_true = make_atom("true", []).

:- func make_true(zcontext) = formula.
make_true(ZC) = put_zc(make_atom("true", []), ZC).

:- func make_tuple(zcontext, list(zvar)) = formula.
make_tuple(ZC, LV) = put_zc(make_atom("make_tuple", LV), ZC).

:- func make_equals(zcontext, zvar, zvar) = formula.
make_equals(ZC, V0, V1) = put_zc(make_atom("equals", [V0, V1]), ZC).

:- func put_zc(formula, zcontext) = formula.
put_zc(F, ZC) = put_annot(F, zcontext(ZC)).

:- pred exists(list(lresult)::in, ref_ids::in, formula::in, formula::in,
	formula::out, logstate::in, logstate::out) is det.
exists(Vs, Is, F0, F1, F) -->
	{Locals = internal(Vs)},
	( {Locals = [],
		F = make_conj([F0, F1])}
	; {Locals = [_|_],
		F = make_exists(VG, Locals, F0, F1)},
		identsToVars(Is, VG)  % global vars
	).

:- func make_forall(zcontext, list(var), list(var), formula, formula) = formula.
make_forall(ZC, VG, VL, CS, CP) =
	make_neg(put_zc(make_exists(VG, VL, CS, put_zc(make_neg(CP), ZC)), ZC)).

:- func lconn(zcontext, lconn, formula, formula) = formula.
lconn(_ZC, disjunction, F0, F1) =  make_disj([F0, F1]).
lconn(_ZC, conjunction, F0, F1) =  make_conj([F0, F1]).
lconn( ZC, implication, F0, F1) =  make_disj([put_zc(make_neg(F0), ZC), F1]).
lconn(_ZC, equivalence, F0, F1) =  make_iff(F0, F1).

:- pred addClause(
	zcontext::in,		% From which part of the Z source?
	source::in,		% From what kind of source construct
	string::in,		% Predicate/clause name
	list(ztype)::in,	% Z base types
	list(variable)::in,	% Head variables
	formula::in,		% Body
	logstate::in, logstate::out) is det.
addClause(ZC, Source, Name, Types, HeadVars, Body, CS,
			log(D, PM, VM, S, CL, R)) :-
	CS = log(D, PM, VM, S, CL, R0),
	lookupV(CS, universe, UV),
	HeadVars1 = [UV|HeadVars],
	list__length(HeadVars1, Arity),
	C0 = make_clause(Name, HeadVars1, Body),
	C1 = put_zc(C0, ZC),
	C2 = put_annot(C1, z_type(Types)),
	C = put_annot(C2, source(Source)),
	add_clause(Name, Arity, C, R0, R).

:- pred new_clause_name(string::out, logstate::in, logstate::out) is det.
new_clause_name(Name, log(D, PM, VM, S0, CL, Rep),
						log(D, PM, VM, S, CL, Rep)) :-
	new_clause_name(S0,Name,S).
% Warning: the following is a kludge--varset is used to generate new clause ids
%	varset__new_var(S0, V, S),
%	varset__lookup_name(S, V, "pred_", Name).

:- pred new_gvar(ident::in, cvar::out, logstate::in, logstate::out) is det.
new_gvar(Id, V, log(D, PM, VM, S0, CL, Rep), log(D, PM, VM, S, CL, Rep)) :-
	new_var(S0,identMangle(Id), V, S).
%	varset__new_var(S0, V, S1),
%	varset__name_var(S1, V, identMangle(Id), S).

:- pred new_lvar(ident::in, cvar::out, logstate::in, logstate::out) is det.
new_lvar(Id, V, log(D, PM, VM, S0, CL, Rep), log(D, PM, VM, S, CL, Rep)) :-
	new_unique_var(S0, identMangle(Id), V, S).
%	varset__new_var(S0, V, S1),
%	string__append(identMangle(Id), "_", Name0),
%	varset__lookup_name(S1, V, Name0, Name),
%	varset__name_var(S1, V, Name, S).

:- pred new_var(string::in, cvar::out, logstate::in, logstate::out) is det.
new_var(Name, V, log(D, PM, VM, S0, CL, Rep), log(D, PM, VM, S, CL, Rep)) :-
	new_unique_var(S0, Name, V, S).
%	varset__new_var(S0, V, S1),
%	varset__lookup_name(S1, V, Name0, Name),
%	varset__name_var(S1, V, Name, S).

:- pred new_gvars(list(ident), assoc_list(ident, cvar), logstate, logstate).
:- mode new_gvars(in, out, in, out) is det.
new_gvars(L, AL) -->
	{P = (pred(Id::in, Id-V::out, in, out) is det --> new_gvar(Id, V))},
	list__map_foldl(P, L, AL).

:- pred new_vars(list(ident), assoc_list(ident, cvar), logstate, logstate).
:- mode new_vars(in, out, in, out) is det.
new_vars(L, AL) -->
	{P = (pred(Id::in, Id-V::out, in, out) is det --> new_lvar(Id, V))},
	list__map_foldl(P, L, AL).

generate_logic(D0, LibIds0, S, Repository) -->
	{list__sort_and_remove_dups([numIdent, stringIdent|LibIds0], LibIds),
	new_varset(VS0),
	map__init(VM),
	map__init(SM),
	empty_repository(Rep0),
	Log0 = log(D0, initPtypes-initGenTypes, VM-SM, VS0, [], Rep0)},
					% inits are dummys: not used
	io__write_string("Start generate ...\n"),
	{generate_logic1(LibIds, S, Log0, Log)},
	io__write_string(" ... end generate\n"),
	{Log = log(_, _, _, VS, _, Repository)},
	print_repository(Repository).
%	Log = log(_, _, _, VS, TL0, _),
%	list__reverse(TL0, TL)}.
%	list__foldl(writeClause(VS), TL),
%	{P = (pred(clause(ZC, src_axdef, Name, _, Args, _)::in,
%					atom(Name, Args)-ZC::out) is semidet),
%	list__filter_map(P, TL, Goal)},
%	io__write_string("\n% Specification goal\n% pred goal.\ngoal :-"),
%	writePredicate(VS, 1, make_conj(Goal)),
%	io__write_string(".\n").

:- pred generate_logic1(list(ident), gen_list, logstate, logstate).
:- mode generate_logic1(in, in, in, out) is det.
generate_logic1(LibIds, S) -->
	% {P = (pred(I::in, I-value(V, yes(G))::out, in, out) is det -->
	% 		new_gvar(I, V),
	% 		{G = make_atom(identPortray(I), [V])})},
	% list__map_foldl(P, LibIds, LibValues),
	% overlayV(LibValues),
	new_gvar(universe, UV),
	overlay([universe-UV]),
	new_gvars(LibIds, IVL),
	overlayI(0, IVL),
	list__foldl(par_logic, S).

:- pred par_logic(pair(triple(par, subst, ptypes), flag), logstate, logstate).
:- mode par_logic(in, in, out) is det.
par_logic(triple(P-ZC, Subst, Ptypes)-Generate) -->
	{substToGenTypes(Subst, GenTypes)},
	setPtypes(Ptypes),
	setGenTypes(GenTypes),
	( {Generate = on}, par_logic1(ZC, P)
	; {Generate = off},  par_vars(ZC, P)
	).

:- pred par_logic1(zcontext, par1, logstate, logstate).
:- mode par_logic1(in, in, in, out) is det.
par_logic1(ZC, given(IL)) -->
	new_gvars(IL, IVL),
	overlayI(ZC, IVL),
	=(CS),
	{ P = (pred(I-V::in, in, out) is det -->
		{lookupId(CS, I, Type),
		Name = identMangle(I)},
		addClause(ZC, src_axdef, Name, [Type], [V],
			put_zc(make_makegiven(Name, V), ZC))) },
	list__foldl(P, IVL).
%par_logic1(ZC, D, let(S)) --> []. % sexpr_logic_define(C, S, _T).
par_logic1(ZC, sdef(SId, Formals, X)) -->
	mark(VM),
		new_vars(Formals, FIV), overlay(FIV),
		sexpr_logic_define(X, G, FX, IsX),
	restore(VM),
	{split_pairs(G, IL, VL)},
	{set__delete_list(IsX, IL, Is1)}, % This may be redundant
	new_gvar(SId, SV),
	identsToVars(Is1, VG),
	{F0 = make_exists([SV|VG], VL, FX, make_tuple(ZC, append(VL, [SV])))},
	{set__delete_list(Is1, Formals, Is2)},
	{assoc_list__values(FIV, FV)},
	identsToFormula(Is2, GF, VU),
	{append(FV, [SV], HeadVars)},
	{ VU = [], F = F0 ; VU = [_|_], F = make_exists(HeadVars, VU, GF, F0) },
	{SName = identMangle(SId)},
	addSchema(SId, SName, Is2),
	% Empty list should be list of types
	addClause(ZC, src_schema, SName, [], HeadVars, F).
par_logic1(ZC, eqeq(Id, Formals, X)) -->
	mark(VM),
		new_vars(Formals, FIV), overlay(FIV),
		expr_logic(X, FX-R0, Is),
	restore(VM),
	new_gvar(Id, IV),
	{assoc_list__values(FIV, FV)},
	{Name = identMangle(Id)},
	=(CS), {lookupV(CS, universe, UV)},
	{append(FV, [IV], HeadVars)},
	{FI = put_zc(make_atom(Name, [UV|HeadVars]), ZC)},
	{ R0 = V0-_},
	overlayV([Id-value(IV, yes(FI))]),
	{ SI = singleton(Id) },
	exists([R0], union([Is, SI]), FX, make_equals(ZC, V0, IV), F0),
	{set__delete_list(Is, Formals, Is1)},
	identsToFormula(Is1, GF, VU),
	{ VU = [], F = F0 ; VU = [_|_], F = make_exists(HeadVars, VU, GF, F0) },
	% Empty list should be list of types
	addClause(ZC, src_axdef, Name, [], HeadVars, F).
par_logic1(ZC, data(Ref, TypeId, L)) -->
	( {list__map(pred(branch(_, I, no)::in, I::out) is semidet, L, IL)} ->
		{P1 = (pred(I::in, I-value(V, yes(P))::out, in, out) is det -->
			new_gvar(I, V),
			{P = put_zc(make_makeconst(identPortray(I), V), ZC)})},
		list__map_foldl(P1, IL, EnumValues),
		overlayV(EnumValues),
		% must overlay these before processing display expression
		{P2 = (pred(I::in, ref(0, I, no)-ZC::out) is det)},
		{list__map(P2, IL, DisplayL)},
		expr_logic(ZC, display(0, set, DisplayL), C, Var-_, Is),
		identsToFormula(Is, F, _VU),
		=(CS), {lookupId(CS, TypeId, Type),
		Name = identMangle(TypeId),
		lookupV(CS, universe, UV)},
		addClause(ZC, src_axdef, Name, [Type], [Var],
							conjoin(ZC, [F, C])),
		{FT = put_zc(make_atom(Name, [UV, Var]), ZC)},
		overlayV([TypeId-value(Var, yes(FT))])
	;	par_logic1(ZC, given([TypeId])),
		{Predicate = []},		% BUG: Not finished here
		{Expand = define([], sexpr(Ref, text(DL, Predicate), ZC)),
		R = ref(0, TypeId, no)-ZC,
		Inj = id(no, "\\inj", []),
		P = (pred(branch(BRef, Id, M)::in, decl([Id], X)::out) is det :-
			( M = no, X = R
			; M = yes(X0), X = ref(BRef, Inj, yes([X0, R]))-ZC
			)),		% This will break if \inj is not defined
		list__map(P, L, DL)},
		par_logic1(ZC, Expand)
	).
par_logic1(ZC, zpred(P)) -->
	zpred_logic(P, FP, Is),
	identsToFormula(Is, GF, VU),
	{ VU = [], F = FP ; VU = [_|_], F = make_exists([], VU, GF, FP) },
	new_clause_name(Name),
	addClause(ZC, src_axdef, Name, [], [], F).
par_logic1(ZC, define(Formals, S)) -->
	mark(VM),
		new_vars(Formals, FIV), overlay(FIV),
		sexpr_logic_define(S, GS, GCS, IsGS, CS, IsS),
	restore(VM),
	overlayI(ZC, GS),
	{assoc_list__keys(GS, IL),
	Name = string_portray_list(identPortray, IL)},
	{set__delete_list(union(IsGS, IsS), Formals, Is)},
	identsToFormula(Is, GF, VU),
	{assoc_list__values(FIV, FV),
	assoc_list__values(GS, IV),
	list__append(FV, IV, HeadVars),
	F0 = conjoin(ZC, [GCS, CS])},
	{ VU = [], F = F0 ; VU = [_|_], F = make_exists(HeadVars, VU, GF, F0) },
	=(LogState), {list__map(lookupId(LogState), IL, Types)},
	% Types should contain all types
	addClause(ZC, src_axdef, Name, Types, HeadVars, F).

:- pred par_vars(zcontext, par1, logstate, logstate).
:- mode par_vars(in, in, in, out) is det.
par_vars(ZC, given(IL)) -->
	new_gvars(IL, IVL), overlayI(ZC, IVL).
%par_vars(ZC, D, let(S)) --> []. % sexpr_logic_define(C, S, _T).
par_vars(_ZC, sdef(I, _F, _X)) -->
	addSchema(I, identMangle(I), empty).
par_vars(ZC, eqeq(I, _, _)) -->
	new_gvar(I, IV), overlayI(ZC, [I-IV]).	% BUG: inconsistent with above
par_vars(ZC, data(_Ref, TypeId, L)) -->
	{list__map(pred(branch(_, I, _)::in, I::out) is det, L, IL)},
	new_gvars([TypeId|IL], IVL), overlayI(ZC, IVL).
par_vars(_ZC, zpred(_)) -->
	{true}.
par_vars(ZC, define(_F, sexpr(Ref, _S, _ZC1))) -->
	=(LogState), {lookupSExpr(Ref, LogState, SL)},
	{assoc_list__keys(SL, IL)},
	new_gvars(IL, IVL), overlayI(ZC, IVL).

:- pred schema_vars_sort(schema_vars, schema_vars, formula).
:- mode schema_vars_sort(in, out, out) is det.
schema_vars_sort(SV0, SV, P) :-
	assoc_list_sort(SV0, SV1),
	schema_vars_merge(SV1, SV, P).

:- pred schema_vars_merge(schema_vars, schema_vars, formula).
:- mode schema_vars_merge(in, out, out) is det.
schema_vars_merge([], [], make_true).
schema_vars_merge([IV|SV0], [IV|SV], make_conj(PL)) :-
	IV = I-V,
	schema_vars_merge(I, V, SV0, SV, PL).

:- pred schema_vars_merge(ident, cvar, schema_vars, schema_vars,
							list(formula)).
:- mode schema_vars_merge(in, in, in, out, out) is det.
schema_vars_merge(_, _, [], [], []).
schema_vars_merge(I, V, [IV0|SV0], SV, P) :-
	IV0 = I0-V0,
	( I = I0 ->
		P = [make_equals(0, V, V0)|P1],
		schema_vars_merge(I, V, SV0, SV, P1)
	;	SV = [IV0|SV1],
		schema_vars_merge(I0, V0, SV0, SV1, P)
	).

:- pred schema_vars_merge(schema_vars, schema_vars, schema_vars,
							list(formula)).
:- mode schema_vars_merge(in, in, out, out) is det.
schema_vars_merge([], [], [], []).
schema_vars_merge([], SV, SV, []) :- SV = [_|_].
schema_vars_merge(SV, [], SV, []) :- SV = [_|_].
schema_vars_merge(SV1, SV2, SV, PL) :-
	SV1 = [IV1|SV1a], IV1 = I1-V1,
	SV2 = [IV2|SV2a], IV2 = I2-V2,
	compare(C, I1, I2),
	( C = (<),
		SV = [IV1|SVa], schema_vars_merge(SV1a, SV2, SVa, PL)
	; C = (=),
		SV = [IV1|SVa],
		(V1 = V2 -> PL = PL1 ; PL = [make_equals(0, V1, V2)|PL1]),
		schema_vars_merge(SV1a, SV2a, SVa, PL1)
	; C = (>),
		SV = [IV2|SVa], schema_vars_merge(SV1, SV2a, SVa, PL)
	).

:- pred assoc_list_sort(assoc_list(K, V), assoc_list(K, V)).
:- mode assoc_list_sort(in, out) is det.
assoc_list_sort(AL0, AL) :-
	P = (pred(K1-_::in, K2-_::in, C::out) is det :- compare(C, K1, K2)),
	list__sort(P, AL0, AL).

% first formula list involves only global vars	%BUG: now redundant?
% second formula list involves declared vars
:- pred decl_logicL(list(decl), list(formula), list(formula), set(ident),
							logstate, logstate).
:- mode decl_logicL(in, out, out, out, in, out) is det.
decl_logicL([], [], [], empty) -->
	[].
decl_logicL([H|T], [GCH|GCT], [CH|CT], union(IsH, IsT)) -->
	decl_logic(H, GCH, CH, IsH),
	decl_logicL(T, GCT, CT, IsT).

:- pred decl_logic(decl, formula, formula, set(ident), logstate, logstate).
:- mode decl_logic(in, out, out, out, in, out) is det.
decl_logic(decl(IL, X), make_true, F, Is) -->
	=(CS),
	{X = _-ZC},
	expr_logic(X, XC-XR, Is),
	{ XR = XV-_ },
	{P = (pred(I::in, IF::out) is det :-
		IF = put_zc(make_atom("in", [V, XV]), ZC),
		lookupV(CS, I, V))},
	{list__map(P, IL, CL)},
	exists([XR], Is, XC, conjoin(ZC, CL), F).
decl_logic(include(S), make_true(ZC), C, Is) -->
	{S = sexpr(_, _, ZC)},
	sexpr_logic(S, C, Is).

:- pred zpred_logicL(list(zpred), formula, ref_ids, logstate, logstate).
:- mode zpred_logicL(in, out, out, in, out) is det.
zpred_logicL(PL, make_conj(CL), union(IL)) -->
	{P = (pred(Pred::in, CO-IsO::out, VSI::in, VSO::out) is det :-
					zpred_logic(Pred, CO, IsO, VSI, VSO))},
	list__map_foldl(P, PL, CIL),
	{split_pairs(CIL, CL, IL)}.

:- pred zpred_logic(zpred, formula, ref_ids, logstate, logstate).
:- mode zpred_logic(in, out, out, in, out) is det.
zpred_logic(X, C, Is) --> zpred_logic0(X, C0, Is), {X = _-ZC, C = put_zc(C0, ZC)}.

:- pred zpred_logic0(zpred, formula, ref_ids, logstate, logstate).
:- mode zpred_logic0(in, out, out, in, out) is det.
zpred_logic0(equality(X0, X1)-ZC, F, Is) -->
	{ Is = union(Is0, Is1), R0 = V0-_, R1 = V1-_ },
	expr_logic(X0, C0-R0, Is0),
	expr_logic(X1, C1-R1, Is1),
	{F1 = make_equals(ZC, V0, V1)},
	exists([R0, R1], Is, conjoin(ZC, [C0, C1]), F1, F).
zpred_logic0(membership(X0, X1)-ZC, F, Is) -->
	expr_logic(X0, C0-R0, Is0),
	expr_logic(X1, C1-R1, Is1),
	{ Is = union(Is0, Is1), R0 = V0-_, R1 = V1-_ },
	{F1 = put_zc(make_atom("in", [V0, V1]), ZC)},
	exists([R0, R1], Is, conjoin(ZC, [C0, C1]), F1, F).
zpred_logic0(truth-_, F, empty) -->
	{F = make_true}.
zpred_logic0(falsehood-_, F, empty) -->
	{F = make_atom("false", [])}.
zpred_logic0(negation(P)-_, F, Is) -->
	zpred_logic(P, F0, Is),
	{F = make_neg(F0)}.
zpred_logic0(lbpred(LConn, P0, P1)-ZC, F, union(Is0, Is1)) -->
	zpred_logic(P0, F0, Is0),
	zpred_logic(P1, F1, Is1),
	{ F = lconn(ZC, LConn, F0, F1) }.
zpred_logic0(quantification(Q, S, P)-ZC, F, Is) -->
	% Q vars | S @ P
	% VG = global vars
	% VL = quantified vars
	% CS = S formula
	% CP = P formula
	( {Q = unique} ->
		unique_logic(ZC, S, P, F, Is)
	;	{ Q = universal ->
			F1 = make_forall(ZC, VG, VL, CS, CP)
		; 	F1 = make_exists(VG, VL, CS, CP)	% Q = exists
		},
		{F = make_conj([GCS, put_zc(F1, ZC)])},
		sexpr_logic_define(S, GS, GCS, IsGS, CS, IsS), % ERROR: Incomplete
		mark(VM),
			overlay(GS),
			zpred_logic(P, CP, IsP0),
		restore(VM),
		{split_pairs(GS, IL, VL),
		set__delete_list(IsP0, IL, IsP),
		Is0 = union(IsS, IsP),
		Is = union(Is0, IsGS)},
		identsToVars(Is0, VG)
	).
zpred_logic0(sexpr(X)-ZC, F, Is) -->
	sexpr_logic(X, F, Is).	% BUG: sexpr vars not ='ed with context
zpred_logic0(let(L, P)-ZC,  F, Is) -->
	{split_pairs(L, LetIds, LetXs)},
	expr_logicL(LetXs, Fs, Rs, LetIs),
	{assoc_list__from_corresponding_lists(LetIds, vars(Rs), LS)},
        mark(VM),
                overlay(LS),
		zpred_logic(P, F0, Is0),
        restore(VM),
	{set__delete_list(Is0, LetIds, Is1),
	Is = union(LetIs, Is1)},
	exists(Rs, Is, put_zc(make_conj(Fs), ZC), F0, F).

%%%
% 5 EXPRESSION

:- type vsource ---> internal ; external.

:- type lresult == pair(variable, vsource).

:- func vars(list(lresult)) = list(var).
vars(LR) = LV :- list__map(pred(V-_::in, V::out) is det, LR, LV).

:- func internal(list(lresult)) = list(var).
internal(LR) = LV :-
	list__filter_map(pred(V-internal::in, V::out) is semidet, LR, LV).

:- func append(list(T), list(T)) = list(T).
append(L0, L1) = L :- list__append(L0, L1, L).

:- pred expr_logicL(list(expr), list(formula), list(lresult), ref_ids,
							logstate, logstate).
:- mode expr_logicL(in, out, out, out, in, out) is det.
expr_logicL([], [], [], empty) -->
	[].
expr_logicL([H|T], [HC|TC], [HV|TV], union(IsH, IsT)) -->
	expr_logic(H, HC-HV, IsH), expr_logicL(T, TC, TV, IsT).

:- pred expr_logic(expr, pair(formula, lresult), ref_ids, logstate, logstate).
:- mode expr_logic(in, out, out, in, out) is det.
expr_logic(X-Context, put_zc(C, Context)-V, Is) -->
	expr_logic(Context, X, C, V, Is).

:- pragma promise_pure(expr_logic/7).
:- pred expr_logic(zcontext, expr1, formula, lresult, ref_ids,
							logstate, logstate).
:- mode expr_logic(in, in, out, out, out, in, out) is det.
% 5.2 Identifier
% 5.3 Generic Instantiation
expr_logic(ZC, ref(Ref, I, MA), C, VR, Is) -->
	=(S),
{impure unsafe_perform_io(io__print(ref(Ref, I, MA)))},
{impure unsafe_perform_io(io__nl)},
	{lookupV(S, I, V, _MP)},
	% ( MP = no,
	% 	set__insert(Is0, I, Is),
	% 	C = C0
	% ; MP = yes(P),
	% 	Is = Is0,
	% 	C = make_conj([P, C0])
	% )},
	{ MA = no, lookupRef(Ref, S, Ps) ; MA = yes(_), Ps = MA },
	( {Ps = no,				% 5.2
		C = make_true,
		VR = V-external,
		Is = singleton(I)}
	; {Ps = yes(A)},			% 5.3
		expr_logicL(A, Cs, Vs, Is0),
		new_var("GenInst", VR0),
		{VR = VR0-internal},
		{set__insert(Is0, I, Is)},
		{C0 = put_zc(
			make_atom("genref", append([V|vars(Vs)], [VR0])), ZC)},
		exists(Vs, Is, conjoin(ZC, Cs), C0, C)
	).
% 5.4 Number Literal
expr_logic(_ZC, number(N), make_makenum(N, V), V-internal, empty) -->
	new_var("Number", V).
% 5.5 String Literal
expr_logic(_ZC, stringl(S), make_makestring(S, V), V-internal, empty) -->
	new_var("String", V).
% 5.6 Set Extension
expr_logic(ZC, display(_Ref, D, L), C, V-internal, Is) -->
					% NOTE: Ref gives (inferred) type
	expr_logicL(L, Cs, Vs, Is),
	{ D = set, Extension = "set_extension"
	; D = seq, Extension = "seq_extension"
	; D = bag, Extension = "bag_extension"
	},
	new_var("SetExtension", V),
	{C0 = put_zc(make_atom(Extension, append(vars(Vs), [V])), ZC)},
	exists(Vs, Is, conjoin(ZC, Cs), C0, C).
% 5.7 Set Comprehension
expr_logic(ZC, setcomp(SExpr, M), C, V, Is) -->
	setcomp_logic(ZC, zsetcomp, SExpr, M, C, V, Is).
expr_logic(ZC, lambda(SText, X), C, V, Is) -->
	setcomp_logic(ZC, zlambda, SText, yes(X), C, V, Is).
% 5.8 Power Set
expr_logic(ZC, powerset(X), F, V-internal, Is) -->
	expr_logic(X, F0-R0, Is),
	{R0 = V0-_},
	new_var("Power", V),
	exists([R0], Is, F0, put_zc(make_atom("power", [V0, V]), ZC), F).
% 5.9 Tuple
expr_logic(ZC, tuple(L), F, V-internal, Is) -->
	expr_logicL(L, Fs, Vs, Is),
	new_var("Tuple", V),
	{F0 = make_tuple(ZC, append(vars(Vs), [V]))},
	exists(Vs, Is, conjoin(ZC, Fs), F0, F).
% 5.10 Cartesian Product
expr_logic(ZC, product(L), F, V-internal, Is) -->
	expr_logicL(L, Cs, Vs, Is),
	new_var("Product", V),
	{F0 = put_zc(make_atom("make_product", append(vars(Vs), [V])), ZC)},
	exists(Vs, Is, conjoin(ZC, Cs), F0, F).
% 5.11 Tuple Selection
expr_logic(ZC, tupleselection(X, I), C, V-internal, Is) -->
	expr_logic(X, C0-R0, Is),
	{R0 = V0-_},
	new_var("TupleSelection", V),
	{ string__append("tuple_selection", I, Selection) },
	exists([R0], Is, C0, put_zc(make_atom(Selection, [V0, V]), ZC), C).
% 5.12 Binding Extension
% (Spivey Z let implemented instead)
expr_logic(ZC, let(L, X), C, R, Is) -->
	{split_pairs(L, LetIds, LetXs)},
	expr_logicL(LetXs, Cs, Rs, LetIs),
	{assoc_list__from_corresponding_lists(LetIds, vars(Rs), LS)},
        mark(VM),
                overlay(LS),
		expr_logic(X, C0-R, Is0),
        restore(VM),
	{set__delete_list(Is0, LetIds, Is1),
	Is = union(LetIs, Is1)},
	exists(Rs, Is, put_zc(make_conj(Cs), ZC), C0, C).
% 5.13 Theta Expression
expr_logic(_ZC, theta(Ref, _X, _D), F, V-internal, empty) -->
	=(S), {
		lookupSExpr(Ref, S, SL),
		assoc_list__keys(SL, DI0),
		list__sort(DI0, DI),
		list__map(lookupV(S), DI, Vs)
	},
	new_var("Theta", V),
	{F = make_atom("make_tuple", append(Vs, [V]))}.
% 5.14 Schema Expression
expr_logic(ZC, sexp(X), C, V, Is) -->
	setcomp_logic(ZC, zsetcomp, X, no, C, V, Is).
% 5.15 Binding Selection
expr_logic(ZC, select(Ref, X, Id), F, V-internal, Is) -->
	=(S), {
		lookupSExpr(Ref, S, SL),
		assoc_list__keys(SL, DI0),
		list__sort(DI0, DI),
		( list__nth_member_search(DI, Id, Index) ->
			string__int_to_string(Index, I)
		;	error("expr_logic/7: selection ident not in type")
		)
	},
	expr_logic(X, F0-R0, Is),
	{R0 = V0-_},
	new_var("Select", V),
	{ string__append("tuple_selection", I, Select) },
	exists([R0], Is, F0, put_zc(make_atom(Select, [V0, V]), ZC), F).
% 5.16 Function Application
expr_logic(ZC, zapply(_, X0, X1), F, V-internal, Is) -->
	new_var("FuncApp", V),
	expr_logic(X0, F0-R0, Is0),
	expr_logic(X1, F1-R1, Is1),
	{ R0 = V0-_, R1 = V1-_, Is = union(Is0, Is1) },
	exists([R0, R1], Is, conjoin(ZC, [F0, F1]),
			make_atom("apply", [V0, V1, V]), F).
% 5.17 Definite Description
expr_logic(ZC, mu(SExpr, M), C, V, Is) -->
	setcomp_logic(ZC, zmu, SExpr, M, C, V, Is).
% 5.18 Conditional Expression
expr_logic(ZC, if(P, X0, X1), F, V-internal, union([IsP, Is0, Is1])) -->
	{F = make_if(FP, F0, F1)},
	{ I = id(no, "***IF HACK***", []), SI = singleton(I) },
	new_var("If", V),
	zpred_logic(P, FP, IsP),
	expr_logic(X0, C0-R0, Is0),
	expr_logic(X1, C1-R1, Is1),
	{ R0 = V0-_, R1 = V1-_ },
	mark(VM),
		overlay([I-V]),
		exists([R0], union([Is0, SI]), C0, make_equals(ZC, V0, V), F0),
		exists([R1], union([Is1, SI]), C1, make_equals(ZC, V1, V), F1),
	restore(VM).
% 5.19 Substitution
% (not yet implemented)

:- pred setcomp_logic(zcontext, comp_type, sexpr, maybe(expr), formula,
					lresult, ref_ids, logstate, logstate).
:- mode setcomp_logic(in, in, in, in, out, out, out, in, out) is det.
setcomp_logic(ZC, Comp, S, M, F, V-internal, Is) -->
	{ R2 = V2-_ },
	new_var("SetComp", V),
        mark(VM),
		sexpr_logic_define(S, IVL, GCS, IsGS, CS, IsS),
		{assoc_list__keys(IVL, IL)},
		( {M = no; Comp = zlambda} ->	% Form characteristic tuple
			{assoc_list__values(IVL, VL)},
			( {VL = [Scalar]} ->
				{CExpr0 = make_true(ZC),
				V0 = Scalar,
				R0 = V0-external
				}
			;	{CExpr0 = make_tuple(ZC, append(VL, [V0]))},
				new_var("CTuple", V0),
				{R0 = V0-internal}
			),
			( {Comp = zlambda} ->
				( {M = yes(Expr)} ->
					expr_logic(Expr, CExpr1-R1, Is0),
					{ R1 = V1-_ },
					new_var("CTuple", V3),
					exists([R0, R1], Is0,
						conjoin(ZC, [CExpr0, CExpr1]),
						make_tuple(ZC, [V0, V1, V3]),
						CExpr),
					{ R2 = V3-internal }
				;	{error(
					   "setcomp_logic/9: lambda maybe is no")}
				)
			;	{CExpr = CExpr0, R2 = R0, Is0 = empty}
			)
		; {M = yes(Expr)} ->
			expr_logic(Expr, CExpr-R2, Is0)
		;	{error("setcomp_logic/9: maybe isn't yes or no")}
		),
        restore(VM),
	{set__delete_list(Is0, IL, Is1),
	Is2 = union(IsS, Is1),
	Is = union(Is2, IsGS)},
	identsToVars(Is2, VG),  % global vars
	{ Comp = zmu ->
		C = make_mu(VG, V2, conjoin(ZC, [CS, CExpr]), V)
    	;	C = make_setcomp(VG, CS, V2, CExpr, V)
	},
	exists([R2], Is, GCS, C, F0),
	{ Comp = zmu, F = put_annot(F0, source(src_mu))
	; Comp = zlambda, F = put_annot(F0, source(src_lambda))
	; Comp = zsetcomp, F = F0
	}.

%%%

% :- pred sexpr_ids(sexpr, set(ident), logstate, logstate).
% :- mode sexpr_ids(in, out, in, out) is det.
% sexpr_ids(sexpr(Ref, _, _), IS) -->
% 	=(LogState),
% 	{lookupSExpr(Ref, LogState, SL)},
% 	{assoc_list__keys(SL, IL)},
% 	{set__sorted_list_to_set(IL, IS)}.

:- pred sexpr_logic_define(
	sexpr::in,
	schema_vars::out,
	formula::out, set(ident)::out, %formula involving global vars only
	formula::out, set(ident)::out, %formula involving declared vars
	logstate::in, logstate::out) is det.
sexpr_logic_define(S, G, make_true, empty, C, Is) --> sexpr_logic_define(S, G, C, Is).
% This predicate should give back the third and fourth args as per schema_logic/8.

% first formula list involves only global vars
% second formula list involves declared vars
%%:- pred schema_logic(
%%	schema::in,
%%	schema_vars::out,
%%	formula::out, set(ident)::out, %formula involving global vars only
%%	formula::out, set(ident)::out, %formula involving declared vars
%%	logstate::in, logstate::out) is det.
%%schema_logic(schema(LD, PL), IVL, make_conj(GCDL), IsD,
%%			make_conj([make_conj([SVP|CDL]), CP]), IsP) -->
%%	decl_logicL(LD, IVL0, GCDL, CDL, IsD),
%%	{schema_vars_sort(IVL0, IVL, SVP)},
%%	mark(VM),
%%		overlay(IVL),
%%		zpred_logicL(PL, CP, IsP0),
%%	restore(VM),
%%	{assoc_list__keys(IVL, IL),
%%	set__delete_list(IsP0, IL, IsP)}.

:- pred sexpr_logic_define(sexpr, schema_vars, formula, set(ident),
							logstate, logstate).
:- mode sexpr_logic_define(in, out, out, out, in, out) is det.
sexpr_logic_define(sexpr(Ref, S, ZC), IVL, C, Is) -->
	=(LogState), {lookupSExpr(Ref, LogState, SL)},
	{assoc_list__keys(SL, IL)},
	% {set__sorted_list_to_set(IL, IS)},
	new_vars(IL, IVL),
        overlay(IVL),
	sexpr_logic(ZC, S, IVL, C, Is).

%:- pred sexpr_logic(sexpr, list(ident), formula, set(ident),
:- pred sexpr_logic(sexpr, schema_vars, formula, set(ident),
							logstate, logstate).
:- mode sexpr_logic(in, in, out, out, in, out) is det.
sexpr_logic(sexpr(_Ref, S, ZC), IVL, C, Is) -->
	sexpr_logic(ZC, S, IVL, C, Is).

:- pred sexpr_logic(sexpr, formula, set(ident), logstate, logstate).
:- mode sexpr_logic(in, out, out, in, out) is det.
sexpr_logic(sexpr(Ref, S, ZC), C, Is) -->
	=(LogState), {
		lookupSExpr(Ref, LogState, SL),
		P = (pred(I-_::in, I-V::out) is det :- lookupV(LogState, I, V)),
		list__map(P, SL, IVL)
	},
	sexpr_logic(ZC, S, IVL, C, Is).

:- pred sexpr_logic(zcontext, sexpr1, schema_vars, formula, set(ident),
							logstate, logstate).
:- mode sexpr_logic(in, in, in, out, out, in, out) is det.
sexpr_logic(ZC, X, G, put_zc(F, ZC), Is) --> sexpr_logic0(ZC, X, G, F, Is).

:- pred sexpr_logic0(zcontext, sexpr1, schema_vars, formula, set(ident),
							logstate, logstate).
:- mode sexpr_logic0(in, in, in, out, out, in, out) is det.
sexpr_logic0(ZC, ref(Id, MA), IVL, C, empty) -->
	=(S), {lookupS(S, Id, Name, Globals)},
	{lookupV(S, universe, UV)},
	% identsToVars(Globals, GVars),
	new_var("Schema", SV),
	{assoc_list__values(IVL, Vs),
	C = make_conj([
		put_zc(make_atom(Name, [UV, SV]), ZC),
		put_zc(make_atom("make_tuple", append(Vs, [SV])), ZC)
		])}.
sexpr_logic0(_ZC, text(DeclL, PredL), G, make_conj([GC, C]),
							union(IsG, Is0)) -->
	text_logic(DeclL, PredL, G, GC, IsG, C, Is0).
sexpr_logic0(_ZC, negation(X), G, make_neg(F), Is) -->
	sexpr_logic(X, G, F, Is).
sexpr_logic0(ZC, lbpred(LConn, X0, X1), _, F, union(Is0, Is1)) -->
	sexpr_logic(X0, F0, Is0),
	sexpr_logic(X1, F1, Is1),
	{ F = lconn(ZC, LConn, F0, F1) }.
sexpr_logic0(ZC, projection(Ref, X0, _X1), Sig, C, Is) -->
	exists_logic(ZC, Ref, X0, Sig, C, Is).
sexpr_logic0(ZC, hide(Ref, X, _L), Sig, C, Is) -->
	exists_logic(ZC, Ref, X, Sig, C, Is).
sexpr_logic0(ZC, quantification(Q, S, X), _, F, Is) -->
	% Q vars | S @ X
	% VG = global vars
	% VL = quantified vars
	% CS = S formula
	% CX = X formula
	( {Q = unique} ->
		unique_logic(ZC, S, sexpr(X)-ZC, F, Is)
	;	{ Q = universal ->
			F1 = make_forall(ZC, VG, VL, CS, CX)
		; 	F1 = make_exists(VG, VL, CS, CX)	% Q = exists
		},
		{F = make_conj([GCS, put_zc(F1, ZC)])},
		sexpr_logic_define(S, GS, GCS, IsGS, CS, IsS), % ERROR: Incomplete
		sexpr_logic(X, CX, IsX0),
		{split_pairs(GS, IL, VL),
		set__delete_list(IsX0, IL, IsX),
		Is0 = union(IsS, IsX),
		Is = union(Is0, IsGS)},
		identsToVars(Is0, VG)
	).
sexpr_logic0(_ZC, renaming(X, _R), Sig, F, Is) -->
	sexpr_logic(X, F, Is).
%sexpr_logic0(ZC, bsexpr(composition, X0, X1)
%sexpr_logic0(ZC, bsexpr(piping, X0, X1)
sexpr_logic0(ZC, bsexpr(Ref, SConn, X0, X1), _, F, Is) -->
	=(LogState), {lookupSExpr(Ref, LogState, SL)},
	{assoc_list__keys(SL, IL1)}, % {set__sorted_list_to_set(IL, IS)},
	new_vars(IL1, IVL1),
	{P = (pred(I::in, O::out) is semidet :- slist_ident_comp(SConn, O, I))},
	{ list__filter_map(P, IVL1, IVL0, _) },	% Last argument should be empty
	mark(VM0),
        	overlay(IVL0),
		sexpr_logic(X0, F0, Is0),
	restore(VM0),
	mark(VM1),
        	overlay(IVL1),
		sexpr_logic(X1, F1, Is1),
	restore(VM1),
	{ split_pairs(IVL0, IL0, VL) },
	{ set__delete_list(Is0, IL0, Is2), set__delete_list(Is1, IL1, Is3) }, 
	{ Is = union(Is2, Is3) },
	identsToVars(Is, VG),
	{ F = make_exists(VG, VL, make_true, put_zc(make_conj([F0, F1]), ZC)) }.
sexpr_logic0(_ZC, decoration(X, _D), Sig, F, Is) -->
	sexpr_logic(X, F, Is).
sexpr_logic0(ZC, pre(Ref, X), Sig, C, Is) -->
	exists_logic(ZC, Ref, X, Sig, C, Is).

:- pred unique_logic(zcontext, sexpr, zpred, formula, set(ident),
							logstate, logstate).
:- mode unique_logic(in, in, in, out, out, in, out) is det.
unique_logic(ZC, SExpr, Pred, F, Is) -->
	{ SExpr = sexpr(Ref, _, _) },
	{ SExpr1 = sexpr(Ref, text([include(SExpr)],[Pred]), ZC) },
	setcomp_logic(ZC, zsetcomp, SExpr1, no, F0, R, Is),
	{ R = V-_ },
	exists([R], Is, F0, make_atom("singleton_set", [V]), F).

:- pred exists_logic(zcontext, ref, sexpr, schema_vars, formula, set(ident),
							logstate, logstate).
:- mode exists_logic(in, in, in, in, out, out, in, out) is det.
exists_logic(ZC, Ref, X, Sig, F, Is) -->
	{F = make_exists(VG, QVars, make_true(ZC), F0)},
	=(LogState), {lookupSExpr(Ref, LogState, SL)},
	{assoc_list__keys(SL, IL)},
	new_vars(IL, IVL),
	{assoc_list__values(IVL, QVars)},
	mark(VM),
        	overlay(IVL),
		sexpr_logic(X, F0, Is0),
	restore(VM),
	{set__delete_list(Is0, IL, Is)},
	=(LogState1), {VG = set_map(lookupV(LogState1), Is)}.  % global vars

% first formula list involves only global vars
% second formula list involves declared vars
:- pred text_logic(
	list(decl)::in,
	list(zpred)::in,
	schema_vars::in,
	formula::out, set(ident)::out, %formula involving global vars only
	formula::out, set(ident)::out, %formula involving declared vars
	logstate::in, logstate::out) is det.
text_logic(LD, PL, IVL, make_conj(GCDL), IsD,
			make_conj([make_conj([SVP|CDL]), CP]), IsP) -->
	% decl_logicL(LD, IVL0, GCDL, CDL, IsD),
	decl_logicL(LD, GCDL, CDL, IsD),
	% {schema_vars_sort(IVL0, IVL, SVP)},	% IVL now an input
	{SVP = make_true},
	mark(VM),
		overlay(IVL),
		zpred_logicL(PL, CP, IsP0),
	restore(VM),
	{assoc_list__keys(IVL, IL),
	set__delete_list(IsP0, IL, IsP)}.

:- func diff(set(T), set(T)) = set(T).
diff(S1, S2) = S :- set__difference(S1, S2, S).

:- func set_map(pred(X, Y), set(X)) = list(Y).
:- mode set_map(pred(in, out) is det, in) = out is det.
set_map(P, S) = L :- set__to_sorted_list(S, L0), list__map(P, L0, L).

% :- pred pre_quantified(schema_vars::in, list(variable)::out) is det.
% pre_quantified(L, Vs) :- assoc_list__keys(L, L1), pre_quantified(L, L1, Vs).
% 
% :- pred pre_quantified(schema_vars::in, list(ident)::in,
% 						list(variable)::out) is det.
% pre_quantified([], _, []).
% pre_quantified([id(M, N, D)-V|T], L, Vs) :-
% 	( (D = [question_mark|_] ; list__member(id(M, N, [prime|D]), L)) ->
% 		Vs = [V|Vs1]
% 	;	Vs = Vs1
% 	),
% 	pre_quantified(T, L, Vs1).

:- func empty = set(T).
empty = E :- set__init(E).

:- func singleton(ident) = set(ident).
singleton(I) = S :- set__singleton_set(S, I).

:- func union(set(ident), set(ident)) = set(ident).
union(S1, S2) = S :- set__union(S1, S2, S).

:- func union(list(set(ident))) = set(ident).
union([]) = empty.
union([S|SL]) = U :- set__union(S, union(SL), U).

:- pred split_pairs(list(pair(X, Y))::in, list(X)::out, list(Y)::out) is det.
split_pairs([], [], []).
split_pairs([H1-H2|T], [H1|T1], [H2|T2]) :- split_pairs(T, T1, T2).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Z idents can't start with an underscore,
% but all other variable names are legal Z names
:- func identMangle(ident) = string.
identMangle(id(M, W, D)) = S :-
	( M = no, S0 = ""
	; M = yes(O), (O = delta, S0 = "$Delta_"; O = xi, S0 = "$Xi_")
	),
	string__append_list(["Z_", S0, wordMangle(W)|strokeLMangle(D)], S).

:- func wordMangle(word) = string.
wordMangle(W) = S :-
	string__to_char_list(W, CL0),
	( CL0 = ['\\'|CL1] ->
		CL = ['_', 'c'|doubleUnderscoresAndNonAlpha(CL1)]
	;	CL = doubleUnderscoresAndNonAlpha(CL0)
	),
	string__from_char_list(CL, S).

:- func doubleUnderscoresAndNonAlpha(list(character)) = list(character).
doubleUnderscoresAndNonAlpha([]) = [].
doubleUnderscoresAndNonAlpha([HI|TI]) = L :-
	( HI = '_' ->
		L = ['_', '_'|TO]
	; char__is_alpha(HI) ->
		L = [HI|TO]
	;	char__to_int(HI, HInt),
		string__int_to_string(HInt, HS),
		string__to_char_list(HS, HCL),
		list__append(['_', 'a' | HCL], TO, L)
	),
	TO = doubleUnderscoresAndNonAlpha(TI).

:- func strokeLMangle(list(stroke)) = list(string).
strokeLMangle(LI) = LO :- strokeLMangle([], LI, LO).

:- pred strokeLMangle(list(string), list(stroke), list(string)).
:- mode strokeLMangle(in, in, out) is det.
strokeLMangle(L, [], L).
strokeLMangle(L0, [H0|T0], L) :- strokeLMangle([strokeMangle(H0)|L0], T0, L).

:- func strokeMangle(stroke) = string.
strokeMangle(exclamation_mark) = "_e".
strokeMangle(question_mark) = "_q".
strokeMangle(prime) = "_p".
strokeMangle(subscript(S0)) = S :- string__append("_s", S0, S).

:- end_module zlogic.
