(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(NICTA_GPL)
 *)

theory Syscall_IF
imports    
     "PasUpdates" (*Only needed for idle thread stuff*)
     "Tcb_IF"
    "Interrupt_IF"
    "Decode_IF"

begin

crunch_ignore (add: OR_choice set_scheduler_action)

(* The contents of the delete_globals_equiv locale *)

lemma globals_equiv_irq_state_update[simp]:
  "globals_equiv st
            (s\<lparr>machine_state := machine_state s
                 \<lparr>irq_state := f (irq_state (machine_state s))\<rparr>\<rparr>) =
          globals_equiv st s"
  apply(auto simp: globals_equiv_def idle_equiv_def)
  done

lemma cap_revoke_globals_equiv:
  "\<lbrace>globals_equiv st and invs\<rbrace> cap_revoke slot \<lbrace>\<lambda>_. globals_equiv st\<rbrace>"
  apply(rule_tac Q="\<lambda>_. globals_equiv st and invs" in hoare_strengthen_post)
   apply(wp cap_revoke_preservation_desc_of cap_delete_globals_equiv preemption_point_inv | auto simp: emptyable_def dest: reply_slot_not_descendant)+
  done

lemma tcb_context_merge[simp]: "tcb_context (tcb_registers_caps_merge tcb tcb') = tcb_context tcb"
  apply (simp add: tcb_registers_caps_merge_def)
  done

lemma thread_set_globals_equiv':
  "\<lbrace>globals_equiv s and valid_ko_at_arm and (\<lambda>s. tptr \<noteq> idle_thread s)\<rbrace> thread_set f tptr \<lbrace>\<lambda>_. globals_equiv s\<rbrace>"
  unfolding thread_set_def
  apply(wp set_object_globals_equiv)
  apply simp
  apply (intro impI conjI allI)
  apply(fastforce simp: valid_ko_at_arm_def obj_at_def get_tcb_def)+
  done

lemma recycle_cap_globals_equiv:
  "\<lbrace>globals_equiv st and cte_wp_at (op = cap) slot and invs\<rbrace> recycle_cap is_final cap \<lbrace>\<lambda>_. globals_equiv st\<rbrace>"
  proof -
  have no_zombie_cap_to_idle: "\<And>word a b slot s. invs s \<Longrightarrow> \<not> cte_wp_at (op = (Zombie (idle_thread s) a b)) slot s"
    apply (fastforce simp: invs_def
                          valid_state_def valid_refs_def cte_wp_at_def
                          cap_range_def
                           valid_global_refs_def global_refs_def)
  done
  show ?thesis
  unfolding recycle_cap_def
  apply (induct cap)
  apply simp_all
  apply (wp ep_cancel_badged_sends_globals_equiv
            thread_set_globals_equiv' dxo_wp_weak
            arch_recycle_cap_globals_equiv
       | wpc
       | clarsimp simp add: invs_valid_ko_at_arm recycle_cap_ext_def no_zombie_cap_to_idle split: option.splits
       | intro impI conjI allI
       | rule hoare_drop_imps)+

 apply blast
done
qed

lemma recycle_cap_valid_global_objs:
  "\<lbrace>invs and cte_wp_at (op = cap) slot\<rbrace> recycle_cap is_final cap \<lbrace>\<lambda>_. valid_global_objs\<rbrace>"
  apply(rule hoare_pre)
   apply(rule hoare_strengthen_post[OF recycle_cap_invs])
   apply(simp add: invs_valid_global_objs)
  apply blast
  done

lemma cap_recycle_globals_equiv:
  "\<lbrace>invs and globals_equiv st and real_cte_at slot\<rbrace> cap_recycle slot \<lbrace>\<lambda>_. globals_equiv st\<rbrace>"
  unfolding cap_recycle_def
  apply (rule hoare_pre)
   apply (wp set_cap_globals_equiv recycle_cap_globals_equiv recycle_cap_valid_global_objs get_cap_wp
         | simp add: unless_def finalise_slot_def split_def split del: split_if)+
     apply(rule hoare_post_impErr[OF valid_validE[where Q="invs and globals_equiv st"]])
       apply(wp rec_del_invs rec_del_globals_equiv | simp)+
      apply fastforce
     apply simp
    apply (wp set_cap_globals_equiv recycle_cap_globals_equiv recycle_cap_valid_global_objs get_cap_wp | simp add: unless_def finalise_slot_def split_def split del: split_if)+
    apply(rule hoare_post_impErr[OF valid_validE[where Q="invs and globals_equiv st"]])
      apply(wp rec_del_invs rec_del_globals_equiv | simp)+
     apply fastforce
    apply simp
   apply (wp cap_revoke_invs cap_revoke_globals_equiv | strengthen real_cte_emptyable_strg | simp)+
done

lemma invoke_cnode_globals_equiv:
  "\<lbrace>globals_equiv st and invs and valid_cnode_inv cinv\<rbrace> invoke_cnode cinv \<lbrace>\<lambda>_. globals_equiv st\<rbrace>"
  unfolding invoke_cnode_def without_preemption_def fun_app_def
  apply(rule hoare_pre)
   apply(wp | wpc)+
          apply(wp cap_insert_globals_equiv cap_move_globals_equiv cap_revoke_globals_equiv cap_delete_globals_equiv cap_swap_globals_equiv hoare_vcg_all_lift cap_recycle_globals_equiv | wpc | wp_once hoare_drop_imps | simp add: invs_valid_global_objs)+
  apply (case_tac cinv)
  apply (clarsimp | strengthen real_cte_emptyable_strg)+
done

(* The contents of the delete_confidentiality locale *)

lemma cap_delete_reads_respects_f:
  "reads_respects_f aag l (silc_inv aag st and only_timer_irq_inv irq st' and einvs and simple_sched_action and emptyable slot and pas_refined aag and K(is_subject aag (fst slot))) (cap_delete slot)"
  unfolding cap_delete_def
  apply (wp rec_del_reads_respects_f)
  apply (simp | blast)+
  done

(* FIXME move *)
lemma spec_gen_asm:
  "(Q \<Longrightarrow> spec_equiv_valid st D A B P f) \<Longrightarrow> spec_equiv_valid st D A B (P and K Q) f"
  apply (simp add: spec_equiv_valid_def equiv_valid_2_def)
  done

(* FIXME move *)
lemma select_ev:
  "equiv_valid_inv I A (K(S \<noteq> {} \<longrightarrow> (\<exists>x. S = {x}))) (select S)"
  apply (clarsimp simp: equiv_valid_def spec_equiv_valid_def
                   equiv_valid_2_def select_def)
  apply blast
  done

lemma next_revoke_eq:
  notes split_paired_All[simp del] split_paired_Ex[simp del]
  shows
  "equiv_for ((aag_can_read aag or aag_can_affect aag l) \<circ> fst) cdt_list rv
         rv' \<Longrightarrow> is_subject aag (fst src_slot) \<Longrightarrow> next_revoke_cap src_slot rv = next_revoke_cap src_slot rv'"
  apply (clarsimp simp: next_child_def equiv_for_def next_revoke_cap_def)
  done

lemma next_revoke_eq':
 "reads_equiv_f aag s t \<Longrightarrow> is_subject aag (fst src_slot) \<Longrightarrow> next_revoke_cap src_slot s = next_revoke_cap src_slot t"
  apply (rule next_revoke_eq)
   apply (fastforce simp: reads_equiv_f_def reads_equiv_def2 states_equiv_for_def equiv_for_def)
  apply simp
  done

lemma cap_revoke_spec_reads_respects_f:
  notes drop_spec_valid[wp_split del] drop_spec_validE[wp_split del]
        drop_spec_ev[wp_split del] rec_del.simps[simp del]
        split_paired_All[simp del] split_paired_Ex[simp del]
  shows
