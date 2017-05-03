(* -------------------------------------------------------------------- *)
open Prog

type 'info coq_tbl

val string_of_string0 : 'a (* coq string *) -> string

val bi_of_nat : Datatypes.nat -> Bigint.zint

val pos_of_int : int -> BinNums.positive
val int_of_pos : BinNums.positive -> int
val bi_of_z    : BinNums.coq_Z -> B.zint

val pos_of_bi : Bigint.zint -> BinNums.positive
val bi_of_pos : BinNums.positive -> Bigint.zint

val z_of_bi : Bigint.zint -> BinNums.coq_Z
val bi_of_z : BinNums.coq_Z -> Bigint.zint

val int64_of_bi : Bigint.zint -> Integers.Int64.int
val bi_of_int64 : Integers.Int64.int -> Bigint.zint


(* -------------------------------------------------------------------- *)
val vari_of_cvari : 'a coq_tbl -> Expr.var_i -> var L.located

val fun_of_cfun : 'info coq_tbl -> BinNums.positive -> funname
val get_iinfo   : 'info coq_tbl -> BinNums.positive -> L.t * 'info
val cfdef_of_fdef : 'info coq_tbl -> 'info func -> BinNums.positive * Expr.fundef
val fdef_of_cfdef : 'info coq_tbl -> BinNums.positive * Expr.fundef -> 'info func

val cprog_of_prog : 'info prog -> 'info coq_tbl * Expr.prog
val prog_of_cprog : 'info coq_tbl -> Expr.prog -> 'info prog

