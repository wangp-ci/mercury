%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1993-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: llds.m.
% Main authors: conway, fjh.
%
% LLDS - The Low-Level Data Structure.
%
% This module defines the LLDS data structure itself.
%
%-----------------------------------------------------------------------------%

:- module ll_backend.llds.
:- interface.

:- import_module backend_libs.builtin_ops.
:- import_module backend_libs.rtti.
:- import_module check_hlds.type_util.
:- import_module hlds.code_model.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module ll_backend.layout.
:- import_module mdbcomp.goal_path.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.program_representation.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_foreign.

:- import_module bool.
:- import_module cord.
:- import_module list.
:- import_module assoc_list.
:- import_module map.
:- import_module maybe.
:- import_module set.
:- import_module counter.
:- import_module term.

%-----------------------------------------------------------------------------%

    % Foreign_interface_info holds information used when generating
    % code that uses the foreign language interface.
    %
:- type foreign_interface_info
    --->    foreign_interface_info(
                module_name,

                % Info about stuff imported from C:
                foreign_decl_info,
                foreign_import_module_info_list,
                foreign_body_info,

                % Info about stuff exported to C:
                foreign_export_decls,
                foreign_export_defns
            ).

%-----------------------------------------------------------------------------%

    % The type `c_file' is the actual LLDS.

:- type c_file
    --->    c_file(
                cfile_modulename            :: module_name,
                cfile_foreign_decl          :: foreign_decl_info,
                cfile_foreign_code          :: list(user_foreign_code),
                cfile_foreign_export        :: list(foreign_export),
                cfile_vars                  :: list(tabling_info_struct),
                cfile_scalar_common_data    :: list(scalar_common_data_array),
                cfile_vector_common_data    :: list(vector_common_data_array),
                cfile_rtti_data             :: list(rtti_data),
                cfile_ptis                  :: list(rval),
                cfile_hlds_var_nums         :: list(int),
                cfile_short_locns           :: list(int),
                cfile_long_locns            :: list(int),
                cfile_user_event_var_nums   :: list(maybe(int)),
                cfile_user_events           :: list(user_event_data),
                cfile_no_var_label_layouts  :: list(label_layout_no_vars),
                cfile_svar_label_layouts    :: list(label_layout_short_vars),
                cfile_lvar_label_layouts    :: list(label_layout_long_vars),
                cfile_i_label_to_layout_map :: map(label, layout_slot_name),
                cfile_p_label_to_layout_map :: map(label, data_id),
                cfile_call_sites            :: list(call_site_static_data),
                cfile_coverage_points       :: list(coverage_point_info),
                cfile_proc_statics          :: list(proc_layout_proc_static),
                cfile_proc_head_var_nums    :: list(int),
                cfile_proc_var_names        :: list(int),
                cfile_proc_body_bytecodes   :: list(int),
                cfile_ts_string_table       :: list(string),
                cfile_table_io_decls        :: list(table_io_decl_data),
                cfile_table_io_decl_map     :: map(pred_proc_id,
                                                layout_slot_name),
                cfile_proc_event_layouts    :: list(layout_slot_name),
                cfile_exec_traces           :: list(proc_layout_exec_trace),
                cfile_proc_layouts          :: list(proc_layout_data),
                cfile_module_layout_data    :: list(module_layout_data),
                cfile_closure_layout_data   :: list(closure_proc_id_data),
                cfile_alloc_sites           :: list(alloc_site_info),
                cfile_alloc_site_map        :: map(alloc_site_id,
                                                layout_slot_name),
                cfile_code                  :: list(comp_gen_c_module),
                cfile_user_init_c_names     :: list(string),
                cfile_user_final_c_names    :: list(string),
                cfile_complexity            :: list(complexity_proc_info)
            ).

    % Global variables generated by the compiler.
:- type tabling_info_struct
    --->    tabling_info_struct(
                % The id of the procedure whose table this structure is.
                tis_proc_label              :: proc_label,
                tis_eval_method             :: eval_method,

                tis_num_inputs              :: int,
                tis_num_outputs             :: int,
                tis_input_steps             :: list(table_step_desc),
                tis_maybe_output_steps      :: maybe(list(table_step_desc)),

                % Pseudo-typeinfos for headvars.
                tis_ptis                    :: rval,
                % Where to fill the ptis in from.
                tis_type_params             :: rval,

                tis_size_limit              :: maybe(int),
                tis_stats                   :: table_attr_statistics
            ).

:- type common_cell_type 
    --->    plain_type(list(llds_type))
            % The type is a structure with one field for each one
            % of the cell's arguments.
    ;       grouped_args_type(assoc_list(llds_type, int)).
            % The type is a structure with one field for each group
            % of the cell's arguments, with each group containing
            % at least two elements of the same llds_type.

:- type common_cell_value
    --->    plain_value(assoc_list(rval, llds_type))
    ;       grouped_args_value(list(common_cell_arg_group)).

:- type common_cell_arg_group
    --->    common_cell_grouped_args(
                % The shared type of the fields in the group.
                llds_type,

                % The number of fields in the group. This will contain
                % the length of the list in the third argument, but computed
                % only once. It ought to be more than one; if a field cannot be
                % grouped with neighbouring values of the same type, it should
                % be stored as an ungrouped arg.
                int,

                % The field values themselves.
                list(rval)
            )
    ;       common_cell_ungrouped_arg(
                llds_type,      % The type of the field.
                rval            % The field value.
            ).

:- type type_num
    --->    type_num(int).

:- type scalar_common_data_array
    --->    scalar_common_data_array(
                % The type of the elements of the array.
                scda_rval_types :: common_cell_type,

                % The type number.
                scda_type_num   :: type_num,

                % The array elements, starting at offset 0.
                scda_values     :: list(common_cell_value)
            ).

:- type vector_common_data_array
    --->    vector_common_data_array(
                % The type of the elements of the array.
                vcda_rval_types :: common_cell_type,
                % The type number.
                vcda_type_num   :: type_num,

                % The number of this vector, among all the vector cells
                % with this type for the elements.
                vcda_vector_num :: int,

                % The array elements, starting at offset 0.
                vcda_values     :: list(common_cell_value)
            ).

:- type comp_gen_c_module
    --->    comp_gen_c_module(
                cgcm_name               :: string,
                                        % The name of this C module.
                cgcm_procs              :: list(c_procedure)
                                        % The code.
            ).

:- type c_procedure
    --->    c_procedure(
                % Predicate name.
                cproc_name              :: string,

                % Original arity.
                cproc_orig_arity        :: int,

                % The pred_proc_id of this code.
                cproc_id                :: pred_proc_id,

                % The code model of the procedure.
                cproc_code_model        :: code_model,

                % The code for this procedure.
                cproc_code              :: list(instruction),

                % Proc_label of this procedure.
                cproc_proc_label        :: proc_label,

                % Source for new label numbers.
                cproc_label_nums        :: counter,

                % The compiler is allowed to perform optimizations on this
                % c_procedure that could alter RTTI information (e.g. the set
                % of variables live at a label) only if this field is set
                % to `may_alter_rtti'.
                cproc_may_alter_rtti    :: may_alter_rtti,

                cproc_c_global_vars     :: set(string)
            ).

:- type may_alter_rtti
    --->    may_alter_rtti
    ;       must_not_alter_rtti.

:- type llds_proc_id    ==  int.

    % We build up instructions as trees and then flatten the tree to a list.
    %
:- type llds_code == cord(instruction).

:- type instruction
    --->    llds_instr(
                llds_inst       :: instr,
                llds_comment    :: string
            ).