"spec_reads_respects_f s aag l (silc_inv aag st and only_timer_irq_inv irq st' and einvs and simple_sched_action and pas_refined aag and K (is_subject aag (fst slot))) (cap_revoke slot)"
  proof (induct rule: cap_revoke.induct[where ?a1.0=s])
  case (1 slot s)
  show ?case
    apply (rule spec_gen_asm)
    apply (rule spec_equiv_valid_guard_imp)
     apply (subst cap_revoke.simps)
     apply (subst spec_equiv_valid_def2)
     apply (subst rel_sum_comb_equals[symmetric])
     apply (rule_tac R'="op =" in spec_equiv_valid_2_inv_bindE)
        apply(rule_tac R'="equiv_for ((aag_can_read aag or aag_can_affect aag l) \<circ> fst) id" in spec_equiv_valid_2_inv_bindE)
        apply (rule_tac R'="op =" in spec_equiv_valid_2_inv_bindE)
                 apply(simp add: rel_sum_comb_equals del: Inr_in_liftE_simp without_preemption_def fun_app_def in_returns)
                 apply(rule spec_equiv_valid_2_inv_by_spec_equiv_valid[OF _ refl refl refl])
                 apply(wp whenE_spec_ev)
                           apply(rule "1.hyps")
                                    apply (assumption | erule | simp)+
                          apply(wp drop_spec_ev[OF preemption_point_reads_respects_f]
                                   drop_spec_ev[OF cap_delete_reads_respects_f[where st=st]]
                                   select_ext_ev
                                   preemption_point_inv'
                                   cap_delete_pas_refined cap_delete_silc_inv[where st=st]
                                   cap_delete_only_timer_irq_inv[where st=st' and irq=irq]
                                   drop_spec_ev[OF assertE_ev] drop_spec_ev[OF liftE_ev]
                                   get_cap_wp select_wp
                                   select_ev
                                   drop_spec_ev2_inv[OF liftE_ev2]
                                   reads_respects_f[OF get_cap_rev, where st=st and aag=aag]
        | simp (no_asm) add: returnOk_def | rule next_revoke_eq'
     | (simp add: pred_conj_def, erule conjE, assumption)
     | (rule irq_state_independent_A_conjI, simp)+)+
               apply (rule_tac P="K(all_children (\<lambda>x. is_subject aag (fst x)) rva)" and P'="K(all_children (\<lambda>x. is_subject aag (fst x)) rv'a)" in drop_spec_ev2_inv[OF return_ev2])
               apply simp
               apply (rule_tac P="\<lambda>x. is_subject aag (fst x)" in all_children_descendants_equal)
               apply (frule aag_can_read_self)
               apply (simp add: equiv_for_def split del: split_if)+
             apply (wp drop_spec_ev2_inv[OF liftE_ev2] gets_evrv | simp)+
     apply (wp drop_spec_ev2_inv[OF liftE_ev2] gets_evrv reads_respects_f[OF get_cap_rev, where st=st and aag=aag and Q="\<top>", simplified equiv_valid_def2]| simp)+
    apply clarsimp
    apply (intro conjI impI allI)
        apply (clarsimp simp: equiv_for_def reads_equiv_f_def  pas_refined_cdt pas_refined_all_children[OF _ refl] elim!: reads_equivE affects_equivE)+
    apply (auto simp: emptyable_def descendants_of_owned dest!: reply_slot_not_descendant | rule_tac y="next_revoke_cap slot s" in prod.exhaust)+
  done
qed

lemmas cap_revoke_reads_respects_f = use_spec_ev[OF cap_revoke_spec_reads_respects_f]

lemma recycle_cap_reads_respects:
  notes gts_st_tcb_at[wp del]
  shows
  "reads_respects aag l (pas_refined aag and invs and
     cte_wp_at (op = cap) slot and is_subject aag \<circ> cur_thread and
     K (is_ep_cap cap \<or> is_pg_cap cap \<longrightarrow> has_recycle_rights cap) and
     K (pas_cap_cur_auth aag cap))
     (recycle_cap is_final cap)"
  apply (rule gen_asm_ev)+
  apply (simp add: recycle_cap_def)
  apply (wp ep_cancel_badged_sends_reads_respects thread_set_reads_respects
            get_thread_state_rev ethread_set_reads_respects
    | simp add: when_def invs_valid_objs invs_sym_refs split: option.splits cap.splits
    | elim conjE
    | intro conjI impI allI
    | (drule (2) aag_cap_auth_subject, simp add: pas_refined_refl)
    | simp add: recycle_cap_ext_def requiv_cur_domain_eq
    | (rule hoare_post_subst[where B="\<lambda>_. \<top>"], fastforce simp: fun_eq_iff)
    )+
  apply (rule equiv_valid_guard_imp)
   apply (wp arch_recycle_cap_reads_respects)
  apply clarsimp
  apply assumption
  done

lemma recycle_cap_reads_respects_f:
  "reads_respects_f aag l (silc_inv aag st and pas_refined aag and invs and
     cte_wp_at (op = cap) slot and is_subject aag \<circ> cur_thread and
     K (is_ep_cap cap \<or> is_pg_cap cap \<longrightarrow> has_recycle_rights cap) and
     K (pas_cap_cur_auth aag cap))
     (recycle_cap is_final cap)"
  apply(rule equiv_valid_guard_imp)
   apply(rule reads_respects_f)
    apply(rule recycle_cap_reads_respects)
   apply(wp recycle_cap_silc_inv | simp | elim conjE, assumption)+
   apply blast
  done

lemma rec_del_subject_cur_thread:
  "\<lbrace>is_subject aag \<circ> cur_thread\<rbrace> rec_del call \<lbrace>\<lambda>_. is_subject aag \<circ> cur_thread\<rbrace>"
  apply (rule rec_del_preservation)
  apply (simp add: comp_def | wp preemption_point_inv)+
  done


lemma cap_revoke_only_timer_irq_inv:
  "\<lbrace>only_timer_irq_inv irq (st::det_ext state)\<rbrace>
   cap_revoke slot \<lbrace>\<lambda>_. only_timer_irq_inv irq st\<rbrace>"
  apply (simp add: only_timer_irq_inv_def)
  apply (rule hoare_wp_simps)
  apply (rule hoare_conjI)
   apply (wp only_timer_irq_pres cap_revoke_irq_masks | force simp: only_timer_irq_inv_def)+
   done

lemma cap_recycle_reads_respects_f:
  "reads_respects_f aag l (silc_inv aag st and only_timer_irq_inv irq st' and einvs
                       and simple_sched_action
                       and is_subject aag \<circ> cur_thread
                       and cte_wp_at has_recycle_rights slot
                       and real_cte_at slot and pas_refined aag
                       and K (is_subject aag (fst slot)))
    (cap_recycle slot)"
  unfolding cap_recycle_def finalise_slot_def
  apply (rule gen_asm_ev)
  apply (wp set_cap_reads_respects_f[where aag=aag and slot=slot and st=st]
            recycle_cap_reads_respects_f[where aag=aag and slot=slot]
            is_final_cap_reads_respects[where aag=aag and slot=slot]
            get_cap_auth_wp recycle_cap_ret_is_silc[where aag=aag, simplified]
    | simp add: unless_def when_def
    | drule sym, simp
    | rule reads_respects_f[OF get_cap_rev, where Q="\<top>", simplified, OF get_cap_silc_inv, where aag=aag])+
      apply (wp rec_del_reads_respects_f)
     apply (rule_tac Q'="\<lambda>_. pas_refined aag and einvs and silc_inv aag st and is_subject aag \<circ> cur_thread and
                          cte_wp_at (\<lambda>cap. is_pg_cap cap \<or> is_ep_cap cap \<longrightarrow> has_recycle_rights cap) slot" in hoare_post_imp_R)
      apply (wp rec_del_respects rec_del_subject_cur_thread
                rec_del_invs validE_validE_R'[OF rec_del_silc_inv]
                rec_del_preserves_cte_zombie_null_insts[where P="(\<lambda>cap. is_pg_cap cap \<or> is_ep_cap cap \<longrightarrow> has_recycle_rights cap)"]
                preemption_point_inv'
           | simp | fastforce simp: is_pg_cap_def)+
     apply (auto intro: caps_of_state_cteD dest: cte_wp_at_eqD2[OF caps_of_state_cteD])[1]
    apply (simp
         | elim conjE
         | wp cap_revoke_reads_respects_f
              cap_revoke_only_timer_irq_inv[where st=st' and irq=irq]
              cap_revoke_pas_refined cap_revoke_invs validE_validE_R'[OF cap_revoke_silc_inv]
              cap_revoke_preserves_cte_zombie_null[where Q="(\<lambda>cap. is_pg_cap cap \<or> is_ep_cap cap \<longrightarrow> has_recycle_rights cap)", THEN use_spec(2), folded validE_R_def, simplified]
         | simp only: split_def 
         | intro conjI impI
         | simp
         | strengthen real_cte_emptyable_strg | fastforce simp: is_pg_cap_def)+
  apply (rule cte_wp_at_weakenE)
   apply simp+
  done


lemma invoke_cnode_reads_respects_f:
  "reads_respects_f aag l
  (silc_inv aag st and only_timer_irq_inv irq st' and pas_refined aag and einvs
   and simple_sched_action
   and valid_cnode_inv ci and (\<lambda>s. is_subject aag (cur_thread s))
   and cnode_inv_auth_derivations ci
   and authorised_cnode_inv aag ci) (invoke_cnode ci)"
  unfolding invoke_cnode_def
  apply(rule equiv_valid_guard_imp)
  apply(wpc
       | wp reads_respects_f[OF cap_insert_reads_respects] cap_insert_silc_inv
            reads_respects_f[OF cap_move_reads_respects] cap_move_silc_inv
            cap_revoke_reads_respects_f cap_delete_reads_respects_f
            reads_respects_f[OF cap_swap_reads_respects] cap_swap_silc_inv
            cap_move_cte_wp_at_other reads_respects_f[OF get_cap_rev] get_cap_auth_wp
            cap_recycle_reads_respects_f
       | simp split del: split_if
       | elim conjE, assumption)+
  apply (clarsimp simp: cnode_inv_auth_derivations_def authorised_cnode_inv_def)
  apply (auto intro: real_cte_emptyable_strg[rule_format] simp: silc_inv_def reads_equiv_f_def requiv_cur_thread_eq cte_wp_at_weak_derived_ReplyCap caps_of_state_cteD)
  done

lemma cap_swap_reads_respects_g:
  "reads_respects_g aag l (\<lambda>s. is_subject aag (fst slot1) \<and>
                          is_subject aag (fst slot2) \<and> valid_global_objs s)
  (cap_swap cap1 slot1 cap2 slot2)"
  apply(fastforce intro: equiv_valid_guard_imp[OF reads_respects_g] cap_swap_reads_respects doesnt_touch_globalsI cap_swap_globals_equiv)
  done

lemma cap_insert_reads_respects_g:
  "reads_respects_g aag l (\<lambda>s. is_subject aag (fst src_slot) \<and>
                          is_subject aag (fst dest_slot) \<and> valid_global_objs s)
  (cap_insert new_cap src_slot dest_slot)"
  apply(fastforce intro: equiv_valid_guard_imp[OF reads_respects_g] cap_insert_reads_respects doesnt_touch_globalsI cap_insert_globals_equiv)
  done

lemma cap_move_reads_respects_g:
  "reads_respects_g aag l (\<lambda>s. is_subject aag (fst src_slot) \<and>
                          is_subject aag (fst dest_slot) \<and> valid_global_objs s)
  (cap_move new_cap src_slot dest_slot)"
  apply(fastforce intro: equiv_valid_guard_imp[OF reads_respects_g] cap_move_reads_respects doesnt_touch_globalsI cap_move_globals_equiv)
  done

