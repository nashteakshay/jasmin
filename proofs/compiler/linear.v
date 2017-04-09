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
Require Import Setoid Morphisms.

From mathcomp Require Import ssreflect ssrfun ssrbool ssrnat ssrint ssralg tuple.
From mathcomp Require Import choice fintype eqtype div seq zmodp.
Require Import ZArith.

Require Import strings word utils type var expr.
Require Import memory sem stack_alloc compiler_util.
Import Memory.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope seq_scope.
(* --------------------------------------------------------------------------- *)
(* Syntax                                                                      *)

Definition label := positive.

Inductive linstr_r := 
  | Lassgn : lval -> assgn_tag -> pexpr -> linstr_r
  | Lopn   : lvals -> sopn -> pexprs -> linstr_r
  | Llabel : label -> linstr_r
  | Lgoto  : label -> linstr_r
  | Lcond  : pexpr -> label -> linstr_r
  | Lreturn: linstr_r.

Record linstr : Type := MkLI { li_ii : instr_info; li_i : linstr_r }.

Definition linstr_r_beq i1 i2 :=
  match i1, i2 with
  | Lassgn x1 tag1 e1, Lassgn x2 tag2 e2 =>
     (tag1 == tag2) && (x1 == x2) && (e1 == e2)
  | Lopn x1 o1 e1, Lopn x2 o2 e2 =>
     (x1 == x2) && (o1 == o2) && (e1 == e2)
  | Llabel l1, Llabel l2 => l1 == l2
  | Lgoto l1, Lgoto l2 => l1 == l2
  | Lcond e1 l1, Lcond e2 l2 => (e1 == e2) && (l1 == l2)
  | Lreturn, Lreturn => true
  | _, _ => false
  end.

Definition linstr_beq i1 i2 :=
  match i1, i2 with
  | MkLI if1 i1, MkLI if2 i2 => (if1 == if2) && (linstr_r_beq i1 i2)
  end.

Lemma linstr_r_eq_axiom : Equality.axiom linstr_r_beq.
Proof.
  rewrite /Equality.axiom.
  move=> [x1 t1 e1|x1 o1 e1|l1|l1|e1 l1|] [x2 t2 e2|x2 o2 e2|l2|l2|e2 l2|] //=; try by right.
  + apply (@equivP ((t1 == t2) && (x1 == x2) && (e1 == e2)));first by apply idP.
    split=> [/andP [] /andP [] /eqP-> /eqP-> /eqP-> | [] <- <- <- ] //.
    by rewrite !eq_refl.
  + apply (@equivP ((x1 == x2) && (o1 == o2) && (e1 == e2)));first by apply idP.
    split=> [/andP [] /andP [] /eqP-> /eqP-> /eqP-> | [] <- <- <- ] //.
    by rewrite !eq_refl.
  + apply (@equivP (l1 == l2)); first by apply idP.
    split=> [/eqP->|[] <-] //.
  + apply (@equivP (l1 == l2)); first by apply idP.
    split=> [/eqP->|[] <-] //.
  + apply (@equivP ((e1 == e2) && (l1 == l2))); first by apply idP.
    split=> [/andP [] /eqP-> /eqP->|[] <- <-] //.
    by rewrite !eq_refl.
  + by left.
Qed.

Definition linstr_r_eqMixin     := Equality.Mixin linstr_r_eq_axiom.
Canonical  linstr_r_eqType      := Eval hnf in EqType linstr_r linstr_r_eqMixin.

Lemma linstr_eq_axiom : Equality.axiom linstr_beq.
Proof. 
  move=> [ii1 r1] [ii2 r2] /=.
  apply (@equivP ((ii1 == ii2) /\ linstr_r_beq r1 r2)); first by apply andP.
  split=> [[] /eqP-> /linstr_r_eq_axiom ->|[] <- <-] //.
  split=> //; by apply/linstr_r_eq_axiom.
Qed.

Definition linstr_eqMixin     := Equality.Mixin linstr_eq_axiom.
Canonical  linstr_eqType      := Eval hnf in EqType linstr linstr_eqMixin.

Definition lcmd := seq linstr.

Definition is_label (lbl: label) (i:linstr) : bool :=
  match i.(li_i) with
  | Llabel lbl' => lbl == lbl'
  | _ => false
  end.

Record lfundef := LFundef {
 lfd_stk_size : Z;                            
 lfd_nstk : Ident.ident;                           
 lfd_arg  : seq var_i;
 lfd_body : lcmd;
 lfd_res  : seq var_i;  (* /!\ did we really want to have "seq var_i" here *)
}.

Definition lfundef_beq fd1 fd2 :=
  match fd1, fd2 with
  | LFundef sz1 id1 p1 c1 r1, LFundef sz2 id2 p2 c2 r2 =>
    (sz1 == sz2) && (id1 == id2) &&
    (p1 == p2) && (c1 == c2) && (r1 == r2)
  end.

Lemma lfundef_eq_axiom : Equality.axiom lfundef_beq.
Proof.
  move=> [s1 id1 p1 c1 r1] [s2 id2 p2 c2 r2] /=.
  apply (@equivP ((s1 == s2) && (id1 == id2) && (p1 == p2) && (c1 == c2) && (r1 == r2)));first by apply idP.
  by split=> [/andP[]/andP[]/andP[]/andP[] | []] /eqP->/eqP->/eqP->/eqP->/eqP->.
Qed.

Definition lfundef_eqMixin   := Equality.Mixin lfundef_eq_axiom.
Canonical  lfundef_eqType      := Eval hnf in EqType lfundef lfundef_eqMixin.

Definition lprog := seq (funname * lfundef).

Section SEM.

Variable P: lprog.