:- type nondet_tail_call
    --->    no_tail_call
            % At the point of the call, the procedure has more alternatives.
            %
            % Under these conditions, the call cannot be transformed
            % into a tail call.

    ;       checked_tail_call
            % At the point of the call, the procedure has no more alternatives,
            % and curfr and maxfr are not guaranteed to be identical.
            %
            % Under these conditions, the call can be transformed into a tail
            % call whenever its return address leads to the procedure epilogue
            % AND curfr and maxfr are found to be identical at runtime.

    ;       unchecked_tail_call.
            % At the point of the call the procedure has no more alternatives,
            % and curfr and maxfr are guaranteed to be identical.
            %
            % Under these conditions, the call can be transformed into a tail
            % call whenever its return address leads to the procedure epilogue.

:- type allow_lco
    --->    do_not_allow_lco
    ;       allow_lco.

:- type call_model
    --->    call_model_det(allow_lco)
    ;       call_model_semidet(allow_lco)
    ;       call_model_nondet(nondet_tail_call).

    % The type defines the various LLDS virtual machine instructions.
    % Each instruction gets compiled to a simple piece of C code
    % or a macro invocation.
    %
:- type instr
    --->    comment(string)
            % Insert a comment into the output code.

    ;       livevals(set(lval))
            % A list of which registers and stack locations are currently live.

    ;       block(int, int, list(instruction))
            % block(NumIntTemps, NumFloatTemps, Instrs):
            % A list of instructions that make use of
            % some local temporary variables.

    ;       assign(lval, rval)
            % assign(Lval, Rval):
            % Assign Rval to the location specified by Lval.

    ;       keep_assign(lval, rval)
            % As assign, but this operation cannot be optimized away or
            % the target replaced by a temp register, even if the target
            % *appears* to be unused by the following code.

    ;       llcall(code_addr, code_addr, list(liveinfo), term.context,
                maybe(forward_goal_path), call_model)
            % llcall(Target, Continuation, _, _, _) is the same as
            % succip = Continuation; goto(Target).
            % The third argument is the live value info for the values live
            % on return. The fourth argument gives the context of the call.
            % The fifth gives the goal id of the call in the body of the
            % procedure; it is meaningful only if execution tracing is enabled.
            % The last gives the code model of the called procedure, and says
            % whether tail recursion elimination may be applied to the call.
            % For model_non calls, this depends on whether there are any other
            % stack frames on top of the stack frame of this procedure on the
            % nondet stack. For model_det and model_semi calls, this depends on
            % whether there is some other code, executing in parallel with this
            % context, that uses the current stack frame.
            %
            % The ll prefix on call is to avoid the use of the call keyword
            % and to distinguish this function symbol from a similar one
            % in the MLDS.

    ;       mkframe(nondet_frame_info, maybe(code_addr))
            % mkframe(NondetFrameInfo, MaybeAddr) creates a nondet stack frame.
            % NondetFrameInfo says whether the frame is an ordinary frame,
            % containing the variables of a model_non procedure, or a temp
            % frame used only for its redoip/redofr slots. If the former,
            % it also gives the details of the size of the variable parts
            % of the frame (temp frames have no variable sized parts).
            % If MaybeAddr = yes(CodeAddr), then CodeAddr is the code address
            % to branch to when trying to generate the next solution from this
            % choice point. If MaybeAddr = no, then the field of the choice
            % point that contains this information is not filled in by mkframe;
            % it is up to the code following to do so.

    ;       label(label)
            % Defines a label that can be used as the target of calls, gotos,
            % etc. If the comment associated with the instruction ends with
            % "nofulljump", then gotos ending at this label will not be
            % replaced by the code starting at this label.

    ;       goto(code_addr)
            % Branch to the specified address. Note that jumps to do_fail,
            % do_redo, etc can get optimized into invocations of the macros
            % fail(), redo(), etc.

    ;       computed_goto(rval, list(maybe(label)))
            % Evaluate rval, which should be an integer, and jump to the
            % (rval+1)th label in the list. e.g. computed_goto(2, [A, B, C, D])
            % will branch to label C. A label that isn't there implicitly means
            % "not reached".

    ;       arbitrary_c_code(proc_affects_liveness, c_code_live_lvals, string)
            % Do whatever is specified by the string, which can be any piece
            % of C code that does not have any non-local flow of control.

    ;       if_val(rval, code_addr)
            % If rval is true, then goto code_addr.

    ;       save_maxfr(lval)
            % Save the current value of maxfr to the given lval. In most
            % grades, this does a straightforward copy, but in grades in which
            % stacks can be reallocated, it saves the offset of maxfr from the
            % start of the nondet stack.

    ;       restore_maxfr(lval)
            % Restore maxfr from the saved copy in the given lval. Assumes the
            % lval was saved with save_maxfr.

    ;       incr_hp(lval, maybe(tag), maybe(int), rval, maybe(alloc_site_id),
                may_use_atomic_alloc, maybe(rval), llds_reuse)
            % incr_hp(Target, MaybeTag, MaybeOffset, SizeRval, MaybeAllocId,
            %   MayUseAtomicAlloc, MaybeRegionId, MaybeReuse)
            %
            % Get a memory block of a size given by SizeRval and put its
            % address in Target, possibly after incrementing it by Offset words
            % (if MaybeOffset = yes(Offset)) and/or after tagging it with Tag
            % (if MaybeTag = yes(Tag)).
            % If MaybeAllocId = yes(AllocId) then AllocId identifies the
            % allocation site, for use in memory profiling.
            % MayUseAtomicAlloc says whether we can use the atomic variants
            % of the Boehm gc allocator calls. If MaybeRegionId =
            % yes(RegionId), then the block should be allocated in the region
            % identified by RegionId (i.e. in the region whose header RegionId
            % points to). If MaybeReuse = llds_reuse(ReuseRval,
            % MaybeFlagLval), then we should try to reuse the cell ReuseRval
            % for the block. If MaybeFlagLval = yes(FlagLval) then FlagLval
            % needs to be set to true or false indicate whether reuse was
            % really possible.

    ;       mark_hp(lval)
            % Tell the heap sub-system to store a marker (for later use in
            % restore_hp/1 instructions) in the specified lval

    ;       restore_hp(rval)
            % The rval must be a marker as returned by mark_hp/1. The effect
            % is to deallocate all the memory which was allocated since that
            % call to mark_hp.

    ;       free_heap(rval)
            % Notify the garbage collector that the heap space associated with
            % the top-level cell of the rval is no longer needed. `free' is
            % useless but harmless without conservative garbage collection.

    ;       push_region_frame(region_stack_id, embedded_stack_frame_id)
            % push_region_frame(RegionStackId, EmbeddedStackId)
            %
            % Set the stack pointer of the region stack identified by
            % RegionStackId to point to the group of stack slots identified
            % by EmbeddedStackId (which specifies the new top embedded
            % stack frame on that stack) *after* saving the old value of the
            % stack pointer in the fixed slot reserved for this purpose in
            % the new frame.
            %
            % The instruction will also fill in whatever other fixed slots
            % of the new stack frame may be filled in at this time.

    ;       region_fill_frame(region_fill_frame_op, embedded_stack_frame_id,
                rval, lval, lval)
            % region_fill_frame(FillOp, EmbeddedStackId,
            %   RegionId, NumLval, AddrLval)
            %
            % EmbeddedStackId should match the parameter of the
            % push_region_frame instruction that created the embedded stack
            % frame to which this instruction refers. RegionId should
            % identify a region (i.e. it should point to the region header).
            %
            % If the condition appropriate to FillOp is true, then this
            % instruction will
            %
            % (a) increment NumLval by one, and
            % (b) store the aspects of the region relevant to FillOp
            %     in one or more consecutive memory locations starting at
            %     AddrRval,  after which it will increment AddrRval
            %     by the number of words this uses.
            %
            % If the condition is false, the instruction will do nothing.
            %
            % The size of the frame must be big enough that the sequence of
            % region_fill_frame operations executed on it don't overflow.
            %
            % At the end of the sequence, NumLval will be stored back into
            % a fixed slot in the embedded frame using a region_set_fixed_slot
            % instruction.

    ;       region_set_fixed_slot(region_set_fixed_op, embedded_stack_frame_id,
                rval)
            % region_set_fixed_op(SetOp, EmbeddedStackId, Value)
            %
            % Given an embedded stack frame identified by EmbeddedStackId,
            % set the fixed field of this frame identified by SetOp to Value.

    ;       use_and_maybe_pop_region_frame(region_use_frame_op,
                embedded_stack_frame_id)
            % use_and_maybe_pop_region_frame(UseOp, EmbeddedStackId)
            %
            % For some values of UseOp, this instruction uses the contents of
            % the frame identified by EmbeddedStackId (including values saved
            % by region_set_fixed_op instructions) to operate on the values
            % recorded in the frame by region_fill_frame instructions.
            %
            % For some other values of UseOp, this instruction logically pops
            % the embedded stack off its stack. (The Mercury stacks are
            % untouched.)
            %
            % For yet other values of UseOp, it does both.

    ;       store_ticket(lval)
            % Allocate a new "ticket" and store it in the lval.
            %
            % Operational semantics:
            %   MR_ticket_counter = ++MR_ticket_high_water;
            %   lval = MR_trail_ptr;

    ;       reset_ticket(rval, reset_trail_reason)
            % The rval must specify a ticket allocated with `store_ticket'
            % and not yet invalidated, pruned or deallocated.
            %
            % If reset_trail_reason is `undo', `exception', or `retry',
            % restore any mutable global state to the state it was in when
            % the ticket was obtained with store_ticket(); invalidates any
            % tickets allocated after this one. If reset_trail_reason is
            % `commit' or `solve', leave the state unchanged, just check that
            % it is safe to commit to this solution (i.e. that there are no
            % outstanding delayed goals -- this is the "floundering" check).
            % Note that we do not discard trail entries after commits,
            % because that would in general be unsafe.
            %
            % Any invalidated ticket which has not yet been backtracked over
            % should be pruned with `prune_ticket' or `prune_tickets_to'.
            % Any invalidated ticket which has been backtracked over is
            % useless and should be deallocated with `discard_ticket'.
            %
            % Operational semantics:
            %   MR_untrail_to(rval, reset_trail_reason);

    ;       prune_ticket
            % Invalidates the most-recently allocated ticket.
            %
            % Operational semantics:
            %   --MR_ticket_counter;

    ;       discard_ticket
            % Deallocates the most-recently allocated ticket.
            %
            % Operational semantics:
            %   MR_ticket_high_water = --MR_ticket_counter;

    ;       mark_ticket_stack(lval)
            % Tell the trail sub-system to store a ticket counter
            % (for later use in prune_tickets_to)
            % in the specified lval.
            %
            % Operational semantics:
            %   lval = MR_ticket_counter;

    ;       prune_tickets_to(rval)
            % The rval must be a ticket counter obtained via
            % `mark_ticket_stack' and not yet invalidated. Prunes any trail
            % tickets allocated after the corresponding call to
            % mark_ticket_stack. Invalidates any later ticket counters.
            %
            % Operational semantics:
            %   MR_ticket_counter = rval;

