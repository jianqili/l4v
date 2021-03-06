(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(NICTA_GPL)
 *)

theory Tcb_DR
imports Ipc_DR Arch_DR
begin

(*
 * A "normal" TCB is a non-idle TCB. (Idle is special, because it
 * doesn't get lifted up to capDL.
 *)
abbreviation "normal_tcb_at x \<equiv> (tcb_at x) and (not_idle_thread x)"


(*
 * Translate an abstract spec TCB invocation into a CDL TCB invocation.
 *)
definition translate_tcb_invocation_thread_ctrl_buffer :: "(word32 \<times> (cap\<times> word32\<times> bool list) option) option \<Rightarrow> (cdl_cap \<times> cdl_cap_ref) option"
where
  "translate_tcb_invocation_thread_ctrl_buffer buffer \<equiv>
  (case buffer of None \<Rightarrow> None | Some (a, None) \<Rightarrow> None
  | Some (a, Some (c,d)) \<Rightarrow> Some (transform_cap c, (transform_cslot_ptr d)))"

definition
  translate_tcb_invocation :: "Invocations_A.tcb_invocation \<Rightarrow> cdl_tcb_invocation"
where
  "translate_tcb_invocation x \<equiv>
    case x of
        Invocations_A.ReadRegisters oid' x' _ _ \<Rightarrow>
          Invocations_D.ReadRegisters oid' x' 0 0
      | Invocations_A.WriteRegisters oid' b' regs' _ \<Rightarrow>
          Invocations_D.WriteRegisters oid' b' [0] 0
      | Invocations_A.CopyRegisters dest_tcb src_tcb a b c d e \<Rightarrow>
          Invocations_D.CopyRegisters dest_tcb src_tcb a b c d 0
      | Invocations_A.ThreadControl target_tcb target_slot faultep _ croot vroot buffer \<Rightarrow>
          Invocations_D.ThreadControl
             target_tcb
             (transform_cslot_ptr target_slot)
             (option_map of_bl faultep)
             (option_map (\<lambda>r. ((transform_cap \<circ> fst) r,(transform_cslot_ptr \<circ> snd) r)) croot)
             (option_map (\<lambda>r. ((transform_cap \<circ> fst) r,(transform_cslot_ptr \<circ> snd) r)) vroot)
             (translate_tcb_invocation_thread_ctrl_buffer buffer)
      | Invocations_A.Suspend target_tcb \<Rightarrow>
          Invocations_D.Suspend target_tcb
      | Invocations_A.Resume target_tcb \<Rightarrow>
          Invocations_D.Resume target_tcb"

lemma decode_set_ipc_buffer_translate_tcb_invocation:
  "\<lbrakk>x \<noteq> [];excaps ! 0 = (a,b,c)\<rbrakk> \<Longrightarrow>
    (\<And>s. \<lbrace>op = s\<rbrace> decode_set_ipc_buffer x (cap.ThreadCap t) slot' excaps
    \<lbrace>\<lambda>rv s'. s' = s \<and> rv = tcb_invocation.ThreadControl t slot' None None None None (tc_new_buffer rv) \<and>
      translate_tcb_invocation_thread_ctrl_buffer (tc_new_buffer rv) = (if (x ! 0) = 0 then None
      else Some (reset_mem_mapping (transform_cap a), transform_cslot_ptr (b, c)))
    \<rbrace>,\<lbrace>\<lambda>ft. op = s\<rbrace>)"
  apply (clarsimp simp:decode_set_ipc_buffer_def whenE_def | rule conjI)+
    apply (wp , simp_all add:translate_tcb_invocation_thread_ctrl_buffer_def)
  apply (clarsimp | rule conjI)+
  apply (wp , clarsimp simp:translate_tcb_invocation_thread_ctrl_buffer_def)
    apply (wp | clarsimp | rule conjI)+
    apply (simp add:check_valid_ipc_buffer_def)
    apply (wpc,wp)
    apply wpc
    apply (wp hoare_whenE_wp)
  apply (case_tac a)
    apply (simp_all add:derive_cap_def split del:if_splits)
    apply (wp|clarsimp split del:if_splits)+
  apply (case_tac arch_cap)
      apply (simp_all add:arch_derive_cap_def split del:if_splits)
      apply (wp | clarsimp split del:if_splits)+
    apply (clarsimp simp:transform_mapping_def)
   apply (rule hoare_pre)
    apply wpc
     apply (wp | clarsimp split del:if_splits)+
  apply (rule hoare_pre)
   apply wpc
    apply wp
  apply clarsimp
done

lemma derive_cap_translate_tcb_invocation:
 "\<lbrace>op = s\<rbrace>derive_cap a b \<lbrace>\<lambda>rv. op = s\<rbrace>,\<lbrace>\<lambda>rv. \<top>\<rbrace>"
 apply (simp add:derive_cap_def)
 apply (case_tac b)
   apply (clarsimp simp:ensure_no_children_def whenE_def |wp)+
 apply (clarsimp simp:arch_derive_cap_def)
 apply (case_tac arch_cap)
   apply (clarsimp simp:ensure_no_children_def whenE_def |wp)+
 apply (clarsimp split:option.splits | rule conjI | wp)+
 done


lemma derive_cnode_cap_as_vroot:
  "\<lbrace>op = s \<rbrace> derive_cap (ba, ca) aa
   \<lbrace>\<lambda>vroot_cap'.
      if is_valid_vtable_root vroot_cap' then \<lambda>sa. sa = s  \<and> vroot_cap' = aa
      else op = s\<rbrace>, \<lbrace>\<lambda>r. op = s\<rbrace>"
  apply (simp add:derive_cap_def is_valid_vtable_root_def)
  apply (case_tac aa)
    apply (clarsimp|wp)+
  apply (case_tac arch_cap)
    apply (clarsimp simp:arch_derive_cap_def split:option.splits |wp)+
  apply (intro conjI)
    apply (clarsimp simp:arch_derive_cap_def split:option.splits |wp)+
  apply (intro conjI)
    apply (clarsimp simp:arch_derive_cap_def | wp)+
done

lemma derive_cnode_cap_as_croot:
  "\<lbrace>op = s\<rbrace> derive_cap (b, c) a
   \<lbrace>\<lambda>croot_cap'. if Structures_A.is_cnode_cap croot_cap' then \<lambda>sa. s = sa \<and> croot_cap' = a \<and> is_cnode_cap a else op = s\<rbrace>,\<lbrace>\<lambda>r. op = s\<rbrace>"
  apply (clarsimp simp:derive_cap_def is_cap_simps)
  apply (case_tac a)
    apply (clarsimp|wp)+
  apply (case_tac arch_cap)
    apply (clarsimp simp:arch_derive_cap_def split:option.splits |wp)+
  apply (intro conjI)
    apply (clarsimp simp:arch_derive_cap_def split:option.splits |wp)+
  apply (intro conjI)
    apply (clarsimp simp:arch_derive_cap_def | wp)+
done

lemma valid_vtable_root_update:
  "\<lbrakk> is_valid_vtable_root (CSpace_A.update_cap_data False x aa)\<rbrakk>
         \<Longrightarrow> CSpace_A.update_cap_data False x aa = aa"
 apply (clarsimp simp:update_cap_data_def badge_update_def is_valid_vtable_root_def Let_def the_cnode_cap_def
   split:if_splits cap.split_asm)
 apply (clarsimp simp:is_arch_cap_def arch_update_cap_data_def the_arch_cap_def split:arch_cap.splits cap.split_asm)
done

lemma decode_set_space_translate_tcb_invocation:
  "\<And>s. \<lbrace>op = s\<rbrace> decode_set_space x (cap.ThreadCap t) slot' (excaps')
    \<lbrace>\<lambda>rv s'. s' = s \<and>
    (rv =  tcb_invocation.ThreadControl t slot' (tc_new_fault_ep rv) None (tc_new_croot rv) (tc_new_vroot rv) None) \<and>
    (tc_new_fault_ep rv = Some (to_bl (x!0)))
    \<and> (option_map (\<lambda>c. snd c)  (tc_new_croot rv) = Some (snd (excaps' ! 0)))
    \<and> (option_map (\<lambda>c. snd c)  (tc_new_vroot rv) = Some (snd (excaps' ! Suc 0)))
    \<and> (option_map (\<lambda>c. fst c ) (tc_new_croot rv)
        = (if (x!1 = 0) then Some (fst (excaps' ! 0)) else Some (update_cap_data False (x ! Suc 0) (fst (excaps' ! 0)))))
    \<and> (option_map (\<lambda>c. fst c)  (tc_new_vroot rv) = Some (fst (excaps' ! Suc 0)))
    \<and> (option_map (\<lambda>c. is_cnode_cap (fst c)) (tc_new_croot rv) = Some True)
    \<rbrace>,\<lbrace>\<lambda>rv. op = s\<rbrace>"
  apply (case_tac "excaps' ! 0")
  apply (case_tac "excaps' ! Suc 0")
  apply (clarsimp simp:decode_set_space_def whenE_def | rule conjI)+
          apply wp
        apply (clarsimp simp: | rule conjI)+
          apply (wp|clarsimp)+
        apply (rule_tac P ="croot_cap' = a \<and> is_cnode_cap a" in hoare_gen_asmE)
        apply clarsimp
        apply (rule validE_validE_R)
        apply (wp hoare_post_impErr[OF derive_cnode_cap_as_vroot],simp)
        apply (wp|clarsimp)+
        apply (wp hoare_post_impErr[OF derive_cnode_cap_as_croot],simp)
        apply (wp|clarsimp)+
  apply (clarsimp simp:whenE_def | rule conjI | wp)+
        apply (rule_tac P ="croot_cap' = update_cap_data False (x! 1) a \<and> is_cnode_cap croot_cap'" in hoare_gen_asmE)
        apply (rule validE_validE_R)
        apply simp
        apply (rule_tac s1 = s in hoare_post_impErr[OF derive_cnode_cap_as_vroot],simp)
        apply (rule conjI|simp split:split_if_asm)+
        apply (wp|clarsimp)+
        apply (rule validE_validE_R)
        apply (rule_tac s1 = s in hoare_post_impErr[OF derive_cnode_cap_as_croot])
        apply (wp|clarsimp)+
  apply (clarsimp simp:whenE_def | rule conjI | wp)+
        apply (rule_tac P ="croot_cap' = a \<and> is_cnode_cap a" in hoare_gen_asmE)
        apply clarsimp
        apply (rule validE_validE_R)
        apply (rule_tac s1 = s in hoare_post_impErr[OF derive_cnode_cap_as_vroot],simp)
          apply (clarsimp split:if_splits simp:valid_vtable_root_update)
        apply (wp|clarsimp)+
        apply (wp hoare_post_impErr[OF derive_cnode_cap_as_croot],simp)
        apply (wp|clarsimp)+
   apply (clarsimp simp: | rule conjI | wp)+
        apply (rule_tac P ="croot_cap' = update_cap_data False (x! 1) a \<and> is_cnode_cap croot_cap'" in hoare_gen_asmE)
        apply (rule validE_validE_R)
        apply simp
        apply (rule_tac s1 = s in hoare_post_impErr[OF derive_cnode_cap_as_vroot],simp)
        apply (rule conjI|simp split:split_if_asm)+
          apply (rule valid_vtable_root_update)
          apply clarsimp+
        apply (wp|clarsimp)+
     apply (rule validE_validE_R)
        apply (rule hoare_post_impErr[OF derive_cnode_cap_as_croot])
        apply fastforce+
        apply (wp|clarsimp)+
done

lemma decode_tcb_cap_label_not_match:
  "\<lbrakk>\<forall>ui. Some (TcbIntent ui) \<noteq> transform_intent (invocation_type label') args'; cap' = Structures_A.ThreadCap t\<rbrakk>
    \<Longrightarrow> \<lbrace>op=s\<rbrace>Decode_A.decode_tcb_invocation label' args' cap' slot' excaps' \<lbrace>\<lambda>r. \<bottom>\<rbrace>,\<lbrace>\<lambda>e. op=s\<rbrace>"
  apply (simp add:Decode_A.decode_tcb_invocation_def)
  apply (case_tac "invocation_type label'")
    apply (simp_all add:transform_intent_def)
    apply wp
    apply (simp_all add:whenE_def transform_intent_tcb_read_registers_def transform_intent_tcb_write_registers_def
        transform_intent_untyped_retype_def transform_intent_tcb_configure_def transform_intent_tcb_set_space_def
        transform_intent_tcb_copy_registers_def transform_intent_tcb_set_priority_def transform_intent_tcb_set_ipc_buffer_def
    split:option.splits)
    apply (simp_all split:List.list.split list.split_asm option.splits)
    apply (wp | clarsimp | rule conjI)+
      apply (simp add: decode_read_registers_def decode_write_registers_def decode_set_ipc_buffer_def
          decode_copy_registers_def decode_set_space_def decode_tcb_configure_def decode_set_priority_def | wp)+
  done

lemma is_cnode_cap_update_cap_data:
  "Structures_A.is_cnode_cap (CSpace_A.update_cap_data x w a) \<Longrightarrow> is_cnode_cap a"
  apply (case_tac a)
    apply (clarsimp simp:update_cap_data_def is_arch_cap_def badge_update_def
      is_cap_simps split:split_if_asm)+
done

lemma update_cnode_cap_data:
  "\<lbrakk>Some af = (if w = 0 then Some ab else Some (CSpace_A.update_cap_data False w ab)); Structures_A.is_cnode_cap af\<rbrakk>
  \<Longrightarrow> transform_cap af = cdl_update_cnode_cap_data (transform_cap ab) w"
  apply (clarsimp simp:is_cap_simps)
  apply (clarsimp split:if_splits)
    apply (simp add:cdl_update_cnode_cap_data_def CSpace_D.update_cap_data_def)
  apply (clarsimp simp: update_cap_data_def split:if_splits)
  apply ((cases ab,simp_all add:badge_update_def)+)[2]
  apply (clarsimp simp:is_cap_simps the_cnode_cap_def word_size split:split_if_asm simp:Let_def)
  apply (clarsimp simp:cdl_update_cnode_cap_data_def WordSetup.word_bits_def of_drop_to_bl
    word_size mask_twice dest!:leI)
done

lemma decode_tcb_corres:
  "\<lbrakk> Some (TcbIntent ui) = transform_intent (invocation_type label') args';
     cap = transform_cap cap';
     cap' = Structures_A.ThreadCap t;
     slot = transform_cslot_ptr slot';
     excaps = transform_cap_list excaps' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> (\<lambda>x y. x = translate_tcb_invocation y)) \<top> \<top>
     (Tcb_D.decode_tcb_invocation cap slot excaps ui)
     (Decode_A.decode_tcb_invocation label' args' cap' slot' excaps')"
  apply(unfold Tcb_D.decode_tcb_invocation_def Decode_A.decode_tcb_invocation_def)
  apply (drule sym, frule transform_tcb_intent_invocation)
  apply (unfold transform_cap_def)
  apply (unfold transform_cap_list_def)
  apply(case_tac "invocation_type label'")
    apply(simp_all)
          (* TCBReadRegisters *)
            apply(clarsimp simp: decode_read_registers_def split: list.split)
            apply(intro conjI impI allI)
              apply(auto)[1]
             apply(auto)[1]
            apply(unfold bindE_def)[1]
            apply(rule corres_symb_exec_r[where Q'="\<lambda> rv s. True"])
               apply(case_tac rv)
                apply(simp add: lift_def)
                apply(rule corres_alternate2, simp)
               apply(simp add: lift_def)
               apply(simp add: liftE_def lift_def)
               apply(rule corres_symb_exec_r[where Q'="\<lambda> rv s. True"])
                  apply(fold bindE_def)
                  apply(rule dcorres_whenE_throwError_abstract')
                   apply(rule corres_alternate2)
                   apply simp
                  apply (rule corres_alternate1)
                  apply (clarsimp simp: returnOk_def translate_tcb_invocation_def)
                 apply(wp)
            apply(simp add: range_check_def unlessE_def[abs_def])

         (* TCBWriteRegisters *)
           apply(clarsimp simp: decode_write_registers_def split: list.split)
           apply(intro impI conjI allI)
             apply(auto)[1]
            apply(auto)[1]
           apply(rule dcorres_whenE_throwError_abstract')
            apply(fastforce intro: corres_alternate2 simp: throwError_def)
           apply(simp add: liftE_def bindE_def lift_def)
           apply(rule corres_symb_exec_r[where Q'="\<lambda> rv s. True"])
              apply(fold bindE_def, rule dcorres_whenE_throwError_abstract')
               apply(fastforce intro: corres_alternate2 simp: throwError_def)
              apply(fastforce intro: corres_alternate1 simp: returnOk_def
                  translate_tcb_invocation_def)
             apply(wp)

          (* TCBCopyRegisters *)
          apply(clarsimp simp: decode_copy_registers_def)
          apply (case_tac args')
            apply (clarsimp simp:whenE_def dcorres_alternative_throw split:option.splits)+
          apply (case_tac "map fst excaps'")
            apply (clarsimp simp: dcorres_alternative_throw split:option.splits)+
          apply (case_tac ab)
            apply (clarsimp simp:throw_on_none_def get_index_def dcorres_alternative_throw split:option.splits)+
            apply (rule corres_alternate1)
            apply (clarsimp simp:returnOk_def corres_underlying_def translate_tcb_invocation_def return_def)
            apply ((clarsimp simp:throw_on_none_def get_index_def dcorres_alternative_throw split:option.splits)+)[5]

          (* TCBConfigures *)
          apply (clarsimp simp:decode_tcb_configure_def dcorres_alternative_throw whenE_def)
          apply (clarsimp simp:decode_set_priority_def)
          apply (clarsimp simp:alternative_bindE_distrib bindE_assoc bind_bindE_assoc)
          apply (rule corres_guard_imp)
           apply (rule dcorres_symb_exec_rE)
              apply (rule dcorres_symb_exec_r)
                apply simp
                apply (rule conjI[rotated])
                 apply clarsimp
                 apply (case_tac "excaps' ! 2")
                 apply (case_tac "excaps' ! Suc 0")
                 apply (case_tac "excaps' ! 0")
                 apply clarsimp
                 apply (rule split_return_throw_thingy)
                   apply (rule_tac a = a and b = b and c = c in decode_set_ipc_buffer_translate_tcb_invocation)
                    apply simp+
                  apply (rule split_return_throw_thingy)
                    apply (rule decode_set_space_translate_tcb_invocation)
                   apply (clarsimp simp:throw_on_none_def get_index_def)
                   apply (rule conjI | clarsimp)+
                     apply (rule corres_alternate1,rule dcorres_returnOk)
                     apply (clarsimp simp:translate_tcb_invocation_def update_cnode_cap_data)
                    apply (clarsimp simp:| rule conjI)+
                    apply (rule corres_alternate1,rule dcorres_returnOk)
                    apply (clarsimp simp:translate_tcb_invocation_def update_cnode_cap_data)
                   apply (clarsimp simp:no_fail_def)+
                apply (rule dcorres_alternative_throw)
               apply wp
              apply ((clarsimp simp: decode_set_priority_error_choice_def | wp)+)[5]
          (* TCBSetPriority *)
          apply (clarsimp simp: decode_set_priority_def dcorres_alternative_throw)
          apply (rule corres_guard_imp)
            apply (rule dcorres_symb_exec_rE)
              apply (rule dcorres_symb_exec_r)
                apply simp
                apply (rule conjI[rotated])
                 apply clarsimp
                 apply (rule corres_alternate1, rule dcorres_returnOk)
                 apply (clarsimp simp:translate_tcb_invocation_def translate_tcb_invocation_thread_ctrl_buffer_def)
                apply clarsimp
                apply (rule dcorres_alternative_throw)
               apply wp
              apply ((clarsimp simp: decode_set_priority_error_choice_def | wp)+)[5]
          (* TCBSetIPCBuffer *)
          apply (clarsimp simp:transform_intent_def transform_intent_tcb_set_ipc_buffer_def)
          apply (case_tac args')
            apply clarsimp+
          apply (case_tac "excaps' ! 0")
          apply (clarsimp simp:throw_on_none_def get_index_def dcorres_alternative_throw | rule conjI)+
            apply (rule corres_return_throw_thingy)
            apply (rule decode_set_ipc_buffer_translate_tcb_invocation)
              apply fastforce+
            apply (clarsimp|rule conjI)+
              apply (clarsimp simp:translate_tcb_invocation_def translate_tcb_invocation_thread_ctrl_buffer_def
                split:option.splits tcb_invocation.splits)
            apply (clarsimp simp:decode_set_ipc_buffer_def dcorres_alternative_throw)+
            apply (rule corres_alternate1[OF dcorres_returnOk])
            apply (clarsimp simp:translate_tcb_invocation_def translate_tcb_invocation_thread_ctrl_buffer_def)

          (* TCBSetSpace *)
          apply (clarsimp simp:throw_on_none_def get_index_def dcorres_alternative_throw | rule conjI)+
          apply (rule corres_return_throw_thingy)
            apply (rule decode_set_space_translate_tcb_invocation)
              apply (clarsimp split del:if_splits)+
            apply (clarsimp simp:translate_tcb_invocation_def translate_tcb_invocation_thread_ctrl_buffer_def)
            apply (case_tac "excaps' ! 0",simp,case_tac "excaps' ! Suc 0",simp)
            apply (simp add:update_cnode_cap_data)
          apply (simp add:decode_set_space_def dcorres_alternative_throw | rule conjI)+

          (* TCBSuspend *)
          apply clarsimp
          apply (rule corres_alternate1[OF dcorres_returnOk])
          apply (simp add:translate_tcb_invocation_def)

          (* TCBResume *)
          apply clarsimp
          apply (rule corres_alternate1[OF dcorres_returnOk])
          apply (simp add:translate_tcb_invocation_def)

          (* ARMPageMap *)
          apply (clarsimp simp:transform_intent_def)

          (* ARMASIDPoolAssign *)
          apply (clarsimp simp:transform_intent_def)
done

(* If the argument to "as_user" is idempotent, then so is the call. *)
lemma dcorres_idempotent_as_user:
  "\<lbrakk> \<And>a. \<lbrace> \<lambda>s. s = a \<rbrace> x \<lbrace> \<lambda>_ s. s = a \<rbrace> \<rbrakk> \<Longrightarrow>
     dcorres dc \<top> (tcb_at u) (return q) (as_user u x)"
  apply (clarsimp simp: as_user_def)
  apply (clarsimp simp: corres_underlying_def bind_def split_def set_object_def return_def get_def put_def
         get_tcb_def gets_the_def gets_def assert_opt_def tcb_at_def select_f_def valid_def split_def
         split: option.split Structures_A.kernel_object.split)
  done

lemma transform_full_intent_kheap_update_eq:
  "\<lbrakk> q \<noteq> u' \<rbrakk> \<Longrightarrow> transform_full_intent (machine_state (s\<lparr>kheap := kheap s(u' \<mapsto> x')\<rparr>)) q = transform_full_intent (machine_state s) q"
  apply (rule ext)
  apply (clarsimp simp: transform_full_intent_def)
 done


(* Various WP rules. *)
crunch tcb_at [wp]: "IpcCancel_A.suspend" "tcb_at t" (wp: set_cap_tcb)

(* Suspend functions correspond. *)
lemma suspend_corres:
  "dcorres dc \<top> (tcb_at obj_id and not_idle_thread obj_id and invs and valid_etcbs)
     (Tcb_D.suspend obj_id) (IpcCancel_A.suspend obj_id)"
  apply (rule corres_guard_imp)
    apply (clarsimp simp: IpcCancel_A.suspend_def Tcb_D.suspend_def)
   apply (rule corres_split[OF _ finalise_ipc_cancel])
     apply (rule dcorres_rhs_noop_below_True[OF tcb_sched_action_dcorres])
     apply (rule set_thread_state_corres)
     apply wp
    apply (clarsimp simp:not_idle_thread_def conj_ac)
    apply wp
   apply simp
  apply (clarsimp simp:st_tcb_at_def not_idle_thread_def
    obj_at_def generates_pending_def
      split:Structures_A.thread_state.split_asm)
done

lemma dcorres_setup_reply_master:
  "dcorres dc \<top> (valid_objs and tcb_at obj_id and not_idle_thread obj_id and valid_idle and valid_etcbs)
             (KHeap_D.set_cap (obj_id, tcb_replycap_slot)
               (cdl_cap.MasterReplyCap obj_id))
             (setup_reply_master obj_id)"
  apply (clarsimp simp:setup_reply_master_def)
  apply (rule_tac Q'="\<lambda>rv. valid_objs and tcb_at obj_id and not_idle_thread obj_id and valid_idle and valid_etcbs and
     cte_wp_at (\<lambda>c. c = rv) (obj_id,tcb_cnode_index 2)" in corres_symb_exec_r)
     prefer 2
    apply (wp get_cap_cte_wp_at)
    apply simp
   apply (rule dcorres_expand_pfx)
   apply (clarsimp simp:tcb_at_def)
   apply (frule valid_tcb_objs)
    apply (simp add:tcb_at_def)
    apply (clarsimp simp:cte_wp_at_cases dest!:get_tcb_SomeD)
    apply (clarsimp simp:valid_tcb_def)
    apply (clarsimp simp:tcb_cap_cases_def)
    apply (case_tac "cap.NullCap = tcb_reply tcb")
     apply (clarsimp simp:when_def)
     apply (rule corres_guard_imp)
       apply (rule dcorres_symb_exec_r)
         apply (rule set_cap_corres)
          apply (clarsimp simp:transform_cap_def)
         apply (clarsimp simp:transform_tcb_slot_simp)
        apply wp[2]
       apply (clarsimp simp:transform_def transform_current_thread_def)
      apply (rule TrueI)
     apply (clarsimp simp: not_idle_thread_def)
    apply (clarsimp simp:when_def is_master_reply_cap_def split:cap.split_asm)
    apply (subgoal_tac "opt_cap (obj_id,tcb_replycap_slot) (transform s')
      = Some (cdl_cap.MasterReplyCap obj_id)")
     apply (clarsimp simp:corres_underlying_def set_cap_is_noop_opt_cap return_def)
    apply (subgoal_tac "cte_wp_at (op =  (cap.ReplyCap obj_id True))
      (obj_id,tcb_cnode_index 2) s'")
     apply (clarsimp dest!:iffD1[OF cte_wp_at_caps_of_state])
     apply (drule caps_of_state_transform_opt_cap)
       apply simp
      apply (clarsimp simp:not_idle_thread_def)
     apply (simp add:transform_cap_def transform_tcb_slot_simp)
    apply (clarsimp simp:cte_wp_at_cases)
   apply wp
  apply simp
   done

lemma set_cdl_cap_noop:
  " dcorres dc \<top> (cte_wp_at (\<lambda>cap. cdlcap = transform_cap cap) slot and not_idle_thread (fst slot) and valid_etcbs)
             (KHeap_D.set_cap (transform_cslot_ptr slot) cdlcap)
             (return x)"
  apply (rule dcorres_expand_pfx)
  apply clarsimp
  apply (drule iffD1[OF cte_wp_at_caps_of_state])
  apply clarsimp
  apply (drule caps_of_state_transform_opt_cap)
   apply simp
    apply (simp add:not_idle_thread_def)
  apply (drule set_cap_is_noop_opt_cap)
  apply (clarsimp simp:corres_underlying_def return_def not_idle_thread_def set_cap_is_noop_opt_cap)
done


lemma runnable_imply:
  "runnable st
   \<Longrightarrow> (infer_tcb_pending_op obj_id st = RunningCap \<or>
    infer_tcb_pending_op obj_id st = RestartCap)"
  apply (case_tac st)
   apply (simp_all add:infer_tcb_pending_op_def)
  done

lemma dcorres_set_thread_state_Restart2:
  "dcorres dc (\<lambda>_. True)
   (\<lambda>a. valid_mdb a \<and> not_idle_thread recver a \<and> st_tcb_at idle (idle_thread a) a \<and> valid_etcbs a)
   (KHeap_D.set_cap (recver, tcb_pending_op_slot) RestartCap)
   (set_thread_state recver Structures_A.thread_state.Restart)"
  apply (simp add:KHeap_D.set_cap_def set_thread_state_def)
  apply (rule dcorres_gets_the)
  apply (clarsimp, frule(1) valid_etcbs_get_tcb_get_etcb, clarsimp)
  apply (frule opt_object_tcb, simp)
    apply (clarsimp simp:not_idle_thread_def)
   apply (clarsimp simp:transform_tcb_def has_slots_def update_slots_def object_slots_def)
   apply (rule dcorres_rhs_noop_below_True[OF set_thread_state_ext_dcorres])
   apply (rule dcorres_set_object_tcb)
     apply (clarsimp simp:transform_tcb_def infer_tcb_pending_op_def)
   apply (clarsimp simp:get_etcb_SomeD)
    apply (simp add:not_idle_thread_def)
   apply (clarsimp simp:get_tcb_SomeD)
  apply (clarsimp simp:get_etcb_SomeD)
  apply (clarsimp, frule(1) valid_etcbs_get_tcb_get_etcb)
  apply (fastforce simp:not_idle_thread_def dest!:opt_object_tcb)
  done

(* Restart functions correspond. *)
lemma restart_corres:
  "dcorres dc \<top>
  (invs and tcb_at obj_id and not_idle_thread obj_id and valid_etcbs)
  (Tcb_D.restart obj_id) (Tcb_A.restart obj_id)"
  apply (clarsimp simp: Tcb_D.restart_def Tcb_A.restart_def
    when_def get_cap_def)
  apply (clarsimp simp: thread_get_def get_thread_state_def )
  apply (rule dcorres_gets_the)
  apply (clarsimp, frule(1) valid_etcbs_get_tcb_get_etcb)
  apply (clarsimp simp:opt_cap_tcb not_idle_thread_def tcb_vspace_slot_def
    tcb_pending_op_slot_def tcb_caller_slot_def tcb_ipcbuffer_slot_def
    tcb_cspace_slot_def tcb_replycap_slot_def tcb_pending_op_slot_def)
  apply (intro conjI impI)
       apply (rule corres_guard_imp)
         apply (rule corres_split[OF _ finalise_ipc_cancel])
           apply (rule corres_split[OF _ dcorres_setup_reply_master[unfolded tcb_replycap_slot_def] ])
            apply (rule dcorres_rhs_noop_below_True[OF dcorres_rhs_noop_below_True])
             apply (rule switch_if_required_to_dcorres)
             apply (rule tcb_sched_action_dcorres)
             apply (rule corres_alternate1)
             apply (rule dcorres_set_thread_state_Restart2[unfolded tcb_pending_op_slot_def])
            apply wp
           apply (simp add:not_idle_thread_def)
           apply ((wp|wps)+)[2]
         apply (rule_tac Q="op = s' and invs" in  hoare_vcg_precond_imp)
          apply (rule hoare_strengthen_post
             [where Q="\<lambda>r. invs and tcb_at obj_id and not_idle_thread obj_id and valid_etcbs"])
           apply (simp add:not_idle_thread_def)
           apply (wp)
             apply (clarsimp simp:invs_def valid_state_def valid_pspace_def
                tcb_at_def not_idle_thread_def)+
         apply (clarsimp simp:valid_idle_def)
        apply assumption
       apply (clarsimp simp:not_idle_thread_def)+
      apply (clarsimp dest!:runnable_imply[where obj_id = obj_id])+
     apply (clarsimp simp:invs_def valid_state_def)
     apply (drule only_idleD[rotated])
      apply (fastforce simp:st_tcb_at_def obj_at_def dest!:get_tcb_SomeD)
     apply simp
    apply (clarsimp simp: runnable_def infer_tcb_pending_op_def
      split:Structures_A.thread_state.split_asm)+
    apply (frule(1) valid_etcbs_get_tcb_get_etcb)
  apply (fastforce simp:opt_cap_tcb not_idle_thread_def)
done

crunch no_effect [wp]: get_thread P
crunch no_effect [wp]: getRegister P

(* Read the registers of another thread. *)
lemma invoke_tcb_corres_read_regs:
  "\<lbrakk> t' = tcb_invocation.ReadRegisters obj_id resume data flags;
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (invs and tcb_at obj_id and not_idle_thread obj_id and valid_etcbs)
  (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  apply (clarsimp simp: Tcb_D.invoke_tcb_def translate_tcb_invocation_def)
  apply (case_tac "resume")
   apply (rule corres_alternate1)
   apply clarsimp
   apply (subst bind_return [symmetric])
   apply (rule corres_guard_imp)
     apply (rule corres_split [where r'=dc])
        apply (rule corres_symb_exec_r)
           apply (rule dcorres_idempotent_as_user)
           apply (rule hoare_mapM_idempotent)
           apply wp
        apply simp
       apply (rule suspend_corres, simp)
      apply wp
    apply simp
   apply simp
  apply clarsimp
  apply (rule corres_alternate2)
  apply (rule corres_symb_exec_r)
     apply (rule dcorres_idempotent_as_user)
     apply (rule hoare_mapM_idempotent)
     apply (wp | simp)+
  done

(* Write the reigsters of another thread. *)
lemma invoke_tcb_corres_write_regs:
  "\<lbrakk> t' = tcb_invocation.WriteRegisters obj_id resume data flags;
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (invs and not_idle_thread obj_id and tcb_at obj_id and valid_etcbs) (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  apply (clarsimp simp: Tcb_D.invoke_tcb_def translate_tcb_invocation_def)
  apply (rule corres_symb_exec_r)
     apply (rule corres_guard_imp)
       apply (rule corres_split [where r'=dc])
          apply (rule corres_cases [where R=resume])
           apply (clarsimp simp: when_def)
           apply (rule corres_bind_return_r)
           apply (rule corres_alternate1)
           apply (clarsimp simp: dc_def, rule restart_corres [unfolded dc_def])
          apply (clarsimp simp: when_def)
          apply (rule corres_alternate2)
          apply (rule corres_return_dc)
         apply (rule corrupt_tcb_intent_as_user_corres)
         apply (wp | simp add:invs_def valid_state_def)+
  done

lemma corres_mapM_x_rhs_induct:
  "\<lbrakk> corres_underlying sr nf dc P P' g (return ());
     \<And>a. corres_underlying sr nf dc P P' g (g' a);
     g = do g; g od;
     \<lbrace> P \<rbrace> g \<lbrace> \<lambda>_. P \<rbrace>;
     \<And>a. \<lbrace> P' \<rbrace> g' a \<lbrace> \<lambda>_. P'\<rbrace> \<rbrakk> \<Longrightarrow>
  corres_underlying sr nf dc P P' g (mapM_x g' l)"
  apply (induct_tac l)
   apply (clarsimp simp: mapM_x_def sequence_x_def dc_def)
  apply (clarsimp simp: mapM_x_def sequence_x_def dc_def)
  apply (erule ssubst)
  apply (rule corres_guard_imp)
    apply (rule corres_split)
       apply (assumption)
      apply assumption
     apply assumption
    apply assumption
   apply simp
  apply simp
  done

(*
 * Copy registers loop.
 *
 * What we show here is that any number of individual register
 * copys from A to B merely results in a corruption of B's
 * registers.
 *)
lemma get_register_rewrite:
  "getRegister = get_register"
  apply (rule ext)
  apply (unfold getRegister_def get_register_def)
  apply simp
done

lemma set_register_rewrite:
  "setRegister = set_register"
  apply (rule ext)+
  apply (unfold setRegister_def set_register_def)
  apply simp
done

lemma invoke_tcb_corres_copy_regs_loop:
  "dcorres dc \<top>
     (tcb_at target_id and tcb_at obj_id' and valid_idle and not_idle_thread target_id and not_idle_thread obj_id' and valid_etcbs)
     (corrupt_tcb_intent target_id)
     (mapM_x
        (\<lambda>r. do v \<leftarrow> as_user obj_id' (getRegister r);
                     as_user target_id (setRegister r v)
             od) x)"
   apply (clarsimp simp:get_register_rewrite set_register_rewrite mapM_x_mapM)
   apply (rule corres_guard_imp)
   apply (rule corres_dummy_return_l)
     apply (rule corres_split[OF corres_free_return[where P=\<top> and P'= \<top>] Intent_DR.set_registers_corres])
     apply (wp|simp)+
  done

crunch idle_thread_constant [wp]: "Tcb_A.restart", "IpcCancel_A.suspend" "\<lambda>s. P (idle_thread s)"
(wp: dxo_wp_weak)

lemma not_idle_after_blocked_ipc_cancel:
  "\<lbrace>valid_idle and not_idle_thread obj_id' and valid_objs and st_tcb_at (op = state) obj_id'\<rbrace>
    blocked_ipc_cancel state obj_id' \<lbrace>\<lambda>y. valid_idle\<rbrace>"
  apply (simp add:blocked_ipc_cancel_def)
    apply wp
    apply (clarsimp simp:not_idle_thread_def)
    apply (clarsimp simp:get_blocking_ipc_endpoint_def)
    apply (case_tac state)
      apply clarsimp+
    apply (clarsimp simp:valid_def return_def st_tcb_at_def valid_objs_def obj_at_def)
      apply (drule_tac x = obj_id' in bspec)
        apply (clarsimp simp:valid_obj_def valid_tcb_def valid_tcb_state_def)+
        apply (drule_tac t = "tcb_state tcb" in sym)
        apply (clarsimp simp:obj_at_def)
    apply (clarsimp simp:valid_def return_def st_tcb_at_def obj_at_def valid_objs_def)
      apply (drule_tac x = obj_id' in bspec)
        apply (clarsimp simp:valid_obj_def valid_tcb_def valid_tcb_state_def)+
        apply (drule_tac t = "tcb_state tcb" in sym)
        apply (clarsimp simp:obj_at_def)
    apply (clarsimp)+
done

lemma valid_idle_set_thread_state:
  "\<lbrace>not_idle_thread xa and valid_idle :: det_state \<Rightarrow> bool\<rbrace> set_thread_state xa Structures_A.thread_state.Restart \<lbrace>\<lambda>xa. valid_idle\<rbrace>"
  apply (simp add:set_thread_state_def not_idle_thread_def)
  apply (simp add:set_object_def)
  apply wp
  apply (clarsimp simp:not_idle_thread_def)
  apply (clarsimp simp:obj_at_def dest!:get_tcb_SomeD)
  apply (auto simp:valid_idle_def st_tcb_at_def obj_at_def)
done

crunch not_idle_thread[wp]: tcb_sched_action "not_idle_thread a"
  (wp: simp: not_idle_thread_def)

lemma tcb_sched_action_tcb_at_not_idle[wp]:
  "\<lbrace>\<lambda>s. \<forall>x\<in>set list. tcb_at x s \<and> not_idle_thread x s\<rbrace> tcb_sched_action a b
   \<lbrace>\<lambda>x s. \<forall>x\<in>set list. tcb_at x s \<and> not_idle_thread x s\<rbrace>"
  by (wp hoare_Ball_helper)

lemma valid_idle_ep_cancel_all:
  "\<lbrace>valid_idle and valid_state :: det_state \<Rightarrow> bool\<rbrace> IpcCancel_A.ep_cancel_all word1 \<lbrace>\<lambda>a. valid_idle\<rbrace>"
  apply (simp add:ep_cancel_all_def)
  apply (wp|wpc|simp)+
  apply (rule_tac I = "(\<lambda>s. (queue = list) \<and> (\<forall>a\<in> set list. tcb_at a s \<and> not_idle_thread a s))
    and ko_at (kernel_object.Endpoint Structures_A.endpoint.IdleEP) word1  and valid_idle" in mapM_x_inv_wp)
    apply clarsimp
    apply (wp KHeap_DR.tcb_at_set_thread_state_wp)
    apply (rule hoare_conjI)
    apply (rule_tac P="(\<lambda>s. (queue = list) \<and> (\<forall>a\<in> set list. tcb_at a s \<and> not_idle_thread a s))
      and valid_idle and ko_at (kernel_object.Endpoint Structures_A.endpoint.IdleEP) word1"
      in hoare_vcg_precond_imp)
      apply (wp | clarsimp)+
      apply (rule set_thread_state_ko)
      apply (simp add:is_tcb_def)
    apply (wp valid_idle_set_thread_state)
    apply (clarsimp simp:)+
    apply wp
    apply (rule hoare_vcg_conj_lift)
      apply (rule hoare_Ball_helper)
      apply (wp set_endpoint_obj_at | clarsimp simp :get_ep_queue_def not_idle_thread_def)+
  apply (rule_tac I = "(\<lambda>s. (queue = list) \<and> (\<forall>a\<in> set list. tcb_at a s \<and> not_idle_thread a s))
    and ko_at (kernel_object.Endpoint Structures_A.endpoint.IdleEP) word1  and valid_idle" in mapM_x_inv_wp)
    apply clarsimp
    apply (wp KHeap_DR.tcb_at_set_thread_state_wp)
    apply (rule hoare_conjI)
    apply (rule_tac P="(\<lambda>s. (queue = list) \<and> (\<forall>a\<in> set list. tcb_at a s \<and> not_idle_thread a s))
      and valid_idle and ko_at (kernel_object.Endpoint Structures_A.endpoint.IdleEP) word1"
      in hoare_vcg_precond_imp)
      apply (rule set_thread_state_ko)
      apply (simp add:is_tcb_def)
    apply (wp valid_idle_set_thread_state)
    apply (clarsimp simp:)+
    apply wp
    apply (rule hoare_vcg_conj_lift)
      apply (rule hoare_Ball_helper)
      apply (wp set_endpoint_obj_at | clarsimp simp :get_ep_queue_def not_idle_thread_def)+
      apply (rule hoare_strengthen_post[OF get_endpoint_sp])
      apply (clarsimp  | rule conjI)+
        apply (clarsimp simp:obj_at_def valid_pspace_def valid_state_def)
        apply (drule(1) valid_objs_valid_ep_simp)
        apply (clarsimp simp:is_tcb_def valid_ep_def obj_at_def)
        apply (drule(1) pending_thread_in_send_not_idle)
        apply (simp add:not_idle_thread_def obj_at_def is_ep_def)+
      apply (clarsimp | rule conjI)+
        apply (clarsimp simp:obj_at_def valid_pspace_def valid_state_def)
        apply (drule(1) valid_objs_valid_ep_simp)
        apply (clarsimp simp:is_tcb_def valid_ep_def obj_at_def)
        apply (drule(1) pending_thread_in_recv_not_idle)
        apply (simp add:not_idle_thread_def obj_at_def is_ep_def)+
done

lemma set_aep_obj_at:
  "\<lbrace>\<lambda>s. P (kernel_object.AsyncEndpoint ep)\<rbrace> set_async_ep ptr ep \<lbrace>\<lambda>rv. obj_at P ptr\<rbrace>"
  apply (simp add:set_async_ep_def)
  apply (wp obj_set_prop_at)
  apply (simp add:get_object_def)
  apply wp
  apply clarsimp
done

lemma valid_idle_aep_cancel_all:
  "\<lbrace>valid_idle and valid_state :: det_state \<Rightarrow> bool\<rbrace> IpcCancel_A.aep_cancel_all word1 \<lbrace>\<lambda>a. valid_idle\<rbrace>"
  apply (simp add:aep_cancel_all_def)
  apply (wp|wpc|simp)+
  apply (rule_tac I = "(\<lambda>s. (\<forall>a\<in> set list. tcb_at a s \<and> not_idle_thread a s))
    and ko_at (kernel_object.AsyncEndpoint async_ep.IdleAEP) word1  and valid_idle" in mapM_x_inv_wp)
    apply clarsimp
    apply (wp KHeap_DR.tcb_at_set_thread_state_wp)
    apply (rule hoare_conjI)
    apply (rule_tac P="(\<lambda>s. (\<forall>a\<in> set list. tcb_at a s \<and> not_idle_thread a s))
      and valid_idle and ko_at (kernel_object.AsyncEndpoint async_ep.IdleAEP) word1"
      in hoare_vcg_precond_imp)
      apply (rule set_thread_state_ko)
      apply (simp add:is_tcb_def)
    apply (wp valid_idle_set_thread_state)
    apply (clarsimp simp:)+
    apply (rule hoare_vcg_conj_lift)
      apply (rule hoare_Ball_helper)
      apply (wp set_aep_tcb| clarsimp simp : not_idle_thread_def)+
      apply (wp set_aep_obj_at)
    apply (rule hoare_strengthen_post[OF get_aep_sp])
      apply (clarsimp  | rule conjI)+
        apply (clarsimp simp:obj_at_def valid_pspace_def valid_state_def)
        apply (drule(1) valid_objs_valid_aep_simp)
        apply (clarsimp simp:is_tcb_def valid_aep_def obj_at_def)
        apply (drule(1) pending_thread_in_wait_not_idle)
      apply (simp add:not_idle_thread_def obj_at_def is_aep_def)+
done

lemma not_idle_after_reply_ipc_cancel:
  "\<lbrace>not_idle_thread obj_id' and invs :: det_state \<Rightarrow> bool \<rbrace> reply_ipc_cancel obj_id'
   \<lbrace>\<lambda>y. valid_idle\<rbrace>"
  apply (simp add:reply_ipc_cancel_def)
  apply wp
       apply (simp add:cap_delete_one_def unless_def)
       apply wp
          apply (simp add:IpcCancel_A.empty_slot_def)
          apply (wp set_cap_idle)+
          apply simp
          apply (rule hoare_strengthen_post[OF get_cap_idle])
          apply simp
         apply (case_tac capa)
                   apply (simp_all add:fast_finalise.simps)
           apply (clarsimp simp:when_def | rule conjI)+
            apply (wp valid_idle_ep_cancel_all valid_idle_aep_cancel_all | clarsimp)+
       apply (rule hoare_strengthen_post[where Q="\<lambda>r. valid_state and valid_idle"])
        apply (wp select_inv|simp)+
  apply (rule hoare_strengthen_post[where Q="\<lambda>r. valid_state and valid_idle"])
   apply wp
   apply (rule hoare_strengthen_post)
    apply (rule hoare_vcg_precond_imp[OF thread_set_invs_trivial])
         apply (simp add:tcb_cap_cases_def invs_def valid_state_def)+
done

lemma not_idle_thread_async_ipc_cancel:
 "\<lbrace>not_idle_thread obj_id' and valid_idle\<rbrace> async_ipc_cancel obj_id' word \<lbrace>\<lambda>r. valid_idle\<rbrace>"
  apply (simp add:async_ipc_cancel_def)
  apply (wp valid_idle_set_thread_state|wpc)+
  apply (rule hoare_strengthen_post[OF get_aep_sp])
  apply (clarsimp simp:not_idle_thread_def obj_at_def is_aep_def)
done

lemma not_idle_after_restart [wp]:
  "\<lbrace>invs and not_idle_thread obj_id' :: det_state \<Rightarrow> bool\<rbrace> Tcb_A.restart obj_id'
           \<lbrace>\<lambda>rv. valid_idle \<rbrace>"
  apply (simp add:Tcb_A.restart_def)
    apply wp
    apply (simp add:ipc_cancel_def)
    apply (wp not_idle_after_blocked_ipc_cancel not_idle_after_reply_ipc_cancel
      not_idle_thread_async_ipc_cancel | wpc)+
    apply (rule hoare_strengthen_post[where Q="\<lambda>r. st_tcb_at (op = r) obj_id'
      and not_idle_thread obj_id' and invs"])
    apply (wp gts_sp)
    apply (clarsimp simp: invs_def valid_state_def valid_pspace_def not_idle_thread_def | rule conjI)+
    apply (rule hoare_strengthen_post)
    apply (wp gts_inv)
    apply (clarsimp)
done

lemma not_idle_after_suspend [wp]:
  "\<lbrace>invs and not_idle_thread obj_id' and tcb_at obj_id'\<rbrace> IpcCancel_A.suspend obj_id'
           \<lbrace>\<lambda>rv. valid_idle \<rbrace>"
  apply (rule hoare_strengthen_post)
  apply (rule hoare_vcg_precond_imp)
    apply (rule suspend_invs)
  apply (simp add:not_idle_thread_def invs_def valid_state_def)+
done

crunch valid_etcbs[wp]:  "switch_if_required_to", "Tcb_A.restart"  "valid_etcbs"

(* Copy registers from one thread to another. *)
lemma invoke_tcb_corres_copy_regs:
  "\<lbrakk> t' = tcb_invocation.CopyRegisters obj_id' target_id' a b c d e;
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top>
   (invs and tcb_at obj_id' and tcb_at target_id' and not_idle_thread target_id' and not_idle_thread obj_id' and valid_etcbs)
     (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
   apply (clarsimp simp: Tcb_D.invoke_tcb_def translate_tcb_invocation_def)
   apply (rule corres_guard_imp)
     apply (rule corres_split [where r'=dc])
        apply (rule corres_split [where r'=dc])
           apply (rule corres_corrupt_tcb_intent_dupl)
           apply (rule corres_split [where r'=dc])
              apply (rule corres_cases [where R="d"])
               apply (clarsimp simp: K_bind_def when_def)
               apply (rule corres_bind_ignore_ret_rhs)
               apply (rule corres_return_dc_rhs)
               apply (rule invoke_tcb_corres_copy_regs_loop)
              apply (clarsimp simp: when_def)
              apply (rule dummy_corrupt_tcb_intent_corres)
             apply (rule corres_cases [where R="c"])
              apply (clarsimp simp: K_bind_def when_def)
              apply (rule corres_bind_ignore_ret_rhs)
              apply (rule corres_corrupt_tcb_intent_dupl)
                apply (rule corres_split [where r'=dc])
                   apply (unfold K_bind_def)
                   apply (rule corres_symb_exec_r)
                      apply (simp add:setNextPC_def set_register_rewrite)
                      apply (rule Intent_DR.set_register_corres[unfolded dc_def], simp)
                     apply (wp | clarsimp simp:getRestartPC_def)+
                    apply (wp as_user_inv)
                   apply simp
                  apply (rule invoke_tcb_corres_copy_regs_loop, simp)
                apply (wp mapM_x_wp [where S=UNIV])
                apply simp
             apply (clarsimp simp: when_def)
             apply (rule dummy_corrupt_tcb_intent_corres)
            apply wp
           apply (wp mapM_x_wp [where S=UNIV])[1]
           apply simp
          apply (rule corres_cases [where R="b"])
           apply (clarsimp simp: when_def)
           apply (rule corres_alternate1)
           apply (rule restart_corres, simp)
          apply (rule corres_alternate2)
          apply (rule corres_free_return [where P="\<top>" and P'="\<top>"])
          apply (wp)
          apply (clarsimp simp:conj_ac)
         apply (clarsimp simp :not_idle_thread_def | wp)+
       apply (rule corres_cases [where R="a"])
        apply (clarsimp simp: when_def)
        apply (rule corres_alternate1)
        apply (rule suspend_corres)
       apply (clarsimp simp: when_def dc_def[symmetric])+
       apply (rule corres_alternate2)
       apply (rule corres_free_return [where P="\<top>" and P'="\<top>"])

      apply clarsimp
      apply (wp alternative_wp)
       apply (clarsimp simp:not_idle_thread_def | wp | rule conjI)+
  done

lemma cnode_cap_unique_bits:
  "is_cnode_cap cap \<Longrightarrow>
  \<lbrace>\<lambda>s. (\<forall>a b. \<not> cte_wp_at (\<lambda>c. obj_refs c = obj_refs cap \<and> table_cap_ref c \<noteq> table_cap_ref cap) (a, b) s)
        \<and> valid_cap cap s \<and> valid_objs s\<rbrace>
    CSpaceAcc_A.get_cap (ba, c)
  \<lbrace>\<lambda>rv s. (Structures_A.is_cnode_cap rv \<and> obj_refs rv = obj_refs cap) \<longrightarrow> (bits_of rv = bits_of cap)\<rbrace>"
  apply (rule hoare_pre)
   apply (rule_tac Q="\<lambda>r s. (\<forall>a b. \<not> cte_wp_at (\<lambda>c. obj_refs c = obj_refs cap \<and>
                                                    table_cap_ref c \<noteq> table_cap_ref cap) (a, b) s)
                            \<and> valid_cap cap s \<and> valid_objs s
                            \<and> valid_objs s \<and> cte_wp_at (\<lambda>x. x = r) (ba,c) s"
    in hoare_strengthen_post)
    apply (wp get_cap_cte_wp_at)
   apply (clarsimp simp:is_cap_simps)
   apply (drule_tac x = ba in spec)
   apply (drule_tac x = c in spec)
   apply (drule(1) cte_wp_at_valid_objs_valid_cap)
   apply (clarsimp simp:valid_cap_def obj_at_def is_ep_def is_aep_def is_cap_table_def,
          clarsimp split:Structures_A.kernel_object.split_asm)+
   apply (clarsimp simp:well_formed_cnode_n_def bits_of_def)
  apply simp
  done

lemma get_cap_ex_cte_cap_wp_to:
  "(tcb_cnode_index x)\<in> dom tcb_cap_cases  \<Longrightarrow> \<lbrace>\<top>\<rbrace> CSpaceAcc_A.get_cap a'
            \<lbrace>\<lambda>rv s. is_thread_cap rv \<and> obj_ref_of rv = obj_id' \<longrightarrow> ex_cte_cap_wp_to (\<lambda>_. True) (obj_id', tcb_cnode_index x) s\<rbrace>"
  apply (rule hoare_strengthen_post[OF get_cap_cte_wp_at])
  apply (case_tac a')
    apply (clarsimp simp:ex_cte_cap_wp_to_def)
    apply (rule exI)+
    apply (rule cte_wp_at_weakenE)
      apply simp
    apply (clarsimp simp:is_cap_simps)
done

crunch idle[wp] : cap_delete "\<lambda>s. P (idle_thread (s :: det_ext state))"
  (wp: crunch_wps  simp: crunch_simps)

lemma imp_strengthen:
  "R \<and> (P x \<longrightarrow> Q x) \<Longrightarrow> P x \<longrightarrow> (Q x \<and> R) "
 by simp

lemma dcorres_corrupt_tcb_intent_ipcbuffer_upd:
  "dcorres dc \<top> (tcb_at y and valid_idle and not_idle_thread y and valid_etcbs)
    (corrupt_tcb_intent  y)
    (thread_set (tcb_ipc_buffer_update (\<lambda>_. a)) y)"
  apply (clarsimp simp:corrupt_tcb_intent_def thread_set_def get_thread_def bind_assoc)
  apply (rule dcorres_expand_pfx)
  apply (clarsimp simp:update_thread_def tcb_at_def)
  apply (rule select_pick_corres[where S = UNIV,simplified])
  apply (frule(1) valid_etcbs_get_tcb_get_etcb)
  apply (rule dcorres_gets_the)
   apply (clarsimp simp:opt_object_tcb not_idle_thread_def)
   apply (simp add:transform_tcb_def)
    apply (rule corres_guard_imp)
     apply (rule_tac s' = s'a in dcorres_set_object_tcb)
       apply (clarsimp simp:transform_tcb_def)
       apply (simp add: get_etcb_def)
      apply (clarsimp dest!: get_tcb_SomeD get_etcb_SomeD split:option.splits)+
  apply (clarsimp simp:opt_object_tcb
    not_idle_thread_def dest!:get_tcb_rev get_etcb_rev)
done

lemma arch_same_obj_as_lift:
  "\<lbrakk>cap_aligned a;is_arch_cap a;ca = transform_cap a;cb=transform_cap b\<rbrakk>
  \<Longrightarrow> cdl_same_arch_obj_as (ca) (cb) = same_object_as a b"
  apply (clarsimp simp:is_arch_cap_def split:cap.split_asm)
  apply (case_tac arch_cap)
      apply (simp add:same_object_as_def)
      apply (clarsimp split:cap.splits simp:cdl_same_arch_obj_as_def)
      apply (case_tac arch_capa)
          apply (clarsimp simp:cdl_same_arch_obj_as_def)+
     apply (simp add:same_object_as_def)
     apply (clarsimp split:cap.splits simp:cdl_same_arch_obj_as_def)
     apply (case_tac arch_cap)
         apply ((clarsimp simp:cdl_same_arch_obj_as_def)+)[5]
    apply (simp add:same_object_as_def)
    apply (clarsimp split:cap.splits simp:cdl_same_arch_obj_as_def)
    apply (case_tac arch_capa)
        apply (fastforce simp:cdl_same_arch_obj_as_def cap_aligned_def)+
   apply (simp add:same_object_as_def)
   apply (clarsimp split:cap.splits simp:cdl_same_arch_obj_as_def)
   apply (case_tac arch_capa)
       apply (fastforce simp:cdl_same_arch_obj_as_def cap_aligned_def)+
  apply (simp add:same_object_as_def)
  apply (clarsimp split:cap.splits simp:cdl_same_arch_obj_as_def)
  apply (case_tac arch_capa)
      apply (fastforce simp:cdl_same_arch_obj_as_def cap_aligned_def)+
done

lemma thread_set_valid_irq_node:
  "(\<And>t getF v. (getF, v) \<in> ran tcb_cap_cases \<Longrightarrow> getF (f t) = getF t)
   \<Longrightarrow>
   \<lbrace>valid_irq_node\<rbrace> thread_set f p
   \<lbrace>\<lambda>rv s. valid_irq_node s\<rbrace>"
  apply (simp add:valid_irq_node_def thread_set_def)
  apply wp
  apply (simp add:KHeap_A.set_object_def)
    apply wp
  apply (clarsimp simp:obj_at_def is_cap_table_def dest!:get_tcb_SomeD)
  apply (drule_tac x = irq in spec)
  apply clarsimp
done

lemma update_ipc_buffer_valid_objs:
  "\<lbrace>valid_objs and K(is_aligned a msg_align_bits)\<rbrace>
  thread_set (tcb_ipc_buffer_update (\<lambda>_. a)) ptr
  \<lbrace>\<lambda>rv s. valid_objs s \<rbrace>"
  apply (wp thread_set_valid_objs'')
  apply (clarsimp simp:valid_tcb_def)
  apply (intro conjI allI)
   apply (clarsimp simp:tcb_cap_cases_def)
  apply (auto simp:valid_ipc_buffer_cap_def
    split:cap.splits arch_cap.splits)
  done

lemma dcorres_tcb_empty_slot:
  "(thread,idx) = (transform_cslot_ptr slot)
  \<Longrightarrow> dcorres (dc \<oplus> dc) (\<lambda>_. True)
  (cte_wp_at (\<lambda>_. True) slot and invs and emptyable slot and not_idle_thread (fst slot) and valid_pdpt_objs and valid_etcbs)
  (tcb_empty_thread_slot thread idx) (cap_delete slot)"
  apply (simp add:liftE_bindE tcb_empty_thread_slot_def)
  apply (simp add:opt_cap_def gets_the_def
    assert_opt_def gets_def bind_assoc split_def)
  apply (rule dcorres_absorb_get_l)
  apply (clarsimp simp add:cte_at_into_opt_cap)
   apply (erule impE)
   apply (clarsimp simp: not_idle_thread_def
     dest!:invs_valid_idle)
  apply (simp add:opt_cap_def whenE_def split_def)
  apply (intro conjI impI)
   apply (case_tac slot,clarsimp)
   apply (rule corres_guard_imp)
   apply (rule delete_cap_corres')
    apply simp
   apply (clarsimp simp:cte_wp_at_caps_of_state)
  apply (simp add:cap_delete_def)
  apply (subst rec_del_simps_ext)
  apply (subst rec_del_simps_ext)
  apply (clarsimp simp:bindE_assoc)
  apply (subst liftE_bindE)
  apply (rule corres_guard_imp[OF corres_symb_exec_r])
       apply (rule_tac F = "x = cap.NullCap" in corres_gen_asm2)
       apply (simp add:bindE_assoc when_def)
       apply (simp add:IpcCancel_A.empty_slot_def returnOk_liftE)
       apply (rule corres_symb_exec_r)
          apply (rule_tac F = "cap = cap.NullCap" in corres_gen_asm2)
          apply (rule corres_trivial)
          apply simp
         apply (simp | wp get_cap_wp)+
  apply (clarsimp simp:cte_wp_at_caps_of_state)
  done

crunch valid_etcbs[wp]: cap_delete "valid_etcbs"

lemma dcorres_tcb_update_ipc_buffer:
  "dcorres (dc \<oplus> dc) (\<top>) (invs and valid_etcbs and tcb_at obj_id' and not_idle_thread obj_id'
         and valid_pdpt_objs
     and
     (\<lambda>y. case ipc_buffer' of None \<Rightarrow> True
       | Some v \<Rightarrow> option_case True ((swp valid_ipc_buffer_cap (fst v) and is_arch_cap and cap_aligned) \<circ> fst) (snd v)
       \<and> (is_aligned (fst v) msg_align_bits) ) and
    option_case (\<lambda>_. True) (option_case (\<lambda>_. True) (cte_wp_at (\<lambda>_. True) \<circ> snd) \<circ> snd) ipc_buffer'
    and option_case (\<lambda>_. True) (option_case (\<lambda>_. True) (not_idle_thread \<circ> fst \<circ> snd) \<circ> snd) ipc_buffer' and
    (\<lambda>s. option_case True (\<lambda>x. not_idle_thread (fst a') s) ipc_buffer') )
     (option_case
         (returnOk () \<sqinter>
           (doE tcb_empty_thread_slot obj_id' tcb_ipcbuffer_slot;
                liftE $ corrupt_tcb_intent obj_id'
            odE))
           (tcb_update_ipc_buffer obj_id' (transform_cslot_ptr a'))
         (translate_tcb_invocation_thread_ctrl_buffer ipc_buffer'))
     (doE y \<leftarrow> option_case (returnOk ())
                       (prod_case
                         (\<lambda>ptr frame.
                             doE cap_delete (obj_id', tcb_cnode_index 4);
                                 liftE $ thread_set (tcb_ipc_buffer_update (\<lambda>_. ptr)) obj_id';
                                 liftE $
                                 option_case (return ())
                                  (prod_case
                                    (\<lambda>new_cap src_slot.
                                        check_cap_at new_cap src_slot $
                                        check_cap_at (cap.ThreadCap obj_id') a' $ cap_insert new_cap src_slot (obj_id', tcb_cnode_index 4)))
                                  frame
                             odE))
                       ipc_buffer';
                  returnOk []
              odE)"
  apply (case_tac ipc_buffer')
    apply (simp_all add:translate_tcb_invocation_thread_ctrl_buffer_def)
    apply (rule corres_alternate1)
    apply (rule corres_guard_imp[OF dcorres_returnOk],clarsimp+)
  apply (clarsimp simp:bindE_assoc split:option.splits,intro conjI)
   apply (clarsimp)
   apply (rule corres_alternate2)
   apply (rule corres_guard_imp)
    apply (rule corres_splitEE[OF _  dcorres_tcb_empty_slot])
       apply (clarsimp simp:liftE_bindE)
       apply (simp add:liftE_def)
       apply (rule corres_split[OF _ dcorres_corrupt_tcb_intent_ipcbuffer_upd])
         apply (rule corres_trivial,clarsimp simp:returnOk_def)
        apply (wp|simp add:transform_tcb_slot_4)+
     apply (rule validE_validE_R)
     apply (rule_tac Q = "\<lambda>r s. invs s \<and> valid_etcbs s \<and> not_idle_thread obj_id' s" in hoare_post_impErr[where E="\<lambda>x. \<top>"])
       apply (simp add:not_idle_thread_def)
       apply (wp cap_delete_cte_at cap_delete_deletes)
      apply (clarsimp simp:invs_def valid_state_def not_idle_thread_def)
     apply (clarsimp simp :emptyable_def not_idle_thread_def)+
   apply (erule tcb_at_cte_at)
   apply (simp add:tcb_cap_cases_def)
(* Main Part *)
  apply (clarsimp simp:tcb_update_ipc_buffer_def tcb_update_thread_slot_def  transform_tcb_slot_simp[symmetric])
  apply (drule sym)
  apply (clarsimp simp:check_cap_at_def)
  apply (rule dcorres_expand_pfx)
  apply (subst alternative_com)
  apply (rule corres_guard_imp)
    apply (rule corres_splitEE[OF _ dcorres_tcb_empty_slot])
    apply (clarsimp simp:tcb_update_thread_slot_def whenE_liftE)
      apply (clarsimp simp:liftE_bindE)
      apply (rule corres_split[OF _ dcorres_corrupt_tcb_intent_ipcbuffer_upd])
        apply (clarsimp simp:bind_assoc)
        apply (rule corres_split[OF _ get_cap_corres])
        apply (clarsimp simp:liftE_def returnOk_def)
          apply (rule corres_split[OF _ corres_when])
            apply (rule corres_trivial)
            apply clarsimp
          apply (rule arch_same_obj_as_lift)
            apply (simp add:valid_ipc_buffer_cap_def is_arch_cap_def split:cap.splits)
            apply (clarsimp simp:valid_cap_def is_arch_cap_def)+
      apply (rule corres_split[OF _ get_cap_corres])
        apply (rule corres_when)
          apply (rule sym)
          apply (case_tac rv')
          apply (clarsimp simp:same_object_as_def)+
          apply (simp add:transform_cap_def split:arch_cap.splits)
        apply (rule dcorres_insert_cap_combine)
          apply (clarsimp+)[2]
      apply (rule hoare_strengthen_post[OF hoare_TrueI[where P = \<top>]],simp)
      apply (rule_tac Q = "\<lambda>r s. cte_wp_at (op = cap.NullCap) (obj_id', tcb_cnode_index 4) s \<and> cte_wp_at (\<lambda>_. True) (ab, ba) s
        \<and> valid_global_refs s \<and> valid_idle s \<and> valid_irq_node s \<and> valid_mdb s \<and> valid_objs s\<and> not_idle_thread ab s \<and> valid_etcbs s
        \<and> ((is_thread_cap r \<and> obj_ref_of r = obj_id') \<longrightarrow> ex_cte_cap_wp_to (\<lambda>_. True) (obj_id', tcb_cnode_index 4) s)"
        in hoare_strengthen_post)
      apply (wp get_cap_ex_cte_cap_wp_to,clarsimp)
      apply (clarsimp simp:same_object_as_def)
      apply (drule ex_cte_cap_to_not_idle, auto simp: not_idle_thread_def)[1]
      apply (wp hoare_when_wp)
      apply (rule hoare_strengthen_post[OF hoare_TrueI[where P = \<top>]],clarsimp+)
      apply (rule hoare_drop_imp,wp)
      apply (clarsimp simp:conj_ac)
      apply (wp thread_set_global_refs_triv thread_set_valid_idle)
        apply (clarsimp simp:tcb_cap_cases_def)
      apply (wp thread_set_valid_idle thread_set_valid_irq_node)
        apply (fastforce simp:tcb_cap_cases_def)
      apply (wp thread_set_mdb)
        apply (fastforce simp:tcb_cap_cases_def)
      apply (simp add:not_idle_thread_def)
      apply (wp thread_set_cte_at update_ipc_buffer_valid_objs
                thread_set_valid_cap thread_set_cte_wp_at_trivial)
        apply (fastforce simp:tcb_cap_cases_def)
       apply (simp add: transform_tcb_slot_4)
      apply (rule hoare_post_impErr[OF validE_R_validE[OF hoare_True_E_R]])
      apply simp+
    apply (rule_tac Q = "\<lambda>r s. invs s \<and> valid_etcbs s \<and> not_idle_thread (fst a') s \<and> tcb_at obj_id' s
                 \<and> not_idle_thread obj_id' s \<and> not_idle_thread ab s \<and> cte_wp_at (\<lambda>_. True) (ab,ba) s \<and>
                 cte_wp_at (\<lambda>c. c = cap.NullCap) (obj_id', tcb_cnode_index 4) s \<and> is_aligned a msg_align_bits"
          in hoare_post_impErr[where E="\<lambda>x. \<top>"])
      apply (simp add:not_idle_thread_def)
      apply (wp cap_delete_cte_at cap_delete_deletes cap_delete_valid_cap)
      apply (clarsimp simp:invs_valid_objs invs_mdb invs_valid_idle)
      apply (clarsimp simp:invs_def  valid_state_def not_idle_thread_def)
      apply (erule cte_wp_at_weakenE,simp+)
    apply (clarsimp simp:emptyable_def not_idle_thread_def)
    apply (erule tcb_at_cte_at,clarsimp)
done

lemma dcorres_tcb_update_vspace_root:
  "dcorres (dc \<oplus> dc) (\<top>) ( invs and valid_etcbs and tcb_at obj_id'
      and not_idle_thread obj_id' and valid_pdpt_objs and
      (\<lambda>y. option_case True (\<lambda>x. not_idle_thread (fst a') y) vroot') and
      (\<lambda>y. option_case True (is_valid_vtable_root \<circ> fst) vroot') and
           option_case (\<lambda>_. True) (valid_cap \<circ> fst) vroot' and
           option_case (\<lambda>_. True) (not_idle_thread \<circ> fst \<circ> snd ) vroot' and
           option_case (\<lambda>_. True) (no_cap_to_obj_dr_emp \<circ> fst) vroot' and
           option_case (\<lambda>_. True) (cte_wp_at (\<lambda>_. True) \<circ> snd) vroot')
    (option_case (returnOk ()) (tcb_update_vspace_root obj_id' (transform_cslot_ptr a'))
      (Option.map (\<lambda>r. (transform_cap (fst r), transform_cslot_ptr (snd r))) vroot'))
    (option_case (returnOk ())
      (prod_case
      (\<lambda>new_cap src_slot.
        doE cap_delete (obj_id', tcb_cnode_index 1);
          liftE $
          check_cap_at new_cap src_slot $
          check_cap_at (cap.ThreadCap obj_id') a' $ cap_insert new_cap src_slot (obj_id', tcb_cnode_index 1)
        odE))
      vroot')"
  apply (case_tac vroot')
    apply simp_all
    apply (rule corres_guard_imp[OF corres_returnOk],simp+)
  apply (case_tac a)
  apply (unfold tcb_update_vspace_root_def tcb_update_thread_slot_def)
  apply (clarsimp simp:tcb_update_thread_slot_def)
  apply (rule dcorres_expand_pfx)
  apply (rule corres_guard_imp)
    apply (rule corres_splitEE[OF _ dcorres_tcb_empty_slot])
    apply (clarsimp simp:check_cap_at_def liftE_bindE)
    apply (clarsimp simp:whenE_liftE bind_assoc)
    apply (clarsimp simp:liftE_def bind_assoc)
    apply (clarsimp simp: is_valid_vtable_root_def )
    apply (rule corres_split[OF _ get_cap_corres])
      apply (rule corres_split[OF _ corres_when])
      apply (rule corres_trivial)
        apply clarsimp
      apply (rule arch_same_obj_as_lift)
        apply (clarsimp simp:valid_cap_def is_arch_cap_def)+
      apply (rule corres_split[OF _ get_cap_corres])
        apply (rule corres_when)
          apply (rule sym)
          apply (case_tac cap')
          apply (clarsimp simp:same_object_as_def)+
          apply (simp add:transform_cap_def split:arch_cap.splits)
        apply (simp add: transform_tcb_slot_1[symmetric])
        apply (rule dcorres_insert_cap_combine[folded alternative_com])
        apply (simp add:transform_cap_def,simp)
        apply wp
      apply (simp add:same_object_as_def)
      apply (rule_tac Q = "\<lambda>r s. cte_wp_at (op = cap.NullCap) (obj_id', tcb_cnode_index (Suc 0)) s \<and> cte_wp_at (\<lambda>_. True) (ba, c) s
        \<and>  valid_global_refs s \<and> valid_idle s \<and> valid_irq_node s \<and> valid_mdb s \<and> not_idle_thread ba s \<and> valid_objs s \<and> valid_etcbs s
        \<and> ((is_thread_cap r \<and> obj_ref_of r = obj_id') \<longrightarrow> ex_cte_cap_wp_to (\<lambda>_. True) (obj_id', tcb_cnode_index (Suc 0)) s)"
        in hoare_strengthen_post)
      apply (wp get_cap_ex_cte_cap_wp_to,clarsimp)
      apply clarsimp
      apply (drule (3) ex_cte_cap_to_not_idle, simp add: not_idle_thread_def)
      apply (wp hoare_when_wp)
    apply (rule hoare_strengthen_post[OF hoare_TrueI[where P =\<top> ]])
    apply (clarsimp+)[2]
    apply (rule hoare_strengthen_post[OF hoare_TrueI[where P =\<top> ]])
    apply clarsimp+
    apply (rule hoare_drop_imp)
    apply (wp | simp add: transform_tcb_slot_1[symmetric])+
    apply (rule validE_validE_R)
    apply (rule_tac Q = "\<lambda>r s. invs s \<and> valid_etcbs s \<and> not_idle_thread ba s \<and>
                 not_idle_thread (fst a') s \<and> cte_wp_at (\<lambda>_. True) (ba, c) s \<and>
                 cte_wp_at (\<lambda>c. c = cap.NullCap) (obj_id', tcb_cnode_index (Suc 0)) s"
          in hoare_post_impErr[where E="\<lambda>x. \<top>"])
      apply (simp add:not_idle_thread_def)
      apply (wp cap_delete_cte_at cap_delete_deletes)
      apply (clarsimp simp:invs_def valid_state_def valid_pspace_def)
      apply (erule cte_wp_at_weakenE,clarsimp+)
    apply (simp add:emptyable_def not_idle_thread_def)
    apply (erule tcb_at_cte_at,clarsimp)
done


lemma dcorres_tcb_update_cspace_root:
  "dcorres (dc \<oplus> dc) (\<top> ) ( invs and valid_etcbs and valid_pdpt_objs
           and not_idle_thread obj_id' and tcb_at obj_id' and
           option_case (\<lambda>_. True) (valid_cap \<circ> fst) croot' and
      (\<lambda>y. option_case True (\<lambda>x. not_idle_thread (fst a') y) croot') and
      (\<lambda>y. option_case True (Structures_A.is_cnode_cap \<circ> fst) croot') and
           option_case (\<lambda>_. True) (not_idle_thread \<circ> fst \<circ> snd ) croot' and
           option_case (\<lambda>_. True) (cte_wp_at (\<lambda>_. True) \<circ> snd) croot' and
           option_case (\<lambda>_. True) (no_cap_to_obj_dr_emp \<circ> fst) croot')
    (option_case (returnOk ()) (tcb_update_cspace_root obj_id' (transform_cslot_ptr a'))
        (Option.map (\<lambda>r. (transform_cap (fst r), transform_cslot_ptr (snd r))) croot'))
    (option_case (returnOk ())
        (prod_case
        (\<lambda>new_cap src_slot.
          doE cap_delete (obj_id', tcb_cnode_index 0);
            liftE $
            check_cap_at new_cap src_slot $
            check_cap_at (cap.ThreadCap obj_id') a' $ cap_insert new_cap src_slot (obj_id', tcb_cnode_index 0)
          odE))
      croot')"
  apply (case_tac croot')
    apply simp_all
    apply (rule corres_guard_imp[OF dcorres_returnOk],simp+)
  apply (case_tac a)
  apply (clarsimp simp:tcb_update_cspace_root_def tcb_update_thread_slot_def)
  apply (simp add:transform_tcb_slot_simp[symmetric])
  apply (rule dcorres_expand_pfx)
    apply (rule corres_guard_imp)
    apply (rule corres_splitEE[OF _  dcorres_tcb_empty_slot])
    apply (simp add:check_cap_at_def liftE_bindE)
    apply (clarsimp simp:no_cap_to_obj_with_diff_ref_def)
    apply (clarsimp simp:whenE_liftE bind_assoc same_object_as_def)
    apply (clarsimp simp:liftE_def bind_assoc)
    apply (rule corres_split[OF _ get_cap_corres])
      apply (rule_tac F = "(is_cnode_cap x \<and> obj_refs x = obj_refs aaa) \<longrightarrow> (bits_of x = bits_of aaa)" in corres_gen_asm2)
          apply (rule corres_split[OF _ corres_when])
          apply (rule corres_trivial)
            apply (clarsimp)
          apply (rule iffI)
            apply (clarsimp simp:is_cap_simps bits_of_def cap_type_def transform_cap_def
              split:cap.split_asm arch_cap.split_asm split_if_asm)
          apply (clarsimp simp:cap_has_object_def is_cap_simps cap_type_def)
          apply (rule corres_split[OF _ get_cap_corres])
            apply (rule corres_when)
          apply (rule sym)
            apply (simp add:table_cap_ref_def)
            apply (case_tac rv')
            (* Following line is incredibly brittle. You may need to change the number if the proof breaks *)
            apply ((clarsimp simp:transform_cap_def split: arch_cap.splits)+)[12]
          apply (simp)
        apply (rule dcorres_insert_cap_combine[folded alternative_com])
        apply ((clarsimp simp:is_cap_simps)+)[2]
        apply wp
      apply (rule_tac Q = "\<lambda>r s. cte_wp_at (op = cap.NullCap) (obj_id', tcb_cnode_index 0) s \<and> cte_wp_at (\<lambda>_. True) (ba, c) s
        \<and>  valid_global_refs s \<and> valid_idle s \<and> valid_irq_node s \<and> valid_mdb s \<and> not_idle_thread ba s \<and> valid_objs s \<and> valid_etcbs s
        \<and> ((is_thread_cap r \<and> obj_ref_of r = obj_id') \<longrightarrow> ex_cte_cap_wp_to (\<lambda>_. True) (obj_id', tcb_cnode_index 0) s)"
        in hoare_strengthen_post)
      apply (wp get_cap_ex_cte_cap_wp_to)
      apply (clarsimp+)[2]
      apply (drule (3) ex_cte_cap_to_not_idle, simp add: not_idle_thread_def)
      apply (erule valid_cap_aligned)
    apply (wp hoare_when_wp)
    apply (rule hoare_strengthen_post[OF hoare_TrueI[where P =\<top> ]])
    apply clarsimp+
    apply wp
    apply (rule hoare_vcg_conj_lift)
      apply (rule hoare_drop_imp)
      apply wp
    apply (rule_tac cnode_cap_unique_bits)
      apply simp
    apply (simp add:transform_tcb_slot_0)
    apply (simp add:validE_def,rule hoare_strengthen_post[OF hoare_TrueI[where P = \<top> ]])
      apply fastforce
    apply (clarsimp simp:conj_ac)
    apply (rule_tac Q = "\<lambda>r s. invs s \<and> valid_etcbs s \<and> not_idle_thread ba s \<and> valid_cap aaa s \<and>
                 not_idle_thread (fst a') s \<and> cte_wp_at (\<lambda>_. True) (ba, c) s \<and>
                 cte_wp_at (\<lambda>c. c = cap.NullCap) (obj_id', tcb_cnode_index 0) s \<and>
                 no_cap_to_obj_dr_emp aaa s"
      in hoare_post_impErr[where E = "\<lambda>r. \<top>"])
      apply (simp add:not_idle_thread_def)
      apply (wp cap_delete_cte_at cap_delete_deletes cap_delete_valid_cap)
     apply (simp add:invs_valid_objs)
     apply (clarsimp simp:invs_def valid_state_def no_cap_to_obj_with_diff_ref_def
       cte_wp_at_def valid_pspace_vo)
  apply (clarsimp simp:empty_set_eq not_idle_thread_def emptyable_def)+
  apply (erule tcb_at_cte_at)
  apply (simp add:tcb_cap_cases_def)
done


lemma tcb_fault_fault_handler_upd:
  "tcb_fault (obj'\<lparr>tcb_fault_handler := a\<rparr>) = tcb_fault obj'"
  by simp

lemma option_update_thread_corres:
  "dcorres (dc \<oplus> dc) \<top> (not_idle_thread obj_id and valid_etcbs)
       (case Option.map of_bl fault_ep' of None \<Rightarrow> returnOk ()
        | Some x \<Rightarrow> liftE $ update_thread obj_id (cdl_tcb_fault_endpoint_update (\<lambda>_. x)))
       (liftE (option_update_thread obj_id (tcb_fault_handler_update \<circ> (\<lambda>x y. x)) fault_ep'))"
  apply (simp add:option_update_thread_def not_idle_thread_def)
  apply (case_tac fault_ep')
    apply (simp add:liftE_def bindE_def returnOk_def)
  apply clarsimp
  apply (simp add:update_thread_def thread_set_def get_thread_def bind_assoc)
  apply (rule dcorres_gets_the)
   apply (clarsimp, frule(1) valid_etcbs_get_tcb_get_etcb)
    apply (clarsimp simp:opt_object_tcb transform_tcb_def)
    apply (rule dcorres_set_object_tcb)
    apply (clarsimp simp:transform_tcb_def infer_tcb_pending_op_def )
    apply (simp add: get_etcb_def cong:transform_full_intent_caps_cong_weak)
    apply simp
   apply (clarsimp simp: get_tcb_def split:option.splits)
   apply (clarsimp simp: get_etcb_def split:option.splits)
   apply (clarsimp, frule(1) valid_etcbs_get_tcb_get_etcb)
  apply (clarsimp simp:opt_object_tcb)
done


lemma check_cap_at_stable:
  "\<lbrace>P\<rbrace>f\<lbrace>\<lambda>r. P\<rbrace>
   \<Longrightarrow>\<lbrace>P\<rbrace>check_cap_at aa b (check_cap_at aaa bb (f)) \<lbrace>\<lambda>r. P\<rbrace>"
  apply (clarsimp simp:check_cap_at_def not_idle_thread_def)
  apply (wp | simp split:if_splits)+
done

lemma option_case_wp:
  "(\<And>x. \<lbrace>P x\<rbrace>a\<lbrace>\<lambda>r. Q x\<rbrace>) \<Longrightarrow> \<lbrace>option_case \<top> P z\<rbrace>a\<lbrace>\<lambda>r. option_case \<top> Q z\<rbrace>"
  by (clarsimp split:option.splits)

lemma hoare_case_some:
  "\<lbrace>P\<rbrace>a\<lbrace>\<lambda>r s. Q s\<rbrace> \<Longrightarrow> \<lbrace>\<lambda>s. case x of None \<Rightarrow> True | Some y \<Rightarrow> P s\<rbrace> a
    \<lbrace>\<lambda>rv s. case x of None \<Rightarrow> True | Some y \<Rightarrow> Q s\<rbrace>"
  apply (case_tac x)
    apply clarsimp+
done

lemma hoare_case_someE:
  "\<lbrace>P\<rbrace>a\<lbrace>\<lambda>r s. Q s\<rbrace>,- \<Longrightarrow> \<lbrace>\<lambda>s. case x of None \<Rightarrow> True | Some y \<Rightarrow> P s\<rbrace> a
    \<lbrace>\<lambda>rv s. case x of None \<Rightarrow> True | Some y \<Rightarrow> Q s\<rbrace>,-"
  apply (case_tac x)
    apply clarsimp+
done

lemma option_case_wpE:
  "(\<And>x. \<lbrace>P x\<rbrace>a\<lbrace>\<lambda>r. Q x\<rbrace>,-) \<Longrightarrow> \<lbrace>option_case \<top> P z\<rbrace>a\<lbrace>\<lambda>r. option_case \<top> Q z\<rbrace>,-"
  by (clarsimp split:option.splits)

lemma option_update_thread_not_idle_thread[wp]:
  "\<lbrace>not_idle_thread x and not_idle_thread a\<rbrace>option_update_thread a b c\<lbrace>\<lambda>r. not_idle_thread x\<rbrace>"
  apply(simp add:option_update_thread_def)
  apply (rule hoare_pre)
  apply wpc
  apply wp
  apply (clarsimp simp:thread_set_def set_object_def)
  apply wp
  apply (clarsimp simp:not_idle_thread_def)
done

lemma reschedule_required_transform: "\<lbrace>\<lambda>ps. transform ps = cs\<rbrace> reschedule_required \<lbrace>\<lambda>r s. transform s = cs\<rbrace>"
  by (clarsimp simp: reschedule_required_def set_scheduler_action_def etcb_at_def
     | wp tcb_sched_action_transform | wpc)+

lemma thread_set_priority_transform: "\<lbrace>\<lambda>ps. transform ps = cs\<rbrace> thread_set_priority tptr prio \<lbrace>\<lambda>r s. transform s = cs\<rbrace>"
  apply (clarsimp simp: thread_set_priority_def ethread_set_def set_eobject_def | wp)+

  apply (clarsimp simp: transform_def transform_objects_def transform_cdt_def transform_current_thread_def transform_asid_table_def)
  apply (rule_tac y="\<lambda>ptr. Option.map (transform_object (machine_state s) ptr ((ekheap s |` (- {idle_thread s})) ptr)) ((kheap s |` (- {idle_thread s})) ptr)" in arg_cong)
  apply (rule ext)
  apply (rule_tac y="transform_object (machine_state s) ptr ((ekheap s |` (- {idle_thread s})) ptr)" in arg_cong)
  apply (rule ext)
  apply (clarsimp simp: transform_object_def transform_tcb_def restrict_map_def get_etcb_def split: option.splits Structures_A.kernel_object.splits)
  done

lemma option_set_priority_corres:
  "dcorres (dc \<oplus> dc) \<top> \<top>
        (returnOk ())
        (liftE (case prio' of None \<Rightarrow> return () | Some prio \<Rightarrow> do_extended_op (set_priority obj_id' prio)))"
  apply (clarsimp)
  apply (case_tac prio')
   apply (clarsimp simp: liftE_def set_priority_def returnOk_def bind_assoc)+
  apply (rule corres_noop)
   apply (wp reschedule_required_transform tcb_sched_action_transform thread_set_priority_transform | simp)+
  done

declare option.weak_case_cong[cong]
declare if_weak_cong[cong]


crunch valid_etcbs[wp]: set_priority "valid_etcbs"
  (wp: crunch_wps simp: crunch_simps)

lemma not_idle_thread_ekheap_update[iff]:
  "not_idle_thread ptr (ekheap_update f s) = not_idle_thread ptr s"
  by (simp add: not_idle_thread_def)

lemma not_idle_thread_scheduler_action_update[iff]:
  "not_idle_thread ptr (scheduler_action_update f s) = not_idle_thread ptr s"
  by (simp add: not_idle_thread_def)

crunch not_idle_thread[wp]: reschedule_required "not_idle_thread ptr"
  (wp: crunch_wps simp: crunch_simps)

crunch not_idle_thread[wp]: set_priority "not_idle_thread ptr"
  (wp: crunch_wps simp: crunch_simps)

crunch emptyable[wp]: tcb_sched_action "emptyable ptr"
  (wp: crunch_wps simp: crunch_simps)

crunch emptyable[wp]: reschedule_required "emptyable ptr"
  (wp: crunch_wps simp: crunch_simps)

crunch emptyable[wp]: set_priority "emptyable ptr"
  (wp: crunch_wps simp: crunch_simps)

lemma set_priority_transform: "\<lbrace>\<lambda>ps. transform ps = cs\<rbrace> set_priority tptr prio \<lbrace>\<lambda>r s. transform s = cs\<rbrace>"
  by (clarsimp simp: set_priority_def ethread_set_def set_eobject_def | wp reschedule_required_transform tcb_sched_action_transform thread_set_priority_transform)+

crunch valid_etcbs[wp]: option_update_thread "valid_etcbs"
  (wp: crunch_wps simp: crunch_simps)

lemma dcorres_thread_control:
  notes option_case_map [simp del]
  shows
  "\<lbrakk> t' = tcb_invocation.ThreadControl obj_id' a' fault_ep' prio' croot' vroot' ipc_buffer';
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (\<lambda>s. invs s \<and> valid_etcbs s \<and>
            not_idle_thread obj_id' s \<and>
            tcb_at obj_id' s \<and> valid_pdpt_objs s \<and>
            option_case (\<lambda>_. True) (valid_cap \<circ> fst) croot' s \<and>
            option_case True (Structures_A.is_cnode_cap \<circ> fst) croot' \<and>
            option_case (\<lambda>_. True) (not_idle_thread \<circ> fst \<circ> snd) croot' s \<and>
      (\<lambda>y.  option_case True (\<lambda>x. not_idle_thread (fst a') y) croot') s \<and>
            option_case (\<lambda>_. True) (cte_wp_at (\<lambda>_. True) \<circ> snd) croot' s \<and>
            option_case (\<lambda>_. True) (no_cap_to_obj_dr_emp \<circ> fst) croot' s \<and>
      (\<lambda>y.  option_case True (\<lambda>x. not_idle_thread (fst a') y) vroot') s \<and>
            option_case True (is_valid_vtable_root \<circ> fst) vroot' \<and>
            option_case (\<lambda>_. True) (valid_cap \<circ> fst) vroot' s \<and>
            option_case (\<lambda>_. True) (not_idle_thread \<circ> fst \<circ> snd) vroot' s \<and>
            option_case (\<lambda>_. True) (cte_wp_at (\<lambda>_. True) \<circ> snd) vroot' s \<and>
            option_case (\<lambda>_. True) (no_cap_to_obj_dr_emp \<circ> fst) vroot' s \<and>
            (\<lambda>s. option_case True (is_valid_vtable_root \<circ> fst) vroot') s \<and>
      (\<lambda>y.  option_case True (\<lambda>x. not_idle_thread (fst a') y) ipc_buffer') s \<and>
            option_case (\<lambda>_. True) (option_case (\<lambda>_. True) (not_idle_thread \<circ> fst \<circ> snd) \<circ> snd) ipc_buffer' s \<and>
            option_case (\<lambda>_. True) (option_case (\<lambda>_. True) (cte_wp_at (\<lambda>_. True) \<circ> snd) \<circ> snd) ipc_buffer' s \<and>
            (case ipc_buffer' of None \<Rightarrow> True
             | Some v \<Rightarrow> option_case True ((swp valid_ipc_buffer_cap (fst v) and is_arch_cap and cap_aligned) \<circ> fst) (snd v)
            \<and> is_aligned (fst v) msg_align_bits)
          \<and> option_case (\<lambda>_. True) (\<lambda>a. case snd a of None \<Rightarrow> \<lambda>_. True | Some a \<Rightarrow> cte_wp_at (\<lambda>_. True) (snd a)) ipc_buffer' s
          \<and> (case fault_ep' of None \<Rightarrow> True | Some bl \<Rightarrow> length bl = WordSetup.word_bits))
       (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  (is "\<lbrakk> ?eq; ?eq' \<rbrakk> \<Longrightarrow> dcorres (dc \<oplus> dc) \<top> ?P ?f ?g")
  apply (clarsimp simp: Tcb_D.invoke_tcb_def)
  apply (clarsimp simp: translate_tcb_invocation_def)
  apply (rule corres_guard_imp)
    apply (rule corres_splitEE[OF _ option_update_thread_corres])
    apply (rule dcorres_symb_exec_rE)
      apply (rule corres_splitEE[OF _ dcorres_tcb_update_cspace_root])
        apply (rule corres_splitEE[OF _ dcorres_tcb_update_vspace_root])
          apply (rule dcorres_tcb_update_ipc_buffer)
   apply (wp)
   apply (wp|wpc)+
   apply (wp checked_insert_tcb_invs | clarsimp)+
   apply (rule check_cap_at_stable,(clarsimp simp:not_idle_thread_def | wp)+)+
   apply (rule check_cap_at_stable)
     apply (rule option_case_wp,clarsimp split:option.splits,wp)
   apply (rule option_case_wp)
   apply simp
   apply (rule option_case_wp)
   apply (rule check_cap_at_stable,clarsimp simp:not_idle_thread_def split:option.splits,wp)
   apply (simp,rule check_cap_at_stable)
   apply (case_tac ipc_buffer')
     apply (clarsimp simp:not_idle_thread_def)+
   apply wp
   apply (clarsimp simp:conj_ac)
     apply (wp cap_delete_deletes cap_delete_valid_cap)
     apply (strengthen tcb_cap_always_valid_strg use_no_cap_to_obj_asid_strg)
     apply (clarsimp simp:tcb_cap_cases_def)
     apply (strengthen is_cnode_or_valid_arch_cap_asid[simplified,THEN conjunct1,THEN impI])
     apply (strengthen is_cnode_or_valid_arch_cap_asid[simplified,THEN conjunct2,THEN impI])
     apply (wp hoare_case_someE)
       apply (clarsimp simp:not_idle_thread_def)
     apply (wp cap_delete_deletes cap_delete_cte_at cap_delete_valid_cap)
     apply (wp option_case_wpE)
       apply simp
       apply (rule option_case_wpE)
         apply simp
         apply (wp cap_delete_cte_at)
     apply (wp option_case_wpE)
       apply (simp add:not_idle_thread_def)
       apply (wp cap_delete_cte_at cap_delete_valid_cap)
   apply (rule_tac Q'="\<lambda>_. ?P" in hoare_post_imp_R[rotated])
   apply (clarsimp simp:is_valid_vtable_root_def is_cnode_or_valid_arch_def
    is_arch_cap_def not_idle_thread_def emptyable_def split:option.splits)
  apply (wpc|wp)+
   apply (wp checked_insert_tcb_invs | clarsimp)+
   apply (rule check_cap_at_stable,(simp add:not_idle_thread_def | wp)+)+
   apply (wp checked_insert_no_cap_to hoare_case_some)
   apply (simp,rule check_cap_at_stable,simp add:not_idle_thread_def)
     apply wp
   apply (simp,rule check_cap_at_stable)
     apply (rule option_case_wp,clarsimp split:option.splits,wp)
   apply (rule option_case_wp)
   apply simp
   apply (rule check_cap_at_stable,clarsimp simp:not_idle_thread_def split:option.splits,wp)
   apply (rule option_case_wp)
   apply simp
   apply (rule check_cap_at_stable,wp)
   apply (rule option_case_wp)
   apply simp
   apply (wp checked_insert_no_cap_to)
   apply (wp hoare_case_some)
   apply (simp, rule check_cap_at_stable,simp add:not_idle_thread_def)
   apply (wp option_case_wp)
   apply simp
   apply (rule option_case_wp,simp add:not_idle_thread_def)
   apply (rule check_cap_at_stable,wp)
   apply (wp option_case_wp check_cap_at_stable | simp)+
     apply (wp cap_delete_deletes cap_delete_valid_cap)
     apply (strengthen tcb_cap_always_valid_strg use_no_cap_to_obj_asid_strg)
     apply (simp add:tcb_cap_cases_def)
     apply (strengthen is_cnode_or_valid_arch_cap_asid[simplified,THEN conjunct1,THEN impI])
     apply (strengthen is_cnode_or_valid_arch_cap_asid[simplified,THEN conjunct2,THEN impI])
     apply simp
     apply (wp cap_delete_deletes cap_delete_cte_at cap_delete_valid_cap)
     apply (wp option_case_wpE cap_delete_valid_cap cap_delete_deletes cap_delete_cte_at hoare_case_someE
       | simp add:not_idle_thread_def)+
       apply (case_tac prio', clarsimp, rule return_wp)
       apply clarsimp
       apply ((wp option_case_wp dxo_wp_weak | clarsimp split: option.splits | rule conjI)+)[1]
      apply ((wp set_priority_transform | clarsimp split: option.splits | rule conjI)+)[1]
     apply (wp option_case_wpE)
  apply (rule_tac Q="\<lambda>_. ?P" in hoare_strengthen_post[rotated])
  apply (clarsimp simp:is_valid_vtable_root_def is_cnode_or_valid_arch_def
    is_arch_cap_def not_idle_thread_def emptyable_def split:option.splits)
  apply (rule_tac P = "(case fault_ep' of None \<Rightarrow> True | Some bl \<Rightarrow> length bl = WordSetup.word_bits)" in hoare_gen_asm)
  apply (wp out_invs_trivialT)
    apply (clarsimp simp:tcb_cap_cases_def)+
  apply (wp option_case_wp out_cte_at out_valid_cap hoare_case_some| simp)+
  apply (wp out_no_cap_to_trivial)
    apply (clarsimp simp:tcb_cap_cases_def)
  apply (wp option_case_wp out_cte_at out_valid_cap hoare_case_some| simp)+
  apply (wp out_no_cap_to_trivial)
    apply (clarsimp simp:tcb_cap_cases_def)
  apply (wp option_case_wp out_cte_at out_valid_cap hoare_case_some | simp)+
  apply (clarsimp split:option.splits)
  done

lemma invoke_tcb_corres_thread_control:
  "\<lbrakk> t' = tcb_invocation.ThreadControl obj_id' a' fault_ep' prio' croot' vroot' ipc_buffer';
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (\<lambda>s. invs s \<and> valid_etcbs s \<and> not_idle_thread obj_id' s
                   \<and> valid_pdpt_objs s \<and> tcb_inv_wf t' s)
       (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  apply (rule corres_guard_imp[OF dcorres_thread_control])
  apply fastforce
  apply ((clarsimp simp:conj_ac
    valid_cap_aligned simp del:split_paired_All)+)[2]
  apply (elim conjE)
   apply (subgoal_tac "\<forall>x. ex_cte_cap_to x s \<longrightarrow> not_idle_thread (fst x) s")
   apply (intro conjI)
     apply ((clarsimp simp del:split_paired_All split:option.splits)+)[19] (* Brittle proof. Change number? *)
     apply (case_tac ipc_buffer',simp)
     apply (case_tac "snd a",simp)
     apply (clarsimp simp del:split_paired_All split:option.splits)
     apply (case_tac ipc_buffer',simp)
     apply (case_tac "snd a",simp)
     apply (clarsimp simp del:split_paired_All split:option.splits)
     apply (case_tac ipc_buffer',simp)
     apply (case_tac "snd a",simp)
     apply (clarsimp simp del:split_paired_All split:option.splits)
     apply (case_tac ipc_buffer',simp)
     apply (case_tac "snd a",simp)
     apply (clarsimp simp del:split_paired_All split:option.splits)
   apply (clarsimp simp del:split_paired_All split:option.splits)
  apply clarsimp
  apply (drule ex_cte_cap_wp_to_not_idle)+
    apply (clarsimp simp:invs_def valid_state_def valid_pspace_def)+
done

lemma invoke_tcb_corres_suspend:
  "\<lbrakk> t' = tcb_invocation.Suspend obj_id';
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (invs and not_idle_thread obj_id' and tcb_at obj_id' and valid_etcbs)
    (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  apply (clarsimp simp: Tcb_D.invoke_tcb_def translate_tcb_invocation_def)
  apply (rule corres_alternate1)
  apply (rule corres_bind_ignore_ret_rhs)
  apply (rule corres_return_dc_rhs)
  apply (rule corres_guard_imp)
  apply (rule suspend_corres, simp+)
  done

lemma invoke_tcb_corres_resume:
  "\<lbrakk> t' = tcb_invocation.Resume obj_id';
     t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (invs and not_idle_thread obj_id' and tcb_at obj_id' and valid_etcbs)
  (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  apply (clarsimp simp: Tcb_D.invoke_tcb_def translate_tcb_invocation_def)
  apply (rule corres_alternate1)
  apply (rule corres_bind_ignore_ret_rhs)
  apply (rule corres_return_dc_rhs)
  apply (rule corres_guard_imp[OF restart_corres],clarsimp+)
  done


lemma ex_nonz_cap_to_idle_from_invs:
  "invs s \<Longrightarrow> \<not> ex_nonz_cap_to (idle_thread s) s"
  apply (rule Invariants_AI.idle_no_ex_cap)
   apply (clarsimp simp: invs_def valid_state_def)
  apply (clarsimp simp: invs_def valid_state_def)
  done

lemma ex_nonz_cap_implies_normal_tcb:
  "\<lbrakk> invs s; tcb_at t' s; ex_nonz_cap_to t' s \<rbrakk> \<Longrightarrow> not_idle_thread t' s"
  by (auto simp: ex_nonz_cap_to_idle_from_invs not_idle_thread_def)

lemmas invoke_tcb_rules = ex_nonz_cap_implies_normal_tcb

lemma invoke_tcb_corres:
  "\<lbrakk> t = translate_tcb_invocation t' \<rbrakk> \<Longrightarrow>
   dcorres (dc \<oplus> dc) \<top> (invs and valid_pdpt_objs and tcb_inv_wf t' and valid_etcbs)
     (Tcb_D.invoke_tcb t) (Tcb_A.invoke_tcb t')"
  apply (clarsimp)
  apply (case_tac t')
       apply (rule corres_guard_imp [OF invoke_tcb_corres_write_regs], assumption, auto intro:invoke_tcb_rules )[1]
      apply (rule corres_guard_imp [OF invoke_tcb_corres_read_regs], assumption, auto intro!:invoke_tcb_rules)[1]
     apply (rule corres_guard_imp [OF invoke_tcb_corres_copy_regs], assumption, auto intro!:invoke_tcb_rules)[1]
    apply (rule corres_guard_imp [OF invoke_tcb_corres_thread_control],assumption,auto intro!:invoke_tcb_rules)[1]
   apply (rule corres_guard_imp [OF invoke_tcb_corres_suspend], assumption, auto intro!:invoke_tcb_rules)[1]
  apply (rule corres_guard_imp [OF invoke_tcb_corres_resume], assumption, auto intro!:invoke_tcb_rules)[1]
  done

end