lemma get_cap_reads_respects_g:
  "reads_respects_g aag l (K (is_subject aag (fst cap))) (get_cap cap)"
using equiv_valid_guard_imp[OF reads_respects_g]
  apply(rule_tac Q1="\<top>" in equiv_valid_guard_imp[OF reads_respects_g])
    apply(wp get_cap_rev doesnt_touch_globalsI | simp)+
    done

lemma invoke_cnode_reads_respects_f_g:
  "reads_respects_f_g aag l
  (silc_inv aag st and only_timer_irq_inv irq st' and pas_refined aag and einvs
   and simple_sched_action
   and valid_cnode_inv ci and (\<lambda>s. is_subject aag (cur_thread s))
   and cnode_inv_auth_derivations ci
   and authorised_cnode_inv aag ci) (invoke_cnode ci)"
  apply (rule equiv_valid_guard_imp)
   apply (rule reads_respects_f_g)
    apply (rule invoke_cnode_reads_respects_f[where st=st])
   apply (rule doesnt_touch_globalsI)
   apply (wp invoke_cnode_globals_equiv)
   apply force+
  done


lemma arch_perform_invocation_reads_respects_g:
  "reads_respects_g aag l (ct_active and K (authorised_arch_inv aag ai)
              and is_subject aag \<circ> cur_thread and pas_refined aag and invs
              and authorised_for_globals_arch_inv ai and valid_arch_inv ai)
    (arch_perform_invocation ai)"
  apply (rule equiv_valid_guard_imp)
   apply (rule reads_respects_g)
    apply (rule arch_perform_invocation_reads_respects)
   apply (rule doesnt_touch_globalsI)
   apply (wp arch_perform_invocation_globals_equiv)
   apply (simp add: invs_valid_vs_lookup invs_def valid_state_def valid_pspace_def)+
  done

definition authorised_for_globals_inv :: "invocation \<Rightarrow> ('z::state_ext) state \<Rightarrow> bool" where
  "authorised_for_globals_inv oper \<equiv> \<lambda>s. case oper of InvokeArchObject ai \<Rightarrow> authorised_for_globals_arch_inv ai s | _ \<Rightarrow> True"

definition authorised_invocation_extra where
  "authorised_invocation_extra aag invo \<equiv> case invo of InvokeTCB ti \<Rightarrow> authorised_tcb_inv_extra aag ti | _ \<Rightarrow> True"

lemma reads_respects_f_g':
  "\<lbrakk>reads_respects_g aag l P f; \<lbrace>silc_inv aag st and Q\<rbrace> f \<lbrace>\<lambda>_. silc_inv aag st\<rbrace>\<rbrakk> \<Longrightarrow>
   reads_respects_f_g aag l (silc_inv aag st and P and Q) f"
  apply(clarsimp simp: equiv_valid_def2 equiv_valid_2_def reads_equiv_f_g_def reads_equiv_g_def)
  apply(rule conjI, fastforce)
  apply(rule conjI, fastforce)
  apply(rule conjI, fastforce)
  apply(subst conj_commute, rule conjI, fastforce)
  apply(rule silc_dom_equiv_trans)
   apply(rule silc_dom_equiv_sym)
   apply(rule silc_inv_silc_dom_equiv)
   apply(erule (1) use_valid, simp)
  apply(rule silc_inv_silc_dom_equiv)
  apply(erule (1) use_valid, simp)
  done

lemma invoke_domain_reads_respects_f_g:
  "reads_respects_f_g aag l \<bottom> (invoke_domain thread domain)"
by (clarsimp simp: equiv_valid_def spec_equiv_valid_def equiv_valid_2_def)

