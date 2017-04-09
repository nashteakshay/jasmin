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

(* * New semantic which is "unsafe" (may not fail on invalid code) but simplifies the Hoare logic *)

(* ** Imports and settings *)

From mathcomp Require Import ssreflect ssrfun ssrbool ssrnat ssrint ssralg tuple.
From mathcomp Require Import choice fintype eqtype div seq zmodp.
Require Import ZArith.

Require Import strings word utils type var expr sem.
Require Import memory.

Require Import Utf8.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Open Scope string_scope.

(* ** Type interpretation
 * -------------------------------------------------------------------- *)

Variant sstype : Type := ssbool | ssint | ssarr | ssword.

Coercion sstype_of_stype (ty: stype) : sstype :=
  match ty with
  | sbool => ssbool
  | sint => ssint
  | sarr _ => ssarr
  | sword => ssword
  end.

Definition ssem_t (t : sstype) : Type :=
  match t with
  | ssbool  => bool
  | ssint   => Z
  | ssarr => FArray.array word
  | ssword  => word
  end.

Definition sdflt_val st : ssem_t st :=
  match st with
  | ssbool         => false
  | ssint          => Z0
  | ssarr        => FArray.cnst (n2w 0)
  | ssword         => I64.repr Z0
  end.

(* ** Values
  * -------------------------------------------------------------------- *)

Inductive svalue : Type :=
  | SVbool :> bool -> svalue
  | SVint  :> Z    -> svalue
  | SVarr  : FArray.array word -> svalue
  | SVword :> word -> svalue.

Definition svalues := seq svalue.

Definition sto_bool v :=
  match v with
  | SVbool b => ok b
  | _        => type_error
  end.

Definition sto_int v :=
  match v with
  | SVint z => ok z
  | _       => type_error
  end.

Definition sto_arr v :=
  match v with
  | SVarr t => ok t
  | _         => type_error
  end.

Definition sto_word v :=
  match v with
  | SVword w => ok w
  | _        => type_error
  end.

Definition of_sval t : svalue -> exec (ssem_t t) :=
  match t return svalue -> exec (ssem_t t) with
  | ssbool  => sto_bool
  | ssint   => sto_int
  | ssarr => sto_arr
  | ssword  => sto_word
  end.

Definition to_sval t : ssem_t t -> svalue :=
  match t return ssem_t t -> svalue with
  | ssbool  => SVbool
  | ssint   => SVint
  | ssarr => SVarr
  | ssword  => SVword
  end.

Definition sval_sstype (s : svalue) :=
  match s with
  | SVbool _ => ssbool
  | SVint  _ => ssint
  | SVarr  a => ssarr
  | SVword _ => ssword
  end.

(* ** Variable map
 * -------------------------------------------------------------------- *)
Delimit Scope svmap_scope with svmap.

Notation svmap    := (Fv.t ssem_t).
Notation svmap0   := (@Fv.empty ssem_t (fun x => sdflt_val x.(vtype))).

Definition sget_var (m:svmap) x :=
  @to_sval (vtype x) (m.[x]%vmap).

Definition sset_var (m:svmap) x v :=
  Let v := @of_sval (vtype x) v in
  ok (m.[x<-v]%vmap).

(* ** Parameter expressions
 * -------------------------------------------------------------------- *)

Definition ssem_prod ts tr := lprod (map ssem_t ts) tr.

Definition mk_ssem_sop2 t1 t2 tr (o:ssem_t t1 -> ssem_t t2 -> ssem_t tr) v1 v2 :=
  Let v1 := of_sval t1 v1 in
  Let v2 := of_sval t2 v2 in
  ok (@to_sval tr (o v1 v2)).

Definition ssem_op2_b  := @mk_ssem_sop2 sbool sbool sbool.
Definition ssem_op2_i  := @mk_ssem_sop2 sint  sint  sint.
Definition ssem_op2_ib := @mk_ssem_sop2 sint  sint  sbool.