%   ;       discard_tickets_to(rval)
            % This is only used in the hand-written code in exception.m.
            %
            % The rval must be a ticket counter obtained via
            % `mark_ticket_stack' and not yet invalidated. Deallocates any
            % trail tickets allocated after the corresponding call to
            % mark_ticket_stack. Invalidates any later ticket counters.
            %
            % Operational semantics:
            %   MR_ticket_counter = rval;
            %   MR_ticket_high_water = MR_ticket_counter;

    ;       incr_sp(int, string, stack_incr_kind)
            % Increment the det stack pointer. The string is the name of the
            % procedure, for use in collecting statistics about stack frame
            % sizes.

    ;       decr_sp(int)
            % Decrement the det stack pointer.

    ;       decr_sp_and_return(int)
            % Pick up the return address from its slot in the stack frame,
            % decrement the det stack pointer, and jump to the return address.

    ;       foreign_proc_code(
                fproc_decls             :: list(foreign_proc_decl),
                fproc_components        :: list(foreign_proc_component),
                fproc_may_call_merc     :: proc_may_call_mercury,
                fproc_fix_nolayout      :: maybe(label),
                fproc_fix_layout        :: maybe(label),
                fproc_fix_onlylayout    :: maybe(label),
                fproc_nofix             :: maybe(label),
                fproc_hash_def_label    :: maybe(label),
                fproc_stack_slot_ref    :: bool,
                fproc_maybe_dupl        :: proc_may_duplicate
            )
            % foreign_proc_code(Decls, Components. MayCallMercury,
            %   FixNoLayout, FixLayout, FixOnlyLayout, NoFix, HashDef,
            %   StackSlotRef, MayBeDupl)
            %
            % Decls says what local variable declarations are required for
            % Components, which in turn can specify how the inputs should be
            % placed in their variables, how the outputs should be picked up
            % from their variables, and C code both from the source program
            % and generated by the compiler. These components can be sequenced
            % in various ways. This flexibility is needed for nondet
            % foreign_procs, which need different copies of several components
            % for different paths through the code.
            %
            % MayCallMercury says whether the user C code components
            % may call Mercury; certain optimizations can be performed
            % across foreign_proc_code instructions that cannot call Mercury.
            %
            % Some components in some foreign_proc_code instructions refer to
            % a Mercury label. If they do, we must prevent the label
            % from being optimized away. To make it known to labelopt,
            % we mention it in the FixNoLayout, FixLayout or FixOnlyLayout
            % fields.
            %
            % FixNoLayout may give the name of a label whose name is fixed
            % because it embedded in raw C code, and which does not have
            % a layout structure. FixLayout and FixOnlyLayout may give
            % the names of labels whose names are fixed because they *do*
            % have an associated label layout structure. The label in FixLayout
            % may appear in C code; the label in FixOnlyLayout argument may not
            % (such a label may therefore may be deleted from the LLDS code
            % if it is not referred to from anywhere else). The NoFix field
            % may give the name of a label that can be changed (because it is
            % not mentioned in C code and has no associated layout structure,
            % being mentioned only in foreign_proc_fail_to components).
            %
            % If HashDef is yes, then when the code generator generates C code
            % for this foreign_proc, it should surround it with code that
            % #defines the symbol MR_HASH_DEF_LABEL_LAYOUT to the address of
            % the label layout structure of the given label. We use this
            % mechanism to pass such addresses to the debugger because when
            % the LLDS code is generated, we do not yet know what the address
            % will be (even in C source form), since the slots in the arrays
            % of label layout structures have not yet been allocated.
            %
            % If we are generating code for a target language other than C,
            % HashDef will always be no.
            %
            % StackSlotRef says whether the contents of the foreign_proc
            % C code can refer to stack slots. User-written shouldn't refer
            % to stack slots, the question is whether any compiler-generated
            % C code does.
            %
            % MayBeDupl says whether this instruction may be duplicated
            % by jump optimization.

    ;       init_sync_term(lval, int, int)
            % Initialize a synchronization term, which is a continuous number
            % of slots on the detstack.  The first argument contains the base
            % address of the synchronization term.  The second argument
            % indicates how many branches we expect to join at the end of the
            % parallel conjunction.  The third argument is an index into the
            % threadscope string table.  The string that it refers to
            % identifies this parallel conjunction within the source code.
            % (See the documentation in par_conj_gen.m and
            % runtime/mercury_context.{c,h} for further information about
            % synchronisation terms.)

    ;       fork_new_child(lval, label)
            % Create a new spark. fork(SyncTerm, Child) creates spark, to begin
            % execution at Child, where SyncTerm contains the base address of
            % the synchronisation term. Control continues at the next
            % instruction.

    ;       join_and_continue(lval, label)
            % Signal that this thread of execution has finished in the current
            % parallel conjunct. For details of how we at the end of a parallel
            % conjunct see runtime/mercury_context.{c,h}.
            % The synchronisation term is specified by the given lval.
            % The label gives the address of the code following the parallel
            % conjunction. 

    ;       lc_create_loop_control(int, lval)
            % Create a loop control structure with the given number of slots,
            % and put its address in the given lval.

    ;       lc_wait_free_slot(rval, lval, label)
            % Given an rval that holds the address of a loop control structure,
            % return the index of a free slot in that structure, waiting for
            % one to become free if necessary. The label acts as a resumption
            % point if the context suspends. It will be both defined and used
            % in the C code generated for this instruction, and should not
            % be referred to from anywhere else.

    ;       lc_spawn_off(rval, rval, label)
            % Spawn off an independent computation whose execution starts
            % at the given label and which will terminate by executing
            % a join_and_terminate_lc instruction. The first rval should
            % hold the address of the loop control structure that controls
            % the spawned-off computation, and the second should hold
            % the index of the slot occupied by that computation.
            %
            % After spawning off that computation, the original thread
            % will just fall through.

    ;       lc_join_and_terminate(rval, rval).
            % Terminate the current context, which was spawned off by a
            % spawn_off instruction. The first rval gives the address of
            % the loop control structure, and the second is the index of
            % this goal's slot in it. These two rvals should be exactly
            % the same as the two rval arguments in the original lc_spawn_off
            % instruction.

:- inst instr_llcall
    --->    llcall(ground, ground, ground, ground, ground, ground).
:- inst instr_goto
    --->    goto(ground).
:- inst instr_if_val
    --->    if_val(ground, ground).
:- inst instr_foreign_proc_code
    --->    foreign_proc_code(ground, ground, ground, ground, ground,
                ground, ground, ground, ground, ground).

:- type alloc_site_id
    --->    alloc_site_id(alloc_site_info).

:- type stack_incr_kind
    --->    stack_incr_leaf         % The incr_sp creates the stack frame
                                    % of a leaf procedure.
    ;       stack_incr_nonleaf.     % The incr_sp creates the stack frame
                                    % of a nonleaf procedure.

:- type nondet_frame_info
    --->    temp_frame(
                temp_frame_type
            )
    ;       ordinary_frame(
                string,                 % Name of the predicate.
                int                     % Number of framevar slots.
            ).

:- type c_code_live_lvals
    --->    no_live_lvals_info  % There is no information available about
                                % the live lvals used in the c_code.

    ;       live_lvals_info(
                set(lval)       % The set of lvals defined before the c_code
                                % that are live inside the c_code.
            ).

    % Temporary frames on the nondet stack exist only to provide a failure
    % environment, i.e. a place to store a redoip and a redofr. Accurate
    % garbage collection and execution tracing need to know how to
    % interpret the layout information associated with the label whose
    % address is in the redoip slot. If the label is in a procedure that
    % stores its variables on the nondet stack, the redofr slot will give
    % the address of the relevant stack frame. If the label is in a
    % procedure that stores its variables on the det stack, the temporary
    % frame will contain an extra slot containing the address of the
    % relevant frame on the det stack.
    %
:- type temp_frame_type
    --->    det_stack_proc
    ;       nondet_stack_proc.

:- type llds_reuse
    --->    no_llds_reuse
    ;       llds_reuse(
                rval,           % The cell to reuse.
                maybe(lval)     % An optional lval to set to indicate
                                % whether cell reuse was actually possible.
            ).

    % A foreign_proc_decl holds the information needed for the declaration
    % of a local variable in a block of C code emitted for a foreign_proc_code
    % instruction.
    %
:- type foreign_proc_decl
    --->    foreign_proc_arg_decl(
                % This local variable corresponds to a procedure arg.
                mer_type,   % The Mercury type of the argument.
                string,     % The string which is used to describe the type
                            % in the C code.
                string      % The name of the local variable that will hold
                            % the value of that argument inside the C block.
            ).

    % A foreign_proc_component holds one component of a foreign_proc_code
    % instruction.
    %
:- type foreign_proc_component
    --->    foreign_proc_inputs(list(foreign_proc_input))
    ;       foreign_proc_outputs(list(foreign_proc_output))
    ;       foreign_proc_user_code(maybe(prog_context), proc_affects_liveness,
                string)
    ;       foreign_proc_raw_code(can_branch_away, proc_affects_liveness,
                c_code_live_lvals, string)
    ;       foreign_proc_fail_to(label)
    ;       foreign_proc_alloc_id(alloc_site_id)
    ;       foreign_proc_noop.

:- type can_branch_away
    --->    can_branch_away
    ;       cannot_branch_away.

    % A foreign_proc_input represents the code that initializes one
    % of the input variables for a foreign_proc_code instruction.
    %
:- type foreign_proc_input
    --->    foreign_proc_input(
                % The name of the foreign language variable.
                in_foreign_lang_var_name    :: string,

                % The type of the Mercury variable being passed.
                in_var_type                 :: mer_type,

                % Whether in_var_type is a dummy type.
                in_var_type_is_dummy        :: is_dummy_type,

                % The type of the argument in original foreign_proc procedure.
                % If the foreign_proc was inlined in some other procedure,
                % then the in_var_type can be an instance of in_original_type;
                % otherwise, the two should be the same.
                in_original_type            :: mer_type,

                % The value being passed.
                in_arg_value                :: rval,

                % If in_original_type is a foreign type, info about
                % that foreign type.
                in_maybe_foreign_type       :: maybe(foreign_proc_type),

                in_box_policy               :: box_policy
            ).

    % A foreign_proc_output represents the code that stores one of
    % of the outputs for a foreign_proc_code instruction.
    %
:- type foreign_proc_output
    --->    foreign_proc_output(
                % The place where the foreign_proc should put this output.
                out_arg_dest                :: lval,

                % The type of the Mercury variable being passed.
                out_var_type                :: mer_type,

                % Whether out_var_type is a dummy type.
                out_var_type_is_dummy       :: is_dummy_type,

                % The type of the argument in original foreign_proc procedure;
                % see in_original_type above.
                out_original_type           :: mer_type,

                % The name of the foreign language variable.
                out_var_name                :: string,

                % If in_original_type is a foreign type, info about
                % that foreign type.
                out_maybe_foreign_type      :: maybe(foreign_proc_type),

                out_box_policy              :: box_policy
            ).

:- type foreign_proc_type
    --->    foreign_proc_type(
                string,         % The C type name.
                list(foreign_type_assertion)
                                % The assertions on the foreign_type
                                % declarations that the C type name came from.
            ).

:- type add_trail_ops
    --->    add_trail_ops
    ;       do_not_add_trail_ops.

:- type add_region_ops
    --->    add_region_ops
    ;       do_not_add_region_ops.

    % See runtime/mercury_trail.h.
:- type reset_trail_reason
    --->    reset_reason_undo
    ;       reset_reason_commit
    ;       reset_reason_solve
    ;       reset_reason_exception
    ;       reset_reason_retry
    ;       reset_reason_gc.

    % See runtime/mercury_region.h
    % XXX The documentation is not there yet, but should be there soon.
:- type region_stack_id
    --->    region_stack_ite
    ;       region_stack_disj
    ;       region_stack_commit.

:- type region_fill_frame_op
    --->    region_fill_ite_protect
    ;       region_fill_ite_snapshot(removed_at_start_of_else)
    ;       region_fill_semi_disj_protect
    ;       region_fill_disj_snapshot
    ;       region_fill_commit.

:- type removed_at_start_of_else
    --->    removed_at_start_of_else
    ;       not_removed_at_start_of_else.

:- type region_set_fixed_op
    --->    region_set_ite_num_protects
    ;       region_set_ite_num_snapshots
    ;       region_set_disj_num_protects
    ;       region_set_disj_num_snapshots
    ;       region_set_commit_num_entries.

:- type region_use_frame_op
    --->    region_ite_then(region_ite_kind)    % uses; pop only if semi
    ;       region_ite_else(region_ite_kind)    % uses and pops
    ;       region_ite_nondet_cond_fail         % pops
    ;       region_disj_later                   % uses
    ;       region_disj_last                    % uses and pops
    ;       region_disj_nonlast_semi_commit     % uses and pops
    ;       region_commit_success               % uses and pops
    ;       region_commit_failure.              % only pops

:- type region_ite_kind
    --->    region_ite_semidet_cond
    ;       region_ite_nondet_cond.

:- type embedded_stack_frame_id
    --->    embedded_stack_frame_id(
                % The emdedded stack frame consists of the lvals
                %
                %   stack_slot_num_to_lval(StackId, FirstSlot)
                % to
                %   stack_slot_num_to_lval(StackId, LastSlot)
                %
                % with FirstSlot < LastSlot.

                main_stack,                     % StackId
                int,                            % FirstSlot
                int                             % LastSlot
            ).

    % first_nonfixed_embedded_slot_addr(EmbeddedStackId, FixedSize):
    %
    % Return the address of the lowest-address non-fixed slot in the given
    % embedded stack frame.
    %
:- func first_nonfixed_embedded_slot_addr(embedded_stack_frame_id, int) = rval.

    % Each call instruction has a list of liveinfo, which stores information
    % about which variables are live after the call (that is, on return).
    % The information is intended for use by the native garbage collector.
    %
:- type liveinfo
    --->    live_lvalue(
                % What location does this lifeinfo structure refer to?
                layout_locn,

                % What is the type of this live value?
                live_value_type,

                % For each tvar that is a parameter of the type of this value,
                % give the set of locations where the type_info variable
                % describing the actual type bound to the type parameter
                % may be found.
                %
                % We record all the locations of the typeinfo, in case
                % different paths of arriving a this program point leave
                % the typeinfo in different sets of locations. However,
                % there must be at least type_info location that is valid
                % along all paths leading to this point.
                map(tvar, set(layout_locn))
            ).

    % For an explanation of this type, see the comment on
    % stack_layout.represent_locn.
    %
:- type layout_locn
    --->    locn_direct(lval)
    ;       locn_indirect(lval, int).

    % live_value_type describes the different sorts of data that
    % can be considered live.
    %
:- type live_value_type
    --->    live_value_succip              % A stored succip.
    ;       live_value_curfr               % A stored curfr.
    ;       live_value_maxfr               % A stored maxfr.
    ;       live_value_redoip              % A stored redoip.
    ;       live_value_redofr              % A stored redofr.
    ;       live_value_hp                  % A stored heap pointer.
    ;       live_value_trail_ptr           % A stored trail pointer.
    ;       live_value_ticket              % A stored ticket.
    ;       live_value_region_ite
    ;       live_value_region_disj
    ;       live_value_region_commit

    ;       live_value_var(prog_var, string, mer_type, llds_inst)
            % A variable (the var number and name are for execution tracing;
            % we have to store the name here because when we want to use
            % the live_value_type, we won't have access to the varset).

    ;       live_value_unwanted.
            % Something we don't need, or at least don't need
            % information about.

    % For recording information about the inst of a variable for use
    % by the garbage collector or the debugger, we don't need to know
    % what functors its parts are bound to, or which parts of it are
    % unique; we just need to know which parts of it are bound.
    % If we used the HLDS type inst to represent the instantiatedness
    % in the LLDS, we would find that insts that the LLDS wants to treat
    % as the same would compare as different. The live_value_types and
    % var_infos containing them would compare as different as well,
    % which can lead to a variable being listed more than once in
    % a label's list of live variables.
    %
    % At the moment, the LLDS only handles ground insts. When this changes,
    % the argument type of partial will have to be changed, and the code
    % that sets this field in live_value_var will have some actual work to do.
    %
:- type llds_inst
    --->    llds_inst_better_be_ground.

:- func stack_slot_to_lval(stack_slot) = lval.
:- func key_stack_slot_to_lval(_, stack_slot) = lval.

:- type lval_or_any_reg
    --->    loa_lval(lval)
    ;       loa_any_reg.

:- func abs_locn_to_lval_or_any_reg(abs_locn) = lval_or_any_reg.

:- func abs_locn_to_lval(abs_locn) = lval.

:- func key_abs_locn_to_lval(_, abs_locn) = lval.

:- type main_stack
    --->    det_stack
    ;       nondet_stack.

    % Return the id of the stack on which procedures with the given code model
    % have their stack frames.
    %
:- func code_model_to_main_stack(code_model) = main_stack.

    % stack_slot_num_to_lval(StackId, N):
    %
    % Return an lval for slot N in a stack frame on StackId.
    %
:- func stack_slot_num_to_lval(main_stack, int) = lval.

    % stack_slot_num_to_lval(StackId, N):
    %
    % Return an rval for the address of slot N in a stack frame on StackId.
    %
:- func stack_slot_num_to_lval_ref(main_stack, int) = rval.

    % An lval represents a data location or register that can be used
    % as the target of an assignment.
    %
:- type lval
    
    % Virtual machine registers.

    --->    reg(reg_type, int)
            % One of the general-purpose virtual machine registers
            % (either an int or float reg).

    ;       succip
            % Virtual machine register holding the return address for
            % det/semidet code.

    ;       maxfr
            % Virtual machine register holding a pointer to the top of
            % the nondet stack.

    ;       curfr
            % Virtual machine register holding a pointer to the current
            % nondet stack frame.

    ;       hp
            % Virtual machine register holding the heap pointer.

    ;       sp
            % Virtual machine register pointing to the top of det stack.

    ;       parent_sp
            % Virtual machine register pointing to the top of the det stack.
            % This is only set at the beginning of a parallel conjunction (and
            % restored afterwards). Parallel conjuncts which refer to stack
            % slots use this register instead of sp, as they could be running
            % in a different context, where sp would be pointing into a
            % different det stack.

    ;       temp(reg_type, int)
            % A local temporary register. These temporary registers are
            % actually local variables declared in `block' instructions.
            % They may only be used inside blocks. The code generator doesn't
            % generate these; they are introduced by use_local_vars.m.
            % The basic idea is to improve efficiency by using local variables
            % that the C compiler may be able to allocate in a register
            % rather than using stack slots.

    % Values on the stack.

    ;       stackvar(int)
            % A det stack slot. The number is the offset relative to the
            % current value of `sp'. These are used in both det and semidet
            % code. Stackvar slot numbers start at 1.

    ;       parent_stackvar(int)
            % A det stack slot. The number is the offset relative to the
            % value of `parent_sp'. These are used only in the code
            % of parallel conjuncts. Stackvar slot numbers start at 1.

    ;       framevar(int)
            % A nondet stack slot. The reference is relative to the current
            % value of `curfr'. These are used in nondet code. Framevar slot
            % numbers start at 1.

    ;       double_stackvar(double_stack_type, int)
            % Two consecutive stack slots for storing a double-precision float:
            % - stackvar(Slot), stackvar(Slot + 1)
            % - parent_stackvar(Slot), parent_stackvar(Slot + 1)
            % - framevar(Slot), framevar(Slot + 1)

    ;       succip_slot(rval)
            % The succip slot of the specified nondet stack frame; holds the
            % code address to jump to on successful exit from this nondet
            % procedure.

    ;       succfr_slot(rval)
            % The succfr slot of the specified nondet stack frame; holds the
            % address of caller's nondet stack frame.  On successful exit
            % from this nondet procedure, we will set curfr to this value.

    ;       redoip_slot(rval)
            % The redoip slot of the specified nondet stack frame; holds the
            % code address to jump to on failure.

    ;       redofr_slot(rval)
            % The redofr slot of the specified nondet stack frame; holds the
            % address of the frame that the curfr register should be set to
            % when backtracking through the redoip slot.

    ;       prevfr_slot(rval)
            % The prevfr slot of the specified nondet stack frame; holds the
            % address of the previous frame on the nondet stack.

    % Values on the heap.

    ;       field(maybe(tag), rval, rval)
            % field(Tag, Address, FieldNum) selects a field of a compound term.
            % Address is a tagged pointer to a cell on the heap; the offset
            % into the cell is FieldNum words. If Tag is yes, the arg gives
            % the value of the tag; if it is no, the tag bits will have to be
            % masked off. The value of the tag should be given if it is known,
            % since this will lead to faster code.

    % Values somewhere in memory.

    ;       mem_ref(rval)
            % A word in the heap, in the det stack or in the nondet stack.
            % The rval should have originally come from a mem_addr rval.

    ;       global_var_ref(c_global_var_ref)
            % A reference to the value of the C global variable with the given
            % name. At least for now, the global variable's type must be
            % MR_Word.

    % Pseudo-values.

    ;       lvar(prog_var).
            % The location of the specified variable. `var' lvals are used
            % during code generation, but should not be present in the LLDS
            % at any stage after code generation.

