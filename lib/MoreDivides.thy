(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(NICTA_BSD)
 *)

theory MoreDivides
imports "~~/src/HOL/Main"
begin

(* FIXME: to Isabelle lib *)
lemma div_mult_le:
  "(a::nat) div b * b \<le> a"
apply(subgoal_tac "a = a div b * b + a mod b")
 apply arith
apply simp
done


(* FIXME: to Isabelle lib *)
lemma mod_le_dividend:
  "m mod n \<le> (m::nat)"
  by (induct m) (auto simp: mod_Suc)

(* diff_mod_le now also in Num_lemmas.ML *)
(* FIXME: to Isabelle lib? *)
lemma diff_mod_le:
  "\<lbrakk> (a::nat) < d; b dvd d \<rbrakk> \<Longrightarrow> a - a mod b \<le> d - b"
apply(subst mult_div_cancel [symmetric])
apply(clarsimp simp: dvd_def)
apply(case_tac "b = 0")
 apply simp
apply(subgoal_tac "a div b \<le> k - 1")
 prefer 2
 apply(subgoal_tac "a div b < k")
  apply(simp add: less_Suc_eq_le [symmetric])
 apply(subgoal_tac "b * (a div b) < b * ((b * k) div b)")
  apply clarsimp
 apply(subst div_mult_self1_is_m)
  apply arith
 apply(rule le_less_trans)
  apply simp
  apply(subst nat_mult_commute)
  apply(rule div_mult_le)
 apply assumption
apply clarsimp
apply(subgoal_tac "b * (a div b) \<le> b * (k - 1)")
 apply(erule le_trans)
 apply(simp add: diff_mult_distrib2)
apply simp
done

lemma int_div_same_is_1 [simp]:
    "0 < a \<Longrightarrow> ((a :: int) div b = a) = (b = 1)"
  by (metis div_by_1 abs_ge_zero abs_of_pos int_div_less_self neq_iff nonneg1_imp_zdiv_pos_iff zabs_less_one_iff)

lemma nat_div_same_is_1 [simp]:
    "a \<noteq> 0 \<Longrightarrow> ((a :: nat) div b = a) = (b = 1)"
  by (metis div_by_0 div_by_1 div_le_dividend div_less_dividend div_self nat_less_le)

lemma int_div_minus_is_minus1 [simp]:
    "a < 0 \<Longrightarrow> ((a :: int) div b = -a) = (b = -1)"
  by (metis div_minus1_right div_minus_right int_div_same_is_1 minus_minus neg_0_less_iff_less minus_one)

end