Definition ssem_sop2 (o:sop2) :=
  match o with
  | Oand => ssem_op2_b andb
  | Oor  => ssem_op2_b orb

  | Oadd => ssem_op2_i Z.add
  | Omul => ssem_op2_i Z.mul
  | Osub => ssem_op2_i Z.sub

  | Oeq  => ssem_op2_ib Z.eqb
  | Oneq => ssem_op2_ib (fun x y => negb (Z.eqb x y))
  | Olt  => ssem_op2_ib Z.ltb
  | Ole  => ssem_op2_ib Z.leb
  | Ogt  => ssem_op2_ib Z.gtb
  | Oge  => ssem_op2_ib Z.geb
  end.

Import UnsafeMemory.

Record sestate := SEstate {
  semem : mem;
  sevm  : svmap
}.

Definition son_arr_var A (s: sestate) (x: var) (f: positive → FArray.array word → exec A) :=
  match vtype x as t return ssem_t t → exec A with
  | sarr n => f n
  | _ => λ _, type_error
  end  (s.(sevm).[ x ]%vmap).

Notation "'SLet' ( n , t ) ':=' s '.[' x ']' 'in' body" :=
  (@son_arr_var _ s x (fun n (t:FArray.array word) => body)) (at level 25, s at level 0).

Fixpoint ssem_pexpr (s:sestate) (e : pexpr) : exec svalue :=
  match e with
  | Pconst z => ok (SVint z)
  | Pbool b  => ok (SVbool b)
  | Pcast e  =>
    Let z := ssem_pexpr s e >>= sto_int in
    ok (SVword (I64.repr z))
  | Pvar v => ok (sget_var s.(sevm) v)
  | Pget x e =>
      SLet (n,t) := s.[x] in
      Let i := ssem_pexpr s e >>= sto_int in
      ok (SVword (FArray.get t i))
  | Pload x e =>
    Let w1 := ok (sget_var s.(sevm) x) >>= sto_word in
    Let w2 := ssem_pexpr s e >>= sto_word in
    let w := read_mem s.(semem) (I64.add w1 w2) in
    ok (@to_sval sword w)
  | Pnot e =>
    Let b := ssem_pexpr s e >>= sto_bool in
    ok (SVbool (negb b))
  | Papp2 o e1 e2 =>
    Let v1 := ssem_pexpr s e1 in
    Let v2 := ssem_pexpr s e2 in
    ssem_sop2 o v1 v2
  end.

Definition ssem_pexprs s := mapM (ssem_pexpr s).

Definition swrite_var (x:var_i) (v:svalue) (s:sestate) : exec sestate :=
  Let vm := sset_var s.(sevm) x v in
  ok {| semem := s.(semem); sevm := vm |}.

Definition swrite_vars xs vs s :=
  fold2 ErrType swrite_var xs vs s.

Definition swrite_lval (l:lval) (v:svalue) (s:sestate) : exec sestate :=
  match l with
  | Lnone _ => ok s
  | Lvar x => swrite_var x v s
  | Lmem x e =>
    Let vx := sto_word (sget_var (sevm s) x) in
    Let ve := ssem_pexpr s e >>= sto_word in
    let p := wadd vx ve in (* should we add the size of value, i.e vx + sz * se *)
    Let w := sto_word v in
    let m := write_mem s.(semem) p w in
    ok {|semem := m;  sevm := s.(sevm) |}
  | Laset x i =>
    SLet (n,t) := s.[x] in
    Let i := ssem_pexpr s i >>= sto_int in
    Let v := sto_word v in
    let t := FArray.set t i v in
    Let vm := sset_var s.(sevm) x (@to_sval (sarr n) t) in
    ok {| semem := s.(semem); sevm := vm |}
  end.

Definition swrite_lvals (s:sestate) xs vs :=
   fold2 ErrType swrite_lval xs vs s.

Fixpoint sapp_sopn ts : ssem_prod ts svalues -> svalues -> exec svalues :=
  match ts return ssem_prod ts svalues -> svalues -> exec svalues with
  | [::] => fun (o:svalues) (vs:svalues) =>
    match vs with
    | [::] => ok o
    | _    => type_error
    end
  | t::ts => fun (o:ssem_t t -> ssem_prod ts svalues) (vs:svalues) =>
    match vs with
    | [::]  => type_error
    | v::vs =>
      Let v := of_sval t v in
      sapp_sopn (o v) vs
    end
  end.
