(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(NICTA_BSD)
 *)

theory HeapLift
imports
  TypHeapSimple
  CorresXF
  L2Defs
  ExecConcrete
  AbstractArrays
  "../../lib/LemmaBucket_C"
begin

definition "L2Tcorres st A C = corresXF st (\<lambda>r _. r) (\<lambda>r _. r) \<top> A C"

lemma L2Tcorres_id:
  "L2Tcorres id C C"
  by (metis L2Tcorres_def corresXF_id)

lemma L2Tcorres_fail:
  "L2Tcorres st L2_fail X"
  apply (clarsimp simp: L2Tcorres_def L2_defs)
  apply (rule corresXF_fail)
  done

definition "abs_expr st P A C \<equiv> \<forall>s. P (st s) \<longrightarrow> (C s) = A (st s) "
definition "abs_modifies st P A C \<equiv> \<forall>s. P (st s) \<longrightarrow> st (C s) = A (st s) "

lemma abs_expr_fun_app [heap_abs_fo]:
  "\<lbrakk> abs_expr st Y b' b; abs_expr st X a' a \<rbrakk> \<Longrightarrow>
      abs_expr st (X and Y) (\<lambda>s. a' s (b' s)) (\<lambda>s. ((a s) $ (b s)))"
  apply (clarsimp simp: abs_expr_def)
  done

lemma abs_expr_constant [heap_abs]:
  "abs_expr st \<top> (\<lambda>s. a) (\<lambda>s. a)"
  apply (clarsimp simp: abs_expr_def)
  done

lemma abs_expr_conj [heap_abs]:
  "\<lbrakk> abs_expr st P G G'; abs_expr st Q H H' \<rbrakk>
      \<Longrightarrow> abs_expr st (\<lambda>s. P s \<and> Q s) (\<lambda>s. G s \<and> H s) (\<lambda>s. G' s \<and> H' s)"
  by (clarsimp simp: abs_expr_def)

lemma L2Tcorres_modify [heap_abs]:
    "\<lbrakk> abs_modifies st P a c \<rbrakk> \<Longrightarrow> L2Tcorres st (L2_seq (L2_guard P) (\<lambda>_. (L2_modify a))) (L2_modify c)"
  apply (monad_eq simp: L2_defs abs_modifies_def L2Tcorres_def corresXF_def)
  done

lemma L2Tcorres_gets [heap_abs]:
    "abs_expr st P a c \<Longrightarrow> L2Tcorres st (L2_seq (L2_guard P) (\<lambda>_. L2_gets a n)) (L2_gets c n)"
  apply (monad_eq simp: corresXF_def L2Tcorres_def L2_defs abs_expr_def)
  done

lemma L2Tcorres_gets_const [heap_abs]:
    "L2Tcorres st (L2_gets (\<lambda>s. a) n) (L2_gets (\<lambda>s. a) n)"
  apply (monad_eq simp: corresXF_def L2Tcorres_def L2_defs abs_expr_def)
  done

lemma L2Tcorres_guard [heap_abs]:
    "\<lbrakk> abs_expr st P a c \<rbrakk> \<Longrightarrow> L2Tcorres st (L2_guard (P and a)) (L2_guard c)"
  apply (monad_eq simp: corresXF_def L2Tcorres_def L2_defs abs_expr_def)
  done

lemma L2Tcorres_recguard [heap_abs]:
    "\<lbrakk> L2Tcorres st A C \<rbrakk> \<Longrightarrow> L2Tcorres st (L2_recguard n A) (L2_recguard n C)"
  apply (monad_eq simp: corresXF_def L2Tcorres_def L2_defs Ball_def Bex_def split: sum.splits)
  done

lemma L2Tcorres_while [heap_abs]:
  assumes body_corres:  "\<And>x. L2Tcorres st (B' x) (B x)"
  and guard_impl_cond:  "\<And>r. abs_expr st (G r) (C' r) (C r)"
  shows "L2Tcorres st (L2_guarded_while G C' B' i n) (L2_while C B i n)"