(* --------------------------------------------------------------------------- *)
(* Semantic                                                                    *)

Lemma is_labelP i lbl: reflect (i.(li_i) = Llabel lbl) (is_label lbl i).
Proof.
  case:i => ii [||l|||] //=;try by constructor.
  by apply:(equivP (_ =P _));split=> [|[]] ->.
Qed.

Fixpoint find_label (lbl: label) (c: lcmd) {struct c} : option lcmd :=
  match c with
  | nil => None
  | i1 :: il => if is_label lbl i1 then Some il else find_label lbl il
  end.

Record lstate := Lstate 
  { lmem : mem;  
    lvm  : vmap;
    lc   : lcmd; }.

Definition to_estate (s:lstate) := Estate s.(lmem) s.(lvm).
Definition of_estate (s:estate) c := Lstate s.(emem) s.(evm) c.
Definition setc (s:lstate) c :=  Lstate s.(lmem) s.(lvm) c.

Inductive lsem1 (c:lcmd) : lstate -> lstate -> Prop:=
| LSem_assgn : forall s1 s2 ii x tag e cs,
    s1.(lc) = MkLI ii (Lassgn x tag e) :: cs ->
    (Let v := sem_pexpr (to_estate s1) e in write_lval x v (to_estate s1)) = ok s2 ->
    lsem1 c s1 (of_estate s2 cs)
| LSem_opn : forall s1 s2 ii xs o es cs,
    s1.(lc) = MkLI ii (Lopn xs o es) :: cs ->
    sem_pexprs (to_estate s1) es >>= sem_sopn o >>= (write_lvals (to_estate s1) xs) = ok s2 ->
    lsem1 c s1 (of_estate s2 cs)
| LSem_lbl : forall s1 ii lbl cs,
    s1.(lc) = MkLI ii (Llabel lbl) :: cs ->
    lsem1 c s1 (setc s1 cs)
