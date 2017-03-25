(* ** License
 * -----------------------------------------------------------------------
 * Copyright 2016--2017 IMDEA Software Institute
 * Copyright 2016--2017 Inria
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * ----------------------------------------------------------------------- *)

(* * Syntax and semantics of the dmasm source language *)

(* ** Imports and settings *)

From mathcomp Require Import ssreflect ssrfun ssrbool ssrnat ssrint ssralg.
From mathcomp Require Import seq tuple finfun.
From mathcomp Require Import choice fintype eqtype div seq zmodp.
Require Import JMeq ZArith Setoid Morphisms.

Require Import word dmasm_utils dmasm_type dmasm_var dmasm_expr.
Require Import memory dmasm_sem dmasm_Ssem dmasm_Ssem_props.
(*Require Import symbolic_expr symbolic_expr_opt.*)

Require Import Utf8.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Inductive mexpr : Type :=
    Mvar : var -> mexpr
  | Mconst : word -> mexpr
  | Mbool : bool -> mexpr
  | Madd : mexpr -> mexpr -> mexpr
  | Mand : mexpr -> mexpr -> mexpr
  | Mget : var -> mexpr -> mexpr.

Fixpoint mexpr_beq (e1 e2: mexpr) :=
  match e1, e2 with
  | Mvar v1, Mvar v2 => v1 == v2
  | Mconst w1, Mconst w2 => w1 == w2
  | Mbool b1, Mbool b2 => b1 == b2
  | Madd e1 f1, Madd e2 f2 => (mexpr_beq e1 e2) && (mexpr_beq f1 f2)
  | Mand e1 f1, Mand e2 f2 => (mexpr_beq e1 e2) && (mexpr_beq f1 f2)
  | Mget v1 e1, Mget v2 e2 => (v1 == v2) && (mexpr_beq e1 e2)
  | _, _ => false
  end.

