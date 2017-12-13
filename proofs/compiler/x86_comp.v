(* -------------------------------------------------------------------- *)
From mathcomp Require Import all_ssreflect.
(* ------- *) Require Import xseq expr linear compiler_util.
(* ------- *) Require Import low_memory x86_sem.
              Require Import oseq.

Require Import Utf8.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* -------------------------------------------------------------------- *)
(* Compilation of variables                                             *) 
Variant destination :=
| Daddr of address 
| DReg  of register
| DFlag of rflag.

Axiom destination_eqMixin : Equality.mixin_of destination. 
Canonical destination_eqType := EqType destination destination_eqMixin.

Definition string_of_register r :=
  match r with
  | RAX => "RAX"
  | RCX => "RCX"
  | RDX => "RDX"
  | RBX => "RBX"
  | RSP => "RSP"
  | RBP => "RBP"
  | RSI => "RSI"
  | RDI => "RDI"
  | R8  => "R8"
  | R9  => "R9"
  | R10 => "R10"
  | R11 => "R11"
  | R12 => "R12"
  | R13 => "R13"
  | R14 => "R14"
  | R15 => "R15"
  end%string.

Definition string_of_rflag (rf : rflag) : string :=
  match rf with
 | CF => "CF"
 | PF => "PF"
 | ZF => "ZF"
 | SF => "SF"
 | OF => "OF"
 | DF => "DF"
 end%string.

Definition regs_strings :=
  Eval compute in [seq (string_of_register x, x) | x <- registers].

Lemma regs_stringsE : regs_strings =
  [seq (string_of_register x, x) | x <- registers].
Proof. by []. Qed.

(* -------------------------------------------------------------------- *)
Definition rflags_strings :=
  Eval compute in [seq (string_of_rflag x, x) | x <- rflags].

Lemma rflags_stringsE : rflags_strings =
  [seq (string_of_rflag x, x) | x <- rflags].
Proof. by []. Qed.

(* -------------------------------------------------------------------- *)
Definition reg_of_string (s : string) :=
  assoc regs_strings s.

(* -------------------------------------------------------------------- *)
Definition rflag_of_string (s : string) :=
  assoc rflags_strings s.

(* -------------------------------------------------------------------- *)
Lemma rflag_of_stringK : pcancel string_of_rflag rflag_of_string.
Proof. by case. Qed.

Lemma reg_of_stringK : pcancel string_of_register reg_of_string.
Proof. by case. Qed.

Lemma inj_string_of_rflag : injective string_of_rflag.
Proof. by apply: (pcan_inj rflag_of_stringK). Qed.

Lemma inj_string_of_register : injective string_of_register.
Proof. by apply: (pcan_inj reg_of_stringK). Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_reg_of_string s1 s2 r :
     reg_of_string s1 = Some r
  -> reg_of_string s2 = Some r
  -> s1 = s2.
Proof. by rewrite /reg_of_string !regs_stringsE; apply: inj_assoc. Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_rflag_of_string s1 s2 rf :
     rflag_of_string s1 = Some rf
  -> rflag_of_string s2 = Some rf
  -> s1 = s2.
Proof. by rewrite /rflag_of_string !rflags_stringsE; apply: inj_assoc. Qed.

(* -------------------------------------------------------------------- *)

Definition var_of_register r := 
  {| vtype := sword; vname := string_of_register r |}. 

Definition var_of_flag f := 
  {| vtype := sbool; vname := string_of_rflag f |}. 

Lemma var_of_register_inj x y :
  var_of_register x = var_of_register y →
  x = y.
Proof. by move=> [];apply inj_string_of_register. Qed.

Lemma var_of_flag_inj x y : 
  var_of_flag x = var_of_flag y →
  x = y.
Proof. by move=> [];apply inj_string_of_rflag. Qed.

Lemma var_of_register_var_of_flag r f :
  ¬ var_of_register r = var_of_flag f.
Proof. by case: r;case: f. Qed.

Definition register_of_var (v:var) : option register := 
  if v.(vtype) == sword then reg_of_string v.(vname)
  else None.

Lemma var_of_register_of_var v r :
  register_of_var v = Some r →
  var_of_register r = v.