proof -
  have cond_match: "\<And>r s. G r (st s) \<Longrightarrow> C' r (st s) = C r s"
    using guard_impl_cond
    by (clarsimp simp: abs_expr_def)

  have "corresXF st (\<lambda>r _. r) (\<lambda>r _. r) (\<lambda>_. True)
           (doE _ \<leftarrow> guardE (G i);
                     whileLoopE C'
                       (\<lambda>i. doE r \<leftarrow> B' i;
                                _ \<leftarrow> guardE (G r);
                                returnOk r
                       odE) i
           odE)
     (whileLoopE C B i)"
    apply (rule corresXF_guard_imp)
     apply (rule corresXF_guarded_while [where P="\<lambda>_ _. True" and P'="\<lambda>_ _. True"])
         apply (clarsimp cong: corresXF_cong)
         apply (rule corresXF_guard_imp)
          apply (rule body_corres [unfolded L2Tcorres_def])
         apply simp
        apply (clarsimp simp: cond_match)
       apply clarsimp
       apply (rule hoareE_TrueI)
      apply simp
     apply simp
    apply simp
    done

  thus ?thesis
    by (clarsimp simp: L2Tcorres_def L2_defs
            guardE_def returnOk_liftE)
qed

definition "abs_spec st P (A :: ('a \<times> 'a) set) (C :: ('c \<times> 'c) set)
           \<equiv> (\<forall>s t. P (st s) \<longrightarrow> (((s, t) \<in> C) \<longrightarrow> ((st s, st t) \<in> A)))
                              \<and> (\<forall>s. P (st s) \<longrightarrow> (\<exists>x. (st s, x) \<in> A) \<longrightarrow> (\<exists>x. (s, x) \<in> C))"

lemma L2Tcorres_spec [heap_abs]:
  "\<lbrakk> abs_spec st P A C \<rbrakk>
     \<Longrightarrow> L2Tcorres st (L2_seq (L2_guard P) (\<lambda>_. (L2_spec A))) (L2_spec C)"
  apply (monad_eq simp: corresXF_def L2Tcorres_def L2_defs image_def set_eq_UNIV
             split_def Ball_def state_select_def abs_spec_def split: sum.splits)
  done

lemma abs_spec_constant [heap_abs]:
  "abs_spec st \<top> {(a, b). C} {(a, b). C}"
  apply (clarsimp simp: abs_spec_def)
  done

lemma L2Tcorres_condition [heap_abs]:
  "\<lbrakk> L2Tcorres st L L';
     L2Tcorres st R R';
     abs_expr st P C' C \<rbrakk> \<Longrightarrow>
   L2Tcorres st (L2_seq (L2_guard P) (\<lambda>_. L2_condition C' L R)) (L2_condition C L' R')"
  apply (clarsimp simp: L2_defs abs_expr_def L2Tcorres_def)
  apply (rule corresXF_exec_abs_guard [unfolded guardE_def])
  apply (rule corresXF_cond)
    apply (metis corresXF_guard_imp)
   apply (metis corresXF_guard_imp)
  apply simp
  done

lemma L2Tcorres_seq [heap_abs]:
  "\<lbrakk> L2Tcorres st L' L; \<And>r. L2Tcorres st (\<lambda>s. R' r s) (\<lambda>s. R r s) \<rbrakk>
      \<Longrightarrow> L2Tcorres st (L2_seq L' (\<lambda>r s. R' r s)) (L2_seq L (\<lambda>r s. R r s))"
  apply (clarsimp simp: L2Tcorres_def L2_defs)
  apply (rule corresXF_guard_imp)
  apply (erule corresXF_join [where P'="\<lambda>x y s. x = y" and Q="\<lambda>_. True"])
     apply (metis (full_types) corresXF_assume_pre)
    apply simp
    apply (rule hoareE_TrueI)
   apply simp
  apply simp
  done

lemma L2Tcorres_catch [heap_abs]:
    "\<lbrakk> L2Tcorres st L L';
      \<And>r. L2Tcorres st (\<lambda>s. R r s) (\<lambda>s. R' r s)
     \<rbrakk> \<Longrightarrow> L2Tcorres st (L2_catch L (\<lambda>r s. R r s)) (L2_catch L' (\<lambda>r s. R' r s))"
  apply (clarsimp simp: L2Tcorres_def L2_defs)
  apply (rule corresXF_guard_imp)
  apply (erule corresXF_except [where P'="\<lambda>x y s. x = y" and Q="\<lambda>_. True"])
     apply (metis (full_types) corresXF_assume_pre)
    apply simp
    apply (rule hoareE_TrueI)
   apply simp
  apply simp
  done

lemma L2Tcorres_unknown [heap_abs]:
  "L2Tcorres st (L2_unknown name) (L2_unknown name)"
  apply (clarsimp simp: L2_unknown_def selectE_def[symmetric])
  apply (clarsimp simp: L2Tcorres_def)
  apply (auto intro!: corresXF_select_select)
  done

lemma L2Tcorres_throw [heap_abs]:
  "L2Tcorres st (L2_throw x n) (L2_throw x n)"
  apply (clarsimp simp: L2Tcorres_def L2_defs)
  apply (rule corresXF_throw)
  apply simp
  done

lemma L2Tcorres_split [heap_abs]:
  "\<lbrakk> \<And>x y. L2Tcorres st (P x y) (P' x y) \<rbrakk> \<Longrightarrow>
    L2Tcorres st (case a of (x, y) \<Rightarrow> P x y) (case a of (x, y) \<Rightarrow> P' x y)"
  apply (clarsimp simp: split_def)
  done

lemma L2Tcorres_seq_unused_result [heap_abs]:
  "\<lbrakk> L2Tcorres st L L'; L2Tcorres st R R' \<rbrakk> \<Longrightarrow> L2Tcorres st (L2_seq L (\<lambda>_. R)) (L2_seq L' (\<lambda>_. R'))"
  apply (rule L2Tcorres_seq, auto)
  done

lemma abs_expr_split [heap_abs]:
  "\<lbrakk> \<And>a b. abs_expr st (P a b) (A a b) (C a b) \<rbrakk>
       \<Longrightarrow> abs_expr st (case r of (a, b) \<Rightarrow> P a b)  (case r of (a, b) \<Rightarrow> A a b) (case r of (a, b) \<Rightarrow> C a b)"
  apply (auto simp: split_def)
  done

lemma L2Tcorres_recguard_0:
    "L2Tcorres st (L2_recguard 0 A) C"
  apply (monad_eq simp: corresXF_def L2Tcorres_def L2_defs)
  done

lemma L2Tcorres_abstract_fail [heap_abs]:
  "L2Tcorres st L2_fail L2_fail"
  apply (clarsimp simp: L2Tcorres_def L2_defs)
  apply (rule corresXF_fail)
  done

lemma abs_expr_id [heap_abs]:
  "abs_expr id \<top> A A"
  apply (clarsimp simp: abs_expr_def)
  done

lemma abs_modify_id [heap_abs]:
  "abs_modifies id \<top> A A"
  apply (clarsimp simp: abs_modifies_def)
  done

lemma L2Tcorres_exec_concrete [heap_abs]:
  "L2Tcorres id A C \<Longrightarrow> L2Tcorres st (exec_concrete st (L2_call A)) (L2_call C)"
  apply (clarsimp simp: L2Tcorres_def L2_call_def)
  apply (rule corresXF_exec_concrete)
  apply (rule corresXF_except)
     apply assumption
    apply (rule corresXF_fail)
   apply wp[1]
  apply simp
  done

lemma L2Tcorres_exec_abstract [heap_abs]:
    "L2Tcorres st A C \<Longrightarrow> L2Tcorres id (exec_abstract st (L2_call A)) (L2_call C)"
  apply (clarsimp simp: L2_call_def L2Tcorres_def)
  apply (rule corresXF_exec_abstract)
  apply (rule corresXF_except)
     apply assumption
    apply (rule corresXF_fail)
   apply wp[1]
  apply simp
  done

lemma L2Tcorres_call [heap_abs]:
  "L2Tcorres st A C \<Longrightarrow> L2Tcorres st (L2_call A) (L2_call C)"
  unfolding L2Tcorres_def L2_call_def
  apply (rule corresXF_except)
     apply simp
    apply (rule corresXF_fail)
   apply (rule hoareE_TrueI)
  apply simp
  done

lemma L2Tcorres_measure_call [heap_abs]:
  "\<lbrakk> monad_mono C; \<And>m. L2Tcorres st (A m) (C m) \<rbrakk>
    \<Longrightarrow> L2Tcorres st (measure_call A) (measure_call C)"
  apply (unfold L2Tcorres_def)
  apply (erule corresXF_measure_call)
  apply assumption
  done

lemma abs_expr_lambda_null [heap_abs]:
  "abs_expr st P A C \<Longrightarrow> abs_expr st P (\<lambda>s r. A s) (\<lambda>s r. C s)"
  apply (clarsimp simp: abs_expr_def)
  done

(*
 * Assert the given abstracted heap (accessed using "getter" and "setter") for type
 * "'a" is a valid abstraction w.r.t. the given state translation functions.
 *)

definition
  "read_write_valid r w \<equiv>
      (\<forall>f s. r (w f s) = f (r s))
        \<and> (\<forall>s f. f (r s) = (r s) \<longrightarrow> w f s = s)
        \<and> (\<forall>f f' s. (f (r s) = f' (r s)) \<longrightarrow> w f s = w f' s)
        \<and> (\<forall>f g s. w f (w g s) = w (\<lambda>x. f (g x)) s)"

lemma read_write_write_id: "read_write_valid r w \<Longrightarrow> w (\<lambda>x. x) s = s"
  by (simp add: read_write_valid_def)

lemma read_write_valid_def1:
  "read_write_valid r w \<Longrightarrow> r (w f s) = f (r s)"
  by (metis read_write_valid_def)

lemma read_write_valid_def2:
  "\<lbrakk> read_write_valid r w; f (r s) = r s \<rbrakk> \<Longrightarrow> w f s = s"
  by (metis read_write_valid_def)

lemma read_write_valid_def3:
  "\<lbrakk> read_write_valid r w; f (r s) = f' (r s) \<rbrakk> \<Longrightarrow> w f s = w f' s"
  by (metis read_write_valid_def)

lemma read_write_o:
  "\<lbrakk> read_write_valid r w; \<And>x. h x = f (g x) \<rbrakk> \<Longrightarrow> w f (w g s) = w h s"
  apply (subst (asm) read_write_valid_def)
  apply metis
  done


definition [simp]:
  "valid_implies_cguard st v\<^sub>r \<equiv> \<forall>s p. v\<^sub>r (st s) p \<longrightarrow> c_guard p"

definition [simp]:
  "heap_decode_bytes st v\<^sub>r h\<^sub>r t_hrs\<^sub>r \<equiv> \<forall>s p. v\<^sub>r (st s) p \<longrightarrow>
              h\<^sub>r (st s) p = h_val (hrs_mem (t_hrs\<^sub>r s)) p"

definition [simp]:
  "heap_encode_bytes st v\<^sub>r h\<^sub>w t_hrs\<^sub>w \<equiv>
         \<forall>s p x. v\<^sub>r (st s) p \<longrightarrow>
           st (t_hrs\<^sub>w (hrs_mem_update (heap_update p x)) s) =
                           h\<^sub>w (\<lambda>f. f(p := x)) (st s)"

definition [simp]:
  "write_preserves_valid v\<^sub>r h\<^sub>w \<equiv>
        (\<forall>p f s. v\<^sub>r s p \<longrightarrow> v\<^sub>r (h\<^sub>w f s) p)"

definition
  valid_typ_heap ::
    "('s \<Rightarrow> 't) \<Rightarrow>
       ('t \<Rightarrow> ('a::c_type) ptr \<Rightarrow> 'a) \<Rightarrow>
       ((('a ptr \<Rightarrow> 'a) \<Rightarrow> ('a ptr \<Rightarrow> 'a)) \<Rightarrow> 't \<Rightarrow> 't) \<Rightarrow>
       ('t \<Rightarrow> ('a::c_type) ptr \<Rightarrow> bool) \<Rightarrow>
       ((('a ptr \<Rightarrow> bool) \<Rightarrow> ('a ptr \<Rightarrow> bool)) \<Rightarrow> 't \<Rightarrow> 't) \<Rightarrow>
       ('s \<Rightarrow> heap_raw_state) \<Rightarrow>
        ((heap_raw_state \<Rightarrow> heap_raw_state) \<Rightarrow> 's \<Rightarrow> 's) \<Rightarrow>
       bool"
where
  "valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update \<equiv>
     (read_write_valid getter setter)
     \<and> (read_write_valid vgetter vsetter)
     \<and> (read_write_valid t_hrs t_hrs_update)
     \<and> (valid_implies_cguard st vgetter)
     \<and> (heap_decode_bytes st vgetter getter t_hrs)
     \<and> (heap_encode_bytes st vgetter setter t_hrs_update)
     \<and> (write_preserves_valid vgetter setter)"

lemma valid_typ_heapI [intro!]:
  assumes getter_setter_idem: "\<And>s x. getter (setter x s) = x (getter s)"
  and setter_getter_idem: "\<And>s f. f (getter s) = (getter s) \<Longrightarrow> setter f s = s"
  and setter_static: "\<And>s f f'. f (getter s) = f' (getter s) \<Longrightarrow> setter f s = setter f' s"
  and setter_chain: "\<And>s f g. setter f (setter g s) = setter (\<lambda>x. f (g x)) s"
  and vgetter_setter_idem: "\<And>s x. vgetter (vsetter x s) = x (vgetter s)"
  and vsetter_getter_idem: "\<And>s f. f (vgetter s) = (vgetter s) \<Longrightarrow> vsetter f s = s"
  and vsetter_static: "\<And>s f f'. f (vgetter s) = f' (vgetter s) \<Longrightarrow> vsetter f s = vsetter f' s"
  and vsetter_chain: "\<And>s f g. vsetter f (vsetter g s) = vsetter (\<lambda>x. f (g x)) s"
  and getter_implies_safe: "\<And>s p. vgetter (st s) p \<Longrightarrow> c_guard p"
  and getter_data_correct: "\<And>s p. vgetter (st s) p \<Longrightarrow>
                       getter (st s) p = h_val (hrs_mem (t_hrs s)) p"
  and setter_keeps_vgetter: "\<And>s f p. vgetter s p \<Longrightarrow> vgetter (setter f s) p"
  and abs_update_matches_conc_update:
      "\<And>s p v. vgetter (st s) p  \<Longrightarrow>
           st (t_hrs_update (hrs_mem_update (heap_update p v)) s) =
                    setter (\<lambda>x. x(p := v)) (st s)"
  and t_hrs_set_get: "\<And>s x. t_hrs (t_hrs_update x s) = x (t_hrs s)"
  and t_hrs_get_set: "\<And>s f. f (t_hrs s) = t_hrs s \<Longrightarrow> t_hrs_update f s = s"
  and t_hrs_set_static: "\<And>s f f'. f (t_hrs s) = f' (t_hrs s) \<Longrightarrow> t_hrs_update f s = t_hrs_update f' s"
  and t_hrs_set_chain: "\<And>s f g. t_hrs_update f (t_hrs_update g s) = t_hrs_update (\<lambda>x. f (g x)) s"
  shows "valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update"
  apply (clarsimp simp: valid_typ_heap_def read_write_valid_def)
  apply (safe | fact | rule ext)+
  done

(*
 * Assert the given field ("field_getter", "field_setter") of the given structure
 * can be abstracted into the heap, and then accessed as a HOL object.
 *)
definition
  valid_struct_field
    :: "('s \<Rightarrow> 't)
           \<Rightarrow> string list
           \<Rightarrow> ('p \<Rightarrow> ('f::c_type))
           \<Rightarrow> ('f \<Rightarrow> 'p \<Rightarrow> 'p)
           \<Rightarrow> ('t \<Rightarrow> (('p::c_type) ptr \<Rightarrow> 'p))
           \<Rightarrow> ((('p ptr \<Rightarrow> 'p) \<Rightarrow> ('p ptr \<Rightarrow> 'p)) \<Rightarrow> 't \<Rightarrow> 't)
           \<Rightarrow> ('t \<Rightarrow> (('p::c_type) ptr \<Rightarrow> bool))
           \<Rightarrow> ((('p ptr \<Rightarrow> bool) \<Rightarrow> ('p ptr \<Rightarrow> bool)) \<Rightarrow> 't \<Rightarrow> 't)
           \<Rightarrow> ('s \<Rightarrow> heap_raw_state)
           \<Rightarrow> ((heap_raw_state \<Rightarrow> heap_raw_state) \<Rightarrow> 's \<Rightarrow> 's)
           \<Rightarrow> bool"
where
  "valid_struct_field st field_name field_getter field_setter
            getter setter vgetter vsetter t_hrs t_hrs_update \<equiv>
      (\<forall>s p. vgetter (st s) p \<longrightarrow>
          h_val (hrs_mem (t_hrs s)) (Ptr &(p\<rightarrow>field_name))
              = field_getter (getter (st s) p))
      \<and> (\<forall>s p val. vgetter (st s) p \<longrightarrow>
                 st (t_hrs_update (hrs_mem_update (heap_update (Ptr &(p\<rightarrow>field_name)) val)) s) =
                           setter (\<lambda>old. old(p := (field_setter val (old p)))) (st s))
      \<and> (\<forall>s p. vgetter (st s) p \<longrightarrow> c_guard p)
      \<and> (\<forall>p. c_guard (p :: 'p ptr) \<longrightarrow> c_guard (Ptr &(p\<rightarrow>field_name) :: 'f ptr))"

lemma valid_struct_fieldI [intro]:
  fixes st :: "'s \<Rightarrow> 't"
  fixes field_getter :: "('a::c_type) \<Rightarrow> ('f::c_type)"
  shows "\<lbrakk> \<And>s p. vgetter (st s) p \<Longrightarrow>
        h_val (hrs_mem (t_hrs s)) (Ptr &(p\<rightarrow>field_name))  = field_getter (getter (st s) p);
     \<And>s p val. vgetter (st s) p \<Longrightarrow>
        st (t_hrs_update (hrs_mem_update (heap_update (Ptr &(p\<rightarrow>field_name)) val)) s) =
             setter (\<lambda>old. old(p := (field_setter val (old p)))) (st s);
     \<And>s p. vgetter (st s) p \<Longrightarrow> c_guard p;
     \<And>(p::'a ptr). c_guard p \<Longrightarrow> c_guard (Ptr &(p\<rightarrow>field_name) :: 'f ptr) \<rbrakk> \<Longrightarrow>
    valid_struct_field st field_name field_getter field_setter getter setter vgetter vsetter t_hrs t_hrs_update"
  apply (fastforce simp: valid_struct_field_def)
  done

lemma valid_typ_heap_get_hvalD:
  "\<lbrakk> valid_typ_heap st getter setter vgetter vsetter
        t_hrs t_hrs_update; vgetter (st s) p \<rbrakk> \<Longrightarrow>
      h_val (hrs_mem (t_hrs s)) p = getter (st s) p"
  apply (clarsimp simp: valid_typ_heap_def)
  done

lemma valid_typ_heap_t_hrs_updateD:
  "\<lbrakk> valid_typ_heap st getter setter vgetter vsetter
         t_hrs t_hrs_update; vgetter (st s) p \<rbrakk> \<Longrightarrow>
           st (t_hrs_update (hrs_mem_update (heap_update p v')) s) =
                           setter (\<lambda>x. x(p := v')) (st s)"
  apply (clarsimp simp: valid_typ_heap_def)
  done

lemma heap_abs_expr_guard [heap_abs]:
  "\<lbrakk> valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update; abs_expr st P x' x \<rbrakk> \<Longrightarrow>
     abs_expr st (P and (\<lambda>s. vgetter s (x' s))) (\<lambda>s. True) (\<lambda>s. (c_guard (x s :: ('a::{c_type}) ptr)))"
  apply (clarsimp simp: abs_expr_def simple_lift_def heap_ptr_valid_def valid_typ_heap_def)
  done

lemma heap_abs_expr_h_val [heap_abs]:
  "\<lbrakk> valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update;
     abs_expr st P x' x \<rbrakk> \<Longrightarrow>
      abs_expr st
       (P and (\<lambda>s. vgetter s (x' s)))
         (\<lambda>s. (getter s (x' s)))
         (\<lambda>s. (h_val (hrs_mem (t_hrs s))) (x s))"
  apply (clarsimp simp: abs_expr_def simple_lift_def)
  apply (metis valid_typ_heap_get_hvalD)
  done

lemma heap_abs_modifies_heap_update [heap_abs]:
  "\<lbrakk>  valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update;
     abs_expr st Pb b' b;
     abs_expr st Pc c' c \<rbrakk> \<Longrightarrow>
      abs_modifies st (Pb and Pc and (\<lambda>s. vgetter s (b' s)))
        (\<lambda>s. setter (\<lambda>x. x(b' s := (c' s))) s)
           (\<lambda>s. t_hrs_update (hrs_mem_update (heap_update (b s :: ('a::c_type) ptr) (c s :: 'a))) s)"
  apply (clarsimp simp: typ_simple_heap_simps abs_expr_def abs_modifies_def)
  apply (metis valid_typ_heap_t_hrs_updateD)
  done

lemma abs_expr_field_getter [heap_abs]:
  "\<lbrakk> valid_struct_field st field_name field_getter field_setter
                     getter setter vgetter vsetter t_hrs t_hrs_setter;
      abs_expr st P a c \<rbrakk> \<Longrightarrow>
   abs_expr st (P and (\<lambda>s. vgetter s (a s))) (\<lambda>s. field_getter (getter s (a s)))
              (\<lambda>s. h_val (hrs_mem (t_hrs s)) (Ptr &((c s)\<rightarrow>field_name)))"
  apply (clarsimp simp: abs_expr_def valid_struct_field_def valid_typ_heap_def)
  done

lemma abs_expr_field_setter [heap_abs]:
  "\<lbrakk> valid_struct_field st field_name
          field_getter field_setter getter setter vgetter vsetter t_hrs t_hrs_update;
     abs_expr st P p p'; abs_expr st Q val val' \<rbrakk> \<Longrightarrow>
  abs_modifies st (P and Q and (\<lambda>s. vgetter s (p s)))
      (\<lambda>s. setter (\<lambda>old. old((p s) := field_setter (val s) (old (p s)))) s)
      (\<lambda>s. t_hrs_update (hrs_mem_update (heap_update (Ptr &((p' s)\<rightarrow>field_name)) (val' s))) s)"
  apply (clarsimp simp: abs_expr_def valid_struct_field_def valid_typ_heap_def abs_modifies_def)
  done

lemma abs_expr_field_guard [heap_abs]:
  "\<lbrakk> valid_struct_field st field_name
          (field_getter :: 'p \<Rightarrow> 'f) field_setter getter setter vgetter vsetter t_hrs t_hrs_update;
     abs_expr st P p p' \<rbrakk> \<Longrightarrow>
  abs_expr st (P and (\<lambda>s. vgetter s (p s :: 'p :: {c_type} ptr )))
      (\<lambda>s. True)
      (\<lambda>s. c_guard (Ptr &((p' s)\<rightarrow>field_name) :: 'f::{c_type} ptr))"
  apply (clarsimp simp: abs_expr_def)
  apply (clarsimp simp: abs_expr_def valid_struct_field_def valid_typ_heap_def)
  done

(*
 * Convert gets/sets to global variables into gets/sets in the new globals record.
 *)

definition
  valid_globals_field :: "
     ('s \<Rightarrow> 't)
     \<Rightarrow> ('s \<Rightarrow> 'a)
     \<Rightarrow> (('a \<Rightarrow> 'a) \<Rightarrow> 's \<Rightarrow> 's)
     \<Rightarrow> ('t \<Rightarrow> 'a)
     \<Rightarrow> (('a \<Rightarrow> 'a) \<Rightarrow> 't \<Rightarrow> 't)
     \<Rightarrow> bool"
where
  "valid_globals_field st old_getter old_setter new_getter new_setter \<equiv>
    (\<forall>s. new_getter (st s) = old_getter s)
    \<and> (\<forall>s v. new_setter v (st s) = st (old_setter v s))"

lemma abs_expr_globals_getter [heap_abs]:
  "\<lbrakk> valid_globals_field st old_getter old_setter new_getter new_setter \<rbrakk>
    \<Longrightarrow> abs_expr st \<top> new_getter old_getter"
  apply (clarsimp simp: valid_globals_field_def abs_expr_def)
  done

lemma abs_expr_globals_setter [heap_abs]:
  "\<lbrakk> valid_globals_field st old_getter old_setter new_getter new_setter;
     \<And>old. abs_expr st (P old) (v old) (v' old) \<rbrakk>
    \<Longrightarrow> abs_modifies st (\<lambda>s. \<forall>old. P old s) (\<lambda>s. new_setter (\<lambda>old. v old s) s) (\<lambda>s. old_setter (\<lambda>old. v' old s) s)"
  apply (clarsimp simp: valid_globals_field_def abs_expr_def abs_modifies_def)
  done

(* Signed words are stored on the heap as unsigned words. *)

lemma uint_scast [simp]:
    "uint (scast x :: 'a word) = uint (x :: 'a::len signed word)"
  apply (subst down_cast_same [symmetric])
   apply (clarsimp simp: cast_simps)
  apply (subst uint_up_ucast)
   apply (clarsimp simp: cast_simps)
  apply simp
  done

lemma to_bytes_signed_word:
    "to_bytes (x :: 'a::len8 signed word) p = to_bytes (scast x :: 'a word) p"
  by (clarsimp simp: to_bytes_def typ_info_word word_rsplit_def)

lemma from_bytes_signed_word:
    "length p = len_of TYPE('a) div 8 \<Longrightarrow>
           (from_bytes p :: 'a::len8 signed word) = ucast (from_bytes p :: 'a word)"
  by (clarsimp simp: from_bytes_def word_rcat_def
              scast_def cast_simps typ_info_word)

lemma hrs_mem_update_signed_word:
    "hrs_mem_update (heap_update (ptr_coerce p :: 'a::len8 word ptr) (scast val :: 'a::len8 word))
               = hrs_mem_update (heap_update p (val :: 'a::len8 signed word))"
  apply (rule ext)
  apply (clarsimp simp: hrs_mem_update_def split_def)
  apply (clarsimp simp: heap_update_def to_bytes_signed_word
             size_of_def typ_info_word)
  done

lemma h_val_signed_word:
    "(h_val a p :: 'a::len8 signed word) = ucast (h_val a (ptr_coerce p :: 'a word ptr))"
  apply (clarsimp simp: h_val_def)
  apply (subst from_bytes_signed_word)
   apply (clarsimp simp: size_of_def typ_info_word)
  apply (clarsimp simp: size_of_def typ_info_word)
  done


lemma align_of_signed_word [simp]:
  "align_of TYPE('a::len8 signed word) = align_of TYPE('a word)"
  by (clarsimp simp: align_of_def typ_info_word)

lemma size_of_signed_word [simp]:
  "size_of TYPE('a::len8 signed word) = size_of TYPE('a word)"
  by (clarsimp simp: size_of_def typ_info_word)

lemma c_guard_ptr_coerce:
  "\<lbrakk> align_of TYPE('a) = align_of TYPE('b);
     size_of TYPE('a) = size_of TYPE('b) \<rbrakk> \<Longrightarrow>
        c_guard (ptr_coerce p :: ('b::c_type) ptr) = c_guard (p :: ('a::c_type) ptr)"
  apply (clarsimp simp: c_guard_def ptr_aligned_def c_null_guard_def)
  done

lemma word_rsplit_signed:
    "(word_rsplit (ucast v' :: ('a::len) signed word) :: 8 word list) = word_rsplit (v' :: 'a word)"
  apply (clarsimp simp: word_rsplit_def)
  apply (clarsimp simp: cast_simps)
  done

lemma heap_update_signed_word [simp]:
    "heap_update (ptr_coerce p :: 'a word ptr) (scast v) = heap_update (p :: ('a::len8) signed word ptr) v"
    "heap_update (ptr_coerce p' :: 'a signed word ptr) (ucast v') = heap_update (p' :: ('a::len8) word ptr) v'"
  apply (auto intro!: ext simp: heap_update_def to_bytes_def
                         typ_info_word word_rsplit_def cast_simps)
  done

lemma valid_typ_heap_c_guard:
  "\<lbrakk> valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update;
           vgetter (st s) p \<rbrakk> \<Longrightarrow> c_guard p"
  by (clarsimp simp: valid_typ_heap_def)

abbreviation (input)
  scast_f :: "(('a::len) signed word ptr \<Rightarrow> 'a signed word)
            \<Rightarrow> ('a word ptr \<Rightarrow> 'a word)"
where
  "scast_f f \<equiv> (\<lambda>p. scast (f (ptr_coerce p)))"

abbreviation (input)
  ucast_f :: "(('a::len) word ptr \<Rightarrow> 'a word)
            \<Rightarrow> ('a signed word ptr \<Rightarrow> 'a signed word)"
where
  "ucast_f f \<equiv> (\<lambda>p. ucast (f (ptr_coerce p)))"

abbreviation (input)
  cast_f' :: "('a ptr \<Rightarrow> 'x) \<Rightarrow> ('b ptr \<Rightarrow> 'x)"
where
  "cast_f' f \<equiv> (\<lambda>p. f (ptr_coerce p))"

lemma read_write_validE_weak:
  "\<lbrakk> read_write_valid r w;
      \<lbrakk> \<And>f s. r (w f s) = f (r s);
        \<And>f s. f (r s) = (r s) \<Longrightarrow> w f s = s \<rbrakk> \<Longrightarrow> R \<rbrakk>
        \<Longrightarrow> R"
  apply atomize_elim
  apply (unfold read_write_valid_def)
  apply blast
  done

lemma read_write_valid_transcode:
  "\<lbrakk> read_write_valid r w; \<And>v. f' (f v) = v; \<And>v. f (f' v) = v  \<rbrakk> \<Longrightarrow> read_write_valid (\<lambda>s. f' (r s)) (\<lambda>g s. w (\<lambda>old. f (g (f' old))) s)"
  apply (unfold read_write_valid_def)
  apply safe
     apply atomize
     apply metis
    apply atomize
    apply (metis (full_types))
   apply atomize
   apply metis
  apply atomize
  apply (metis (lifting, mono_tags))
  done

lemma valid_typ_heap_signed_word:
  "\<lbrakk> valid_typ_heap st
        (getter :: 's \<Rightarrow> ('a::len8) word ptr  \<Rightarrow> 'a word) setter
              vgetter vsetter t_hrs t_hrs_update \<rbrakk>
    \<Longrightarrow> valid_typ_heap st
              (\<lambda>s p. ucast (getter s (ptr_coerce p)) :: 'a signed word)
              (\<lambda>f.  (setter ((\<lambda>x. scast_f (f (ucast_f x))))))
              (\<lambda>s p. vgetter s (ptr_coerce p))
              (\<lambda>f. (vsetter ((\<lambda>x. cast_f' (f (cast_f' x))))))
              t_hrs t_hrs_update"
  apply (clarsimp simp: valid_typ_heap_def
          Option.map.compositionality o_def c_guard_ptr_coerce)
  apply (rule read_write_validE_weak [where r=getter], assumption)
  apply (rule read_write_validE_weak [where r=vgetter], assumption)
  apply (rule read_write_validE_weak [where r=t_hrs], assumption)
  apply (intro conjI impI)
      apply (erule read_write_valid_transcode, auto)[1]
     apply (erule read_write_valid_transcode, auto)[1]
    apply clarsimp
    apply (drule spec, drule spec, erule (1) impE)+
    apply (subst (asm) c_guard_ptr_coerce, simp, simp)
    apply simp
   apply clarsimp
   apply (drule spec, drule spec, erule (1) impE)+
   apply (subst (asm) c_guard_ptr_coerce, simp, simp)
   apply (metis (hide_lams, mono_tags) h_val_signed_word scast_ucast_norm(2))
  apply clarsimp
  apply (drule_tac x=s in spec)+
  apply (drule_tac x="ptr_coerce p" in spec)+
  apply clarsimp
  apply (drule_tac x="scast x" in spec)+
  apply clarsimp
  apply (clarsimp simp: fun_upd_def split: option.splits)
  apply (rule arg_cong2 [where f=setter])
   apply (rule ext)
   apply (rule ext)
   apply (clarsimp simp: split: option.splits)
  apply (metis ptr_coerce_id ptr_coerce_idem)
  done

lemma c_guard_ptr_ptr_coerce:
    "\<lbrakk> c_guard (a :: ('a::c_type) ptr ptr); ptr_val a = ptr_val b \<rbrakk> \<Longrightarrow>
         c_guard (b :: ('b::c_type) ptr ptr)"
  by (clarsimp simp: c_guard_def ptr_aligned_def c_null_guard_def)

abbreviation (input)
  ptr_coerce_f :: "('a ptr ptr \<Rightarrow> 'a ptr) \<Rightarrow> ('b ptr ptr \<Rightarrow> 'b ptr)"
where
  "ptr_coerce_f f \<equiv> (\<lambda>p. ptr_coerce (f (ptr_coerce p)))"

abbreviation (input)
  ptr_coerce_range_f :: "('a ptr  \<Rightarrow> bool) \<Rightarrow> ('b ptr \<Rightarrow> bool)"
where
  "ptr_coerce_range_f f \<equiv> (\<lambda>p. (f (ptr_coerce p)))"

lemma valid_typ_heap_ptr_coerce:
  "\<lbrakk> valid_typ_heap st
        (getter :: 's \<Rightarrow> ('a::c_type) ptr ptr  \<Rightarrow> 'a ptr) setter
              vgetter vsetter t_hrs t_hrs_update \<rbrakk>
    \<Longrightarrow> valid_typ_heap st
              (\<lambda>s p. ptr_coerce (getter s (ptr_coerce p)) :: ('b::c_type) ptr)
              (\<lambda>f.  (setter ((\<lambda>x. ptr_coerce_f (f (ptr_coerce_f x))))))
              (\<lambda>s p. vgetter s (ptr_coerce p))
              (\<lambda>f. (vsetter ((\<lambda>x. ptr_coerce_range_f (f (ptr_coerce_range_f x))))))
              t_hrs t_hrs_update"
  apply (clarsimp simp: valid_typ_heap_def fun_upd_def)
  apply (rule read_write_validE_weak [where r=getter], assumption)
  apply (rule read_write_validE_weak [where r=vgetter], assumption)
  apply (rule read_write_validE_weak [where r=t_hrs], assumption)
  apply safe
      apply (erule read_write_valid_transcode, auto)[1]
     apply (erule read_write_valid_transcode, auto)[1]
    apply (erule allE, erule allE, erule impE, assumption)+
    apply (erule c_guard_ptr_ptr_coerce, simp)
   apply (clarsimp simp: h_val_def typ_info_ptr from_bytes_def)
  apply (erule allE, erule allE, erule (1) impE)+
  apply (erule allE)
  apply (erule_tac x="ptr_coerce x" in allE)
  apply (clarsimp simp: heap_update_def [abs_def] to_bytes_def typ_info_ptr)
  apply (clarsimp simp: if_distrib [where f=ptr_coerce])
  apply (metis (hide_lams, mono_tags) Ptr_ptr_val ptr_coerce.simps)
  done

(*
 * Nasty hack: Convert signed word pointers-to-pointers to word
 * pointers-to-pointers.
 *
 * The idea here is that types of the form:
 *
 *    int ***x;
 *
 * need to be converted to accesses of the "unsigned int ***" heap.
 *)
lemmas signed_valid_typ_heaps =
  valid_typ_heap_signed_word
  valid_typ_heap_ptr_coerce [where 'a="('x::len8) word"  and 'b="('x::len8) signed word"]
  valid_typ_heap_ptr_coerce [where 'a="('x::len8) word ptr"  and 'b="('x::len8) signed word ptr"]
  valid_typ_heap_ptr_coerce [where 'a="('x::len8) word ptr ptr"  and 'b="('x::len8) signed word ptr ptr"]
  valid_typ_heap_ptr_coerce [where 'a="('x::len8) word ptr ptr ptr"  and 'b="('x::len8) signed word ptr ptr ptr"]

(*
 * The above lemmas generate a mess in its output, generating things
 * like:
 *
 * (heap_w32_update
 *    (\<lambda>a b. scast
 *            (((\<lambda>b. ucast (a (ptr_coerce b)))(a := 3))
 *              (ptr_coerce b))))
 *
 * This theorem cleans it up a little.
 *)
lemma ptr_coerce_eq:
  "(ptr_coerce x = ptr_coerce y) = (x = y)"
  by (cases x, cases y, auto)

lemma signed_word_heap_opt [L2opt]:
  "(scast (((\<lambda>x. ucast (a (ptr_coerce x))) (p := v :: 'a::len signed word)) (b :: 'a signed word ptr)))
  = ((a(ptr_coerce p := (scast v :: 'a word))) ((ptr_coerce b) :: 'a word ptr))"
  by (auto simp: fun_upd_def scast_id ptr_coerce_eq)

lemma signed_word_heap_ptr_coerce_opt [L2opt]:
  "(ptr_coerce (((\<lambda>x. ptr_coerce (a (ptr_coerce x))) (p := v :: 'a ptr)) (b :: 'a ptr ptr)))
  = ((a(ptr_coerce p := (ptr_coerce v :: 'b ptr))) ((ptr_coerce b) :: 'b ptr ptr))"
  by (auto simp: fun_upd_def scast_id ptr_coerce_eq)

declare ptr_coerce_idem [L2opt]
declare scast_ucast_id [L2opt]
declare ucast_scast_id [L2opt]

(* array rules *)
lemma heap_abs_expr_c_guard_array [heap_abs]:
  "\<lbrakk> valid_typ_heap st getter setter vgetter vsetter t_hrs t_hrs_update;
      abs_expr st P (\<lambda>s. x' s) (\<lambda>s. ptr_coerce (x s) :: 'a ptr)  \<rbrakk> \<Longrightarrow>
     abs_expr st
        (P and (\<lambda>s. \<forall>a \<in> set (array_addrs (x' s) CARD('b)). (vgetter s a)))
           (\<lambda>s. True)
           (\<lambda>s. (c_guard (x s :: ('a::oneMB_size, 'b::fourthousand_count) array ptr)))"
  apply (clarsimp simp: abs_expr_def simple_lift_def heap_ptr_valid_def)
  apply (subgoal_tac "\<forall>a\<in>set (array_addrs (x' (st s)) CARD('b)). c_guard a")
   apply (erule allE, erule (1) impE)
   apply (rule c_guard_array_c_guard)
   apply (subst (asm) (2) set_array_addrs)
   apply force
  apply clarsimp
  apply (erule (1) my_BallE)
  apply (drule (1) valid_typ_heap_c_guard)
  apply simp
  done

(* begin machinery for abs_array_update *)
lemma fold_over_st:
  "\<lbrakk> xs = ys; P s;
     \<And>s x. x \<in> set xs \<and> P s \<Longrightarrow> P (g x s) \<and> f x (st s) = st (g x s)
   \<rbrakk> \<Longrightarrow> fold f xs (st s) = st (fold g ys s)"
  apply (erule subst)
  apply (induct xs arbitrary: s)
   apply simp
  apply simp
  done

lemma fold_lift_write:
  "\<lbrakk> xs = ys; read_write_valid r w
   \<rbrakk> \<Longrightarrow> fold (\<lambda>i. w (f i)) xs s = w (fold f ys) s"
  apply (erule subst)
  apply (induct xs arbitrary: s)
   apply (simp add: read_write_valid_def2)
  apply (force elim!: read_write_o)
  done

(* cf. heap_update_nmem_same *)
lemma fold_heap_update_list_nmem_same:
  "\<lbrakk> n * size_of TYPE('a :: mem_type) < addr_card;
     n * size_of TYPE('a) \<le> k; k < addr_card;
     \<And>i h. length (pad i h) = size_of TYPE('a) \<rbrakk> \<Longrightarrow>
     h (ptr_val (p :: 'a ptr) + of_nat k) =
     (fold (\<lambda>i h. heap_update_list (ptr_val (p +\<^sub>p int i))
                 (to_bytes (val i h :: 'a) (pad i h)) h) [0..<n] h) (ptr_val p + of_nat k)"
  apply (induct n arbitrary: k)
   apply simp
  apply (clarsimp simp: ptr_add_def simp del: mult_Suc)
  apply (subst heap_update_nmem_same)
   apply (subst len)
    apply simp
   apply (simp add: intvl_def)
   apply (intro allI impI)
   apply (subst (asm) of_nat_mult[symmetric] of_nat_add[symmetric])+
   apply (rename_tac j)
   apply (erule_tac Q = "of_nat k = of_nat (n * size_of TYPE('a) + j)" in contrapos_pn)
   apply (subst of_nat_inj)
     apply (subst len_of_addr_card)
     apply simp
    apply (subst len_of_addr_card)
    apply simp
   apply simp
  apply simp
  done

lemma heap_list_of_disjoint_fold_heap_update_list:
  "\<lbrakk> n * size_of TYPE('a :: mem_type) < addr_card;
     n * size_of TYPE('a) + k < addr_card;
     \<And>i h. length (pad i h) = size_of TYPE('a) \<rbrakk> \<Longrightarrow>
   heap_list (fold (\<lambda>i h. heap_update_list (ptr_val ((p :: 'a ptr) +\<^sub>p int i))
                            (to_bytes (val i h :: 'a) (pad i h)) h) [0..<n] h)
             k (ptr_val (p +\<^sub>p int n))
   = heap_list h k (ptr_val (p +\<^sub>p int n))"
  apply (rule nth_equalityI)
   apply simp
  apply (clarsimp simp: heap_list_nth)
  apply (rule_tac t = "ptr_val (p +\<^sub>p int n) + of_nat i"
              and s = "ptr_val p + of_nat (n * size_of TYPE('a) + i)"
               in subst)
   apply (clarsimp simp: ptr_add_def)
  apply (rule fold_heap_update_list_nmem_same[symmetric])
     apply simp_all
  done

(* remove false dependency *)
lemma fold_heap_update_list:
  "n * size_of TYPE('a :: mem_type) < 2^32 \<Longrightarrow>
   fold (\<lambda>i h. heap_update_list (ptr_val ((p :: 'a ptr) +\<^sub>p int i))
                 (to_bytes (val i :: 'a)
                   (heap_list h (size_of TYPE('a)) (ptr_val (p +\<^sub>p int i)))) h)
        [0..<n] h =
   fold (\<lambda>i. heap_update_list (ptr_val (p +\<^sub>p int i))
               (to_bytes (val i)
                 (heap_list h (size_of TYPE('a)) (ptr_val (p +\<^sub>p int i)))))
        [0..<n] h"
  apply (induct n)
   apply simp
  apply clarsimp
  apply (subst heap_list_of_disjoint_fold_heap_update_list)
     apply (simp add: len_of_addr_card[symmetric])+
  done

(* cf. access_ti_list_array *)
lemma access_ti_list_array_unpacked:
  "\<lbrakk> \<forall>n. size_td_pair (f n) = v3; length xs = v3 * n;
     \<forall>m xs. length xs = v3 \<and> m < n \<longrightarrow>
              access_ti_pair (f m) (FCP g) xs = h m xs
   \<rbrakk> \<Longrightarrow>
   access_ti_list (map f [0 ..< n]) (FCP g) xs
     = foldl (op @) [] (map (\<lambda>m. h m (take v3 (drop (v3 * m) xs))) [0 ..< n])"
  apply (subgoal_tac "\<forall>ys. size_td_list (map f ys) = v3 * length ys")
   prefer 2
   apply (rule allI, induct_tac ys, simp+)
  apply (induct n arbitrary: xs)
   apply simp
  apply (simp add: access_ti_append)
  apply (rule foldl_cong)
    apply simp
   apply (rule map_cong[OF refl])
   apply (subst take_drop)
   apply (subst take_take)
   apply (subst min_absorb1)
    apply clarsimp
    apply (metis Suc_leI mult_Suc_right nat_mult_le_cancel_disj)
   apply (subst take_drop[symmetric])
   apply (rule refl)
  apply simp
  done

lemma concat_nth_chunk:
  "\<lbrakk> \<forall>x \<in> set xs. length (f x) = chunk; n < length xs \<rbrakk>
   \<Longrightarrow> take chunk (drop (n * chunk) (concat (map f xs))) = f (xs ! n)"
  apply (induct xs arbitrary: n)
   apply simp
  apply (case_tac n)
   apply clarsimp
  apply clarsimp
  done

lemma array_update_split:
  "\<lbrakk> valid_typ_heap st (getter :: 's \<Rightarrow> ('a::oneMB_size) ptr \<Rightarrow> 'a) setter
                    vgetter vsetter t_hrs t_hrs_update;
     \<forall>x \<in> set (array_addrs (ptr_coerce p) CARD('b::fourthousand_count)).
        vgetter (st s) x
   \<rbrakk> \<Longrightarrow> st (t_hrs_update (hrs_mem_update (heap_update p (arr :: 'a['b]))) s) =
          fold (\<lambda>i. setter (\<lambda>x. x(ptr_coerce p +\<^sub>p int i := index arr i)))
               [0 ..< CARD('b)] (st s)"
  apply (clarsimp simp: valid_typ_heap_def)

  (* unwrap st *)
  apply (subst fold_over_st[OF refl,
           where P = "\<lambda>s. \<forall>x\<in>set (array_addrs (ptr_coerce p) CARD('b)). vgetter (st s) x"
             and g = "\<lambda>i. t_hrs_update (hrs_mem_update (heap_update
                            (ptr_coerce p +\<^sub>p int i) (index arr i)))"])
    apply simp
   apply (subgoal_tac "vgetter (st sa) (ptr_coerce p +\<^sub>p int x)")
    apply clarsimp
   apply (clarsimp simp: set_array_addrs)
   apply metis
  apply (rule_tac f = st in arg_cong)
  apply (subst hrs_mem_update_def)+

  (* unwrap t_hrs_update *)
  apply (subst fold_lift_write[OF refl, where w = t_hrs_update])
   apply assumption
  apply (rule_tac f = "\<lambda>f. t_hrs_update f s" in arg_cong)
  apply (rule ext)
  apply (subst fold_lift_write[OF refl,
           where r = fst and w = "\<lambda>f s. case s of (h, z) \<Rightarrow> (f h, z)"])
   apply (simp (no_asm) add: read_write_valid_def)
  apply clarsimp

  (* split up array update *)
  apply (clarsimp simp: heap_update_def[abs_def])
  apply (subst coerce_heap_update_to_heap_updates[unfolded foldl_conv_fold,
           where chunk = "size_of TYPE('a)" and m = "CARD('b)"])
    apply (rule size_of_array[unfolded mult_commute])
   apply simp

  (* remove false dependency *)
  apply (subst fold_heap_update_list[OF fourthousand_size])
  apply (rule fold_cong[OF refl refl])

  apply (clarsimp simp: ptr_add_def)
  apply (rule_tac f = "heap_update_list (ptr_val p + of_nat x * of_nat (size_of TYPE('a)))"
               in arg_cong)

  apply (subst fcp_eta[where g = arr, symmetric])
  apply (clarsimp simp: to_bytes_def typ_info_array array_tag_def array_tag_n_eq)
  apply (subst access_ti_list_array_unpacked)
     apply clarsimp
     apply (rule refl)
    apply (simp add: size_of_def)
   apply clarsimp
   apply (rule refl)
  apply (clarsimp simp: fcp_eta foldl_conv_concat)

  (* we need this later *)
  apply (subgoal_tac
    "\<And>x. x < CARD('b) \<Longrightarrow>
          size_td (typ_info_t TYPE('a))
           \<le> CARD('b) * size_td (typ_info_t TYPE('a)) - size_td (typ_info_t TYPE('a)) * x")
   prefer 2
   apply (subst le_diff_conv2)
    apply simp
   apply (subst mult_commute, subst mult_Suc[symmetric])
   apply (rule mult_le_mono1)
   apply simp

  apply (subst concat_nth_chunk)
    apply clarsimp
    apply (subst fd_cons_length)
      apply simp
     apply (simp add: size_of_def)
    apply (simp add: size_of_def)
   apply simp
  apply (subst drop_heap_list_le)
   apply (simp add: size_of_def)
  apply (subst take_heap_list_le)
   apply (simp add: size_of_def)
  apply (clarsimp simp: size_of_def)
  apply (subst mult_commute, rule refl)
  done

lemma fold_update_id:
  "\<lbrakk> read_write_valid getter setter;
     \<forall>i \<in> set xs. \<forall>j \<in> set xs. (i = j) = (ind i = ind j);
     \<forall>i \<in> set xs. val i = getter s (ind i)
  \<rbrakk> \<Longrightarrow> fold (\<lambda>i. setter (\<lambda>x. x(ind i := val i))) xs s = s"
  apply (induct xs)
   apply simp
  apply clarsimp
  apply (subgoal_tac "setter (\<lambda>x. x(ind a := getter s (ind a))) s = s")
   apply simp
  apply (subst (asm) read_write_valid_def)
  apply simp
  done

lemma fourthousand_index:
  "\<lbrakk> i < CARD('b::fourthousand_count); j < CARD('b) \<rbrakk>
   \<Longrightarrow> (i = j) =
        ((of_nat (i * size_of TYPE('a::oneMB_size)) :: word32)
          = of_nat (j * size_of TYPE('a)))"
  apply (rule_tac t = "i = j" and s = "i * size_of TYPE('a) = j * size_of TYPE('a)" in subst)
   apply clarsimp
   apply (metis sz_nzero less_nat_zero_code)

  apply (rule of_nat_inj[symmetric])
  apply (rule_tac t = "len_of TYPE(32)" and s = 32 in subst,
          simp,
         rule less_trans,
          erule_tac b = "CARD('b)" in mult_strict_right_mono,
          rule sz_nzero,
         rule fourthousand_size)+
  done

(* end machinery for abs_array_update *)

theorem abs_array_update [heap_abs]:
 "\<lbrakk>  valid_typ_heap st (getter :: 's \<Rightarrow> 'a ptr \<Rightarrow> 'a) setter
                    vgetter vsetter t_hrs t_hrs_update;
     (*\<And>s p. getter s p = the (simple_lift (t_hrs s) p);
     \<And>s p. vgetter s p = ((simple_lift (t_hrs s) p) \<noteq> None);*)
     abs_expr st Pb b' b \<rbrakk> \<Longrightarrow>
      abs_modifies st (Pb and (\<lambda>_. n < CARD('b)) and
                         (\<lambda>s. \<forall>ptr \<in> set (array_addrs (ptr_coerce (b' s)) CARD('b)). (vgetter s ptr)))
        (\<lambda>s. setter (\<lambda>v. v(ptr_coerce (b' s) +\<^sub>p int n := val)) s)
        (\<lambda>s. t_hrs_update (hrs_mem_update (
              heap_update (b s) (Arrays.update ((h_val (hrs_mem (t_hrs s)) (b s))
                       :: ('a::oneMB_size)['b::fourthousand_count]) n val))) s)"
  apply (clarsimp simp: abs_modifies_def abs_expr_def)
  (* rewrite heap_update of array *)
  apply (subst array_update_split
    [where st = st and t_hrs = t_hrs and t_hrs_update = t_hrs_update])
    apply assumption
   apply assumption
  apply (clarsimp simp: valid_typ_heap_def)

  (* rewrite array reads to pointer reads *)
  apply (subst fold_cong[OF refl refl,
           where g = "\<lambda>i. setter (\<lambda>x. x(ptr_coerce (b' (st s)) +\<^sub>p int i :=
                         if i = n then val else getter (st s) (ptr_coerce (b' (st s)) +\<^sub>p int i)))"])
   apply (rule_tac f = setter in arg_cong)
   apply (case_tac "x = n")
    apply (simp add: index_update)
   apply (subst index_update2)
     apply simp
    apply simp
   apply (rule_tac x = "index (h_val (hrs_mem (t_hrs s)) (b' (st s))) x" in arg_cong)
   apply (subst heap_access_Array_element)
    apply simp
   apply (clarsimp simp: set_array_addrs)
   apply metis

  (* split away the indices that don't change *)
  apply (subst split_upt_on_n[where n = n])
   apply simp
  apply clarsimp

  (* [0..<n] doesn't change *)
  apply (subst fold_update_id[where s = "st s"])
     apply assumption
    apply (clarsimp simp: ptr_add_def)
    apply (subst of_nat_mult[symmetric])+
    apply (rule fourthousand_index)
     apply (erule less_trans, assumption)+
   apply clarsimp

  (* [Suc n..<CARD('b)] doesn't change *)
  apply (subst fold_update_id)
     apply assumption
    apply (clarsimp simp: ptr_add_def)
    apply (subst of_nat_mult[symmetric])+
    apply (erule fourthousand_index)
    apply assumption
   apply clarsimp
   (* index n is disjoint *)
   apply (subst read_write_valid_def1[where r = getter and w = setter])
    apply assumption
   apply (clarsimp simp: ptr_add_def)
   apply (subgoal_tac "of_nat (i * size_of TYPE('a)) \<noteq> of_nat (n * size_of TYPE('a))")
    apply force
   apply (subst fourthousand_index[symmetric])
     apply assumption
    apply simp
   apply simp
  apply simp
  done

lemma the_fun_upd_lemma1:
    "(\<lambda>x. the (f x))(p := v) = (\<lambda>x. the ((f (p := Some v)) x))"
  by (auto intro!: ext simp: fun_upd_def)

lemma the_fun_upd_lemma2:
   "\<exists>z. f p = Some z \<Longrightarrow>
       (\<lambda>x. \<exists>z. (f (p := Some v)) x = Some z) =  (\<lambda>x. \<exists>z. f x = Some z) "
  by (auto intro!: ext simp: fun_upd_def)

lemma the_fun_upd_lemma3:
    "((\<lambda>x. the (f x))(p := v)) x = the ((f (p := Some v)) x)"
  by (auto intro!: ext simp: fun_upd_def)

lemma the_fun_upd_lemma4:
   "\<exists>z. f p = Some z \<Longrightarrow>
       (\<exists>z. (f (p := Some v)) x = Some z) =  (\<exists>z. f x = Some z) "
  by (auto intro!: ext simp: fun_upd_def)

lemmas the_fun_upd_lemmas =
    the_fun_upd_lemma1
    the_fun_upd_lemma2
    the_fun_upd_lemma3
    the_fun_upd_lemma4


(* Used by heap_abs_syntax to simplify signed word updates. *)
lemma sword_update:
"\<And>ptr :: ('a :: len) signed word ptr.
   (\<lambda>(x :: 'a word ptr \<Rightarrow> 'a word) p :: 'a word ptr.
     if ptr_coerce p = ptr then scast (n :: 'a signed word) else x (ptr_coerce p))
    =
   (\<lambda>(old :: 'a word ptr \<Rightarrow> 'a word) x :: 'a word ptr.
     if x = ptr_coerce ptr then scast n else old x)"
  by force

end