Lemma mexpr_beq_axiom: Equality.axiom mexpr_beq.
Proof.
  elim=> [v1|v1|v1|e1 He1 f1 Hf1|e1 He1 f1 Hf1|v1 e1 H1] [v2|v2|v2|e2 f2|e2 f2|v2 e2] //=;
  try (apply: (@equivP (v1 = v2)); [exact: eqP|split=> [->|[]->] //]);
  try exact: ReflectF;
  try (apply: (@equivP (mexpr_beq e1 e2 /\ mexpr_beq f1 f2)); [apply/andP|split=> [[H11 H12]|]];
  [apply: (equivP (He1 e2))=> [|//]; split; [|by move=>[] ->];
  by move=> ->; congr (_ _); apply: (equivP (Hf1 f2))|
  move=> [] <- <-; split; [by apply/He1|by apply/Hf1]]).
  apply: (@equivP ((v1 == v2) /\ mexpr_beq e1 e2)); [apply/andP|split].
  move=> [/eqP -> ?].
  apply: (equivP (H1 e2))=> //; split=> [->|[] ->] //.
  by move=> [] <- <-; split; [exact: eq_refl|apply/H1].
Qed.

Definition mexpr_eqMixin := Equality.Mixin mexpr_beq_axiom.
Canonical mexpr_eqType := Eval hnf in EqType mexpr mexpr_eqMixin.

Fixpoint var_in (v: var) (e: mexpr) :=
  match e with
  | Mvar v' => v == v'
  | Madd e1 e2 => (var_in v e1) || (var_in v e2)
  | Mand e1 e2 => (var_in v e1) || (var_in v e2)
  | Mget v' e => (v == v') || (var_in v e)
  | _ => false
  end.

Variant mrval : Type :=
    MRvar : var -> mrval
  | MRaset : var -> mexpr -> mrval.

Definition mrval_beq (x1:mrval) (x2:mrval) :=
  match x1, x2 with
  | MRvar  x1   , MRvar  x2    => x1 == x2
  | MRaset x1 e1, MRaset x2 e2 => (x1 == x2) && (e1 == e2)
  | _          , _           => false
  end.

Lemma mrval_eq_axiom : Equality.axiom mrval_beq.
Proof.
  case=> [v1|v1 e1] [v2|v2 e2] /=; try exact: ReflectF.
  by apply: (@equivP (v1 = v2)); [by apply: eqP|split=> [->|[] ->]].
  by apply: (@equivP ((v1 == v2) /\ (e1 == e2))); [apply/andP|split=> [[] /eqP -> /eqP ->|[] -> ->]].
Qed.

Definition mrval_eqMixin     := Equality.Mixin mrval_eq_axiom.
Canonical  mrval_eqType      := Eval hnf in EqType mrval mrval_eqMixin.

Definition mvrv (rv:mrval) :=
  match rv with
  | MRvar  x    => Sv.singleton x
  | MRaset x _  => Sv.singleton x
  end.

Variant minstr : Type :=
  MCassgn : mrval -> mexpr -> minstr.

Fixpoint minstr_beq i1 i2 :=
  match i1, i2 with
  | MCassgn r1 e1, MCassgn r2 e2 => (r1 == r2) && (e1 == e2)
  end.

Lemma minstr_eq_axiom : Equality.axiom minstr_beq.
Proof.
  case=> [r1 e1] [r2 e2] /=.
  by apply: (@equivP ((r1 == r2) /\ (e1 == e2))); [apply/andP|split=> [[] /eqP -> /eqP ->|[] -> ->]].
Qed.

Definition minstr_eqMixin     := Equality.Mixin minstr_eq_axiom.
Canonical  minstr_eqType      := Eval hnf in EqType minstr minstr_eqMixin.

Notation mcmd := (seq minstr).

Definition var_in_instr (v: var) (i: minstr) :=
  match i with
  | MCassgn _ e => var_in v e
  end.

Definition var_in_cmd (v: var) (c: mcmd) := foldl (fun b i => b || (var_in_instr v i)) false c.

Definition mon_arr_var A (s: svmap) (x: var) (f: positive → FArray.array word → exec A) :=
  match vtype x as t return ssem_t t → exec A with
  | sarr n => f n
  | _ => λ _, type_error
  end  (s.[ x ]%vmap).

Notation "'MLet' ( n , t ) ':=' s '.[' x ']' 'in' body" :=
  (@mon_arr_var _ s x (fun n (t:FArray.array word) => body)) (at level 25, s at level 0).

(*
Lemma mon_arr_varP A (f : forall n : positive, FArray.array word -> exec A) v s x P:
  (forall n t, vtype x = sarr n ->
               sget_var s x = @SVarr n t ->
               f n t = ok v -> P) ->
  mon_arr_var s x f = ok v -> P.
Proof.
  rewrite /mon_arr_var.
  rewrite /sget_var.
  rewrite /mon_arr_var=> H;apply: rbindP => vx.
  rewrite /get_var;case: x H => -[ | | n | ] nx H; apply:rbindP => ? Hnx [] <- //.
  by apply H;rewrite // /get_var Hnx.
Qed.
*)

(* TODO: move *)
Lemma svmap_eq_exceptS vm1 s vm2 : vm1 = vm2 [\s] -> vm2 = vm1 [\s].
Proof. by move=> Heq x Hin;rewrite Heq. Qed.
Lemma svmap_eq_exceptT vm2 s vm1 vm3: vm1 = vm2 [\s] → vm2 = vm3 [\s] → vm1 = vm3 [\s].
Proof. by move=> H1 H2 x Hin;rewrite H1 ?H2. Qed.

Global Instance equiv_svmap_eq_except s: Equivalence (svmap_eq_except s).
Proof.
  constructor=> //.
  move=> ??;apply: svmap_eq_exceptS.
  move=> ???;apply: svmap_eq_exceptT.
Qed.

Fixpoint msem_mexpr (s: svmap) (e: mexpr) : exec svalue :=
  match e with
  | Mvar v => ok (sget_var s v)
  | Mbool b => ok (SVbool b)
  | Mconst z => ok (SVword z)
  | Madd e1 e2 =>
    Let x1 := msem_mexpr s e1 in
    Let x2 := msem_mexpr s e2 in
    Let i1 := sto_word x1 in
    Let i2 := sto_word x2 in
    ok (SVword (I64.add i1 i2))
  | Mand e1 e2 =>
    Let x1 := msem_mexpr s e1 in
    Let x2 := msem_mexpr s e2 in
    Let i1 := sto_bool x1 in
    Let i2 := sto_bool x2 in
    ok (SVbool (andb i1 i2))
  | Mget x e =>
    MLet (n,t) := s.[x] in
    Let i := msem_mexpr s e >>= sto_word in
    ok (SVword (FArray.get t i))
  end.

Lemma var_in_eq x e s s': ¬ var_in x e ->
  s = s' [\Sv.singleton x] ->
  msem_mexpr s e = msem_mexpr s' e.
Proof.
  elim: e=> [v|w|b|e1 He1 e2 He2|e1 He1 e2 He2|x' e He] //= Hin Hss'.
  + rewrite /sget_var.
    suff ->: s.[v]%vmap = s'.[v]%vmap=> //.
    apply: Hss'.
    move=> Habs.
    move: (SvD.F.singleton_1 Habs)=> H'.
    by rewrite H' in Hin.
  + rewrite He1 ?He2 //.
    move=> Habs.
    apply: Hin.
    by rewrite Habs orbT.
    move=> Habs.
    apply: Hin.
    by rewrite Habs.
  + rewrite He1 ?He2 //.
    move=> Habs.
    apply: Hin.
    by rewrite Habs orbT.
    move=> Habs.
    apply: Hin.
    by rewrite Habs.
  + rewrite He.
    rewrite /mon_arr_var.
    suff ->: s.[x']%vmap = s'.[x']%vmap=> //.
    apply: Hss'.
    move=> Habs.
    move: (SvD.F.singleton_1 Habs)=> H'.
    by rewrite H' eq_refl in Hin.
    move=> Habs.
    by rewrite Habs orbT in Hin.
    by [].
Qed.

Definition mwrite_rval (l: mrval) (v: svalue) (s: svmap) : exec svmap :=
  match l with
  | MRvar x => sset_var s x v
  | MRaset x i =>
    MLet (n,t) := s.[x] in
    Let i := msem_mexpr s i >>= sto_word in
    Let v := sto_word v in
    let t := FArray.set t i v in
    sset_var s x (@to_sval (sarr n) t)
  end.

Lemma mvrvP: ∀ (x : mrval) (v : svalue) (s1 s2 : svmap), mwrite_rval x v s1 = ok s2 → s1 = s2 [\mvrv x].
Proof.
  case=> [x|x e] v s1 s2.
  + rewrite /= /sset_var.
    apply: rbindP=> sv Hsv [] <- z Hz.
    rewrite Fv.setP_neq=> //.
    apply/eqP; SvD.fsetdec.
  + rewrite /=.
    admit.
Admitted.

Inductive msem : svmap -> mcmd -> svmap -> Prop :=
    MEskip : forall s : svmap, msem s [::] s
  | MEseq : forall (s1 s2 s3 : svmap) (i : minstr) (c : mcmd),
           msem_I s1 i s2 -> msem s2 c s3 -> msem s1 (i :: c) s3
  with msem_I : svmap -> minstr -> svmap -> Prop :=
  | MEassgn : forall (s1 s2 : svmap) (r : mrval) (e : mexpr),
    Let v := msem_mexpr s1 e in mwrite_rval r v s1 = ok s2 ->
    msem_I s1 (MCassgn r e) s2.

Lemma msem_inv s c s' :
  msem s c s' →
  match c with
  | [::] => s' = s
  | i :: c' => ∃ s1, msem_I s i s1 ∧ msem s1 c' s'
end.
Proof. by case; eauto. Qed.

Lemma msem_I_inv s i s' :
  msem_I s i s' →
  match i with
  | MCassgn r e => ∃ v, msem_mexpr s e = ok v ∧ mwrite_rval r v s = ok s'
  end.
Proof.
  by case=> s1 s2 x e H; case: (bindW H); eauto.
Qed.

Lemma msem_cat_inv s c1 c2 s': msem s (c1 ++ c2) s' -> exists s1, msem s c1 s1 /\ msem s1 c2 s'.
Proof.
elim: c1 s=> [|a l IH] s /=.
+ exists s; split=> //; exact: MEskip.
+ move=> /msem_inv [s1 [Hi Hc]].
  move: (IH _ Hc)=> [s2 [Hc1 Hc2]].
  exists s2; split=> //.
  apply: MEseq; [exact: Hi|exact: Hc1].
Qed.

Lemma msem_I_det s s1 s2 i: msem_I s i s1 -> msem_I s i s2 -> s1 = s2.
Proof.
  case: i=> r e.
  move=> /msem_I_inv [v1 [Hv1 Hr1]].
  move=> /msem_I_inv [v2 []].
  rewrite {}Hv1 => -[] <-.
  by rewrite Hr1=> -[] <-.
Qed.

(*
 * Define the trace of instructions
 *)

Module Trace.
Definition trace := seq (exec word).

Fixpoint trace_expr (s: svmap) (e: mexpr) : trace :=
  match e with
  | Mvar v => [::]
  | Mbool b => [::]
  | Mconst z => [::]
  | Madd e1 e2 => (trace_expr s e1) ++ (trace_expr s e2)
  | Mand e1 e2 => (trace_expr s e1) ++ (trace_expr s e2)
  | Mget x e => [:: msem_mexpr s e >>= sto_word]
  end.

Lemma size_trace_expr e s1 s2:
  size (trace_expr s1 e) = size (trace_expr s2 e).
Proof.
  elim: e=> // e1 H1 e2 H2 /=; by rewrite !size_cat H1 H2.
Qed.

Definition trace_instr (s: svmap) (c: minstr) : trace :=
  match c with
  | MCassgn _ e => trace_expr s e
  end.

Lemma size_trace_instr a s1 s2:
  size (trace_instr s1 a) = size (trace_instr s2 a).
Proof.
  case: a=> e r; exact: size_trace_expr.
Qed.

End Trace.

Import Trace.

(*
 * Definition 1/4: use a fixpoint
 *)
Module Leakage_Fix.
Fixpoint leakage_fix (s: svmap) (c: mcmd) (s': svmap) (p: msem s c s') {struct p} : trace.
  refine
  (match c as c0 return c = c0 -> trace with
  | [::] => fun _ => [::]
  | i :: c' => fun (Hc: c = i::c') =>
    (trace_instr s i) ++
    (match i as i0 return i = i0 -> trace with
    | MCassgn r e => fun (Hi: i = MCassgn r e) =>
      match msem_mexpr s e as e0 return msem_mexpr s e = e0 -> trace with
      | Ok v => fun (He : msem_mexpr s e = ok v) =>
        match mwrite_rval r v s as s0 return mwrite_rval r v s = s0 -> trace with
        | Ok s1 => fun (Hs: mwrite_rval r v s = ok s1) => (leakage_fix s1 c' s' _)
        | Error err => _
        end (erefl _)
      | Error err => _
      end (erefl _)
    end (erefl _))
  end (erefl _)).
  + case: p Hc He Hs;first by done.
    move=> s0 s2 s3 i0 c0 H1 H2 H.
    move: H H1 H2 => [-> ->] H1.
    case: H1 Hi => ???? H Heq.
    move: Heq H=> [-> ->] H1 H2 H3 H4.
    move: H1;rewrite H3 /= H4 => -[->];exact H2.
  + by move=> _;exact [::].
  by move=> _;exact [::].
Defined.
End Leakage_Fix.

(*
 * Definition 2/4: put the trace in Prop to make it simpler
 *)
Module Leakage_Ex.
Variant trace : Prop :=
  ExT : Trace.trace -> trace.

Definition trace_cat t1 t2 :=
  match t1 with
  | ExT s1 =>
    match t2 with
    | ExT s2 => ExT (s1 ++ s2)
    end
  end.

Definition trace_cons l t :=
  match t with
  | ExT s => ExT (l :: s)
  end.

Definition leakage (s: svmap) (c: mcmd) (s': svmap) (p: msem s c s') : trace.
Proof.
  elim: c s p=> [s H|i c H s].
  exact (ExT [::]).
  move => /msem_inv [s1 [Hi /H [] q]].
  exact (ExT ((trace_instr s i) ++ q)).
Defined.

Lemma leakage_irr (s: svmap) (c: mcmd) (s': svmap) (p: msem s c s') (p': msem s c s'):
  leakage p = leakage p'.
Proof.
  elim: c s p p'=> [p p'|a l IH s p p'].
  by rewrite /leakage /=.
  rewrite /leakage /=.
  move: p=> /msem_inv [s1 [Hi1 Hc1]].
  move: p'=> /msem_inv [s2 [Hi2 Hc2]].
  move: (msem_I_det Hi1 Hi2)=> H.
  move: Hi1 Hi2 Hc1 Hc2.
  case: _ / H=> _ Hi Hc1 Hc2.
  move: (IH _ Hc1 Hc2).
  rewrite /leakage /==> -> //.
Qed.

Lemma leakage_cat s c1 c2 s' (p: msem s (c1 ++ c2) s'):
  exists s1 p' p'',
  @leakage s (c1 ++ c2) s' p = trace_cat (@leakage s c1 s1 p') (@leakage s1 c2 s' p'').
Proof.
  move: (msem_cat_inv p)=> [s1 [p' p'']].
  exists s1; exists p'; exists p''.
  elim: c1 s p p'=> /= [s p p'|a l IH s p p'].
  move: p'=> /msem_inv H.
  move: p p''.
  case: _ / H=> p p''.
  rewrite (leakage_irr p p'') //.
  case: (leakage p'')=> //.
  move: p=> /msem_inv [s2 [Hs2 Hs2']].
  move: p'=> /msem_inv [s3 [Hs3 Hs3']].
  move: (msem_I_det Hs2 Hs3)=> Hs.
  move: Hs2 Hs2' Hs3 Hs3'.
  case: _ / Hs=> _ Hs2' _ Hs3'.
  rewrite (IH _ Hs2' Hs3').
  case: (leakage Hs3')=> // t.
  rewrite /trace_cat /=.
  case: (leakage p'')=> // v.
  by rewrite catA.
Qed.
End Leakage_Ex.

(*
 * Definition 3/4: instrumented big step semantics
 *)
Module Leakage_Instr.
  Inductive mtsem : svmap -> mcmd -> Trace.trace -> svmap -> Prop :=
    MTEskip : forall s : svmap, mtsem s [::] [::] s
  | MTEseq : forall (s1 s2 s3 : svmap) (i : minstr) (c : mcmd) (t: trace),
           mtsem_I s1 i s2 -> mtsem s2 c t s3 -> mtsem s1 (i :: c) ((trace_instr s1 i) ++ t) s3
  with mtsem_I : svmap -> minstr -> svmap -> Prop :=
  | MTEassgn : forall (s1 s2 : svmap) (r : mrval) (e : mexpr),
    Let v := msem_mexpr s1 e in mwrite_rval r v s1 = ok s2 ->
    mtsem_I s1 (MCassgn r e) s2.

  Lemma mtsem_inv s c t s' :
    mtsem s c t s' →
    match c with
    | [::] => s' = s /\ t = [::]
    | i :: c' => ∃ s1 t1, mtsem_I s i s1 ∧ mtsem s1 c' t1 s' /\ t = (trace_instr s i) ++ t1
  end.
  Proof. by case; eauto. Qed.

  Lemma mtsem_I_inv s i s' :
    mtsem_I s i s' →
    match i with
    | MCassgn r e => ∃ v, msem_mexpr s e = ok v ∧ mwrite_rval r v s = ok s'
    end.
  Proof.
    by case=> s1 s2 x e H; case: (bindW H); eauto.
  Qed.

  Lemma mtsem_cat_inv s c1 c2 s' t: mtsem s (c1 ++ c2) t s' ->
    exists s1 t1 t2, mtsem s c1 t1 s1 /\ mtsem s1 c2 t2 s' /\ t = t1 ++ t2.
  Proof.
  elim: c1 t s=> [|a l IH] t s /=.
  + exists s; exists [::]; exists t; split=> //; exact: MTEskip.
  + move=> /mtsem_inv [s1 [t1 [Hi [Hc Ht]]]].
    move: (IH _ _ Hc)=> [s2 [t2 [t3 [Hc1 [Hc2 Ht2]]]]].
    exists s2; exists (trace_instr s a ++ t2); exists t3; split.
    apply: MTEseq; [exact: Hi|exact: Hc1].
    split=> //.
    by rewrite Ht Ht2 catA.
  Qed.
End Leakage_Instr.

(*
 * Definition 4/4: using small step semantics (two possibilities?)
 *)
Module Leakage_Smallstep.
  Definition state := (svmap * mcmd)%type.

  Variant outcome :=
  | Next : exec state -> outcome.

  Definition step_instr (s: svmap) (i: minstr) :=
    match i with
    | MCassgn r e =>
      Let v := msem_mexpr s e in
      Let s' := mwrite_rval r v s in
      ok s'
    end.

  Definition step (s: state) : outcome :=
    match s with
    | (m, [::]) => Next (ok s)
    | (m, h :: q) =>
      Next (Let m' := step_instr m h in ok (m', q))
    end.

  Definition finished (s: state) := (s.2 == [::]).

  Fixpoint stepn n (s: state) : outcome :=
    match n with
    | 0 => Next (ok s)
    | n'.+1 =>
      match (step s) with
      | Next (Ok v) => stepn n' v
      | e => e
      end
    end.

  Definition stepR (a b: state) : Prop := step a = Next (ok b).

  Definition stepRn n (a b: state) := stepn n a = Next (ok b).

  Definition exec (s: svmap) (c: mcmd) (s': svmap) :=
    exists n, stepRn n (s, c) (s', [::]).

  Lemma eq_step1 s s' i:
    msem_I s i s' -> step_instr s i = ok s'.
  Proof.
    case: i=> r e /=.
    by move=> /msem_I_inv [v [-> /= -> /=]].
  Qed.

  Lemma eq_step2 s s' i:
    step_instr s i = ok s' -> msem_I s i s'.
  Proof.
    case: i=> r e /= H.
    apply: MEassgn; move: H.
    apply: rbindP=> v -> /=.
    by apply: rbindP=> w -> ->.
  Qed.

  Lemma eq_bigstep1 s s' c: msem s c s' -> exec s c s'.
  Proof.
    rewrite /exec.
    elim; clear.
    move=> s; exists 42=> //.
    move=> s1 s2 s3 i c Hi Hsem [n Hn].
    exists n.+1.
    rewrite /stepRn /=.
    rewrite (eq_step1 Hi) /=.
    exact: Hn.
  Qed.

  Lemma eq_bigstep2 s s' c: exec s c s' -> msem s c s'.
  Proof.
    elim: c s=> [|a l IH] s [n Hn].
    have ->: s = s'.
      elim: n Hn=> //=.
      by rewrite /stepRn /stepn=> -[] ->.
    exact: MEskip.
    case: n Hn=> // n Hn.
    rewrite /stepRn /= in Hn.
    case Heq: (Let m' := step_instr s a in ok (m', l)) Hn=> [m'|] //=.
    case: (bindW Heq)=> m Hm [] <- Hstep.
    apply: MEseq; [apply: eq_step2; exact: Hm|apply: IH; exists n; exact: Hstep].
  Qed.

  Theorem eq_bigstep : forall s s' c, msem s c s' <-> exec s c s'.
  Proof.
    split; [exact: eq_bigstep1|exact: eq_bigstep2].
  Qed.

  Definition leak_step (s: state) : outcome * trace :=
    match s with
    | (m, [::]) => (step s, [::])
    | (m, h :: q) => (step s, trace_instr m h)
    end.

  Fixpoint leak_stepn n (s: state) : outcome * trace :=
    match n with
    | 0 => (Next (ok s), [::])
    | n'.+1 =>
      match (leak_step s) with
      | (Next (Ok v), t) => let res := leak_stepn n' v in (res.1, res.2 ++ t)
      | e => e
      end
    end.

  Fixpoint leak_stepn' n (s: state) : outcome * trace :=
    match n with
    | 0 => (Next (ok s), [::])
    | n'.+1 =>
      match (leak_stepn' n' s) with
      | (Next (Ok v), t) => let res := leak_step v in (res.1, res.2 ++ t)
      | e => e
      end
    end.

  Lemma leak_step_fromend n s:
    leak_stepn n s = leak_stepn' n s.
  Proof.
    elim: n s=> //= n IH s.
    rewrite -{}IH.
    elim: n s=> //= [|n IH] s.
    + case: (leak_step s); case; case=> // a b.
      by rewrite /= cats0.
      by rewrite /= cats0.
    + case: (leak_step s); case; case=> // a b.
      rewrite IH.
      case: (leak_stepn n a); case; case=> // a0 b0.
      by rewrite /= catA.
  Qed.

  Definition leak_stepRn n t (a b: state) := leak_stepn n a = (Next (ok b), t).

  Definition leakage (s: svmap) (c: mcmd) (t: trace) (s': svmap) :=
    exists n, leak_stepRn n t (s, c) (s', [::]).

  Lemma leak_stepn_end_next s c s' n t:
    leak_stepn n (s, c) = (Next (ok (s', [::])), t) ->
    leak_stepn n.+1 (s, c) = (Next (ok (s', [::])), t).
  Proof.
    move=> H.
    by rewrite leak_step_fromend /= -leak_step_fromend H /=.
  Qed.

  Lemma leak_stepn_end_cont s c s' n n' t:
    n <= n' ->
    leak_stepn n (s, c) = (Next (ok (s', [::])), t) ->
    leak_stepn n' (s, c) = (Next (ok (s', [::])), t).
  Proof.
    move=> Hn.
    have ->: n' = n + (n' - n).
      by rewrite subnKC.
    move: (n' - n)=> d {Hn} {n'}.
    elim: d=> /=.
    + by rewrite addn0.
    + move=> d IH H.
      rewrite addnS.
      apply: leak_stepn_end_next.
      exact: IH.
  Qed.

  Lemma leak_stepn_err_next s c e n t:
    leak_stepn n (s, c) = (Next (Error e), t) ->
    leak_stepn n.+1 (s, c) = (Next (Error e), t).
  Proof.
    move=> H.
    by rewrite leak_step_fromend /= -leak_step_fromend H.
  Qed.

  Lemma leak_stepn_err_cont s c e n n' t:
    n <= n' ->
    leak_stepn n (s, c) = (Next (Error e), t) ->
    leak_stepn n' (s, c) = (Next (Error e), t).
  Proof.
    move=> Hn.
    have ->: n' = n + (n' - n).
      by rewrite subnKC.
    move: (n' - n)=> d {Hn} {n'}.
    elim: d=> /=.
    + by rewrite addn0.
    + move=> d IH H.
      rewrite addnS.
      apply: leak_stepn_err_next.
      exact: IH.
  Qed.

  Lemma leak_stepn_end n s:
    leak_stepn n (s, [::]) = (Next (ok (s, [::])), [::]).
  Proof.
    elim: n=> // n IH.
    by rewrite /= !IH.
  Qed.

  Lemma leakage_cat_inv' s c1 c2 s' t n: leak_stepRn n t (s, (c1 ++ c2)) (s', [::]) ->
    exists s1 t1 t2 n1 n2, leak_stepRn n1 t1 (s, c1) (s1, [::]) /\
                           leak_stepRn n2 t2 (s1, c2) (s', [::]) /\ t = t2 ++ t1.
  Proof.
    elim: c1 n t s=> //= [|a l IH] n t s H.
    + exists s, [::], t, 0, n=> //.
      by rewrite cats0.
    + move: H=> /leak_stepn_end_cont.
      move=> /(_ n.+1 (leqnSn n)) /= H.
      case Hstep: (step_instr s a) H=> [m' /=|//] H.
      rewrite {1}/leak_stepRn in IH.
      case: H=> H1 H2.
      have H': leak_stepn n (m', l ++ c2) = (Next (ok (s', [::])), (leak_stepn n (m', l ++ c2)).2).
        by case: (leak_stepn n (m', l ++ c2)) H1=> a0 b /= ->.
      move: (IH _ _ _ H')=> [s1 [t1 [t2 [n1 [n2 [H1' [H2' Ht]]]]]]].
      exists s1, (t1 ++ trace_instr s a), t2, n1.+1, n2; repeat split=> //.
      rewrite /leak_stepRn /= Hstep /=.
      rewrite /leak_stepRn /= in H1'.
      by move: H1' ->.
      rewrite Ht in H2.
      by rewrite -H2 catA.
  Qed.

  Lemma leakage_cat_inv s c1 c2 s' t: leakage s (c1 ++ c2) t s' ->
    exists s1 t1 t2, leakage s c1 t1 s1 /\ leakage s1 c2 t2 s' /\ t = t2 ++ t1.
  Proof.
    rewrite /leakage=> -[n Hn].
    move: (leakage_cat_inv' Hn)=> [s1 [t1 [t2 [n1 [n2 [H1 [H2 Ht]]]]]]].
    exists s1, t1, t2; repeat split; [exists n1|exists n2|]=> //.
  Qed.

  Lemma leakage_cat' s1 s2 s3 n1 n2 c1 c2 t1 t2:
    leak_stepRn n1 t1 (s1, c1) (s2, [::]) -> leak_stepRn n2 t2 (s2, c2) (s3, [::]) ->
    leak_stepRn (n1 + n2) (t2 ++ t1) (s1, c1 ++ c2) (s3, [::]).
  Proof.
    elim: c1 t1 s1 n1=> /= [|a l IH] t1 s1 n1 H1 H2.
    + rewrite /leak_stepRn leak_stepn_end in H1.
      move: H1=> -[] -> <-.
      rewrite cats0.
      apply: leak_stepn_end_cont; last by exact: H2.
      exact: leq_addl.
    + have Hn1: n1 = n1.-1.+1.
        rewrite prednK //.
        case: n1 H1 IH=> [|n1] H1 _=> //.
      rewrite Hn1 /leak_stepRn /= in H1.
      case Hstep: (step_instr s1 a) H1=> [m' /=|//] H1.
      case: H1=> H11 H12.
      have H1': leak_stepn n1.-1 (m', l) = (Next (ok (s2, [::])), (leak_stepn n1.-1 (m', l)).2).
        by case: (leak_stepn _ _) H11=> a0 b /= ->.
      move: (IH _ _ _ H1' H2)=> IH'.
      rewrite /leak_stepRn in IH'.
      rewrite Hn1 /leak_stepRn /= Hstep /=.
      by rewrite IH' /= -H12 catA.
  Qed.

  Lemma leakage_cat s1 s2 s3 c1 c2 t1 t2: leakage s1 c1 t1 s2 -> leakage s2 c2 t2 s3 ->
    leakage s1 (c1 ++ c2) (t2 ++ t1) s3.
  Proof.
    move=> [n1 Hn1] [n2 Hn2].
    exists (n1 + n2).
    apply: leakage_cat'.
    exact: Hn1.
    exact: Hn2.
  Qed.

  Lemma stepn_leak_same n s c: exists t',
    leak_stepn n (s, c) = (stepn n (s, c), t').
  Proof.
    elim: n s c=> /= [|n IH] s c.
    + exists [::]=> //.
    + case: c IH=> // [|a l] IH.
      + rewrite cats0.
        move: (IH s [::])=> [t' Ht'].
        exists t'.
        rewrite -Ht'.
        by case: (leak_stepn _ _).
      + case Heq: (step_instr s a)=> [m'|e] /=.
        move: (IH m' l)=> [t' Ht'].
        exists (t' ++ trace_instr s a).
        by rewrite Ht' /=.
        exists (trace_instr s a)=> //.
  Qed.

  Lemma leak_imp_exec s c t s':
    leakage s c t s' -> exec s c s'.
  Proof.
    move=> [n Hn].
    exists n.
    move: (stepn_leak_same n s c)=> [t' Ht'].
    rewrite /leak_stepRn Ht' in Hn.
    rewrite /stepRn.
    by move: Hn=> [] -> _.
  Qed.

  Lemma exec_imp_leak s c s':
    exec s c s' -> exists t, leakage s c t s'.
  Proof.
    move=> [n Hn].
    move: (stepn_leak_same n s c)=> [t Ht].
    exists t.
    exists n.
    rewrite /leak_stepRn Ht Hn //.
  Qed.

  Lemma exec_leak_same s c t s1 s2:
    exec s c s1 -> leakage s c t s2 -> s1 = s2.
  Proof.
    move=> [n Hn] [n' Hn'].
    rewrite /stepRn in Hn.
    rewrite /leak_stepRn in Hn'.
    rewrite /exec /leakage.
    move: (stepn_leak_same n s c)=> [t' Ht'].
    rewrite Hn in Ht'.
    case: (leqP n' n).
    + move=> Hw.
      rewrite (leak_stepn_end_cont Hw Hn') in Ht'.
      by move: Ht'=> [] ->.
    + move=> /ltnW Hw.
      rewrite (leak_stepn_end_cont Hw Ht') in Hn'.
      by move: Hn'=> [] ->.
  Qed.

  Lemma exec_cat_inv s c1 c2 s': exec s (c1 ++ c2) s' ->
    exists s1, exec s c1 s1 /\ exec s1 c2 s'.
  Proof.
    move=> /exec_imp_leak [t /leakage_cat_inv [s1 [_ [_ [/leak_imp_exec ? [/leak_imp_exec ? _]]]]]].
    by exists s1.
  Qed.

  Lemma leakage_instr_inv s s' a t:
    leakage s [:: a] t s' -> t = (trace_instr s a) /\ step_instr s a = ok s'.
  Proof.
    move=> [n Hn].
    have := (leak_stepn_end_cont _ Hn).
    move=> /(_ n.+1 (ltnW (ltnSn n))) /=.
    case Hstep: (step_instr s a)=> [v /=|//].
    rewrite leak_stepn_end /=.
    by move=> [] <- <-.
  Qed.

  Lemma leakage_instr s s' a t:
    t = (trace_instr s a) -> step_instr s a = ok s' -> leakage s [:: a] t s'.
  Proof.
    move=> Ht Hs.
    exists 1.
    by rewrite /leak_stepRn /= Hs /= Ht.
  Qed.

  Lemma leakage_next s s' s'' l a t:
    leakage s l t s' -> exec s (l ++ [:: a]) s'' ->
    leakage s (l ++ [:: a]) (trace_instr s' a ++ t) s''.
  Proof.
    move=> Hl Hsem.
    apply: leakage_cat.
    exact: Hl.
    apply: leakage_instr=> //.
    move: Hsem=> /exec_cat_inv [s1 [Hs1 Hs1']].
    have Heq := (exec_leak_same Hs1 Hl).
    rewrite {}Heq in Hs1, Hs1'.
    move: Hs1'=> /exec_imp_leak [t_ Hs1'].
    by move: Hs1'=> /leakage_instr_inv [_ ->].
  Qed.
End Leakage_Smallstep.

(*
 * Define the constant time property (here, associated with Leakage_Ex)
 *)

Definition seq_on (s : Sv.t) (vm1 vm2 : svmap) :=
  forall x, Sv.In x s -> vm1.[x]%vmap = vm2.[x]%vmap.

Section ConstantTime.
  Variable P: prog.

  Definition is_pub (v: var_i) := (var_info_to_attr v.(v_info)).(va_pub).

  Definition pub_vars vars : Sv.t :=
    foldl (fun s v => if (is_pub v) then (Sv.add v s) else s) Sv.empty vars.

  Definition same_pubs s s' := forall f, f \in P -> seq_on (pub_vars f.2.(f_params)) s s'.

  Definition constant_time_ex c :=
    forall s1 s2 s1' s2' H H', same_pubs s1 s2 ->
      @Leakage_Ex.leakage s1 c s1' H = @Leakage_Ex.leakage s2 c s2' H'.

  Definition constant_time_instr c :=
    forall s1 s2 s1' s2' t1 t2, same_pubs s1 s2 ->
      Leakage_Instr.mtsem s1 c t1 s1' -> Leakage_Instr.mtsem s2 c t2 s2' -> t1 = t2.

  Definition constant_time_ss c :=
    forall s1 s2 s1' s2' t1 t2, same_pubs s1 s2 ->
      Leakage_Smallstep.leakage s1 c t1 s1' -> Leakage_Smallstep.leakage s2 c t2 s2' -> t1 = t2.
End ConstantTime.

Module ArrAlloc.
  Variable glob_arr : var.

  Definition glob_acc_l s := MRaset glob_arr (Mconst (I64.repr s)).
  Definition glob_acc_r s := Mget glob_arr (Mconst (I64.repr s)).

  Fixpoint arralloc_e (e:mexpr) (st: Z) : mcmd :=
    match e with
    | Madd e1 e2 => (arralloc_e e1 (st * 3 + 0)) ++ (arralloc_e e2 (st * 3 + 1))
                 ++ [:: MCassgn (glob_acc_l (st * 3 + 2)) (Madd (glob_acc_r (st * 3 + 0)) (glob_acc_r (st * 3 + 1)))]
    | Mand e1 e2 => (arralloc_e e1 (st * 3 + 0)) ++ (arralloc_e e2 (st * 3 + 1))
                 ++ [:: MCassgn (glob_acc_l (st * 3 + 2)) (Mand (glob_acc_r (st * 3 + 0)) (glob_acc_r (st * 3 + 1)))]
    | _ => [:: MCassgn (glob_acc_l st) e]
    end.

  Fixpoint arralloc_i (i:minstr) : mcmd :=
    match i with
    | MCassgn x e => (arralloc_e e 0) ++ [:: MCassgn x (glob_acc_r 0)]
    end.

  Definition arralloc_cmd (c:mcmd) : mcmd :=
    foldr (fun i c' => arralloc_i i ++ c') [::] c.

  Lemma arralloc_cat (c1 c2: mcmd) :
    arralloc_cmd (c1 ++ c2) = (arralloc_cmd c1) ++ (arralloc_cmd c2).
  Proof.
    elim: c1=> // a l IH /=.
    by rewrite IH catA.
  Qed.

  Variable P: prog.

  (*
   * Try with Leakage_Ex
   *)
  (*
  Module Ex_Proof.
  Import Leakage_Ex.
  Lemma arralloc_i_ct i:
    constant_time_ex P [:: i]
    -> constant_time_ex P (arralloc_i i).
  Proof.
    case: i=> r e Hsrc /=.
    elim: e Hsrc=> /= [v|w|b|e1 IH1 e2 IH2| |] Hsrc; try (
    move=> s1 s2 s1' s2' H H' Hpub;
    rewrite /leakage /=;
    move: H=> /msem_inv [s1'' [Hi1 /msem_inv [s1''' [Hc1 Hskip1]]]];
    move: H'=> /msem_inv [s2'' [Hi2 /msem_inv [s2''' [Hc2 Hskip2]]]] //).
    move=> s1 s2 s1' s2' H H' Hpub.
    rewrite /leakage /=.
    move: H=> /msem_inv [s1'' [Hi1 Hc1]] /=.
    move: H'=> /msem_inv [s2'' [Hi2 Hc2]] /=.
    move: (leakage_cat Hc2)=> [s2''' [p' [p'' H2]]].
  Admitted.

  Lemma ct_head a l:
    constant_time_ex P (a :: l)
    -> constant_time_ex P [:: a].
  Proof.
    elim: l=> // a' l IH H.
    apply: IH.
    move=> s1 s2 s1' s2' H1 H2 Hpub.
    rewrite /constant_time_ex in H.
  Admitted.

  Theorem preserve_ct: forall c,
    constant_time_ex P c
    -> constant_time_ex P (arralloc_cmd c).
  Proof.
    elim=> // a l IH Hsrc.
    rewrite /=.
    move=> s1 s2 s1' s2' H H' Hpub.
    move: (leakage_cat H)=> [s1'' [p'1 [p''1 ->]]].
    move: (leakage_cat H')=> [s2'' [p'2 [p''2 ->]]].
    congr (trace_cat _ _).
    apply: arralloc_i_ct=> //.

    move=> s1'0 s2'0 s1'1 s2'1 H0 H'0 Hpub'.

    rewrite /leakage /=.
    move: H0=> /msem_inv [s1'2 [Hs1'2 Hskip1]].
    rewrite /=.
  Admitted.
  End Ex_Proof.
  *)

  (*
  Module Instr_Proof.
  Import Leakage_Instr.
  Lemma arralloc_i_ct i:
    constant_time_instr P [:: i]
    -> constant_time_instr P (arralloc_i i).
  Proof.
    case: i=> r e Hsrc /=.
    elim: e Hsrc=> /= [v|w|b|e1 IH1 e2 IH2| |] Hsrc; try (
    move=> s1 s2 s1' s2' t1 t2 Hpub;
    move=> /mtsem_inv /= [s1_1 [t1_1 [Hi1 [Hc1 Ht1]]]];
    move: Hc1=> /mtsem_inv /= [s1_2 [t1_2 [Hi1' [Hc1 Ht1']]]];
    rewrite -{}Ht1' in Hc1;
    move: Hc1=> /mtsem_inv [_ Ht1'2];
    rewrite {}Ht1'2 in Ht1;
    move=> /mtsem_inv /= [s2_1 [t2_1 [Hi2 [Hc2 Ht2]]]];
    move: Hc2=> /mtsem_inv /= [s2_2 [t2_2 [Hi2' [Hc2 Ht2']]]];
    rewrite -{}Ht2' in Hc2;
    move: Hc2=> /mtsem_inv [_ Ht2'2];
    rewrite {}Ht2'2 in Ht2;
    by rewrite Ht2 Ht1).
    move=> s1 s2 s1' s2' t1 t2 Hpub.
    admit. (* Annoying! *)
  Admitted.

  Lemma ct_head a l:
    (forall s, exists s' t, mtsem s (l ++ [:: a]) t s') ->
    constant_time_instr P (l ++ [:: a]) -> constant_time_instr P l.
  Proof.
    move=> Hsem H s1 s2 s1' s2' t1 t2 Hpub H1 H2.
    rewrite /constant_time_instr in H.
    move: (Hsem s1)=> [s1'' [t1' Hs1]].
    move: (Hsem s2)=> [s2'' [t2' Hs2]].
    move: H=> /(_ _ _ _ _ _ _ Hpub Hs1 Hs2) H.
    move: Hs1=> /mtsem_cat_inv [s1'_ [t1_ [t1'' [Hc1 [Hi1 Ht1]]]]].
    move: Hi1=> /mtsem_inv [s1''_ [t1'_ [Hi1 [Hskip1 Ht1'_]]]].
    move: Hs2=> /mtsem_cat_inv [s2'_ [t2_ [t2'' [Hc2 [Hi2 Ht2]]]]].
    move: Hi2=> /mtsem_inv [s2''_ [t2'_ [Hi2 [Hskip2 Ht2'_]]]].
    have: t1_ = t2_.
      rewrite {}Ht2'_ in Ht2.
      rewrite {}Ht1'_ in Ht1.
      rewrite {}Ht2 {}Ht1 in H.
  Admitted.

  Theorem preserve_ct: forall c,
    constant_time_instr P c
    -> constant_time_instr P (arralloc_cmd c).
  Proof.
    elim/List.rev_ind=> // a l IH Hsrc.
    rewrite arralloc_cat.
    move=> s1 s2 s1' s2' t1 t2 Hpub.
    move=> /mtsem_cat_inv [s1'' [t1_1 [t1_2 [Hc1 [/= Hi1 ->]]]]].
    rewrite cats0 in Hi1.
    move=> /mtsem_cat_inv [s2'' [t2_1 [t2_2 [Hc2 [/= Hi2 ->]]]]].
    rewrite cats0 in Hi2.
    congr (_ ++ _).
    have Hl: constant_time_instr P l.
      apply: (ct_head _ Hsrc).
      admit.
    exact: (IH Hl _ _ _ _ _ _ Hpub Hc1 Hc2).
    case: a Hsrc Hi1 Hi2=> r e Hsrc /= Hi1 Hi2.
    move: Hi1=> /mtsem_inv [s1_3 [t1_3 [Hi1 [Hc1' ->]]]].
    move: Hi2=> /mtsem_inv [s2_3 [t2_3 [Hi2 [Hc2' ->]]]].
    rewrite /=.
    congr (_ :: _).
    admit.
  Admitted.
  End Instr_Proof.
  *)

  Module Smallstep_Proof.
  Import Leakage_Smallstep.

  Lemma correct c s s'1 s'2:
    exec s c s'1 ->
    exec s (arralloc_cmd c) s'2 ->
    s'1 = s'2 [\Sv.singleton glob_arr].
  Admitted.

  Lemma correct_e' e n s s': exec s (arralloc_e e n) s' -> s = s' [\ Sv.singleton glob_arr].
  Proof.
  Admitted.

  Lemma preserve_ct_expr e n s_1 s_2 s1 s2:
    ~ var_in glob_arr e ->
    s_1 = s1 [\ Sv.singleton glob_arr] → s_2 = s2 [\ Sv.singleton glob_arr] →
    (trace_expr s_1 e = trace_expr s_2 e) →
    forall s1' s2' t1 t2, leakage s1 (arralloc_e e n) t1 s1' → leakage s2 (arralloc_e e n) t2 s2' → t1 = t2.
  Proof.
    elim: e n s_1 s_2 s1 s2=> [v|w|b|e1 He1 e2 He2|e1 He1 e2 He2|v e He] n s_1 s_2 s1 s2 Hglob Hs1 Hs2 Hts1s2 s1' s2' t1 t2 H1 H2; try (
      move: H1=> /leakage_instr_inv [-> _];
      by move: H2=> /leakage_instr_inv [-> _]).
    (***)
    move: H1=> /= /leakage_cat_inv [s11 [t11 [t11' [H11 [H1 ->]]]]].
    move: H1=> /leakage_cat_inv [s12 [t12 [t12' [H12 [H1 ->]]]]].
    move: H2=> /= /leakage_cat_inv [s21 [t21 [t21' [H21 [H2 ->]]]]].
    move: H2=> /leakage_cat_inv [s22 [t22 [t22' [H22 [H2 ->]]]]].
    rewrite /= in Hts1s2.
    have Ht: trace_expr s_1 e1 = trace_expr s_2 e1 /\ trace_expr s_1 e2 = trace_expr s_2 e2.
      move: Hts1s2=> /eqP Hts1s2.
      rewrite eqseq_cat in Hts1s2.
      by move: Hts1s2=> /andP [/eqP -> /eqP ->].
      exact: size_trace_expr.
    congr ((_ ++ _) ++ _).
    + move: H1=> /leakage_instr_inv [-> _].
      by move: H2=> /leakage_instr_inv [-> _].
    + apply: (He2 _ _ _ _ _ _ _ _ _ _ _ _ _ H12 H22).
      move=> Habs.
      apply: Hglob.
      by rewrite /= Habs orbT.
      apply: (svmap_eq_exceptT Hs1).
      exact: (correct_e' (leak_imp_exec H11)).
      apply: (svmap_eq_exceptT Hs2).
      exact: (correct_e' (leak_imp_exec H21)).
      exact: Ht.2.
    + apply: (He1 _ _ _ _ _ _ _ _ _ _ _ _ _ H11 H21).
      move=> Habs.
      apply: Hglob.
      by rewrite /= Habs.
      exact: Hs1.
      exact: Hs2.
      exact: Ht.1.
    (*** TODO: fix copypaste *)
    move: H1=> /= /leakage_cat_inv [s11 [t11 [t11' [H11 [H1 ->]]]]].
    move: H1=> /leakage_cat_inv [s12 [t12 [t12' [H12 [H1 ->]]]]].
    move: H2=> /= /leakage_cat_inv [s21 [t21 [t21' [H21 [H2 ->]]]]].
    move: H2=> /leakage_cat_inv [s22 [t22 [t22' [H22 [H2 ->]]]]].
    rewrite /= in Hts1s2.
    have Ht: trace_expr s_1 e1 = trace_expr s_2 e1 /\ trace_expr s_1 e2 = trace_expr s_2 e2.
      move: Hts1s2=> /eqP Hts1s2.
      rewrite eqseq_cat in Hts1s2.
      by move: Hts1s2=> /andP [/eqP -> /eqP ->].
      exact: size_trace_expr.
    congr ((_ ++ _) ++ _).
    + move: H1=> /leakage_instr_inv [-> _].
      by move: H2=> /leakage_instr_inv [-> _].
    + apply: (He2 _ _ _ _ _ _ _ _ _ _ _ _ _ H12 H22).
      move=> Habs.
      apply: Hglob.
      by rewrite /= Habs orbT.
      apply: (svmap_eq_exceptT Hs1).
      exact: (correct_e' (leak_imp_exec H11)).
      apply: (svmap_eq_exceptT Hs2).
      exact: (correct_e' (leak_imp_exec H21)).
      exact: Ht.2.
    + apply: (He1 _ _ _ _ _ _ _ _ _ _ _ _ _ H11 H21).
      move=> Habs.
      apply: Hglob.
      by rewrite /= Habs.
      exact: Hs1.
      exact: Hs2.
      exact: Ht.1.
    (***)
    rewrite /= in H1, H2.
    move: H1=> /leakage_instr_inv [-> _].
    move: H2=> /leakage_instr_inv [-> _] /=.
    move: Hglob=> /negP Hglob.
    rewrite negb_or in Hglob.
    move: Hglob=> /andP [_ /negP Hglob'].
    rewrite (@var_in_eq glob_arr _ s1 s_1) ?(@var_in_eq glob_arr _ s2 s_2)=> //; by symmetry.
  Qed.

  Lemma ct_head a l:
    (forall s, exists s'', exec s (l ++ [:: a]) s'') ->
    constant_time_ss P (l ++ [:: a]) -> constant_time_ss P l.
  Proof.
    move=> Hsem H s1 s2 s1' s2' t1 t2 Hpub H1 H2.
    move: (Hsem s1)=> [s1'' Hs1''].
    move: (Hsem s2)=> [s2'' Hs2''].
    move: H=> /(_ s1 s2 s1'' s2'' ((trace_instr s1' a) ++ t1) ((trace_instr s2' a) ++ t2) Hpub) H.
    have H': trace_instr s1' a ++ t1 = trace_instr s2' a ++ t2.
      apply: H.
      apply: leakage_next=> //.
      apply: leakage_next=> //.
    move: H'=> /eqP H'.
    rewrite eqseq_cat in H'.
    by move: H'=> /andP [_ /eqP ->].
    exact: size_trace_instr.
  Qed.

  Theorem preserve_ct: forall c,
    ~ var_in_cmd glob_arr c ->
    (forall s, exists s', exec s c s') ->
    constant_time_ss P c ->
    constant_time_ss P (arralloc_cmd c).
  Proof.
    elim/List.rev_ind=> // a l IH Hglob Hsem Hsrc.
    rewrite arralloc_cat.
    move=> s1 s2 s1' s2' t1 t2 Hpub.
    move=> /leakage_cat_inv [s1'' [t1' [t1'' [H1 [H1' ->]]]]].
    move=> /leakage_cat_inv [s2'' [t2' [t2'' [H2 [H2' ->]]]]].
    congr (_ ++ _).
    case: a Hglob Hsem Hsrc H1' H2'=> r e Hglob Hsem Hsrc H1' H2'.
    rewrite /= cats0 in H1', H2'.
    move: H1'=> /leakage_cat_inv [s'1 [t1_1 [t1_2 [H1_1 [H1_2 ->]]]]].
    move: H2'=> /leakage_cat_inv [s'2 [t2_1 [t2_2 [H2_1 [H2_2 ->]]]]].
    move: (leakage_instr_inv H1_2)=> [-> _] /=.
    move: (leakage_instr_inv H2_2)=> [-> _] /=.
    congr (_ :: _).
    move: (Hsem s1)=> [s'_1 /exec_cat_inv [s''_1 [Hsrc11 Hsrc12]]].
    move: (Hsem s2)=> [s'_2 /exec_cat_inv [s''_2 [Hsrc21 Hsrc22]]].
    apply: (preserve_ct_expr _ _ _ _ H1_1 H2_1).
    move=> Habs.
    apply: Hglob.
    rewrite /var_in_cmd foldl_cat /=.
    by rewrite Habs orbT.
    have Hbla1: s''_1 = s1'' [\Sv.singleton glob_arr].
      apply: correct.
      exact: Hsrc11.
      exact: (leak_imp_exec H1).
    exact: Hbla1.
    have Hbla2: s''_2 = s2'' [\Sv.singleton glob_arr].
      apply: correct.
      exact: Hsrc21.
      exact: (leak_imp_exec H2).
    exact: Hbla2.
    move: Hsrc11=> /exec_imp_leak [t11' Hsrc11'].
    move: Hsrc21=> /exec_imp_leak [t21' Hsrc21'].
    move: Hsrc=> /(_ s1 s2 s'_1 s'_2 (trace_expr s''_1 e ++ t11') (trace_expr s''_2 e ++ t21') Hpub) Hsrc.
    have Hok: trace_expr s''_1 e ++ t11' = trace_expr s''_2 e ++ t21'.
      apply: Hsrc.
      + apply: leakage_cat.
        exact: Hsrc11'.
        apply: leakage_instr=> //.
        by move: Hsrc12=> /exec_imp_leak [t12' /leakage_instr_inv [_ ->]].
      + apply: leakage_cat.
        exact: Hsrc21'.
        apply: leakage_instr=> //.
        by move: Hsrc22=> /exec_imp_leak [t22' /leakage_instr_inv [_ ->]].
      move: Hok=> /eqP Hok.
      rewrite eqseq_cat in Hok.
      by move: Hok=> /andP [/eqP -> _].
      exact: size_trace_expr.
    apply: IH.
    move=> Habs.
    apply: Hglob.
    rewrite /var_in_cmd foldl_cat /=.
    by rewrite -[foldl _ _ _]/(var_in_cmd _ _) Habs.
    move=> s.
    by move: Hsem=> /(_ s) [s' /exec_cat_inv [s'' [Hs' _]]]; exists s''.
    apply: (ct_head _ Hsrc)=> //.
    exact: Hpub.
    exact: H1.
    exact: H2.
  Qed.
  End Smallstep_Proof.
End ArrAlloc.