Proof.
  rewrite /register_of_var /var_of_register;case:ifP => //.
  case: v => [vt vn] /= /eqP -> H;apply f_equal.
  by apply: inj_reg_of_string H; apply reg_of_stringK.
Qed.

Definition flag_of_var (v: var) : option rflag :=
  if v.(vtype) == sbool then rflag_of_string v.(vname)
  else None.

Lemma var_of_flag_of_var v f :
  flag_of_var v = Some f →
  var_of_flag f = v.
Proof.
  rewrite /flag_of_var /var_of_flag;case:ifP => //.
  case: v => [vt vn] /= /eqP -> H; apply f_equal.
  by apply: inj_rflag_of_string H; apply rflag_of_stringK.
Qed.

Definition compile_var (v: var) : option destination :=
  match register_of_var v with
  | Some r => Some (DReg r)
  | None =>
    match flag_of_var v with
    | Some f => Some (DFlag f)
    | None => None
    end
  end.

Lemma register_of_var_of_register r :
  register_of_var (var_of_register r) = Some r.
Proof.
  rewrite /register_of_var /var_of_register /=.
  by apply reg_of_stringK.
Qed.

(* -------------------------------------------------------------------- *)
Variant arg_ty := TYcondt | TYoprd | TYreg | TYireg | Tyopt_oprd_w.

Scheme Equality for arg_ty.

Definition arg_ty_eqMixin := comparableClass arg_ty_eq_dec.
Canonical arg_ty_eqType := EqType arg_ty arg_ty_eqMixin.

Definition interp_ty (ty : arg_ty) : Type :=
  match ty with
  | TYcondt => condt
  | TYoprd  => oprd
  | TYreg   => register
  | TYireg  => ireg
  | Tyopt_oprd_w => option (oprd * option word)
  end.

Fixpoint interp_tys (tys : seq arg_ty) :=
  if tys is ty :: tys then
    interp_ty ty -> interp_tys tys
  else asm.
 
Record garg := { targ : arg_ty; varg : interp_ty targ }.