:- type double_stack_type
    --->    double_stackvar
    ;       double_parent_stackvar
    ;       double_framevar.

    % An rval is an expression that represents a value.
    %
:- type rval
    --->    lval(lval)
            % The value of an `lval' rval is just the value stored in
            % the specified lval.

    ;       var(prog_var)
            % The value of a `var' rval is just the value of the specified
            % variable. `var' rvals are used during code generation, but
            % should not be present in the LLDS at any stage after code
            % generation.

    ;       mkword(tag, rval)
            % Given a pointer and a tag, mkword returns a tagged pointer.

    ;       const(rval_const)

    ;       unop(unary_op, rval)

    ;       binop(binary_op, rval, rval)

    ;       mem_addr(mem_ref).
            % The address of a word in the heap, the det stack or the nondet
            % stack.

:- type mem_ref
    --->    stackvar_ref(rval)
            % Stack slot number.

    ;       framevar_ref(rval)
            % Stack slot number.

    ;       heap_ref(rval, maybe(int), rval).
            % The cell pointer, the tag to subtract (if unknown, all the tag
            % bits must be masked off), and the field number.

:- type c_global_var_ref
    --->    env_var_ref(string).

:- type rval_const
    --->    llconst_true
    ;       llconst_false
    ;       llconst_int(int)
    ;       llconst_foreign(string, llds_type)
            % A constant in the target language.
            % It may be a #defined constant in C which is why
            % it is represented as string.
            
    ;       llconst_float(float)
    ;       llconst_string(string)
    ;       llconst_multi_string(list(string))
            % A string containing an embedded NULL between each substring
            % in the list.

    ;       llconst_code_addr(code_addr)
    ;       llconst_data_addr(data_id, maybe(int)).
            % If the second arg is yes(Offset), then increment the address
            % of the first by Offset words.

    % A data_id is an lval representing the given variable or array slot.
    % Most references to the data_ref will want to take the address of this
    % lval (by sticking a & in front of it), but in a few situations we need
    % to be able to refer to the lval itself. One of those situations is when
    % we are defining the variable. Another is when the variable is an array,
    % and its name is implicitly taken by the C compiler as the address of the
    % first element.
    %
:- type data_id
    --->    rtti_data_id(rtti_id)
            % The global variable holding the RTTI structure identified
            % by the rtti_id.

    ;       proc_tabling_data_id(proc_label, proc_tabling_struct_id)
            % The tabling structure of the kind identified by the
            % proc_tabling_struct_id for the procedure given by the
            % proc_label.

    ;       scalar_common_data_id(type_num, int)
            % scalar_common_ref(TypeNum, CellNum) is the slot at index CellNum
            % in the array of scalar cells of type TypeNum.

    ;       vector_common_data_id(type_num, int)
            % vector_common_ref(TypeNum, CellNum) is the sequence of slots
            % starting at index CellNum in the array of vector cells of
            % type TypeNum.

    ;       layout_id(layout_name)
            % The global variable holding the layout structure identified
            % by the layout_name.

    ;       layout_slot_id(layout_slot_id_kind, pred_proc_id).
            % The slot reserved for the given pred_proc_id in in the array
            % identified by the layout_slot_id_kind.

:- type layout_slot_id_kind
    --->    table_io_decl_id.

    % There are two kinds of labels: entry labels and internal labels.
    % Entry labels are the entry points of procedures; internal labels are not.
    %
    % We have three ways of referring to entry labels. One way is valid from
    % everywhere in the program (external). Another way is valid only from
    % within the C file that defines the procedure (local). The last is valid
    % only from within the BEGIN_MODULE/END_MODULE pair that contains the
    % procedure definition. The more specialized the reference, the faster
    % jumping to the label may be, though the implementations of adjacent
    % entry_label_types may be identical in some grades.
    %
    % It is valid to declare a label using one entry_label_type and to
    % refer to it using a more specialized entry_label_type.

:- type entry_label_type
    --->    entry_label_c_local
            % proc entry; internal to a C module
    ;       entry_label_local
            % proc entry; internal to a Mercury module
    ;       entry_label_exported.
            % proc entry; exported from a Mercury module

:- type label
    --->    internal_label(int, proc_label)
    ;       entry_label(entry_label_type, proc_label).

:- type code_addr
    --->    code_label(label)
            % A label defined in this Mercury module.

    ;       code_imported_proc(proc_label)
            % A label for a procedure from another Mercury module.

    ;       code_succip
            % The address in the `succip' register.

    ;       do_succeed(bool)
            % The bool is `yes' if there are any alternatives left.
            % If the bool is `no', we do a succeed_discard() rather than
            % a succeed().

    ;       do_redo
    ;       do_fail

    ;       do_trace_redo_fail_shallow
    ;       do_trace_redo_fail_deep
            % Labels in the runtime, the code at which calls MR_trace with
            % a REDO event and then fails. The shallow variety only does this
            % if the from_full flag was set on entry to the given procedure.

    ;       do_call_closure(ho_call_variant)
    ;       do_call_class_method(ho_call_variant)

    ;       do_not_reached.
            % We should never jump to this address.