Arguments sapp_sopn ts o l:clear implicits.

Definition spval t1 t2 (p: ssem_t t1 * ssem_t t2) :=
  [::to_sval p.1; to_sval p.2].

Notation soww o  := (sapp_sopn [::ssword] (fun x => [::SVword (o x)])).
Notation sowww o := (sapp_sopn [:: ssword; ssword] (fun x y => [::SVword (o x y)])).

Definition ssem_sopn (o:sopn) : svalues -> exec svalues :=
  match o with
  | Olnot => soww I64.not
  | Oxor  => sowww I64.xor
  | Oland => sowww I64.and
  | Olor  => sowww I64.or
  | Olsr  => sowww I64.shru
  | Olsl  => sowww I64.shl
  | Omuli => sowww (fun x y => let (h,l) := wumul x y in l) (* FIXME: check imul INTEL manual *)
  | Oif   =>
    sapp_sopn [::ssbool; ssword; ssword] (fun b x y => [::SVword (if b then x else y)])
  | Omulu =>
    sapp_sopn [::ssword; ssword] (fun x y => @spval sword sword (wumul x y))
  | Oaddcarry =>
    sapp_sopn [::ssword; ssword; ssbool] (fun x y c => @spval sbool sword (waddcarry x y c))
  | Osubcarry =>
    sapp_sopn [::ssword; ssword; ssbool] (fun x y c => @spval sbool sword (wsubcarry x y c))
  end.

(* ** Instructions
 * -------------------------------------------------------------------- *)

Section SEM.

Variable P:prog.

Inductive ssem : sestate -> cmd -> sestate -> Prop :=
| SEskip s :
    ssem s [::] s

| SEseq s1 s2 s3 i c :
    ssem_I s1 i s2 -> ssem s2 c s3 -> ssem s1 (i::c) s3

with ssem_I : sestate -> instr -> sestate -> Prop :=
| SEmkI ii i s1 s2:
    ssem_i s1 i s2 ->
    ssem_I s1 (MkI ii i) s2

with ssem_i : sestate -> instr_r -> sestate -> Prop :=
| SEassgn s1 s2 (x:lval) tag e:
    (Let v := ssem_pexpr s1 e in swrite_lval x v s1) = ok s2 ->
    ssem_i s1 (Cassgn x tag e) s2

| SEopn s1 s2 o xs es:
    ssem_pexprs s1 es >>= ssem_sopn o >>= (swrite_lvals s1 xs) = ok s2 ->
    ssem_i s1 (Copn xs o es) s2

| SEif_true s1 s2 e c1 c2 :
    ssem_pexpr s1 e >>= sto_bool = ok true ->
    ssem s1 c1 s2 ->
    ssem_i s1 (Cif e c1 c2) s2

| SEif_false s1 s2 e c1 c2 :
    ssem_pexpr s1 e >>= sto_bool = ok false ->
    ssem s1 c2 s2 ->
    ssem_i s1 (Cif e c1 c2) s2

| SEwhile_true s1 s2 s3 e c :
    ssem_pexpr s1 e >>= sto_bool = ok true ->
    ssem s1 c s2 ->
    ssem_i s2 (Cwhile e c) s3 ->
    ssem_i s1 (Cwhile e c) s3

| SEwhile_false s e c :
    ssem_pexpr s e >>= sto_bool = ok false ->
    ssem_i s (Cwhile e c) s

| SEfor s1 s2 (i:var_i) d lo hi c vlo vhi :
    ssem_pexpr s1 lo >>= sto_int = ok vlo ->
    ssem_pexpr s1 hi >>= sto_int = ok vhi ->
    ssem_for i (wrange d vlo vhi) s1 c s2 ->
    ssem_i s1 (Cfor i (d, lo, hi) c) s2