lemma perform_invocation_reads_respects_f_g:
  "reads_respects_f_g aag l (
          silc_inv aag st
          and only_timer_irq_inv irq st'
          and pas_refined aag
          and pas_cur_domain aag
          and einvs and schact_is_rct and
          valid_invocation oper
          and authorised_invocation aag oper
          and is_subject aag \<circ> cur_thread
          and authorised_for_globals_inv oper
          and K (authorised_invocation_extra aag oper))
    (perform_invocation blocking calling oper)"
  apply (subst pi_cases)
  apply (rule equiv_valid_guard_imp)
   apply (wpc
          | simp
          | wp invoke_domain_reads_respects_f_g
               reads_respects_f_g'[OF invoke_untyped_reads_respects_g]
               invoke_untyped_silc_inv
               reads_respects_f_g'[OF send_ipc_reads_respects_g]
               send_ipc_silc_inv
               reads_respects_f_g'[OF send_async_ipc_reads_respects_g, where Q="\<top>"]
               send_async_ipc_silc_inv
               do_reply_transfer_reads_respects_f_g
               invoke_tcb_reads_respects_f_g
               invoke_cnode_reads_respects_f_g
               reads_respects_f_g'[OF invoke_irq_control_reads_respects_g]
               invoke_irq_control_silc_inv
               invoke_irq_handler_reads_respects_f_g
               reads_respects_f_g'[OF arch_perform_invocation_reads_respects_g]
               arch_perform_invocation_silc_inv
         )+
  apply (simp add: tcb_at_invs)
  apply (simp add: invs_def valid_state_def valid_pspace_def)
  apply clarsimp
  apply (intro allI impI conjI)
                     apply (simp add: authorised_invocation_def authorised_for_globals_inv_def authorised_invocation_extra_def reads_equiv_g_def requiv_cur_thread_eq is_cap_simps valid_arch_state_ko_at_arm valid_sched_def | elim exE | rule emptyable_cte_wp_atD | clarsimp | fastforce simp: reads_equiv_f_g_def)+
  done

crunch valid_ko_at_arm[wp]: reply_from_kernel "valid_ko_at_arm" (simp: crunch_simps)

lemma syscall_reads_respects_f_g:
  assumes reads_res_m_fault:
    "reads_respects_f_g aag l P m_fault"
  assumes reads_res_m_error:
    "\<And> v. reads_respects_f_g aag l (Q'' v) (m_error v)"
  assumes reads_res_h_fault:
    "\<And> v. reads_respects_f_g aag l (Q' v) (h_fault v)"
  assumes reads_res_m_finalise:
    "\<And> v. reads_respects_f_g aag l (R'' v) (m_finalise v)"
  assumes reads_res_h_error:
    "\<And> v. reads_respects_f_g aag l (R' v) (h_error v)"
  assumes m_fault_hoare:
    "\<lbrace> P \<rbrace> m_fault \<lbrace> sum_case Q' Q'' \<rbrace>"
  assumes m_error_hoare:
    "\<And> v. \<lbrace> Q'' v \<rbrace> m_error v \<lbrace> sum_case R' R'' \<rbrace>"
  shows "reads_respects_f_g aag l P (Syscall_A.syscall m_fault h_fault m_error h_error m_finalise)"
  unfolding Syscall_A.syscall_def without_preemption_def fun_app_def
  apply (wp assms equiv_valid_guard_imp[OF liftE_bindE_ev]
       | rule hoare_strengthen_post[OF m_error_hoare]
       | rule hoare_strengthen_post[OF m_fault_hoare]
       | wpc
       | fastforce)+
  done