| LSem_goto : forall s1 ii lbl cs cs',
    s1.(lc) = MkLI ii (Lgoto lbl) :: cs ->
    find_label lbl c = Some cs' ->
    lsem1 c s1 (setc s1 cs')
| LSem_condTrue : forall ii s1 e lbl cs cs',
    s1.(lc) = MkLI ii (Lcond e lbl) :: cs ->
    sem_pexpr (to_estate s1) e >>= to_bool = ok true ->
    find_label lbl c = Some cs' ->
    lsem1 c s1 (setc s1 cs')
| LSem_condFalse : forall ii s1 e lbl cs,
    s1.(lc) = MkLI ii (Lcond e lbl) :: cs ->
    sem_pexpr (to_estate s1) e >>= to_bool = ok false ->
    lsem1 c s1 (setc s1 cs).

Inductive lsem (c:lcmd) : lstate -> lstate -> Prop:=
| LSem0 : forall s, lsem c s s
| LSem1 : forall s1 s2 s3, lsem1 c s1 s2 -> lsem c s2 s3 -> lsem c s1 s3.

Inductive lsem_fd m1 fn va m2 vr : Prop := 
| LSem_fd : forall p cs fd ii vm2 m2' s1 s2,
    get_fundef P fn = Some fd ->
    alloc_stack m1 fd.(lfd_stk_size) = ok p ->
    let c := fd.(lfd_body) in
    write_var  (S.vstk fd.(lfd_nstk)) p.1 (Estate p.2 vmap0) = ok s1 ->
    write_vars fd.(lfd_arg) va s1 = ok s2 ->
    lsem c (of_estate s2 c)
           {| lmem := m2'; lvm := vm2; lc := (MkLI ii Lreturn) :: cs |} ->
    mapM (fun (x:var_i) => get_var vm2 x) fd.(lfd_res) = ok vr ->
    m2 = free_stack m2' p.1 fd.(lfd_stk_size) ->
    List.Forall is_full_array vr ->
    lsem_fd m1 fn va m2 vr.

Lemma lsem_trans s2 s1 s3 c : 
  lsem c s1 s2 -> lsem c s2 s3 -> lsem c s1 s3.
Proof. by elim=> //= {s1 s2} s1 s2 s4 H1 H2 Hrec/Hrec;apply : LSem1. Qed.
   
(* --------------------------------------------------------------------------- *)
(* Translation                                                                 *)

Notation "c1 ';;' c2" :=  (c2 >>= (fun p => c1 p.1 p.2))
   (at level 26, right associativity).

Notation "c1 '>;' c2" :=  (c2 >>= (fun p => ok (p.1, c1 :: p.2)))
   (at level 26, right associativity).

Section LINEAR_C.

  Variable linear_i : instr -> label -> lcmd -> ciexec (label * lcmd).

  Fixpoint linear_c (c:cmd) (lbl:label) (lc:lcmd) := 
    match c with
    | [::] => ciok (lbl, lc)
    | i::c => 
      linear_i i ;; linear_c c lbl lc
    end.

End LINEAR_C.

Definition next_lbl lbl := (lbl + 1)%positive.

Fixpoint linear_i (i:instr) (lbl:label) (lc:lcmd) :=
  let (ii, ir) := i in
  match ir with
  | Cassgn x tag e => ok (lbl, MkLI ii (Lassgn x tag e) :: lc)
  | Copn xs o es => ok (lbl, MkLI ii (Lopn xs o es) :: lc)

  | Cif e [::] c2 =>
    let L1 := lbl in
    let lbl := next_lbl L1 in
    MkLI ii (Lcond e L1) >; linear_c linear_i c2 lbl (MkLI ii (Llabel L1) :: lc)

  | Cif e c1 [::] =>
    let L1 := lbl in
    let lbl := next_lbl L1 in
    MkLI ii (Lcond (Pnot e) L1) >; linear_c linear_i c1 lbl (MkLI ii (Llabel L1) :: lc)

  | Cif e c1 c2 =>
    let L1 := lbl in
    let L2 := next_lbl L1 in
    let lbl := next_lbl L2 in
    MkLI ii (Lcond e L1) >; linear_c linear_i c2 ;; MkLI ii (Lgoto L2) >;
    MkLI ii (Llabel L1) >; linear_c linear_i c1 lbl (MkLI ii (Llabel L2) :: lc)

  | Cwhile e c =>
    let L1 := lbl in
    let L2 := next_lbl L1 in
    let lbl := next_lbl L2 in
    MkLI ii (Lgoto L1) >;
    MkLI ii (Llabel L2) >;
    linear_c linear_i c lbl
    (MkLI ii (Llabel L1) :: MkLI ii (Lcond e L2) :: lc)

  | Cfor _ _ _ => cierror ii (Cerr_linear "for found in linear")
    
  | Ccall _ _ _ _ => cierror ii (Cerr_linear "call found in linear")

  end.

End SEM.

Definition linear_fd (fd: sfundef) :=
  Let fd' := linear_c linear_i (sf_body fd) 1%positive [:: MkLI xH Lreturn] in
  ok (LFundef (sf_stk_sz fd) (sf_stk_id fd) (sf_params fd) fd'.2 (sf_res fd)).

Definition linear_prog (p: sprog) : cfexec lprog :=
  map_cfprog linear_fd p.

Section CAT.

  Let Pi (i:instr) := 
    forall lbl l , 
     linear_i i lbl l = 
     linear_i i lbl [::] >>= (fun (p:label*lcmd) => ok (p.1, p.2 ++ l)).

  Let Pr (i:instr_r) :=
    forall ii, Pi (MkI ii i).

  Let Pc (c:cmd) := 
    forall lbl l , 
     linear_c linear_i c lbl l = 
     linear_c linear_i c lbl [::] >>= 
       (fun (p:label*lcmd) => ok (p.1, p.2 ++ l)).

  Let Pf (fd:fundef) := True.

  Let HmkI: forall i ii, Pr i -> Pi (MkI ii i).
  Proof. by []. Qed.  

  Let Hskip : Pc [::].
  Proof. by []. Qed.

  Let Hseq : forall i c,  Pi i -> Pc c -> Pc (i::c).
  Proof.
    move=> i c Hi Hc lbl l /=.
    rewrite Hc !bindA;apply bind_eq => //= p.
    by rewrite Hi (Hi p.1 p.2) bindA;apply bind_eq => //= p';rewrite catA.
  Qed.

  Let Hassgn : forall x t e, Pr (Cassgn x t e).
  Proof. by []. Qed.

  Let Hopn : forall xs o es, Pr (Copn xs o es).
  Proof. by []. Qed.

  Let Hif   : forall e c1 c2,  Pc c1 -> Pc c2 -> Pr (Cif e c1 c2).
  Proof.
    move=> e c1 c2 Hc1 Hc2 ii lbl l /=.
    case Heq1: (c1)=> [|i1 l1].
    + by rewrite Hc2 (Hc2 _ [::_]) !bindA;apply bind_eq => //= p;rewrite -catA.
    rewrite -Heq1=> {Heq1 i1 l1};case Heq2: (c2)=> [|i2 l2].
    + by rewrite Hc1 (Hc1 _ [::_]) !bindA;apply bind_eq => //= p;rewrite -catA.
    rewrite -Heq2=> {Heq2 i2 l2}.
    rewrite Hc1 (Hc1 _ [::_]) !bindA;apply bind_eq => //= p.
    rewrite Hc2 (Hc2 _ [::_ & _])!bindA;apply bind_eq => //= p1.
    by rewrite -!catA /= -catA.
  Qed.

  Let Hfor : forall v dir lo hi c, Pc c -> Pr (Cfor v (dir, lo, hi) c).
  Proof. by []. Qed.

  Let Hwhile : forall e c, Pc c -> Pr (Cwhile e c).
  Proof.
    move=> e c Hc ii lbl l /=.
    by rewrite Hc (Hc _ [::_;_]) !bindA;apply bind_eq => //= p;rewrite -!catA.
  Qed.

  Let Hcall : forall i xs f es, Pr (Ccall i xs f es).
  Proof. by []. Qed.

  Lemma linear_i_nil i lbl l :
     linear_i i lbl l = 
     linear_i i lbl [::] >>= (fun (p:label*lcmd) => ok (p.1, p.2 ++ l)).
  Proof. 
    apply (@instr_Rect Pr Pi Pc HmkI Hskip Hseq Hassgn Hopn Hif Hfor Hwhile Hcall).
  Qed.

  Lemma linear_c_nil c lbl l :
     linear_c linear_i c lbl l = 
     linear_c linear_i c lbl [::] >>= (fun (p:label*lcmd) => ok (p.1, p.2 ++ l)).
  Proof. 
    apply (@cmd_rect Pr Pi Pc HmkI Hskip Hseq Hassgn Hopn Hif Hfor Hwhile Hcall).
  Qed.

End CAT.

Definition valid min max lc :=
  all (fun (i: linstr) => let (ii, ir) := i in match ir with
       | Llabel  lbl => ((min <=? lbl) && (lbl <? max))%positive
       | Lgoto   lbl => ((min <=? lbl) && (lbl <? max))%positive
       | Lcond _ lbl => ((min <=? lbl) && (lbl <? max))%positive
       | _           => true
       end) lc.

Lemma valid_cat min max lc1 lc2 : 
  valid min max (lc1 ++ lc2) = valid min max lc1 && valid min max lc2.
Proof. by rewrite /valid all_cat. Qed.

Lemma valid_le_min min2 min1 max lc : 
  (min1 <=? min2)%positive -> 
  valid min2 max lc ->
  valid min1 max lc.
Proof.
  by move=> Hle1; apply: sub_all=> -[ii [| |lbl|lbl|e lbl|]] //= /andP [] Hle2 ->;
  rewrite (Pos_leb_trans Hle1 Hle2).
Qed.

Lemma valid_le_max max2 max1 min lc : 
  (max1 <=? max2)%positive -> 
  valid min max1 lc ->
  valid min max2 lc.
Proof.
  by move=> Hle1; apply sub_all=> -[ii [| |lbl|lbl|e lbl|]] //= /andP [] -> Hlt1 /=;
   rewrite (Pos_lt_leb_trans Hlt1 Hle1).
Qed.

Lemma le_next lbl : (lbl <=? next_lbl lbl)%positive.
Proof.
  by apply Pos.leb_le; have: (Zpos lbl <= Zpos lbl + 1)%Z by omega.
Qed.

Lemma lt_next lbl : (lbl <? next_lbl lbl)%positive.
Proof.
  by apply Pos.ltb_lt; have: (Zpos lbl < Zpos lbl + 1)%Z by omega.
Qed.

Lemma find_label_cat_tl c1 c2 lbl c:
  find_label lbl c1 = Some c -> find_label lbl (c1++c2) = Some (c++c2).
Proof.
  elim: c1=> //= i c1 Hrec;by case: ifP => [_[]<-|_/Hrec].
Qed.

Lemma lsem_cat_tl c2 c1 s1 s2 : lsem c1 s1 s2 -> 
  lsem (c1++c2) (setc s1 (s1.(lc)++c2)) (setc s2 (s2.(lc)++c2)).
Proof.
  elim=> [s|{s1}{s2} s1 s2 s3 Hsem1 _];first by constructor.
  apply: LSem1.
  case: Hsem1 => {s1 s2 s3}.
  + by move=> [m1 vm1 c] s2 ii x tag e cs /= -> Heq2 /=; by apply: LSem_assgn.
  + move=> [m1 vm1 c] s2 ii xs o es cs /= -> Heq2 /=; by apply: LSem_opn.
  + move=> [m1 vm1 c] ii lbl cs /= -> /=.
    by apply: (@LSem_lbl (c1++c2) _ _ lbl (cs++c2)).
  + move=> [m1 vm1 c] ii lbl cs cs' /= -> Heq2.
    apply: (@LSem_goto (c1 ++ c2) _ _ lbl (cs++c2) (cs'++c2)) => //=.
    by apply: find_label_cat_tl.
  + move=> ii [m1 vm1 c] e lbl cs cs' /= -> Heq1 Heq2.
    apply: (@LSem_condTrue (c1 ++ c2) _ _ e lbl (cs++c2) (cs'++c2))=> //.
    by apply: find_label_cat_tl.
  + move=> ii [m1 vm1 c] e lbl cs /= -> Heq1.
    apply: (@LSem_condFalse (c1 ++ c2) _ _ e lbl (cs++c2))=> //.
Qed.

Lemma valid_find_label p1 p2 c c' lbl: 
  valid p1 p2 c ->
  find_label lbl c = Some c' ->
  valid p1 p2 c'.
Proof.
  elim: c => //= -[ii [| b| lbl'|lbl'|e lbl'|]] l Hrec //= /andP[_ H];
    move:(H) => /Hrec H' //.
  by case:ifP => [_[]<-|_].
Qed.

Definition is_jump lbl (i:linstr) :=
 let (ii, ir) := i in
 match ir with
 | Lgoto lbl' => lbl == lbl'
 | Lcond _ lbl' => lbl == lbl'
 | _ => false
end.
  
Lemma find_label_cat_hd lbl c1 c2:
  ~~ has (is_label lbl) c1 ->
  find_label lbl (c1 ++ c2) = find_label lbl c2.
Proof.
  elim: c1 => //= i c1 Hrec Hdisj.
  have Hdisj' :  ~~ has (is_label lbl) c1.
  + by move: Hdisj;apply contra=> ->;rewrite orbC.
  have {Hrec}Hrec := Hrec Hdisj'.
  case:i Hdisj=> [ii [|b|lbl'|lbl'|e lbl'|]] //=;case:ifP => //= /eqP ?.
Qed.

Definition disjoint_lbl c1 c2 := 
  forall lbl, ~~(has (is_label lbl) c1 && has (is_jump lbl) c2).

Lemma disjoint_lbl_cons i c1 c2: 
  disjoint_lbl c1 (i :: c2) -> disjoint_lbl c1 c2.
Proof.
  by move=> Hd lbl;apply: contra (Hd lbl)=> /= /andP[]->->;rewrite orbC.
Qed.

Lemma disjoint_find_label c1 c2 c lbl: 
  disjoint_lbl c1 c2 ->
  find_label lbl c2 = Some c ->
  disjoint_lbl c1 c.
Proof.
  elim: c2 => //= i c2 Hrec Hd.
  have H:= (disjoint_lbl_cons Hd); have {Hrec}Hrec := Hrec H.
  by case:ifP => //= ? [] <-.
Qed.

Lemma lsem_cat_hd_aux c1 c2 s1 s2 : 
  disjoint_lbl c1 c2 ->
  disjoint_lbl c1 s1.(lc) ->
  lsem c2 s1 s2 -> 
  lsem (c1++c2) s1 s2.
Proof.
  move=> Hdisj2 Hdisjc Hsem.
  elim: Hsem Hdisjc => {s1 s2} [s1 | s1 s2 s3 Hsem1 _ Hrec] Hdisjc.
  + by constructor.
  have [Hv1' Hsem1']: disjoint_lbl c1 (lc s2) /\ lsem1 (c1 ++ c2) s1 s2.
  + case: Hsem1 Hdisjc=> {Hrec s1 s2 s3}.
    + move=> [m1 vm1 c] s2 ii x tag e cs /= -> Heq2 /= H;split=> //.
      by apply: LSem_assgn.
    + move=> [m1 vm1 c] s2 ii xs o es cs /= -> Heq2 /= H;split=> //.
      by apply: LSem_opn.
    + move=> [m1 vm1 c] ii lbl cs /= -> /= H;split => //.
      by apply: (@LSem_lbl (c1++c2) _ _ lbl cs).
    + move=> [m1 vm1 c] ii lbl cs cs' /= -> Hf H;split.
      + by apply: disjoint_find_label Hf.
      apply: (@LSem_goto (c1 ++ c2) _ _ lbl cs cs')=> //.
      rewrite find_label_cat_hd //.
      by apply:contra (H lbl)=> /= ->;rewrite eq_refl.
    + move=> ii [m1 vm1 c] e lbl cs cs' /= -> Hcond Hf H; split.
      by apply: disjoint_find_label Hf.
      apply: (@LSem_condTrue (c1 ++ c2) _ _ e lbl cs cs')=> //.
      rewrite find_label_cat_hd //.
      by apply: contra (H lbl)=> /= ->;rewrite eq_refl.
    + move=> ii [m1 vm1 c] e lbl cs /= -> Hcond H; split.
      apply: disjoint_lbl_cons H.
      apply: (@LSem_condFalse (c1 ++ c2) _ _ e lbl cs)=> //.
  by apply: (LSem1 Hsem1');apply Hrec.
Qed.

Lemma lsem_cat_hd c1 c2 s1 s2 : 
  disjoint_lbl c1 c2 ->
  (lc s1) = c2 ->
  lsem c2 s1 s2 -> 
  lsem (c1++c2) s1 s2.
Proof. by move=> Hdisj Heq; apply: (lsem_cat_hd_aux Hdisj _);rewrite Heq. Qed.

Lemma valid_has c lbl p1 p2 :
  valid p1 p2 c -> has (is_label lbl) c || has (is_jump lbl) c -> 
  ((p1 <=? lbl) && (lbl <? p2))%positive.
Proof.
  elim: c => //= i c Hrec /andP[] H /Hrec.
  by case: i H=>[ii [| |lbl'|lbl'|e lbl'|]] //=;
  rewrite {2}/is_label /=; case: eqP=> [->|].
Qed.

Lemma valid_disjoint p1 p2 p3 p4 c1 c2 : 
  ((p2 <=? p3) || (p4 <=? p1))%positive ->
  valid p1 p2 c1 -> 
  valid p3 p4 c2 ->
  disjoint_lbl c1 c2.
Proof.
  move=> Hp Hv1 Hv2 lbl;apply /negP=>/andP[] H1 H2.
  have := @valid_has _ lbl _ _ Hv1;rewrite H1=> /(_ isT) /andP[]/P_leP ? /P_ltP ?.
  have := @valid_has _ lbl _ _ Hv2;rewrite H2 orbT => /(_ isT) /andP[]/P_leP ? /P_ltP ?.
  case/orP: Hp => /P_leP ?;omega.
Qed.

Lemma disjoint_cat_l c1 c2 c : 
  disjoint_lbl (c1++c2) c <-> (disjoint_lbl c1 c /\ disjoint_lbl c2 c).
Proof.
  rewrite /disjoint_lbl;split.
  + move=> H1;split=> lbl;have := H1 lbl;rewrite has_cat;apply contra=>/andP[]->->//.
    by rewrite orbC.                                                             
  move=> [H1 H2] lbl;rewrite has_cat;apply /negP => /andP[]/orP []H H'.
  + by move: (H1 lbl);rewrite H H'.
  by move: (H2 lbl);rewrite H H'.
Qed.

Lemma LSem_step c s1 s2 : lsem1 c s1 s2 -> lsem c s1 s2.
Proof. by move=> H; apply (LSem1 H); apply LSem0. Qed.

Section PROOF.

  Variable p: sprog.
  Variable p': lprog.
  Hypothesis linear_ok : linear_prog p = ok p'.

  Let Pi (i:instr) := 
    forall lbl lbli li, linear_i i lbl [::] = ok (lbli, li) ->
    [/\ (lbl <=? lbli)%positive,
     valid lbl lbli li & 
     forall s1 s2, S.sem_I p s1 i s2 -> 
       lsem li (of_estate s1 li) (of_estate s2 [::])].

  Let Pi_r (i:instr_r) :=
    forall ii lbl lbli li, linear_i (MkI ii i) lbl [::] = ok (lbli, li) ->
    [/\ (lbl <=? lbli)%positive,
     valid lbl lbli li & 
     forall s1 s2, S.sem_i p s1 i s2 -> 
       lsem li (of_estate s1 li) (of_estate s2 [::])].

  Let Pc (c:cmd) := 
    forall lbl lblc lc, linear_c linear_i c lbl [::] = ok (lblc, lc) ->
    [/\ (lbl <=? lblc)%positive,
     valid lbl lblc lc & 
     forall s1 s2, S.sem p s1 c s2 -> 
       lsem lc (of_estate s1 lc) (of_estate s2 [::])].

  Let HmkI : forall i ii, Pi_r i -> Pi (MkI ii i).
  Proof.
    move=> i ii Hi_r lbl lbli li Hli.
    move: Hi_r=> /(_ ii lbl lbli li Hli) [H1 H2 H3]; split=> //.
    move=> s1 s2 Hs.
    by sinversion Hs; apply: H3.
  Qed.

  Let Hskip : Pc [::].
  Proof. 
    move=> lbl lbli li /= [] <- <-;split=> //. apply Pos.leb_refl.
    move=> s1 s2 H;inversion H;clear H;subst;constructor.
  Qed.

  Let Hseq : forall i c,  Pi i -> Pc c -> Pc (i::c).
  Proof.   
    move=> i c Hi Hc lbl lbl' l' /=.
    case Heqc: linear_c => [[lblc lc]|] //=.
    have {Hc}[Hle1 Hvc Hc]:= Hc _ _ _ Heqc.
    rewrite linear_i_nil.
    case Heqi: linear_i => [[lbli li]|] //= []??;subst lbl' l'.
    have {Hi}[Hle2 Hvi Hi]:= Hi _ _ _ Heqi;split.
    + by apply /P_leP;move/P_leP: Hle1;move/P_leP: Hle2=> ??;omega.
    + by rewrite valid_cat (valid_le_min Hle1 Hvi) (valid_le_max Hle2 Hvc).
    move=> [m1 vm1] s2 H;inversion H;clear H;subst.
    case: s0 H3 H5 => m2 vm2 H3 H5.
    apply (@lsem_trans (of_estate {| emem := m2; evm := vm2 |} lc)).
    + by apply (lsem_cat_tl lc (Hi _ _ H3)).
    have Hvc1 : valid 1 lblc lc.
    apply: valid_le_min Hvc.
    + by rewrite /is_true Pos.leb_le;apply Pos.le_1_l.
    apply: lsem_cat_hd=>//.
    + by apply: valid_disjoint Hvi Hvc;rewrite Pos.leb_refl orbC.
    by apply: Hc H5.
  Qed.

  Let Hassgn : forall x e tag, Pi_r (Cassgn x e tag).
  Proof.
    move=> x e tag ii lbl lbl' l' [] <- <-;rewrite Pos.leb_refl;split=>//.
    move=> -[m1 vm1] s2 H;inversion H;clear H;subst;apply LSem_step.
    eapply LSem_assgn=> /=; eauto.
  Qed.

  Let Hopn : forall xs o es, Pi_r (Copn xs o es).
  Proof.
    move=> x e tag ii lbl lbl' l' [] <- <-;rewrite Pos.leb_refl;split=>//.
    move=> -[m1 vm1] s2 H;inversion H;clear H;subst;apply LSem_step.
    eapply LSem_opn=> /=; eauto.
  Qed.
 
  Let Hif   : forall e c1 c2,  Pc c1 -> Pc c2 -> Pi_r (Cif e c1 c2).
  Proof.
    move=> e c1 c2 Hc1 Hc2 ii lbl lbl' l' /=.
    case Heq1: (c1)=> [|i1 l1].
    + subst;rewrite linear_c_nil;case Heq: linear_c => [[lbl2 lc2]|] //= [] <- <-.
      have Hlen := le_next lbl.
      have [Hle Hv2 Hs2]:= Hc2 _ _ _ Heq;split.
      + by apply: Pos_leb_trans Hle.
      + rewrite /= valid_cat Pos.leb_refl (valid_le_min Hlen Hv2) /= Pos.leb_refl.
        by rewrite (Pos_lt_leb_trans (lt_next _) Hle).
      move=> [m1 vm1] s2 H;inversion H;clear H;subst.
      + apply: LSem1.
        apply: LSem_condTrue=> //.
        rewrite -cat_cons.
        rewrite find_label_cat_hd.
        by rewrite /= /is_label /= eq_refl.
        apply /negP=> H.
        rewrite /= in H.
        have := @valid_has _ lbl _ _ Hv2; rewrite H=> /(_ isT) /andP[].
        by rewrite Pos.leb_antisym lt_next.
        sinversion H6.
        apply: LSem0.
      + apply: LSem1.
        apply: LSem_condFalse=> //.
        have {Hs2}Hs2:= Hs2 _ _ H6.
        have Hvc : valid lbl (next_lbl lbl) [:: MkLI ii (Lcond e lbl)].
        + by rewrite /= Pos.leb_refl lt_next.
        have Hd: disjoint_lbl [:: MkLI ii (Lcond e lbl)] lc2 by move=> ?.
        have /(_ (erefl _)):= @lsem_cat_hd [:: MkLI ii (Lcond e lbl)] lc2 _ _ Hd _ Hs2.
        move=> /(@lsem_cat_tl [:: MkLI ii (Llabel lbl)]) Hsem.
        apply (lsem_trans Hsem);case s2 => m2 vm2.
        by apply LSem_step;apply: LSem_lbl.
    rewrite -Heq1 => {Heq1 l1 i1};case Heq2: c2 => [|i2 l2].
    + subst;rewrite linear_c_nil;case Heq: linear_c => [[lbl1 lc1]|] //= [] <- <-.
      have Hlen := le_next lbl.
      have [Hle Hv1 Hs1]:= Hc1 _ _ _ Heq;split.
      + by apply: Pos_leb_trans Hle.
      + rewrite /= valid_cat Pos.leb_refl (valid_le_min Hlen Hv1) /= Pos.leb_refl.
        by rewrite (Pos_lt_leb_trans (lt_next _) Hle).
      move=> [m1 vm1] s2 H;inversion H;clear H;subst.
      + apply: LSem1.
        apply: LSem_condFalse=> //.
        by rewrite /= H5.
        have {Hs1}Hs1:= Hs1 _ _ H6.
        have Hvc : valid lbl (next_lbl lbl) [:: MkLI ii (Lcond (Pnot e) lbl)].
        + by rewrite /= Pos.leb_refl lt_next.
        have Hd: disjoint_lbl [:: MkLI ii (Lcond (Pnot e) lbl)] lc1 by move=> ?.
        have /(_ (erefl _)):= @lsem_cat_hd [:: MkLI ii (Lcond (Pnot e) lbl)] lc1 _ _ Hd _ Hs1.
        move=> /(@lsem_cat_tl [:: MkLI ii (Llabel lbl)]) Hsem.
        apply (lsem_trans Hsem);case s2 => m2 vm2.
        by apply LSem_step;apply: LSem_lbl.
      + apply: LSem1.
        apply: LSem_condTrue=> //.
        by rewrite /= H5.
        rewrite -cat_cons find_label_cat_hd //=.
        by rewrite /is_label /= eq_refl.
        apply/negP=> H.
        have := @valid_has _ lbl _ _ Hv1; rewrite H=> /(_ isT) /andP[].
        by rewrite Pos.leb_antisym lt_next.
        sinversion H6.
        apply: LSem0.
    rewrite -Heq2 => {Heq2 l2 i2}.
    rewrite linear_c_nil;case Heq1: linear_c => [[lbl1 lc1]|] //=.
    rewrite linear_c_nil;case Heq2: linear_c => [[lbl2 lc2]|] //= [] <- <-.
    have leL1 := le_next lbl; have leL2 := le_next (next_lbl lbl).
    have [Hle1 Hv1 Hs1]:= Hc1 _ _ _ Heq1;have [Hle2 Hv2 Hs2]:= Hc2 _ _ _ Heq2.
    have L2lbl2 := Pos_leb_trans Hle1 Hle2.
    have L1lbl2 := Pos_leb_trans leL2 L2lbl2.
    have lblL2 := Pos_leb_trans leL1 leL2.
    have lbllbl1 := Pos_leb_trans lblL2 Hle1;split.
    + by apply: Pos_leb_trans Hle2.
    + rewrite /= valid_cat /= valid_cat /=.
      rewrite Pos.leb_refl leL1 (Pos_lt_leb_trans (lt_next lbl) L1lbl2). 
      rewrite (Pos_lt_leb_trans (lt_next _) L2lbl2).  
      by rewrite (valid_le_min _ Hv2) // (valid_le_max Hle2 (valid_le_min lblL2 Hv1)).
    move=> [m1 vm1] s2 H;inversion H;clear H;subst.
    + apply LSem1 with (of_estate {| emem := m1; evm := vm1 |} (lc1 ++ [:: MkLI ii (Llabel (next_lbl lbl))])).
      + apply: LSem_condTrue=> //=.
        rewrite find_label_cat_hd /= /is_label /= ?eq_refl //.
        apply /negP => H; have := @valid_has _ lbl _ _ Hv2;rewrite H=> /(_ isT) /andP[].
        have Hlt := Pos_leb_trans leL2 Hle1.
        by rewrite Pos.leb_antisym (Pos_lt_leb_trans(lt_next _)(Pos_leb_trans leL2 Hle1)).
      have {Hs1}Hs1 := Hs1 _ _ H6.
      have Hd: 
        disjoint_lbl ([:: MkLI ii (Lcond e lbl)]++lc2++[:: MkLI ii (Lgoto (next_lbl lbl)); MkLI ii (Llabel lbl)]) lc1.
      + rewrite !disjoint_cat_l;split;first by move=> ?.
        split;first by apply: valid_disjoint Hv2 Hv1;rewrite Pos.leb_refl orbC.
        move=> lbl0 /=;rewrite orbF /is_label /=;case:eqP=> //= ?;subst lbl0.
        apply /negP => H; have := @valid_has _ lbl _ _ Hv1;rewrite H orbT.
        move=> /(_ isT) /andP[];rewrite Pos.leb_antisym. 
        by rewrite (Pos_lt_leb_trans (lt_next _) leL2).
      have /(_ (erefl _)):= lsem_cat_hd Hd _ Hs1.
      move=> /(@lsem_cat_tl [:: MkLI ii (Llabel (next_lbl lbl))]) /=.
      rewrite -!catA /= => Hsem; apply (lsem_trans Hsem).
      by apply LSem_step;apply: LSem_lbl.
    + apply LSem1 with (of_estate {| emem := m1; evm := vm1 |} (lc2 ++ [:: MkLI ii (Lgoto (next_lbl lbl)), MkLI ii (Llabel lbl) & lc1 ++ [:: MkLI ii (Llabel (next_lbl lbl))]])).
      + apply: LSem_condFalse=> //.
      apply lsem_trans with (of_estate s2 [:: MkLI ii (Lgoto (next_lbl lbl)), MkLI ii (Llabel lbl) & lc1 ++ [:: MkLI ii (Llabel (next_lbl lbl))]]).
      + have := Hs2 _ _ H6.
        move=> /(@lsem_cat_tl [:: MkLI ii (Lgoto (next_lbl lbl)), MkLI ii (Llabel lbl) & lc1 ++ [:: MkLI ii (Llabel (next_lbl lbl))]]) /= H.
        by have /= /(_ [:: MkLI ii (Lcond e lbl)]) H0:= lsem_cat_hd _ _ H;apply H0.
      apply LSem_step. eapply LSem_goto=> /=;eauto.
      rewrite find_label_cat_hd /= /is_label /=.
      + case: eqP => Heq. 
        + by have := lt_next lbl;rewrite Pos.ltb_antisym Heq Pos.leb_refl.
        rewrite find_label_cat_hd /= /is_label /= ?eq_refl //.
        apply /negP=> H;have := @valid_has _ (next_lbl lbl) _ _ Hv1.
        by rewrite H Pos.leb_antisym lt_next /= => /(_ isT).
      apply /negP=> H;have := @valid_has _ (next_lbl lbl) _ _ Hv2.
      by rewrite H Pos.leb_antisym (Pos_lt_leb_trans (lt_next _) Hle1) /= => /(_ isT).
  Qed.

  Let Hfor : forall v dir lo hi c, Pc c -> Pi_r (Cfor v (dir, lo, hi) c).
  Proof. by []. Qed.

  Let Hwhile : forall e c, Pc c -> Pi_r (Cwhile e c).
  Proof.
    move=> e c Hc ii lbl lbli li /=;rewrite linear_c_nil.
    case Heq:linear_c => [[lblc lc]|] //= [] ??;subst lbli li.
    have leL1 := le_next lbl; have leL2 := le_next (next_lbl lbl).
    have lblL2 := Pos_leb_trans leL1 leL2.
    have {Heq} [Hle Hv Hs]:= Hc _ _ _ Heq;split.
    + by apply: (Pos_leb_trans lblL2 Hle).
    + rewrite /= valid_cat /= Pos.leb_refl leL1 (valid_le_min _ Hv) //.
      rewrite (Pos_lt_leb_trans (lt_next _) Hle).        
      by rewrite (Pos_lt_leb_trans (lt_next _) (Pos_leb_trans leL2 Hle)).
    move=> s1 s2 H.
    + apply LSem1 with (of_estate s1 [::MkLI ii (Lcond e (next_lbl lbl))]).
      + eapply LSem_goto=> /=;eauto.
        rewrite /is_label /=.
        case: eqP => H'.
        + by have := lt_next lbl;rewrite Pos.ltb_antisym -H' Pos.leb_refl.
        rewrite find_label_cat_hd /= ?eq_refl //.
        rewrite /is_label /=.
        case: eqP => //.
        apply /negP=> H1;have := @valid_has _ lbl _ _ Hv.
        by rewrite H1 Pos.leb_antisym (Pos_lt_leb_trans (lt_next _) leL2) /= => /(_ isT).
    set C1 := lc ++ [:: MkLI ii (Llabel lbl); MkLI ii (Lcond e (next_lbl lbl))];
    set C2 := [:: MkLI ii (Lgoto lbl), MkLI ii (Llabel (next_lbl lbl)) & C1].
    elim: _ {-1}_ _ / H Hs (erefl (Cwhile e c))=> // {s1 s2}.
    + move=> s1 s2 s3 e0 c0 He Hsem Hsemi IH Hs [] He' Hc'.
      subst e0; subst c0.
      apply: LSem1.
      apply: LSem_condTrue=> //.
      rewrite /= /to_estate /=.
      by case: s1 He Hsem.
      by rewrite /= /is_label /= eq_refl.
      apply: lsem_trans.
      have Hd : disjoint_lbl [:: MkLI ii (Lgoto lbl); MkLI ii (Llabel (next_lbl lbl))] lc.
      + move=> lbl0 /=;rewrite orbF /is_label /=;case: eqP => //= ?;subst.
        apply /negP=> H;have := @valid_has _ (next_lbl lbl) _ _ Hv.
        by rewrite H Pos.leb_antisym lt_next /= orbC => /(_ isT).
      have /(_ (erefl _)):= lsem_cat_hd Hd _ (Hs _ _ Hsem).
      move=> /(@lsem_cat_tl [:: MkLI ii (Llabel lbl); MkLI ii (Lcond e (next_lbl lbl))]).
      rewrite /= -/C2 => H.
      apply: (lsem_trans H);apply: LSem_step.
      eapply LSem_lbl=> /=; eauto.
      exact: IH.
    + move=> s e0 c0 He Hs [] He' Hc'; subst e0; subst c0.
      apply: LSem1.
      apply: LSem_condFalse=> //.
      rewrite /= /to_estate /=.
      by case: s He.
      apply: LSem0.
  Qed.

  Let Hcall : forall i xs f es, Pi_r (Ccall i xs f es).
  Proof. by []. Qed.

  Lemma linear_cP c lbl lblc lc:
    linear_c linear_i c lbl [::] = ok (lblc, lc) ->
    [/\ (lbl <=? lblc)%positive,
     valid lbl lblc lc & 
     forall s1 s2, S.sem p s1 c s2 -> 
       lsem lc (of_estate s1 lc) (of_estate s2 [::])].
  Proof.
    apply (@cmd_rect Pi_r Pi Pc HmkI Hskip Hseq Hassgn Hopn Hif Hfor Hwhile Hcall).
  Qed.

  Lemma linear_fdP:
    forall fn m1 va m2 vr,
    S.sem_call p m1 fn va m2 vr -> lsem_fd p' m1 fn va m2 vr.
  Proof.
    move=> fn m1 va m2 vr H.
    sinversion H.
    have H0' := linear_ok.
    rewrite /linear_prog in H0'.
    have [f' [Hf'1 Hf'2]] := (get_map_cfprog H0' H0).
    have Hf'3 := Hf'1.
    apply: rbindP Hf'3=> [l Hc] [] Hf'3.
    rewrite /add_finfo in Hc.
    case Heq: linear_c Hc=> [[lblc lc]|] //= [] Hl.
    rewrite linear_c_nil in Heq.
    apply: rbindP Heq=> [[lblc' lc']] Heq [] Hz1 Hz2.
    have [_ _ H] := linear_cP Heq.
    move: H4=> /H /(@lsem_cat_tl [:: MkLI xH Lreturn]) Hs.
    rewrite -Hf'3 in Hf'2.
    apply: LSem_fd.
    exact: Hf'2.
    exact: H1.
    exact: H2.
    exact: H3.
    rewrite -Hl /=.
    rewrite /= Hz2 in Hs.
    exact: Hs.
    exact: H5.
    rewrite //.
    exact: H7.
  Qed.

End PROOF.