| SEcall s1 m2 s2 ii xs f args vargs vs :
    ssem_pexprs s1 args = ok vargs ->
    ssem_call s1.(semem) f vargs m2 vs ->
    swrite_lvals {|semem:= m2; sevm := s1.(sevm) |} xs vs = ok s2 ->
    ssem_i s1 (Ccall ii xs f args) s2

with ssem_for : var -> seq Z -> sestate -> cmd -> sestate -> Prop :=
| SEForDone s i c :
    ssem_for i [::] s c s

| SEForOne s1 s1' s2 s3 i w ws c :
    swrite_var i (SVint w) s1 = ok s1' ->
    ssem s1' c s2 ->
    ssem_for i ws s2 c s3 ->
    ssem_for i (w :: ws) s1 c s3

with ssem_call : mem -> funname -> seq svalue -> mem -> seq svalue -> Prop := 
| SEcallRun m1 m2 fn f vargs s1 vm2 vres:
    get_fundef P fn = Some f ->
    swrite_vars f.(f_params) vargs (SEstate m1 svmap0) = ok s1 ->
    ssem s1 f.(f_body) (SEstate m2 vm2) ->
    map (fun (x:var_i) => sget_var vm2 x) f.(f_res) = vres ->
    ssem_call m1 fn vargs m2 vres.

End SEM.

Definition MkI_inj {ii i ii' i'} (H: MkI ii i = MkI ii' i') :
  ii = ii' ∧ i = i' :=
  let 'Logic.eq_refl := H in conj Logic.eq_refl Logic.eq_refl.

Definition Some_inj {A} (a a': A) (H: Some a = Some a') : a = a' :=
  let 'Logic.eq_refl := H in Logic.eq_refl.

Definition ok_inj {E A} (a a': A) (H: Ok E a = ok a') : a = a' :=
  let 'Logic.eq_refl := H in Logic.eq_refl.

Definition Error_inj {E A} (a a': E) (H: @Error E A a = Error a') : a = a' :=
  let 'Logic.eq_refl := H in Logic.eq_refl.

Lemma sval_sstype_to_sval sst (z : ssem_t sst) :
  sval_sstype (to_sval z) = sst.
Proof. by case: sst z. Qed.

Lemma sval_sstype_of_sval sst (z : svalue) y :
  of_sval sst z = ok y -> sval_sstype z = sst.
Proof. by case: sst y z => y []. Qed.

Lemma of_sval_inj sst z1 z2 :
     sval_sstype z1 = sst
  -> sval_sstype z2 = sst
  -> of_sval sst z1 = of_sval sst z2
  -> z1 = z2.
Proof. by case: sst; case: z2; case: z1 => //= x1 x2 _ _ [->]. Qed.

Lemma of_sval_to_sval ty x :
  of_sval ty (to_sval x) = ok x.
Proof. by move: x; case ty. Qed.

Lemma sto_word_inv x i :
  sto_word x = ok i →
  x = i.
Proof. case: x => // i' H; apply ok_inj in H. congruence. Qed.

Lemma sto_int_inv x i :
  sto_int x = ok i →
  x = i.
Proof. case: x => // i' H; apply ok_inj in H. congruence. Qed.

Lemma sto_bool_inv x b :
  sto_bool x = ok b →
  x = b.
Proof. case: x => // i' H; apply ok_inj in H. congruence. Qed.

Lemma sto_arr_inv x a :
  sto_arr x = ok a →
  x = SVarr a.
Proof. case: x => // a' H;apply ok_inj in H. congruence. Qed.

Lemma slet_inv {A s x} {f: _ → _ → exec A} {y} :
  SLet (n, t) := s.[x] in f n t = ok y →
  ∃ n (Tx: vtype x = sarr n), f n (eq_rect _ _ (sevm s).[x]%vmap _ Tx) = ok y.
Proof.
  unfold son_arr_var.
  generalize ((sevm s).[x])%vmap.
  case: (vtype x) => // n t E.
  exists n, Logic.eq_refl. exact E.
Qed.