(*FIXME: move *)
lemma syscall_requiv_f_g: "
  \<lbrakk>reads_respects_f_g aag l P m_fault;
 \<And>v. reads_respects_f_g aag l (R' v) (h_error v);
 \<And>v. reads_respects_f_g aag l (R'' v)
      (m_finalise v);

 \<And>v. reads_respects_f_g aag l (Q'' v) (m_error v);
 \<And>v. reads_respects_f_g aag l (Q' v) (h_fault v);

  \<And>v. \<lbrace>Q''' v\<rbrace> m_error v \<lbrace>R''\<rbrace>,\<lbrace>R'\<rbrace>;
 \<lbrace>P\<rbrace> m_fault \<lbrace>\<lambda>rv. Q'' rv and Q''' rv\<rbrace>,\<lbrace>Q'\<rbrace> \<rbrakk>
\<Longrightarrow> reads_respects_f_g aag l P
    (syscall m_fault h_fault m_error h_error m_finalise)"
  apply (rule syscall_reads_respects_f_g[where Q''="\<lambda>rv. Q'' rv and Q''' rv"])
  apply (unfold validE_def)
  apply (assumption)+
  apply (rule equiv_valid_guard_imp, assumption, simp)
  apply assumption+
  apply (rule hoare_strengthen_post)
  apply assumption
  apply (case_tac r)
  apply simp
  apply simp
  apply (rule hoare_strengthen_post, rule hoare_pre)
    apply assumption
   apply simp
  apply (case_tac r)
  apply simp+
done


(*FIXME: Move to base*)
lemma requiv_g_cur_thread_eq: "reads_equiv_g aag s t \<Longrightarrow> (cur_thread s) = (cur_thread t)"
  apply (frule reads_equiv_gD)
  apply (clarsimp simp add: requiv_cur_thread_eq)
done

(*Weird hack. Not sure why this is necessary. Something is getting
instantiated too early*)
lemma lookup_cap_and_slot_reads_respects_g':
  "
  reads_equiv_valid_g_inv (affects_equiv aag l) aag (pas_refined aag and K (is_subject aag param_a2) and P)
     (lookup_cap_and_slot param_a2 param_b3)"
  apply (rule equiv_valid_guard_imp)
  apply (rule lookup_cap_and_slot_reads_respects_g)
  apply simp
done


lemma sts_authorised_for_globals_inv: "\<lbrace>authorised_for_globals_inv oper\<rbrace> set_thread_state d f \<lbrace>\<lambda>r. authorised_for_globals_inv oper\<rbrace>"
  unfolding authorised_for_globals_inv_def
            authorised_for_globals_arch_inv_def
            authorised_for_globals_page_table_inv_def
            authorised_for_globals_page_inv_def
  apply (case_tac oper)
          apply (wp | simp)+
  apply (case_tac arch_invocation)
      apply simp
      apply (case_tac page_table_invocation)
       apply simp+
       apply (wp set_thread_state_arm_global_pd)
     apply simp
     apply wp
    apply simp
    apply (case_tac page_invocation)
       apply (simp | wp hoare_ex_wp)+
done



lemma authorised_for_globals_triv:
  "\<forall> x y. f x \<noteq> InvokeArchObject y \<Longrightarrow>
  \<lbrace> \<top> \<rbrace> m \<lbrace> authorised_for_globals_inv \<circ> f \<rbrace>,-"
  apply(clarsimp simp: validE_R_def validE_def valid_def authorised_for_globals_inv_def split: invocation.splits sum.splits)
  done

lemma decode_invocation_authorised_globals_inv:
  "\<lbrace>cte_wp_at (diminished cap) slot and invs and
    (\<lambda>s. \<forall>x\<in>set excaps.
           cte_wp_at (diminished (fst x)) (snd x) s)\<rbrace>
    decode_invocation info_label args ptr slot cap excaps
   \<lbrace>\<lambda>rv. authorised_for_globals_inv rv\<rbrace>, -"
  unfolding decode_invocation_def
  apply (rule hoare_pre)
  apply wpc
             apply((wp authorised_for_globals_triv | wpc | simp add: uncurry_def)+)[11]
   apply (simp add: authorised_for_globals_inv_def)
   apply wp
   apply (unfold comp_def)
   apply simp
   apply (wp decode_arch_invocation_authorised_for_globals)
  apply (intro impI conjI allI | clarsimp simp add: authorised_for_globals_inv_def)+
  apply (erule_tac x="(a, aa, b)" in ballE)
  apply simp+
done

lemma set_thread_state_reads_respects_g:
  "reads_respects_g aag l (is_subject aag \<circ> cur_thread and valid_ko_at_arm)
    (set_thread_state ref ts)"
  apply (rule equiv_valid_guard_imp)
   apply (rule reads_respects_g)
    apply (rule set_thread_state_reads_respects)
   apply (rule doesnt_touch_globalsI)
   apply (rule set_thread_state_globals_equiv)
  apply simp
done

lemmas get_thread_state_reads_respects_g = reads_respects_g_from_inv[OF get_thread_state_rev get_thread_state_inv]

lemma decode_invocation_authorised_extra:
  "\<lbrace>K (is_subject aag (fst slot))\<rbrace>
   decode_invocation info_label args ptr slot cap excaps
   \<lbrace>\<lambda> rv s. authorised_invocation_extra aag rv\<rbrace>,-"
  unfolding decode_invocation_def authorised_invocation_extra_def
  apply(rule hoare_pre)
   apply(wp decode_tcb_invocation_authorised_extra | wpc | simp add: split_def o_def uncurry_def)+
  apply(auto intro!: TrueI)
  done

lemma sts_schact_is_rct_runnable: "\<lbrace>schact_is_rct and K(runnable b)\<rbrace> set_thread_state a b \<lbrace>\<lambda>_. schact_is_rct\<rbrace>"
  apply (simp add: set_thread_state_def
                   set_scheduler_action_def set_object_def)
  apply (simp add: set_thread_state_ext_def)
  apply (wp modify_wp set_scheduler_action_wp gts_wp)
  apply (clarsimp simp: schact_is_rct_def st_tcb_at_def obj_at_def)
  done

lemma set_thread_state_only_timer_irq_inv:
  "\<lbrace>only_timer_irq_inv irq (st::det_ext state)\<rbrace>
   set_thread_state ref ts \<lbrace>\<lambda>_. only_timer_irq_inv irq st\<rbrace>"
  apply (simp add: only_timer_irq_inv_def)
  apply (wp only_timer_irq_pres | force)+
  done




lemma ct_active_not_idle': "valid_idle s \<Longrightarrow> ct_active s \<Longrightarrow> cur_thread s \<noteq> idle_thread s"
  apply (clarsimp simp: invs_def valid_idle_def ct_in_state_def
                        st_tcb_at_def obj_at_def)
  done

lemma ct_active_not_idle: "invs s \<Longrightarrow> ct_active s \<Longrightarrow> cur_thread s \<noteq> idle_thread s"
  apply (rule ct_active_not_idle')
  apply (simp add: invs_valid_idle)+
  done

lemma handle_invocation_reads_respects_g:
  notes gts_st_tcb[wp del] gts_st_tcb_at[wp del]
  notes get_message_info_reads_respects_g = reads_respects_g_from_inv[OF get_message_info_rev get_mi_inv]
  shows "reads_respects_f_g aag l
           (silc_inv aag st and only_timer_irq_inv irq st' and einvs and schact_is_rct and ct_active and pas_refined aag and pas_cur_domain aag and is_subject aag \<circ> cur_thread and K (\<not> pasMaySendIrqs aag))
           (handle_invocation calling blocking)"
  apply (rule gen_asm_ev)
  apply (simp add: handle_invocation_def fun_app_def split_def)
  apply (wpc | simp add: when_def tcb_at_st_tcb_at[symmetric]
            | intro impI conjI | erule conjE
            | rule doesnt_touch_globalsI |

            wp syscall_requiv_f_g gts_inv
            reads_respects_f_g'[OF lookup_extra_caps_reads_respects_g, where Q="\<top>" and st=st]
            reads_respects_f_g'[OF lookup_ipc_buffer_reads_respects_g, where Q="\<top>" and st=st]
            reads_respects_f_g'[OF cap_fault_on_failure_rev_g, where Q="\<top>" and st=st]
            valid_validE_R[OF wp_post_taut]
            lookup_ipc_buffer_has_read_auth'

            lookup_cap_and_slot_reads_respects_g' (*Weird*)
            decode_invocation_reads_respects_f_g
            get_mrs_reads_respects_g
            handle_fault_reads_respects_g
            reads_respects_f_g'[OF set_thread_state_reads_respects_g, where st=st and Q="\<top>"]
            reads_respects_f_g'[OF get_thread_state_reads_respects_g, where st=st and Q="\<top>"]
            reads_respects_f_g'[OF reads_respects_g[OF reply_from_kernel_reads_respects], where st=st and Q="\<top>"]
            get_thread_state_reads_respects_g
            perform_invocation_reads_respects_f_g
            set_thread_state_pas_refined
            sts_first_restart
            set_thread_state_ct_st
            lookup_extra_caps_authorised
            lookup_extra_caps_auth lookup_ipc_buffer_disjoint_from_globals_frame

            handle_fault_globals_equiv
            set_thread_state_globals_equiv
            reply_from_kernel_globals_equiv | (rule hoare_drop_imps)
        )+
               apply (rule_tac Q'="\<lambda>r s. silc_inv aag st s \<and> invs s \<and> is_subject aag rv \<and> is_subject aag (cur_thread s) \<and> rv \<noteq> idle_thread s" in hoare_post_imp_R)
                apply (wp pinv_invs perform_invocation_silc_inv)
               apply (simp add: invs_def valid_state_def valid_pspace_def valid_arch_state_ko_at_arm)
              apply(wp reads_respects_f_g'[OF set_thread_state_reads_respects_g, where Q="\<top>" and st=st] | simp)+

             apply (simp |
                    wp set_thread_state_only_timer_irq_inv[where st=st']
                       set_thread_state_reads_respects_g
                       set_thread_state_globals_equiv
                       sts_Restart_invs
                       set_thread_state_pas_refined
                       set_thread_state_ct_st
                      set_thread_state_runnable_valid_sched
                       sts_authorised_for_globals_inv
                       sts_schact_is_rct_runnable
                       decode_invocation_reads_respects_f_g
                       reads_respects_f_g'[OF get_mrs_reads_respects_g, where Q="\<top>" and st=st]
                       reads_respects_f_g'[OF handle_fault_reads_respects_g]
                       decode_invocation_authorised
                       decode_invocation_authorised_globals_inv
                       decode_invocation_authorised_extra
                       lec_valid_fault
                       lookup_extra_caps_authorised
                       lookup_extra_caps_auth
                       lookup_ipc_buffer_has_read_auth'
                       lookup_ipc_buffer_disjoint_from_globals_frame |
                    (rule hoare_vcg_conj_liftE_R, rule hoare_drop_impE_R)
                   )+
         apply (rule hoare_pre) (*Weird schematic in precondition necessary*)
          apply (simp add: o_def|
                 wp lookup_cap_and_slot_valid_fault3
                    lookup_cap_and_slot_authorised
                    lookup_cap_and_slot_cur_auth
                    reads_respects_f_g'[OF reads_respects_g[OF as_user_reads_respects], where Q="\<top>" and st=st] as_user_silc_inv
                    as_user_globals_equiv
                    user_getreg_inv
                    reads_respects_f_g'[OF get_message_info_reads_respects_g, where Q="\<top>" and st=st]
                    get_mi_inv
                    get_mi_length
                    get_mi_length' |
                rule doesnt_touch_globalsI | (clarify,assumption)
          )+
  apply (rule conjI)
   apply (clarsimp simp: requiv_g_cur_thread_eq simp: reads_equiv_f_g_conj)
  apply (clarsimp simp: get_register_def invs_sym_refs invs_def valid_state_def valid_arch_state_ko_at_arm valid_pspace_vo valid_pspace_distinct)
  apply (rule context_conjI)
  apply (simp add: ct_active_not_idle')
  apply (clarsimp simp: valid_pspace_def ct_in_state_def)
  apply (rule conjI)
   apply(fastforce intro: reads_lrefl)
  apply(rule conjI, fastforce)+
  apply (simp add: conj_ac)
  apply (rule conjI)
   apply (clarsimp elim!: schact_is_rct_simple)
  apply (rule conjI)
   apply (rule st_tcb_ex_cap)
     apply simp+
   apply (case_tac "sta",clarsimp+)
  apply (force intro: reads_lrefl simp: only_timer_irq_inv_def runnable_eq_active)
  done

lemma delete_caller_cap_reads_respects_f:
  "reads_respects_f aag l (silc_inv aag st and invs and pas_refined aag and
         K (is_subject aag (fst (x, tcb_cnode_index 3)))) (delete_caller_cap x)"
  unfolding delete_caller_cap_def
  apply (rule cap_delete_one_reads_respects_f)
  done

lemma delete_caller_cap_globals_equiv:
  "\<lbrace>globals_equiv st and valid_ko_at_arm\<rbrace> delete_caller_cap x \<lbrace>\<lambda>r. globals_equiv st\<rbrace>"
  unfolding delete_caller_cap_def
  apply (wp cap_delete_one_globals_equiv)
  done



lemma lookup_cap_cap_fault:
  "\<lbrace>invs\<rbrace> lookup_cap c b -, \<lbrace>\<lambda>f s. valid_fault (CapFault x y f)\<rbrace>"
  apply (simp add: lookup_cap_def)
  apply wp
   apply (case_tac xa)
   apply (simp add: validE_E_def)
   apply (wp)
  apply (fold validE_E_def)
  apply (wp lookup_slot_for_thread_cap_fault)
  done

crunch pas_cur_domain[wp]: delete_caller_cap "pas_cur_domain aag"


lemma handle_wait_reads_respects_f:
  "reads_respects_f aag l (silc_inv aag st and einvs and
        pas_refined aag and pas_cur_domain aag and is_subject aag \<circ> cur_thread) handle_wait"
  apply (simp add: handle_wait_def Let_def lookup_cap_def split_def)
  apply (wp reads_respects_f[OF cap_fault_on_failure_rev, where st=st]
            receive_ipc_reads_respects
            receive_async_ipc_reads_respects
            lookup_slot_for_thread_rev
            lookup_slot_for_thread_authorised
            get_cap_auth_wp get_cap_rev
    | wpc | simp)+
           apply (rule_tac Q'="\<lambda>r s. einvs s \<and> pas_refined aag s \<and> pas_cur_domain aag s \<and> is_subject aag rv \<and> silc_inv aag st s \<and> is_subject aag (cur_thread s)" in hoare_post_imp_R)
            apply wp
           apply (clarsimp simp add: invs_valid_objs invs_sym_refs
                  | intro impI allI conjI
                  | rule cte_wp_valid_cap caps_of_state_cteD
                  | fastforce simp: aag_cap_auth_def cap_auth_conferred_def
                                   cap_rights_to_auth_def valid_fault_def
                 )+
          apply (wp handle_fault_reads_respects get_cap_auth_wp[where aag=aag] receive_ipc_silc_inv
                | wpc)+
           apply (rule_tac Q="\<lambda>r s. silc_inv aag st s \<and> einvs s \<and> pas_refined aag s \<and> is_subject aag rv \<and> is_subject aag (fst (fst r))" and
     E = "\<lambda>r s. silc_inv aag st s" in hoare_post_impErr)
             apply (rule hoare_pre)
              apply (wp lookup_slot_for_thread_authorised | simp)+
            apply(fastforce simp: aag_cap_auth_def cap_auth_conferred_def cap_rights_to_auth_def)
           apply assumption
          apply(wp reads_respects_f[OF handle_fault_reads_respects] get_cap_wp | simp | wpc)+
         apply (rule_tac Q="\<lambda>r s. silc_inv aag st s \<and> invs s \<and> pas_refined aag s \<and> pas_cur_domain aag s \<and> is_subject aag rv \<and> is_subject aag (cur_thread s)" and
     E = "\<lambda>r s. valid_fault (CapFault (of_bl rvb) True r) \<and> silc_inv aag st s \<and> invs s \<and> pas_refined aag s \<and> pas_cur_domain aag s \<and> is_subject aag rv \<and> is_subject aag (cur_thread s)" in hoare_post_impErr)
           apply (rule hoare_pre)
            apply (rule hoare_vcg_E_conj)
             apply (wp lookup_slot_for_thread_cap_fault)
           apply (simp add: invs_valid_objs invs_sym_refs valid_fault_def invs_distinct invs_valid_global_refs invs_arch_state invs_mdb
                  | intro impI conjI allI)+

        apply (wp liftM_ev reads_respects_f[OF as_user_reads_respects, where Q="\<top>" and st=st]
                  delete_caller_cap_reads_respects_f delete_caller_cap_silc_inv
               | simp)+
  apply (auto simp: get_register_det intro: reads_lrefl simp: reads_equiv_f_def)
  done

lemma handle_wait_globals_equiv:
  "\<lbrace>globals_equiv (st :: det_state) and invs and ct_active\<rbrace> handle_wait \<lbrace>\<lambda>r. globals_equiv st\<rbrace>"
  unfolding handle_wait_def
  apply (wp handle_fault_globals_equiv | wpc | simp add: Let_def)+
      apply (rule_tac Q="\<lambda>r s. invs s \<and> globals_equiv st s" and
                      E = "\<lambda>r s. valid_fault (CapFault (of_bl ep_cptr) True r)" in hoare_post_impErr)
        apply (rule hoare_vcg_E_elim)
         apply (wp lookup_cap_cap_fault receive_ipc_globals_equiv
                   receive_async_ipc_globals_equiv
                | wpc | simp add: Let_def invs_imps invs_valid_idle valid_fault_def)+
     apply (rule_tac Q'="\<lambda>r s. invs s \<and> globals_equiv st s \<and> thread \<noteq> idle_thread s" in hoare_post_imp_R)
      apply (wp as_user_globals_equiv | simp add: invs_imps valid_fault_def)+
   apply (rule_tac Q="\<lambda>r s. invs s \<and> globals_equiv st s \<and> thread \<noteq> idle_thread s" in hoare_strengthen_post)
    apply (wp delete_caller_cap_invs delete_caller_cap_globals_equiv | simp add: invs_imps invs_valid_idle ct_active_not_idle)+
  done

lemma handle_wait_reads_respects_f_g:
  "reads_respects_f_g aag l (silc_inv aag st and einvs and ct_active and
        pas_refined aag and pas_cur_domain aag and is_subject aag \<circ> cur_thread) handle_wait"
  apply (rule equiv_valid_guard_imp)
  apply (rule reads_respects_f_g)
  apply (wp handle_wait_reads_respects_f[where st=st])
  apply (rule doesnt_touch_globalsI)
  apply (wp handle_wait_globals_equiv)
  apply simp+
  done


lemma dmo_return_reads_respects:
  "reads_respects aag l \<top> (do_machine_op (return ()))"
  apply (rule use_spec_ev)
  apply (rule do_machine_op_spec_reads_respects)
  apply wp
  done

lemma dmo_return_globals_equiv:
  "\<lbrace>globals_equiv st\<rbrace> do_machine_op (return ()) \<lbrace>\<lambda>r .globals_equiv st\<rbrace>"
  apply (rule dmo_no_mem_globals_equiv)
  apply wp
  done

lemma get_irq_slot_reads_respects':
  "reads_respects aag l (K(aag_can_read_label aag (pasIRQAbs aag irq))) (get_irq_slot irq)"
  unfolding get_irq_slot_def
  apply(rule equiv_valid_guard_imp)
   apply(rule gets_ev)
  apply(simp add: reads_equiv_def states_equiv_for_def equiv_for_def
       affects_equiv_def)
  done


lemma get_irq_slot_can_read_from_slot:
  "\<lbrace>K(aag_can_read_label aag (pasIRQAbs aag irq)) and pas_refined aag\<rbrace> get_irq_slot irq \<lbrace>\<lambda>r. K(aag_can_read_label aag (pasObjectAbs aag (fst r)))\<rbrace>"
  unfolding get_irq_slot_def
  apply (wp gets_wp)
  apply (simp add: pas_refined_def policy_wellformed_def irq_map_wellformed_aux_def)
  done

lemma get_irq_state_rev':
  "reads_equiv_valid_inv A aag (K (aag_can_read_label aag (pasIRQAbs aag irq))) (get_irq_state irq)"
  unfolding get_irq_state_def
  apply(rule equiv_valid_guard_imp[OF gets_ev])
  apply(fastforce simp: reads_equiv_def2 elim: states_equiv_forE_interrupt_states intro: aag_can_read_irq_self)
  done

lemma equiv_valid_vacuous:
  "equiv_valid_inv I A \<bottom> f"
  apply(clarsimp simp: equiv_valid_def2 equiv_valid_2_def)
  done

declare gts_st_tcb_at[wp del]

lemma handle_interrupt_globals_equiv:
  "\<lbrace>globals_equiv st and invs\<rbrace> handle_interrupt irq \<lbrace>\<lambda>r. globals_equiv st\<rbrace>"
  unfolding handle_interrupt_def
  apply (wp dmo_maskInterrupt_globals_equiv
            dmo_return_globals_equiv
            send_async_ipc_globals_equiv
            hoare_vcg_if_lift2
            hoare_drop_imps
            dxo_wp_weak
    | wpc | simp add: ackInterrupt_def resetTimer_def invs_imps invs_valid_idle)+
  done



axiomatization dmo_reads_respects where
  dmo_getDFSR_reads_respects: "reads_respects aag l \<top> (do_machine_op getDFSR)" and
  dmo_getFAR_reads_respects: "reads_respects aag l \<top> (do_machine_op getFAR)" and
  dmo_getIFSR_reads_respects: "reads_respects aag l \<top> (do_machine_op getIFSR)"


lemma handle_vm_fault_reads_respects:
  "reads_respects aag l (K(is_subject aag thread)) (handle_vm_fault thread vmfault_type)"
  apply (cases vmfault_type)
  apply (wp dmo_getDFSR_reads_respects dmo_getFAR_reads_respects
            dmo_getIFSR_reads_respects as_user_reads_respects
         | simp add: getRestartPC_def getRegister_def reads_lrefl)+
  done

lemma handle_vm_fault_globals_equiv:
  "\<lbrace>globals_equiv st and valid_ko_at_arm and (\<lambda>s. thread \<noteq> idle_thread s)\<rbrace> handle_vm_fault thread vmfault_type \<lbrace>\<lambda>r. globals_equiv st\<rbrace>"
  apply (cases vmfault_type)
   apply (wp dmo_no_mem_globals_equiv | simp add: getDFSR_def getFAR_def getIFSR_def)+
  done

lemma handle_vm_fault_reads_respects_g:
  "reads_respects_g aag l (K(is_subject aag thread) and (valid_ko_at_arm and (\<lambda>s. thread \<noteq> idle_thread s))) (handle_vm_fault thread vmfault_type)"
  apply (rule reads_respects_g)
   apply (rule handle_vm_fault_reads_respects)
  apply (rule doesnt_touch_globalsI)
  apply (wp handle_vm_fault_globals_equiv)
  apply simp
  done

lemma irq_state_indepedent_top[simp, intro!]:
  "irq_state_independent (\<lambda>s. True)"
  apply(simp add: irq_state_independent_def)
  done

crunch cur_thread[wp]: handle_yield "\<lambda>s. P (cur_thread s)"
  (wp: dxo_wp_weak ignore: tcb_sched_action reschedule_required)
crunch cur_domain[wp]: handle_yield "\<lambda>s. P (cur_domain s)"

lemma handle_yield_reads_respects:
  "reads_respects aag l (pas_refined aag) handle_yield"
  apply (simp add: handle_yield_def | wp tcb_sched_action_reads_respects)+
  apply (simp add: reads_equiv_def)
  done

crunch silc_inv[wp]: handle_yield "silc_inv aag st"

crunch globals_equiv[wp]: handle_yield "globals_equiv st" (wp: dxo_wp_weak ignore: reschedule_required)

crunch pas_cur_domain[wp]: handle_reply, handle_vm_fault "pas_cur_domain aag"
  (wp: crunch_wps ignore: getFAR getDFSR getIFSR)

lemma equiv_valid_hoist_guard:
  assumes a: "Q \<Longrightarrow> equiv_valid_inv I A P f"
  assumes b: "\<And> s. P s \<Longrightarrow> Q"
  shows "equiv_valid_inv I A P f"
  using assms apply(fastforce simp: equiv_valid_def2 equiv_valid_2_def)
  done

(* we explicitly exclude the case where ev is Interrupt since this is a scheduler action *)
lemma handle_event_reads_respects_f_g:
  "reads_respects_f_g aag l (silc_inv aag st and only_timer_irq_inv irq st' and einvs and schact_is_rct and domain_sep_inv (pasMaySendIrqs aag) st' and (\<lambda>s. ev \<noteq> Interrupt \<and> (ct_active s)) and pas_refined aag and pas_cur_domain aag and is_subject aag \<circ> cur_thread and K (\<not> pasMaySendIrqs aag)) (handle_event ev)"
  apply(rule gen_asm_ev)
  apply(rule_tac Q="ev \<noteq> Interrupt" in equiv_valid_hoist_guard)
   prefer 2
   apply fastforce
  apply (case_tac ev, simp_all)
    apply (case_tac syscall, simp_all add: handle_send_def handle_call_def)
          apply ((wp handle_invocation_reads_respects_g[simplified]
                  handle_wait_reads_respects_f_g[where st=st]
                  handle_reply_valid_sched
                  reads_respects_f_g[OF reads_respects_f[where st=st and aag=aag and Q=\<top>, OF handle_yield_reads_respects] doesnt_touch_globalsI]
                  handle_reply_reads_respects_g handle_reply_silc_inv[where st=st]
                | simp add: invs_imps | rule equiv_valid_guard_imp | force)+)[7]
     apply (wp reads_respects_f_g'[OF handle_fault_reads_respects_g, where st=st]
               | simp add: reads_equiv_f_g_conj
            | clarsimp simp: invs_imps requiv_g_cur_thread_eq schact_is_rct_simple
            | wpc | intro impI conjI allI)+
       apply (rule equiv_valid_guard_imp)
        apply ((wp reads_respects_f_g'[OF handle_vm_fault_reads_respects_g, where Q="\<top>" and st=st] handle_vm_fault_silc_inv | simp)+)[1]
        prefer 2
        apply ((wp reads_respects_f_g'[OF handle_fault_reads_respects_g, where st=st] | simp)+)[1]
       prefer 2
       apply (simp add: validE_E_def)
       apply (rule_tac E="\<lambda>r s.  invs s \<and> is_subject aag rv \<and> is_subject aag (cur_thread s) \<and> valid_fault r \<and> pas_refined aag s \<and> pas_cur_domain aag s \<and> silc_inv aag st s \<and> rv \<noteq> idle_thread s" and Q="\<top>\<top>" in hoare_post_impErr)
         apply (rule hoare_vcg_E_conj)
          apply (wp hv_invs handle_vm_fault_silc_inv)
       apply (simp add: invs_imps invs_mdb invs_valid_idle)+
       apply wp
  apply (clarsimp simp: requiv_g_cur_thread_eq reads_equiv_f_g_conj ct_active_not_idle)
  done

lemma as_user_reads_respects_g:
  "reads_respects_g aag k (valid_ko_at_arm and (\<lambda>s. thread \<noteq> idle_thread s) and K (det f \<and> is_subject aag thread)) (as_user thread f)"
  apply (rule equiv_valid_guard_imp)
   apply (rule reads_respects_g)
    apply (rule as_user_reads_respects)
   apply (rule doesnt_touch_globalsI)
   apply (wp as_user_globals_equiv)
   apply simp+
  done

lemma setNextPC_det :
  "det (setNextPC rva)"
  apply (auto simp: det_def setNextPC_def setRegister_def modify_def get_def put_def bind_def)
  done


lemma get_thread_state_reads_respects':
  "reads_respects aag l (K(aag_can_read_label aag (pasObjectAbs aag thread))) (get_thread_state thread)"
  unfolding get_thread_state_def thread_get_def
  apply (wp | simp)+
  apply clarify
  apply (rule requiv_get_tcb_eq')
  apply simp+
  done

lemma activate_thread_reads_respects:
  "reads_respects aag l (cur_tcb and (\<lambda>s. aag_can_read_label aag (pasObjectAbs aag (cur_thread s)))) activate_thread"
  apply (simp add: activate_thread_def)
  apply (wp set_thread_state_runnable_reads_respects
            get_thread_state_reads_respects'
         | wpc
         | simp add: arch_activate_idle_thread_def
  )+
               apply (unfold as_user_def)
               apply (wp set_object_reads_respects
                         get_thread_state_reads_respects'
                      | simp add: setNextPC_def setRegister_def
                                  select_f_returns getRestartPC_def
                                  getRegister_def arch_activate_idle_thread_def
                                  tcb_at_st_tcb_at[symmetric] cur_tcb_def
                      | clarify
                      | rule hoare_drop_imps conjI
                             requiv_cur_thread_eq requiv_get_tcb_eq'
                      | clarsimp simp: st_tcb_at_def obj_at_def is_tcb_def
                      | simp split: Structures_A.kernel_object.split_asm)+
  done

lemma activate_thread_globals_equiv:
  "\<lbrace>globals_equiv st and valid_ko_at_arm and valid_idle\<rbrace> activate_thread \<lbrace>\<lambda> r. globals_equiv st\<rbrace>"
  unfolding activate_thread_def
  apply (wp set_thread_state_globals_equiv gts_wp | wpc | 
     clarsimp simp add: arch_activate_idle_thread_def valid_idle_def st_tcb_at_def obj_at_def | rule hoare_vcg_conj_lift)+
  done

lemma activate_thread_reads_respects_g:
  "reads_respects_g aag l (invs and (\<lambda>s. aag_can_read_label aag (pasObjectAbs aag (cur_thread s)))) activate_thread"
  apply (rule equiv_valid_guard_imp)
   apply (rule reads_respects_g)
    apply (rule activate_thread_reads_respects)
   apply (rule doesnt_touch_globalsI)
   apply (rule hoare_pre)
   apply (rule activate_thread_globals_equiv)
   apply (simp add: invs_imps invs_valid_idle)+
  done

(*Globals equiv for top level events*)
lemma set_thread_state_ct_st':
  "\<lbrace>\<lambda>s. thread = cur_thread s \<and> P st\<rbrace> set_thread_state thread st \<lbrace>\<lambda>rv. ct_in_state P\<rbrace>"
  apply (rule hoare_pre)
   apply (rule set_thread_state_ct_st)
  apply simp
  done

crunch globals_equiv[wp]: invoke_domain "globals_equiv st"
  (wp: dxo_wp_weak ignore: reschedule_required set_domain)

lemma perform_invocation_globals_equiv:
  "\<lbrace>invs and ct_active and valid_invocation oper and globals_equiv st and authorised_for_globals_inv oper and K (case oper of (InvokeUntyped i) \<Rightarrow> (0::word32) < of_nat (length (slots_of_untyped_inv i)) | _ \<Rightarrow> True)\<rbrace>
    perform_invocation blocking calling oper
   \<lbrace>\<lambda>_. globals_equiv st\<rbrace>"
  apply (subst pi_cases)
  apply (rule hoare_pre)
   apply (wp invoke_untyped_globals_equiv
             send_ipc_globals_equiv
             send_async_ipc_globals_equiv
             do_reply_transfer_globals_equiv
             invoke_tcb_globals_equiv
             invoke_cnode_globals_equiv
             invoke_irq_control_globals_equiv
             invoke_irq_handler_globals_equiv
             arch_perform_invocation_globals_equiv
         | wpc | simp)+
  apply (auto simp add: invs_imps invs_arch_objs
                        invs_psp_aligned invs_kernel_mappings
                        authorised_for_globals_inv_def)
  done

lemma dui_length_slots:
  "\<lbrace>\<top>\<rbrace>
  decode_untyped_invocation label args slot cap excaps
  \<lbrace>\<lambda>rv s. (0::word32) < of_nat (length (slots_of_untyped_inv rv))\<rbrace>,-"
  unfolding decode_untyped_invocation_def
  apply(rule hoare_pre)
  apply (simp add: unlessE_def[symmetric] whenE_def[symmetric] unlessE_whenE
           split del: split_if)
    apply(wp whenE_throwError_wp
         |wpc
         |simp add: nonzero_unat_simp split del: split_if add: split_def)+
  apply(intro impI, rule TrueI)
  done

lemma di_untyped_length_slots:
  "\<lbrace>\<top>\<rbrace>
   decode_invocation label args cap_index slot cap excaps
   \<lbrace>\<lambda> rv s. (case rv of (InvokeUntyped ui) \<Rightarrow> (0::word32) < of_nat (length (slots_of_untyped_inv ui)) | _ \<Rightarrow> True)\<rbrace>,-"
  unfolding decode_invocation_def
  apply(rule hoare_pre)
  apply(wp dui_length_slots | wpc | simp add: comp_def split_def uncurry_def)+
  apply auto
  done

lemma handle_invocation_globals_equiv:
  "\<lbrace>invs and ct_active and globals_equiv st\<rbrace> handle_invocation calling blocking \<lbrace>\<lambda>_. globals_equiv (st::det_ext state)\<rbrace>"
  apply (simp add: handle_invocation_def ts_Restart_case_helper split_def
                   liftE_liftM_liftME liftME_def bindE_assoc)
  apply (wp syscall_valid handle_fault_globals_equiv
            reply_from_kernel_globals_equiv set_thread_state_globals_equiv
            hoare_vcg_all_lift
       | simp split del: split_if
       | wp_once hoare_drop_imps)+
        apply (rule_tac Q="\<lambda>r. invs and globals_equiv st and (\<lambda>s. thread \<noteq> idle_thread s)" and E="\<lambda>_. globals_equiv st"
                         in hoare_post_impErr)
          apply (wp pinv_invs perform_invocation_globals_equiv
                    set_thread_state_ct_st' set_thread_state_globals_equiv
                    sts_authorised_for_globals_inv
                    decode_invocation_authorised_globals_inv
                    di_untyped_length_slots
                | simp add: crunch_simps invs_imps)+
  apply (auto intro: st_tcb_ex_cap simp: ct_active_not_idle ct_in_state_def)
  done

lemma handle_fault_globals_equiv':
  "\<lbrace>invs and globals_equiv st and K(valid_fault ex)\<rbrace>
  handle_fault thread ex \<lbrace>\<lambda>_. globals_equiv st\<rbrace>"
  apply (rule hoare_pre)
   apply (rule handle_fault_globals_equiv)
  apply (simp add: invs_imps invs_valid_idle)
  done

lemma handle_event_globals_equiv:
  "\<lbrace>invs and (\<lambda>s. ev \<noteq> Interrupt \<longrightarrow> ct_active s) and globals_equiv st\<rbrace> handle_event ev \<lbrace>\<lambda>_. globals_equiv (st::det_ext state)\<rbrace>"
  apply (case_tac ev)
      apply (rule hoare_pre)
       apply (wp handle_invocation_globals_equiv
                 hoare_weaken_pre[OF receive_ipc_globals_equiv,
                       where P="globals_equiv st and invs" and st1=st]
                 hoare_weaken_pre[OF receive_async_ipc_globals_equiv,
                       where P="globals_equiv st and invs" and s1=st]
                 handle_fault_globals_equiv'
                 handle_wait_globals_equiv
                 handle_reply_globals_equiv
                 handle_interrupt_globals_equiv
                 handle_vm_fault_globals_equiv
              | wpc | simp add: handle_send_def handle_call_def Let_def
              | wp_once hoare_drop_imps | clarsimp simp: invs_imps invs_valid_idle ct_active_not_idle)+
  done

end
