%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: disj_gen.m:
%
% Generate code for disjunctions.
%
%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- module disj_gen.

:- interface.

:- import_module hlds, llds, code_gen, code_info, code_util.

:- pred disj_gen__generate_semi_disj(list(hlds__goal),
					code_tree, code_info, code_info).
:- mode disj_gen__generate_semi_disj(in, out, in, out) is det.

:- pred disj_gen__generate_non_disj(list(hlds__goal),
					code_tree, code_info, code_info).
:- mode disj_gen__generate_non_disj(in, out, in, out) is det.

%---------------------------------------------------------------------------%
:- implementation.

:- import_module set, tree, list, map, std_util, require, options, globals.

%---------------------------------------------------------------------------%

disj_gen__generate_semi_disj(Goals, Code) -->
	(
		{ Goals = [] }
	->
		code_info__generate_failure(Code)
	;
		{ error("disj_gen__generate_semi_disj: should be eliminated") }
	).

%---------------------------------------------------------------------------%

disj_gen__generate_non_disj(Goals0, Code) -->
	{ disj_gen__sort_cases(Goals0, Goals1) },

		% Sanity check
	{ Goals1 = [] ->
		error("empty disjunction shouldn't be non-det")
	; Goals1 = [_]  ->
		error("singleton disjunction")
	;
		true
	},

	code_info__get_live_variables(VarList),
	{ set__list_to_set(VarList, Vars) },
	code_info__make_known_failure_cont(Vars, yes, HijackCode),

	code_info__get_globals(Globals),
	{ globals__lookup_bool_option(Globals,
			reclaim_heap_on_nondet_failure, ReclaimHeap) },
	code_info__maybe_save_hp(ReclaimHeap, SaveHeapCode),

	code_info__get_next_label(EndLab, yes),
	disj_gen__generate_non_disj_2(Goals1, EndLab, GoalsCode),
	{ Code = tree(HijackCode, tree(SaveHeapCode, GoalsCode)) },

		% since we don't know which disjunct we have come from
		% we must set the current failure continuation to unkown.
	code_info__unset_failure_cont.

:- pred disj_gen__generate_non_disj_2(list(hlds__goal), label, 
					code_tree, code_info, code_info).
:- mode disj_gen__generate_non_disj_2(in, in, out, in, out) is det.

disj_gen__generate_non_disj_2([], _EndLab, _Code) -->
	{ error("disj_gen__generate_non_disj_2") }.
disj_gen__generate_non_disj_2([Goal|Goals], EndLab, DisjCode) -->
	code_info__get_globals(Globals),
	{ globals__lookup_bool_option(Globals,
			reclaim_heap_on_nondet_failure, ReclaimHeap) },
	code_info__get_live_variables(Vars),
	code_gen__ensure_vars_are_saved(Vars, GoalCode0), 
	code_info__grab_code_info(CodeInfo),
	code_gen__generate_forced_non_goal(Goal, GoalCode1),
	{ GoalCode = tree(GoalCode0, GoalCode1) },
	code_info__slap_code_info(CodeInfo),
	{ SuccCode =
		node([
			goto(label(EndLab), label(EndLab)) -
				"Jump to end of disj"
		])
	},
	( { Goals = [] } ->
		{ error("disj_gen__generate_non_disj_2 #2") }
	; { Goals = [Goal2] } ->
		code_info__remake_with_call_info,
		code_info__restore_failure_cont(RestoreAfterFailureCode),
		code_info__maybe_get_old_hp(ReclaimHeap, RestoreHeapCode),
		code_info__maybe_pop_stack(ReclaimHeap, PopCode),
		code_gen__generate_forced_non_goal(Goal2, Goal2Code),
		{ EndCode = node([
			label(EndLab) - "End of disj"
		]) },
		{ DisjCode = tree(tree(GoalCode, SuccCode),
				tree(RestoreAfterFailureCode,
				tree(RestoreHeapCode, tree(PopCode,
				tree(Goal2Code, EndCode))))) }
	;
		code_info__remake_with_call_info,
		code_info__modify_failure_cont(ModifyFailureContCode),
		code_info__maybe_get_old_hp(ReclaimHeap, RestoreHeapCode),
		disj_gen__generate_non_disj_2(Goals, EndLab, RestCode),
		{ DisjCode = tree(tree(GoalCode, SuccCode),
				tree(ModifyFailureContCode,
				tree(RestoreHeapCode, RestCode))) }
	).

%---------------------------------------------------------------------------%

:- pred disj_gen__sort_cases(list(hlds__goal), list(hlds__goal)).
:- mode disj_gen__sort_cases(in, out) is det.

disj_gen__sort_cases(Goals0, Goals) :-
	disj_gen__sort_cases_2(Goals0, CanFail, CannotFail),
	list__append(CannotFail, CanFail, Goals).

:- pred disj_gen__sort_cases_2(list(hlds__goal), list(hlds__goal),
					list(hlds__goal)).
:- mode disj_gen__sort_cases_2(in, out, out) is det.

disj_gen__sort_cases_2([], [], []).
disj_gen__sort_cases_2([Goal0 - GoalInfo0 | Goals0], CanFail, CannotFail) :-
	disj_gen__sort_cases_2(Goals0, CanFail0, CannotFail0),
	goal_info_get_code_model(GoalInfo0, CodeModel),
	( CodeModel = model_det ->
		CannotFail = [Goal0 - GoalInfo0 | CannotFail0],
		CanFail = CanFail0
	;
		CannotFail = CannotFail0,
		CanFail = [Goal0 - GoalInfo0 | CanFail0]
	).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