Lemma ssem_inv { prg s c s' } :
  ssem prg s c s' →
  match c with
  | [::] => s' = s
  | i :: c' => ∃ si, ssem_I prg s i si ∧ ssem prg si c' s'
end.
Proof. case; eauto. Qed.

Lemma ssem_I_inv { prg s i s' } :
  ssem_I prg s i s' →
  ∃ i' ii, i = MkI ii i' ∧ ssem_i prg s i' s'.
Proof. case; eauto. Qed.

Lemma ssem_i_inv { prg s i s' } :
  ssem_i prg s i s' →
  match i with
  | Cassgn x tg e => ∃ v, ssem_pexpr s e = ok v ∧ swrite_lval x v s = ok s'
  | Copn xs op es => ∃ args vs, ssem_pexprs s es = ok args ∧ ssem_sopn op args = ok vs ∧ swrite_lvals s xs vs = ok s'
  | Cif e c1 c2 => ∃ b : bool, ssem_pexpr s e = ok (SVbool b) ∧ ssem prg s (if b then c1 else c2) s'
  | _ => True
  end.
Proof.
  case; eauto; clear.
  - (* Cassgn *)
  move=> s s' x _ e; apply: rbindP; eauto.
  - (* Copn *)
  move=> s s' xs op es; apply: rbindP => vs; apply: rbindP; eauto.
  - (* Cif true *)
  move=> s s' e c1 c2; apply: rbindP => v Hv /sto_bool_inv ?; subst v; eauto.
  - (* Cif false *)
  move=> s s' e c1 c2; apply: rbindP => v Hv /sto_bool_inv ?; subst v; eauto.
Qed.

Lemma swrite_lval_inv {x v s s'} :
  swrite_lval x v s = ok s' →
  match x with
  | Lnone _ => s' = s
  | Lvar x => ∃ v', of_sval (vtype x) v = ok v' ∧
                    s' = {| semem := semem s ; sevm := (sevm s).[ x <- v' ] |}
  | Lmem x e =>
    ∃ (Tx: vtype x = sword),
    ∃ vx ve w: word, eq_rect _ _ ((sevm s).[ x ]) _ Tx = vx ∧ ssem_pexpr s e = ok (SVword ve) ∧ v = w ∧
               s' = {| semem := write_mem (semem s) (I64.add vx ve) w ; sevm := sevm s |}
  | Laset x i =>
    ∃ n (Tx: vtype x = sarr n) (vi : Z) (w: word),
  ssem_pexpr s i = ok (SVint vi) ∧
  v = w ∧
  let q := FArray.set (eq_rect (vtype x) ssem_t ((sevm s).[x]) (sarr n) Tx) vi w in
  s' = {| semem := semem s ; sevm := (sevm s).[x <- eq_rect _ _ q _ (Logic.eq_sym Tx)] |}
end%vmap.
Proof.
  destruct x as [ vi | x | x e | x i ].
  - move=> H; apply ok_inj in H; auto.
  - apply: rbindP => vm H K; apply ok_inj in K; subst s'.
    revert H; apply: rbindP => v' H X; apply ok_inj in X; subst vm; eauto.
  - apply: rbindP => vx /sto_word_inv H.
    apply: rbindP => ve.
    apply: rbindP => ve' He /sto_word_inv ?; subst ve'.
    apply: rbindP => w /sto_word_inv -> X; apply ok_inj in X; subst s'.
    unfold sget_var in H.
    case: x H=> [[[] x] xi] //.
    exists Logic.eq_refl, vx, ve, w.
    split. simpl in *. congruence. auto.
  - move=> /slet_inv [n [Tx H]].
    exists n, Tx.
    apply: rbindP H=> vi;apply: rbindP => vj Hi /sto_int_inv H;subst vj.
    apply: rbindP => w /sto_word_inv ->;apply: rbindP => vm' L [<-].
    exists vi, w;split=> //;split=>//=;f_equal;f_equal.
    by case: x Tx L=>  -[ty x] xi /= ?;subst ty => /= -[] <-.
Qed.