Definition typed_apply_garg {T} (ty: arg_ty) (arg: garg) : 
  (interp_ty ty → T) → option T.
  case: arg => ty'.
  case: (arg_ty_eq_dec ty ty').
  + move=> <- a op;exact (Some (op a)).
  move=> _ _ _;exact None.
Defined.

Fixpoint typed_apply_gargs (tys: seq arg_ty) (iregs: seq garg)
  : interp_tys tys -> option asm :=
  match tys, iregs with
  | [::], [::] => Some
  | ty :: tys', ir :: iregs' => λ op,
                          (@typed_apply_garg _ ty ir op >>=
                           @typed_apply_gargs tys' iregs')%O
  | _, _ => λ _, None
  end.

(* -------------------------------------------------------------------- *)

(* Describe where to recover the argument in the intermediate language *)
Variant arg_desc :=
| ADImplicit of var
| ADExplicit of nat & option var. 
 (* [ADExplicit i (Some x)] in this case the ith argument should be the variable x (see SHL) *)

Definition arg_desc_beq ad1 ad2 := 
  match ad1, ad2 with
  | ADImplicit x1, ADImplicit x2 => x1 == x2
  | ADExplicit i1 ox1, ADExplicit i2 ox2 => (i1 == i2) && (ox1 == ox2)
  | _, _ => false
  end.

Lemma arg_desc_beq_axiom : Equality.axiom arg_desc_beq.
Proof.
  move=> [x1 | i1 ox1] [x2 | i2 ox2] //=.
  + by case: (x1 =P x2) => [-> | neq ];constructor;congruence.
  + by constructor.
  + by constructor.
  case: (i1 =P i2) => [-> | neq ];last by constructor;congruence.
  by case: (_ =P _) => [-> | neq ];constructor;congruence.
Qed.

Definition arg_desc_eqMixin := Equality.Mixin arg_desc_beq_axiom .
Canonical arg_desc_eqType := EqType _ arg_desc_eqMixin.

Definition wf_implicit (ad: arg_desc) : bool :=
  if ad is ADImplicit x then
    compile_var x != None
  else true.

(* -------------------------------------------------------------------- *)
(* Generated ASM semantics                                              *)

Variant argument :=
 | Aflag  of rflag
 | Aoprd  of oprd
 | Acondt of condt.

Axiom argument_eqMixin : Equality.mixin_of argument.
Canonical argument_eqType := EqType argument argument_eqMixin.

Definition arg_of_dest (d: destination): argument :=
  match d with
  | Daddr addr => Aoprd (Adr_op addr)
  | DReg  r    => Aoprd (Reg_op r)
  | DFlag f    => Aflag f
  end.

Print garg.
Show Match arg_ty.
Definition arg_of_garg (i: garg) : argument :=
  let (ty, arg) := i in
  match ty return interp_ty ty -> argument with
  | TYcondt =>
    | TYoprd =>
    | TYreg =>
    | TYireg =>
    | Tyopt_oprd_w =>
    end
      

match # with
 | TYcondt =>
 | TYoprd =>
 | TYreg =>
 | TYireg =>
 | Tyopt_oprd_w =>
 end
|
  
  match i with
  | IRReg r => AReg r
  | IRImm i => AInt i
  end.

Definition sem_lo_ad_in (xs : seq ireg) (ad : arg_desc) : option argument :=
  match ad with
  | ADImplicit x => ssrfun.omap arg_of_dest (compile_var x)
  | ADExplicit n => ssrfun.omap arg_of_ireg (onth xs n)
  end.

Definition sem_lo_ad_out (xs : seq ireg) (ad : arg_desc) : option destination :=
  match ad with
  | ADImplicit x => compile_var x
  | ADExplicit n =>
      if onth xs n is Some (IRReg y) then Some (DReg y) else None
  end.

Definition eval_lo (m : lomem) (a : argument) : value :=
  match a with
  | AReg x => VInt (lm_reg m x)
  | AFlag f => VBool (lm_fgs m f)
  | AInt i => VInt i
  end.

Definition set_lo (d: destination) (v: value) (m: lomem) : option lomem :=
  match d, v with
  | DReg r, VInt i => Some (write_reg m r i)
  | DFlag f, VBool b => Some (write_flag m f b)
  | _, _ => None
  end.

Definition sets_lo (m : lomem) (x : seq destination) (v : seq value) :=
  if size x == size v then
    foldl (fun m xv => obind (set_lo xv.1 xv.2) m) (Some m) (zip x v)
  else None.

Definition sem_lo_cmd (op : seq value -> option (seq value)) m outv inv :=
  if op [seq eval_lo m x | x <- inv] is Some res then
    sets_lo m outv res
  else None.

Definition cmd_name_of_loid (loid: low_instr) : cmd_name :=
  match loid with
  | ADDC_lo _ _ => ADDC
  | SUBC_lo _ _ => SUBC
  | MUL_lo => MUL
  end.

Definition operands_of_loid (li: low_instr) : seq ireg :=
  match li with
  | ADDC_lo x y => [:: IRReg x ; y ]
  | SUBC_lo x y => [:: IRReg x ; IRImm y ]
  | MUL_lo => [::]
  end.

Definition sem_lo_gen_aux (m: lomem) 
     (c:cmd_name) (outx inx: seq arg_desc) (li: low_instr) : option lomem :=
  let xs := operands_of_loid li in
  let inx  := omap (sem_lo_ad_in xs) inx in
  let outx := omap (sem_lo_ad_out xs) outx in

  if (inx, outx) is (Some inx, Some outx) then
    sem_lo_cmd (semop c) m outx inx
  else None.

(* -------------------------------------------------------------------- *)

Definition wf_sem (c: cmd_name) (tys: seq arg_ty) (sem: interp_tys tys) : Prop :=
  ∀ irs loid,
    typed_apply_iregs irs sem = Some loid →
    cmd_name_of_loid loid = c ∧
    operands_of_loid loid = irs.

Definition gen_sem_correct (tys: seq arg_ty) id_name id_out id_in (sem:interp_tys tys) := 
  ∀ m irs loid,
    typed_apply_iregs irs sem = Some loid →
    sem_lo_gen_aux m id_name id_out id_in loid = Some (sem_lo m loid).     

Record instr_desc := {
  id_name : cmd_name;
  id_in   : seq arg_desc;
  id_out  : seq arg_desc;
  id_lo   : seq arg_ty;
  id_sem  : interp_tys id_lo;

  (* FIXME : Add the functionnal semantic of the operator in the record,
             this require to the have its syntatic type *)
  id_in_wf : all wf_implicit id_in;
  id_out_wf : all wf_implicit id_out;
  id_sem_wf: wf_sem id_name id_sem;
  id_gen_sem_wf : gen_sem_correct id_name id_out id_in id_sem;
}.

Definition sem_lo_gen (m: lomem) (id: instr_desc) (li: low_instr) : option lomem :=
  sem_lo_gen_aux m id.(id_name) id.(id_out) id.(id_in) li.

(* -------------------------------------------------------------------- *)
(* Generated mixed semantics                                            *)

Definition sem_ad_in (xs : seq expr) (ad : arg_desc) : option expr :=
  match ad with
  | ADImplicit x => Some (EVar x)
  | ADExplicit n => onth xs n
  end.

Definition sem_ad_out (xs : seq expr) (ad : arg_desc) : option var :=
  match ad with
  | ADImplicit x => Some x
  | ADExplicit n =>
      if onth xs n is Some (EVar y) then Some y else None
  end.

Definition sem_id
  (m : mem) (id : instr_desc) (xs : seq expr) : option mem :=
  let: inx  := omap (sem_ad_in xs) id.(id_in ) in
  let: outx := omap (sem_ad_out xs) id.(id_out) in

  if (inx, outx) is (Some inx, Some outx) then
    sem_cmd (semop id.(id_name)) m outx inx
  else None.

(* -------------------------------------------------------------------- *)
(* Definitions of descriptors                                           *)

Lemma eval_lo_arg_of_ireg m i :
  eval_lo m (arg_of_ireg i) = eval_ireg m i.
Proof. by case: i. Qed.

Definition evalrw := (compile_var_CF, eval_lo_arg_of_ireg).

Definition ADDC_desc : instr_desc. refine {|
  id_name := ADDC;
  id_in   := [:: ADExplicit 0; ADExplicit 1; ADImplicit vCF];
  id_out  := [:: ADExplicit 0; ADImplicit vCF];
  id_lo   := [:: TYVar; TYVL];
  id_sem  := ADDC_lo;
|}.
Proof.
  abstract by rewrite/= compile_var_CF.
  abstract by rewrite/= compile_var_CF.
  abstract by move => irs loid; case: irs => // [] // [] // x [] // y [] // [] <-.
  abstract 
    by move=> r [] // [] // x [] // y [] // loid [<-];
    rewrite /sem_lo_gen_aux /= ?evalrw /sem_lo_cmd /= ?evalrw;
    case: addc.
Defined.

Definition SUBC_desc : instr_desc. refine {|
  id_name := SUBC;
  id_in   := [:: ADExplicit 0; ADExplicit 1; ADImplicit vCF];
  id_out  := [:: ADExplicit 0; ADImplicit vCF];
  id_lo   := [:: TYVar; TYLiteral];
  id_sem  := SUBC_lo;
|}.
Proof.
  abstract by rewrite/= compile_var_CF.
  abstract by rewrite/= compile_var_CF.
  abstract by case => // [] // [] // x [] // [] // n [] // loid [] <-.
  abstract 
    by move=> r [] // [] // x [] // [] // n [] // loid [] <-;
    rewrite /sem_lo_gen_aux /= ?evalrw /sem_lo_cmd /= ?evalrw;
    case: subc.
Defined.

Definition MUL_desc : instr_desc. refine {|
  id_name := MUL;
  id_in   := [:: ADImplicit (var_of_register R1); ADImplicit (var_of_register R2)];
  id_out   := [:: ADImplicit (var_of_register R1); ADImplicit (var_of_register R2)];
  id_lo   := [::];
  id_sem  := MUL_lo;
|}.
Proof.
  abstract by rewrite/= /compile_var !register_of_var_of_register.
  abstract by rewrite/= /compile_var !register_of_var_of_register.
  abstract by move => [] // loid [] <-.
  abstract 
    by move => r [] // loid [] <-;
    rewrite /sem_lo_gen_aux /= /compile_var !register_of_var_of_register /=
    /sem_lo_cmd /=; case: mul.
Defined.

Definition get_id (c : cmd_name) :=
  match c with
  | ADDC => ADDC_desc
  | SUBC => SUBC_desc
  | MUL => MUL_desc
  end.

Lemma get_id_ok c : (get_id c).(id_name) = c.
Proof. by case: c. Qed.

(* -------------------------------------------------------------------- *)
(* High level to mixed semantics                                        *)

Definition check_cmd_arg (loargs : seq expr) (x : expr) (ad : arg_desc) :=
  match ad with
  | ADImplicit y => x == EVar y
  | ADExplicit n => (n < size loargs) && (x == nth x loargs n)
  end.

Definition check_cmd_res (loargs : seq expr) (x : var) (ad : arg_desc) :=
  match ad with
  | ADImplicit y => x == y
  | ADExplicit n => (n < size loargs) && (EVar x == nth (EVar x) loargs n)
  end.

Definition check_cmd_args
  (c : cmd_name) (outx : seq var) (inx : seq expr) (loargs : seq expr)
:=
  let: id := get_id c in

     all2 (check_cmd_res loargs) outx id.(id_out)
  && all2 (check_cmd_arg loargs) inx  id.(id_in ).

Lemma Pin (loargs hiargs : seq expr) (ads : seq arg_desc) :
     all2 (check_cmd_arg loargs) hiargs ads
  -> omap (sem_ad_in loargs) ads = Some hiargs.
Proof.
rewrite all2P => /andP [/eqP eqsz h];rewrite omap_map.
apply/eqP; rewrite oseqP.
apply/eqP/(eq_from_nth (x0 := None)); rewrite ?(size_map, eqsz) //.
move=> i lt_i_ads; have ad0 : arg_desc := (ADExplicit 0).
rewrite (nth_map ad0) // (nth_map (EVar vCF)) ?eqsz // /sem_ad_in.
set x1 := nth (EVar vCF) _ _; set x2 := nth ad0 _ _.
have -/(allP h) /=: (x1, x2) \in zip hiargs ads.
+ by rewrite -nth_zip // mem_nth // size_zip eqsz minnn.
rewrite /check_cmd_arg; case: x2 => [? /eqP->//|].
by move=> n /andP[len /eqP->];apply /eqP;rewrite (onth_sizeP x1).
Qed.

Lemma Pout (loargs : seq expr) (hiargs : seq var) (ads : seq arg_desc) :
     all2 (check_cmd_res loargs) hiargs ads
  -> omap (sem_ad_out loargs) ads = Some hiargs.
Proof.
rewrite all2P => /andP [/eqP eqsz h]; rewrite omap_map.
apply/eqP; rewrite oseqP.
apply/eqP/(eq_from_nth (x0 := None)); rewrite ?(size_map, eqsz) //.
move=> i lt_i_ads; have ad0 : arg_desc := (ADExplicit 0).
rewrite (nth_map ad0) // (nth_map vCF) ?eqsz // /sem_ad_out.
set x1 := nth vCF _ _; set x2 := nth ad0 _ _.
have -/(allP h) /=: (x1, x2) \in zip hiargs ads.
+ by rewrite -nth_zip // mem_nth // size_zip eqsz minnn.
rewrite /check_cmd_res; case: x2 => [? /eqP->//|].
by move=> n /andP[len /eqP];rewrite (onth_nth_size (EVar x1) len) => <-.
Qed.

Theorem L0 c outx inx loargs m1 m2 :
     check_cmd_args c outx inx loargs
  -> semc m1 (c, outx, inx) = Some m2
  -> sem_id m1 (get_id c) loargs = Some m2.
Proof.
by case/andP=> h1 h2; rewrite /sem_id /semc (Pin h2) (Pout h1) get_id_ok.
Qed.

Inductive source_position := 
  | InArgs of nat
  | InRes  of nat.

Definition get_loarg (outx: seq var) (inx:seq expr) (d:source_position) := 
  match d with
  | InArgs x => onth inx x
  | InRes  x => ssrfun.omap EVar (onth outx x)
  end.

(* FIXME: provide a more efficiant version of map on nat here *)
Definition nmap (T:Type) := nat -> option T.
Definition nget (T:Type) (m:nmap T) (n:nat) := m n.
Definition nset (T:Type) (m:nmap T) (n:nat) (t:T) := 
  fun x => if x == n then Some t else nget m x.
Definition nempty (T:Type) := fun n:nat => @None T.

Definition set_expr (m:nmap source_position) (n:nat) (x:source_position) :=
  match nget m n with
  | Some _ => m 
  | None   => nset m n x
  end.

Definition compile_hi_arg (p:nat -> source_position) (ad: arg_desc) (i:nat) (m: nmap source_position) := 
  match ad with
  | ADImplicit _ => m
  | ADExplicit n => set_expr m n (p i)
  end.

Definition mk_loargs (c : cmd_name)  :=
  let: id := get_id c in
  let m := foldl (fun m p => compile_hi_arg InArgs p.1 p.2 m) (nempty _)
                 (zip id.(id_in) (iota 0 (size id.(id_in)))) in
  let m := foldl (fun m p => compile_hi_arg InRes p.1 p.2 m) m
                 (zip id.(id_out) (iota 0 (size id.(id_out)))) in 
  odflt [::] (omap (nget m) (iota 0 (size id.(id_lo)))).

Definition compile_hi_cmd (c : cmd_name) (outx : seq var) (inx : seq expr) := 
  let: id := get_id c in
  omap (get_loarg outx inx) (mk_loargs c) >>= fun loargs =>
    if check_cmd_args c outx inx loargs then Some loargs
    else None.

Lemma compile_hiP (c : cmd_name) (outx : seq var) (inx : seq expr) loargs :
  compile_hi_cmd c outx inx = Some loargs ->
  check_cmd_args c outx inx loargs.
Proof. by move=> /obindI [loargs'] [H1];case:ifP => // ? [<-]. Qed.

Theorem L1 c outx inx m1 m2 loargs :
     compile_hi_cmd c outx inx = Some loargs 
  -> semc m1 (c, outx, inx) = Some m2
  -> sem_id m1 (get_id c) loargs = Some m2.
Proof. by move=> /compile_hiP;apply L0. Qed.

(* -------------------------------------------------------------------- *)
(* Mixed semantics to generated ASM semantics                           *)

Variant lom_eqv (m : mem) (lom : lomem) :=
  | MEqv of
      (forall r, VInt  (lom.(lm_reg) r) = get m (var_of_register r))
    & (forall f, VBool (lom.(lm_fgs) f) = get m (var_of_flag f)).

Definition ireg_of_expr (arg: expr) : option ireg :=
  match arg with
  | EVar x => ssrfun.omap IRReg (register_of_var x)
  | EInt i => Some (IRImm i)
  end.

Lemma toto_in ads vs args irs m lom :
  lom_eqv m lom →
  all wf_implicit ads →
  omap ireg_of_expr vs = Some irs →
  omap (sem_ad_in vs) ads = Some args →
  ∃ loargs, omap (sem_lo_ad_in irs) ads = Some loargs ∧
  map (eval_lo lom) loargs = map (eval m) args.
Proof.
  move => eqm hwf hirs.
  elim: ads args hwf.
  - by move => args _ [] <-; exists [::].
  move => ad ads ih args' h; rewrite /= in h; case/andP: h => hwf hwf'.
  case/omap_consI => arg [] args [] -> ha has.
  case: (ih _ hwf' has) => {ih} loargs [hlo hlo'].
  case: ad ha hwf.
  + move => x /= [] ?; subst arg.
    case hd: compile_var => [ d | ] // _.
    exists (arg_of_dest d :: loargs); split; first by rewrite /= hlo.
    rewrite/=; f_equal => //.
    case: eqm => hr hf.
    move: hd; rewrite/compile_var.
    case eq1: register_of_var => [ r | ].
    * by case => <- /=; rewrite hr (var_of_register_of_var eq1).
    case eq2: flag_of_var => [ f | ] //.
    by case => <- /=; rewrite hf (var_of_flag_of_var eq2).
  move => /= x /onthP - /(_ (EInt 0)) /andP [] hx /eqP hx' _; subst arg.
  case: (onth_omap_size (EInt 0) hirs hx) => y [hy eqy].
  rewrite hy /= hlo /=.
  eexists; split; first by reflexivity.
  rewrite /=; f_equal => //.
  rewrite eval_lo_arg_of_ireg /=.
  case eqx: nth eqy => [ vx | i ]; last by case => <-.
  case: eqm => eqm _.
  by case eq1: register_of_var => [ z | ] // [] <-; rewrite eqm (var_of_register_of_var eq1).
Qed.

Lemma lom_eqv_set_register m lom x r i :
  lom_eqv m lom →
  register_of_var x = Some r →
  lom_eqv (set m x (VInt i)) (write_reg lom r i).
Proof.
  case => hr hf hx; rewrite -(var_of_register_of_var hx) => {x hx}.
  split => q; rewrite get_set /=.
  + case: eqP; first by move ->; rewrite eq_refl.
    move => ne; case: eqP => // /var_of_register_inj //.
  case: eqP => // h; elim: (var_of_register_var_of_flag (esym h)).
Qed.

Lemma lom_eqv_set_flag m lom x f b :
  lom_eqv m lom →
  flag_of_var x = Some f →
  lom_eqv (set m x (VBool b)) (write_flag lom f b).
Proof.
  case => hr hf hx; rewrite -(var_of_flag_of_var hx) => {x hx}.
  split => q; rewrite get_set /=.
  + case: eqP => // h; elim: (var_of_register_var_of_flag h).
  case: eqP; first by move ->; rewrite eq_refl.
  move => ne; case: eqP => // /var_of_flag_inj //.
Qed.

Lemma set_lom_eqv m lom x y v lom' :
  lom_eqv m lom →
  compile_var x = Some y →
  set_lo y v lom = Some lom' →
  lom_eqv (set m x v) lom'.
Proof.
  case => hr hf.
  rewrite /compile_var.
  case e1: register_of_var => [ r | ].
  + case => <-; case: v => // i [] <-.
    exact: lom_eqv_set_register.
  case e2: flag_of_var => // [ i ] [] <-; case: v => //= b [] <-.
  exact: lom_eqv_set_flag.
Qed.

Lemma sets_lo_cons m d ds v vs :
  sets_lo m (d :: ds) (v :: vs) = set_lo d v m >>= λ m', sets_lo m' ds vs.
Proof.
  rewrite {1} /sets_lo /=.
  case: set_lo; last by case: eqP => // _; exact: foldl_bind_None.
  case: eqP.
  + move/succn_inj => eq_sz /=.
     by move => m' /=; rewrite /sets_lo; case: eqP.
  move => ne_sz /= m'.
  by rewrite /sets_lo; case: eqP => // k; elim: ne_sz; rewrite k.
Qed.

Lemma toto_out ads vs out irs m1 lom1 outv m2 :
  lom_eqv m1 lom1 →
  all wf_implicit ads →
  omap ireg_of_expr vs = Some irs →
  omap (sem_ad_out vs) ads = Some out →
  sets m1 out outv = Some m2 →
  ∃ outx, omap (sem_lo_ad_out irs) ads = Some outx ∧
  ∃ lom2 : lomem, sets_lo lom1 outx outv = Some lom2 ∧ lom_eqv m2 lom2.
Proof.
  move => eqm hwf hirs.
  elim: ads out outv m1 lom1 eqm hwf.
  - move => out outv m1 lom1 eqm _ [] <- /setsI [hsz ->]; exists [::]; split => //.
    by case: outv hsz => // _; exists lom1.
  move => ad ads ih args' outv' m1 lom1 eqm h; rewrite /= in h; case/andP: h => hwf hwf'.
  case/omap_consI => arg [] args [] -> ha has /sets_consI [v] [outv] [? hm2]; subst outv'.
  case: ad ha hwf.
  + move => x /= [] ?; subst arg.
    case hd: compile_var => [ d | ] // _.
    have : ∃ lom', set_lo d v lom1 = Some lom'.
    admit.
    case => lom' hlom'.
    have eqm' := set_lom_eqv eqm hd hlom'.
    case: (ih args outv (set m1 x v) lom' eqm' hwf' has hm2)
      => dst [hdst] [lom2] [hlom2 eqm2].
    exists (d :: dst); split; first by rewrite hdst.
    exists lom2; split; first by rewrite sets_lo_cons hlom' /=. done.

  move => n /=.
  case eq1: onth => [ [] q | ] // [] ? _; subst q.
  move: eq1 => /onthP - /(_ (EInt 0)) /andP [] hsz /eqP harg.
  case: (onth_omap_size (EInt 0) hirs hsz) => y [hy]; rewrite harg.
  case eqy: register_of_var => [ y' | ] // - [] ?; subst y.
  have eqy' : compile_var arg = Some (DReg y') by rewrite /compile_var eqy.
  have : ∃ i, v = VInt i.
  admit.
  case => i ?; subst v.
  have : ∃ lom', set_lo (DReg y') i lom1 = Some lom' by eexists.
  case => lom' hlom'.
  have eqm' := set_lom_eqv eqm eqy' hlom'.
  have := ih _ _ _ _ eqm' hwf' has hm2.
  case => dst [hdst] [lom2] [hlom2 eqm2].
  rewrite hy hdst /=.
  eexists; split; first by reflexivity.
  case: hlom' => ?; subst lom'.
  by exists lom2.
Admitted.

(* -------------------------------------------------------------------- *)
Definition compile_lo (tys: seq arg_ty) (args: seq expr) (op: interp_tys tys) : option low_instr :=
  omap ireg_of_expr args >>= fun iregs =>
    @typed_apply_iregs tys iregs op.


Definition compile_gen (c : cmd_name) (args : seq expr) :=
  let id := get_id c in compile_lo args id.(id_sem).

Theorem L2 c vs m1 m2 loid lom1:
     compile_gen c vs = Some loid
  -> sem_id m1 (get_id c) vs = Some m2
  -> lom_eqv m1 lom1
  -> exists lom2, sem_lo_gen lom1 (get_id c) loid = Some lom2
  /\ lom_eqv m2 lom2.
Proof.
rewrite /compile_gen /sem_id => h.
case E1: (omap _) => [args|//].
case E2: (omap _) => [out|//].
rewrite get_id_ok; set op := (X in sem_cmd X).
rewrite /sem_cmd; case E3: (op _) => [outv|//].
rewrite /sem_lo_gen /sem_lo_gen_aux.
move: h. rewrite /compile_lo. case h: omap => // [irs] hirs.
rewrite (proj2 (id_sem_wf hirs)).
rewrite /sem_lo_cmd.
rewrite get_id_ok -/op.
move => hsets heqm.
have [ inx [ E4 E5 ] ] := toto_in heqm (id_in_wf _) h E1. rewrite E4.
have [ outx [ E6 [ lom2 [ E7 E8 ] ] ] ] := toto_out heqm (id_out_wf _) h E2 hsets.
rewrite E6 E5 E3. eauto.
Qed.

(* -------------------------------------------------------------------- *)
(* From generated ASM semantics to TCB ASM semantics                    *)

Lemma compile_cmd_name c vs loid :
  compile_gen c vs = Some loid →
  cmd_name_of_loid loid = c.
Proof.
  rewrite /compile_gen /compile_lo.
  case: omap => // irs h.
  have := @id_sem_wf (get_id c) irs loid h.
  rewrite get_id_ok.
  by case.
Qed.

Theorem L3 c vs m1 m2 loid lom :
     compile_gen c vs = Some loid
  -> sem_id m1 (get_id c) vs = Some m2
  -> lom_eqv m1 lom
  -> lom_eqv m2 (sem_lo lom loid).
Proof.
  move => hc.
  move/L2: (hc) => h/h{h} h/h{h} [lom'] [].
  rewrite -(compile_cmd_name hc).
  move /obindI : (hc) => [irs [? Hwt]].
  have := (id_gen_sem_wf lom Hwt).  
  by rewrite /sem_lo_gen (compile_cmd_name hc) => -> [<-].
Qed.

(* -------------------------------------------------------------------- *)
(* Putting all together                                                 *)

Definition compile (c : cmd_name) (outx : seq var) (inx:seq expr) := 
  compile_hi_cmd c outx inx >>= compile_gen c.

Theorem L (c : cmd_name) (outx : seq var) (inx : seq expr) loid (m1 m2 : mem) lom :
     compile c outx inx = Some loid 
  -> semc m1 (c, outx, inx) = Some m2
  -> lom_eqv m1 lom
  -> lom_eqv m2 (sem_lo lom loid).
Proof. 
  by move=> /obindI [lexprs []] /L1 H1 /L3 H3 /H1 /H3 H4 /H4.
Qed.