:- type ho_call_variant
    --->    generic
            % This calls for the use of one of do_call_closure_compact and
            % do_call_class_method_compact, which work for any number of
            % visible input arguments.

    ;       specialized_known(int).
            % If the integer is N, this calls for the use of do_call_closure_N
            % or do_call_class_method_N. These are specialized to assume N
            % visible input arguments.

    % A tag (used in mkword, create and field expressions and in incr_hp
    % instructions) is a small integer.
    %
:- type tag ==  int.

    % We categorize the data types used in the LLDS into a small number of
    % categories, for purposes such as choosing the right sort of register
    % for a given value to avoid unnecessary boxing/unboxing of floats.
    %
:- type llds_type
    --->    lt_bool
            % A boolean value represented using the C type `MR_Integer'.

    ;       lt_int_least8
            % A signed value that fits that contains at least eight bits,
            % represented using the C type MR_int_least8_t. Intended for use
            % in static data declarations, not for data that gets stored in
            % registers, stack slots etc.

    ;       lt_uint_least8
            % An unsigned version of int_least8, represented using the C type
            % MR_uint_least8_t.

    ;       lt_int_least16
            % A signed value that fits that contains at least sixteen bits,
            % represented using the C type MR_int_least16_t. Intended for use
            % in static data declarations, not for data that gets stored in
            % registers, stack slots etc.

    ;       lt_uint_least16
            % An unsigned version of int_least16, represented using the C type
            % MR_uint_least16_t.

    ;       lt_int_least32
            % A signed value that fits that contains at least 32 bits,
            % represented using the C type MR_int_least32_t. Intended for use
            % in static data declarations, not for data that gets stored in
            % registers, stack slots etc.

    ;       lt_uint_least32
            % An unsigned version of intleast_32, represented using the C type
            % uint_least32_t.

    ;       lt_integer
            % A Mercury `int', represented in C as a value of type `MR_Integer'
            % (which is a signed integral type of the same size as a pointer).

    ;       lt_unsigned
            % Something whose C type is `MR_Unsigned' (the unsigned equivalent
            % of `MR_Integer').

    ;       lt_float
            % A Mercury `float', represented in C as a value of type `MR_Float'
            % (which may be either `float' or `double', but is usually
            % `double').

    ;       lt_string
            % A Mercury string; represented in C as a value of type
            % `MR_String'.

    ;       lt_data_ptr
            % A pointer to data; represented in C as a value of C type
            % `MR_Word *'.

    ;       lt_code_ptr
            % A pointer to code; represented in C as a value of C type
            % `MR_Code *'.

    ;       lt_word.
            % Something that can be assigned to a value of C type `MR_Word',
            % i.e., something whose size is a word but which may be either
            % signed or unsigned (used for registers, stack slots, etc).

:- type cell_arg
    --->    cell_arg_full_word(rval, completeness)
            % Fill a single word field of a cell with the given rval, which
            % could hold a single constructor argument, or multiple constructor
            % arguments if they are packed. If the second argument is
            % `incomplete' it means that the rval covers multiple constructor
            % arguments but some of the arguments are not instantiated.

    ;       cell_arg_double_word(rval)
            % Fill two words of a cell with the given rval, which must be a
            % double precision float.

    ;       cell_arg_skip
            % Leave a single word of a cell unfilled.

    ;       cell_arg_take_addr(prog_var, maybe(rval)).
            % Take the address of a field. If the second argument is
            % `yes(Rval)' then the field is set to Rval beforehand.

:- type completeness
    --->    complete
    ;       incomplete.

:- func region_stack_id_to_string(region_stack_id) = string.

:- pred break_up_local_label(label::in, proc_label::out, int::out) is det.

    % Given a non-var rval, figure out its type.
    %
:- pred rval_type(rval::in, llds_type::out) is det.

    % Given a non-var lval, figure out its type.
    %
:- pred lval_type(lval::in, llds_type::out) is det.

    % Given a constant, figure out its type.
    %
:- pred const_type(rval_const::in, llds_type::out) is det.

    % Given a unary operator, figure out its return type.
    %
:- pred unop_return_type(unary_op::in, llds_type::out) is det.

    % Given a unary operator, figure out the type of its argument.
    %
:- pred unop_arg_type(unary_op::in, llds_type::out) is det.

    % Given a binary operator, figure out its return type.
    %
:- pred binop_return_type(binary_op::in, llds_type::out) is det.

    % Given a register, figure out its type.
    %
:- pred register_type(reg_type::in, llds_type::out) is det.

:- func get_proc_label(label) = proc_label.

:- func get_defining_module_name(proc_label) = module_name.

:- type have_non_local_gotos
    --->    have_non_local_gotos
    ;       do_not_have_non_local_gotos.

:- type have_asm_labels
    --->    have_asm_labels
    ;       do_not_have_asm_labels.

:- type have_unboxed_floats
    --->    have_unboxed_floats
    ;       do_not_have_unboxed_floats.

:- type use_float_registers
    --->    use_float_registers
    ;       do_not_use_float_registers.

:- type have_static_ground_cells
    --->    have_static_ground_cells
    ;       do_not_have_static_ground_cells.

:- type have_static_ground_floats
    --->    have_static_ground_floats
    ;       do_not_have_static_ground_floats.

:- type have_static_code_addresses
    --->    have_static_code_addresses
    ;       do_not_have_static_code_addresses.

:- type exprn_opts
    --->    exprn_opts(
                non_local_gotos         :: have_non_local_gotos,
                asm_labels              :: have_asm_labels,
                unboxed_floats          :: have_unboxed_floats,
                float_registers         :: use_float_registers,
                static_ground_cells     :: have_static_ground_cells,
                static_ground_floats    :: have_static_ground_floats,
                static_code_addresses   :: have_static_code_addresses
            ).

:- func get_nonlocal_gotos(exprn_opts) = have_non_local_gotos.
:- func get_asm_labels(exprn_opts) = have_asm_labels.
:- func get_unboxed_floats(exprn_opts) = have_unboxed_floats.
:- func get_float_registers(exprn_opts) = use_float_registers.
:- func get_static_ground_cells(exprn_opts) = have_static_ground_cells.
:- func get_static_ground_floats(exprn_opts) = have_static_ground_floats.
:- func get_static_code_addresses(exprn_opts) = have_static_code_addresses.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module require.

%-----------------------------------------------------------------------------%

first_nonfixed_embedded_slot_addr(EmbeddedStackId, FixedSize) = Rval :-
    EmbeddedStackId = embedded_stack_frame_id(MainStackId,
        _FirstSlot, LastSlot),
    % LastSlot has the lowest address; FirstSlot has the highest address.
    % The fixed slots are at the lowest addresses.
    % XXX Quan: we may need a +1 here.
    LowestAddrNonfixedSlot = LastSlot - FixedSize,
    Rval = stack_slot_num_to_lval_ref(MainStackId, LowestAddrNonfixedSlot).

stack_slot_to_lval(Slot) = Lval :-
    (
        Slot = det_slot(N, Width),
        (
            Width = single_width,
            Lval = stackvar(N)
        ;
            Width = double_width,
            Lval = double_stackvar(double_stackvar, N)
        )
    ;
        Slot = parent_det_slot(N, Width),
        (
            Width = single_width,
            Lval = parent_stackvar(N)
        ;
            Width = double_width,
            Lval = double_stackvar(double_parent_stackvar, N)
        )
    ;
        Slot = nondet_slot(N, Width),
        (
            Width = single_width,
            Lval = framevar(N)
        ;
            Width = double_width,
            Lval = double_stackvar(double_framevar, N)
        )
    ).

key_stack_slot_to_lval(_, Slot) =
    stack_slot_to_lval(Slot).

abs_locn_to_lval_or_any_reg(any_reg) = loa_any_reg.
abs_locn_to_lval_or_any_reg(abs_reg(Type, N)) = loa_lval(reg(Type, N)).
abs_locn_to_lval_or_any_reg(abs_stackvar(N, Width)) =
    loa_lval(stack_slot_to_lval(det_slot(N, Width))).
abs_locn_to_lval_or_any_reg(abs_parent_stackvar(N, Width)) =
    loa_lval(stack_slot_to_lval(parent_det_slot(N, Width))).
abs_locn_to_lval_or_any_reg(abs_framevar(N, Width)) =
    loa_lval(stack_slot_to_lval(nondet_slot(N, Width))).

abs_locn_to_lval(any_reg) = _ :-
    unexpected($module, $pred, "any_reg").
abs_locn_to_lval(abs_reg(Type, N)) = reg(Type, N).
abs_locn_to_lval(abs_stackvar(N, Width)) =
    stack_slot_to_lval(det_slot(N, Width)).
abs_locn_to_lval(abs_parent_stackvar(N, Width)) =
    stack_slot_to_lval(parent_det_slot(N, Width)).
abs_locn_to_lval(abs_framevar(N, Width)) =
    stack_slot_to_lval(nondet_slot(N, Width)).

key_abs_locn_to_lval(_, AbsLocn) =
    abs_locn_to_lval(AbsLocn).

code_model_to_main_stack(model_det) = det_stack.
code_model_to_main_stack(model_semi) = det_stack.
code_model_to_main_stack(model_non) = nondet_stack.

stack_slot_num_to_lval(det_stack, SlotNum) = stackvar(SlotNum).
stack_slot_num_to_lval(nondet_stack, SlotNum) = framevar(SlotNum).

stack_slot_num_to_lval_ref(det_stack, SlotNum) =
    mem_addr(stackvar_ref(const(llconst_int(SlotNum)))).
stack_slot_num_to_lval_ref(nondet_stack, SlotNum) =
    mem_addr(framevar_ref(const(llconst_int(SlotNum)))).

region_stack_id_to_string(region_stack_ite) = "region_ite_stack".
region_stack_id_to_string(region_stack_disj) = "region_disj_stack".
region_stack_id_to_string(region_stack_commit) = "region_commit_stack".

break_up_local_label(Label, ProcLabel, LabelNum) :-
    (
        Label = internal_label(LabelNum, ProcLabel)
    ;
        Label = entry_label(_, _),
        unexpected($module, $pred, "entry label")
    ).

lval_type(reg(RegType, _), Type) :-
    register_type(RegType, Type).
lval_type(succip, lt_code_ptr).
lval_type(maxfr, lt_data_ptr).
lval_type(curfr, lt_data_ptr).
lval_type(hp, lt_data_ptr).
lval_type(sp, lt_data_ptr).
lval_type(parent_sp, lt_data_ptr).
lval_type(temp(RegType, _), Type) :-
    register_type(RegType, Type).
lval_type(stackvar(_), lt_word).
lval_type(parent_stackvar(_), lt_word).
lval_type(framevar(_), lt_word).
lval_type(double_stackvar(_, _), lt_float).
lval_type(succip_slot(_), lt_code_ptr).
lval_type(redoip_slot(_), lt_code_ptr).
lval_type(redofr_slot(_), lt_data_ptr).
lval_type(succfr_slot(_), lt_data_ptr).
lval_type(prevfr_slot(_), lt_data_ptr).
lval_type(field(_, _, _), lt_word).
lval_type(lvar(_), _) :-
    unexpected($module, $pred, "lvar").
lval_type(mem_ref(_), lt_word).
lval_type(global_var_ref(_), lt_word).

rval_type(lval(Lval), Type) :-
    lval_type(Lval, Type).
rval_type(var(_), _) :-
    unexpected($module, $pred, "var").
    %
    % Note that mkword and data_addr consts must be of type data_ptr,
    % not of type word, to ensure that static consts containing them
    % get type `const MR_Word *', not type `MR_Word'; this is necessary because
    % casts from pointer to int must not be used in the initializers for
    % constant expressions -- if they are, then lcc barfs, and gcc generates
    % bogus code on some systems, (e.g. IRIX with shared libs). If the second
    % argument to mkword is an integer, not a pointer, then we will end up
    % casting it to a pointer, but casts from integer to pointer are OK;
    % it is only the reverse direction we need to avoid.
    %
rval_type(mkword(_, _), lt_data_ptr).
rval_type(const(Const), Type) :-
    const_type(Const, Type).
rval_type(unop(UnOp, _), Type) :-
    unop_return_type(UnOp, Type).
rval_type(binop(BinOp, _, _), Type) :-
    binop_return_type(BinOp, Type).
rval_type(mem_addr(_), lt_data_ptr).

const_type(llconst_true, lt_bool).
const_type(llconst_false, lt_bool).
const_type(llconst_int(_), lt_integer).
const_type(llconst_foreign(_, Type), Type).
const_type(llconst_float(_), lt_float).
const_type(llconst_string(_), lt_string).
const_type(llconst_multi_string(_), lt_string).
const_type(llconst_code_addr(_), lt_code_ptr).
const_type(llconst_data_addr(_, _), lt_data_ptr).

unop_return_type(mktag, lt_word).
unop_return_type(tag, lt_word).
unop_return_type(unmktag, lt_word).
unop_return_type(strip_tag, lt_word).
unop_return_type(mkbody, lt_word).
unop_return_type(unmkbody, lt_word).
unop_return_type(bitwise_complement, lt_integer).
unop_return_type(logical_not, lt_bool).
unop_return_type(hash_string, lt_integer).
unop_return_type(hash_string2, lt_integer).
unop_return_type(hash_string3, lt_integer).

unop_arg_type(mktag, lt_word).
unop_arg_type(tag, lt_word).
unop_arg_type(unmktag, lt_word).
unop_arg_type(strip_tag, lt_word).
unop_arg_type(mkbody, lt_word).
unop_arg_type(unmkbody, lt_word).
unop_arg_type(bitwise_complement, lt_integer).
unop_arg_type(logical_not, lt_bool).
unop_arg_type(hash_string, lt_string).
unop_arg_type(hash_string2, lt_string).
unop_arg_type(hash_string3, lt_string).

binop_return_type(int_add, lt_integer).
binop_return_type(int_sub, lt_integer).
binop_return_type(int_mul, lt_integer).
binop_return_type(int_div, lt_integer).
binop_return_type(int_mod, lt_integer).
binop_return_type(unchecked_left_shift, lt_integer).
binop_return_type(unchecked_right_shift, lt_integer).
binop_return_type(bitwise_and, lt_integer).
binop_return_type(bitwise_or, lt_integer).
binop_return_type(bitwise_xor, lt_integer).
binop_return_type(logical_and, lt_bool).
binop_return_type(logical_or, lt_bool).
binop_return_type(eq, lt_bool).
binop_return_type(ne, lt_bool).
binop_return_type(array_index(_Type), lt_word).
binop_return_type(str_eq, lt_bool).
binop_return_type(str_ne, lt_bool).
binop_return_type(str_lt, lt_bool).
binop_return_type(str_gt, lt_bool).
binop_return_type(str_le, lt_bool).
binop_return_type(str_ge, lt_bool).
binop_return_type(str_cmp, lt_integer).
binop_return_type(int_lt, lt_bool).
binop_return_type(int_gt, lt_bool).
binop_return_type(int_le, lt_bool).
binop_return_type(int_ge, lt_bool).
binop_return_type(unsigned_le, lt_bool).
binop_return_type(float_plus, lt_float).
binop_return_type(float_minus, lt_float).
binop_return_type(float_times, lt_float).
binop_return_type(float_divide, lt_float).
binop_return_type(float_eq, lt_bool).
binop_return_type(float_ne, lt_bool).
binop_return_type(float_lt, lt_bool).
binop_return_type(float_gt, lt_bool).
binop_return_type(float_le, lt_bool).
binop_return_type(float_ge, lt_bool).
binop_return_type(float_word_bits, lt_word).
binop_return_type(float_from_dword, lt_float).
binop_return_type(body, lt_word).
binop_return_type(compound_eq, lt_bool).
binop_return_type(compound_lt, lt_bool).

register_type(reg_r, lt_word).
register_type(reg_f, lt_float).

get_proc_label(entry_label(_, ProcLabel)) = ProcLabel.
get_proc_label(internal_label(_, ProcLabel)) = ProcLabel.

get_defining_module_name(ordinary_proc_label(ModuleName, _, _, _, _, _))
    = ModuleName.
get_defining_module_name(special_proc_label(ModuleName, _, _, _, _, _))
    = ModuleName.

get_nonlocal_gotos(ExprnOpts) = ExprnOpts ^ non_local_gotos.
get_asm_labels(ExprnOpts) = ExprnOpts ^ asm_labels.
get_static_ground_cells(ExprnOpts) = ExprnOpts ^ static_ground_cells.
get_unboxed_floats(ExprnOpts) = ExprnOpts ^ unboxed_floats.
get_float_registers(ExprnOpts) = ExprnOpts ^ float_registers.
get_static_ground_floats(ExprnOpts) = ExprnOpts ^ static_ground_floats.
get_static_code_addresses(ExprnOpts) = ExprnOpts ^ static_code_addresses.

%-----------------------------------------------------------------------------%
:- end_module ll_backend.llds.
%-----------------------------------------------------------------------------%
