(* * License
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

(* * Utility functions for intermediate language *)
(* ** Imports and abbreviations *)
open Core_kernel.Std
open IL_Lang
open IL_Utils

module L = ParserUtil.Lexing
module P = ParserUtil
module HT = Hashtbl
module DS = Dest.Set
module SS = String.Set
module PS = Param.Set
module VS = Var.Set

(* ** Map over all function bodies in modul, fundef, func
 * ------------------------------------------------------------------------ *)

let map_body_func ~f fd =
  { f_body      = f fd.f_body;
    f_arg       = fd.f_arg;
    f_ret       = fd.f_ret;
    f_call_conv = fd.f_call_conv;
  }

let map_body_named_func ~f nf =
  { nf_name = nf.nf_name;
    nf_func = map_body_func ~f nf.nf_func }

let map_body_modul ~f modul fname =
  map_named_func ~f:(map_body_named_func ~f) modul fname

let map_body_modul_all ~f modul =
  { mod_rust_sections   = modul.mod_rust_sections;
    mod_funprotos       = modul.mod_funprotos;
    mod_params          = modul.mod_params;
    mod_rust_attributes = modul.mod_rust_attributes;
    mod_funcs =
      List.map ~f:(map_body_named_func ~f) modul.mod_funcs
  }



(* ** Concat-map instructions (with position and info)
 * ------------------------------------------------------------------------ *)

let rec concat_map_instr ~f pos instr =
  let loc = instr.L.l_loc in
  match instr.L.l_val with
  | Block(bis,i) ->
    f loc pos i @@ Block(bis,None)
  | While(wt,fc,s,i) ->
    let s = concat_map_stmt ~f (pos@[0]) s in
    f loc pos i @@ While(wt,fc,s,None)
  | For(iv,lb,ub,s,i) ->
    let s = concat_map_stmt ~f (pos@[0]) s in
    f loc pos i @@ For(iv,lb,ub,s,None)
  | If(c,s1,s2,i) ->
    let s1 = concat_map_stmt ~f (pos@[0]) s1 in
    let s2 = concat_map_stmt ~f (pos@[1]) s2 in
    f loc pos i @@ If(c,s1,s2,None)

and concat_map_stmt ~f pos stmt =
  List.concat @@
    List.mapi ~f:(fun i instr -> concat_map_instr ~f (pos@[i]) instr) stmt

let concat_map_func ~f = map_body_func ~f:(concat_map_stmt [] ~f)

let concat_map_modul_all ~f m = map_body_modul_all ~f:(concat_map_stmt [] ~f) m

let concat_map_modul ~f = map_body_modul ~f:(concat_map_stmt [] ~f)

(* ** Map function over all variables
 * ------------------------------------------------------------------------ *)

let map_vars_patom ~f pa =
  match pa with
  | Pparam(_) -> pa
  | Pvar(v)   -> Pvar(f v)

let rec map_vars_idx ~f i =
  match i with
  | Ipexpr(pe) -> Ipexpr(map_vars_pexpr ~f pe)
  | Ivar(v)    -> Ivar(f v)

and map_vars_rdest ~f rd =
  match rd with
  | Mem(sd,pe) -> Mem(map_vars_sdest ~f sd, map_vars_pexpr ~f pe)
  | Sdest(sd)  -> Sdest(map_vars_sdest ~f sd)

and map_vars_dest ~f d =
  match d with
  | Ignore(_) -> d
  | Rdest(rd) -> Rdest(map_vars_rdest ~f rd)

and map_vars_sdest ~f sd =
  { d_var = f sd.d_var
  ; d_idx = Option.map ~f:(map_vars_idx ~f) sd.d_idx
  ; d_loc = sd.d_loc }
    
and map_vars_pexpr pe ~f =
  let mvp = map_vars_pexpr ~f in
  let mva = map_vars_patom ~f in
  match pe with
  | Patom(pa)         -> Patom(mva pa)
  | Pbinop(o,pe1,pe2) -> Pbinop(o,mvp pe1, mvp pe2)
  | Pconst(c)         -> Pconst(c)

let rec map_vars_pcond ~f pc =
  let mvpc = map_vars_pcond ~f in
  let mvpe = map_vars_pexpr ~f in
  match pc with
  | Pbool(_)        -> pc
  | Pnot(pc)        -> Pnot(mvpc pc)
  | Pbop(o,pc1,pc2) -> Pbop(o,mvpc pc1, mvpc pc2)
  | Pcmp(o,pe1,pe2) -> Pcmp(o,mvpe pe1, mvpe pe2)

let map_vars_src ~f = function
  | Imm(i,pe) -> Imm(i,map_vars_pexpr ~f pe)
  | Src(d)    -> Src(map_vars_rdest ~f d)

let map_vars_fcond ~f fc =
  { fc with fc_var = f fc.fc_var }

let map_vars_fcond_or_pcond ~f = function
  | Fcond(fc) -> Fcond(map_vars_fcond ~f fc)
  | Pcond(pc) -> Pcond(map_vars_pcond ~f pc)

let map_vars_base_instr ~f lbi =
  let mvd = map_vars_dest ~f in
  let mvds = List.map ~f:mvd in
  let mvs = map_vars_src ~f in
  let mvss = List.map ~f:mvs in
  let bi = lbi.L.l_val in
  let bi =
    match bi with
    | Comment(_)        -> bi
    | Assgn(d,s,at)     -> Assgn(mvd d, mvs s, at)
    | Op(o,ds,ss)       -> Op(o,mvds ds, mvss ss)
    | Call(fn,ds,ss,di) -> Call(fn,mvds ds, mvss ss,di)
  in
  { L.l_loc = lbi.L.l_loc; L.l_val = bi }

let rec map_vars_instr linstr ~f =
  let mvbi = map_vars_base_instr ~f in
  let mvs = map_vars_stmt ~f in
  let mvc = map_vars_fcond_or_pcond ~f in
  let mvfc = map_vars_fcond ~f in
  let mvsd = map_vars_sdest ~f in
  let mvp = map_vars_pexpr ~f in
  let instr = 
    match linstr.L.l_val with
    | Block(bis,i)      -> Block(List.map ~f:mvbi bis,i)
    | If(c,s1,s2,i)     -> If(mvc c,mvs s1,mvs s2,i)
    | For(sd,lb,ub,s,i) -> For(mvsd sd,mvp lb,mvp ub,mvs s,i)
    | While(wt,fc,s,i)  -> While(wt,mvfc fc,mvs s,i)
  in
  { L.l_val = instr; L.l_loc = linstr.L.l_loc }

and map_vars_stmt stmt ~f =
  List.map stmt ~f:(map_vars_instr ~f)

let map_vars_func ~f fd =
  { f_body      = map_vars_stmt ~f fd.f_body;
    f_arg       = List.map ~f fd.f_arg;
    f_ret       = List.map ~f fd.f_ret;
    f_call_conv = fd.f_call_conv;
  }

let map_vars_named_func ~f nf =
  { nf_name = nf.nf_name;
    nf_func = map_vars_func ~f nf.nf_func }

let map_vars_modul ~f modul fname =
  map_named_func ~f:(map_vars_named_func ~f) modul fname

let map_vars_modul_all ~f modul =
  List.map ~f:(map_vars_named_func ~f) modul

(* ** Map function over all parameters
 * ------------------------------------------------------------------------ *)

let rec map_params_patom ~f pa =
  match pa with
  | Pparam(p) -> Pparam(map_params_param ~f p)
  | Pvar(v)   -> Pvar(map_params_var ~f v)

and map_params_param ~f p =
  f { p with Param.ty = map_params_ty ~f p.Param.ty }

and map_params_idx ~f i =
  match i with
  | Ipexpr(pe) -> Ipexpr(map_params_pexpr ~f pe)
  | Ivar(v)    -> Ivar(map_params_var ~f v)

and map_params_rdest ~f rd =
  match rd with
  | Sdest(sd)  -> Sdest(map_params_sdest ~f sd)
  | Mem(sd,pe) -> Mem(map_params_sdest ~f sd, map_params_pexpr ~f pe)

and map_params_dest ~f d =
  match d with
  | Ignore(_) -> d
  | Rdest(rd) -> Rdest(map_params_rdest ~f rd)

and map_params_sdest ~f sd =
  { d_var = map_params_var ~f sd.d_var
  ; d_idx = Option.map ~f:(map_params_idx ~f) sd.d_idx
  ; d_loc = sd.d_loc }
    
and map_params_pexpr pe ~f =
  let mvp = map_params_pexpr ~f in
  let mva = map_params_patom ~f in
  match pe with
  | Patom(pa)         -> Patom(mva pa)
  | Pbinop(o,pe1,pe2) -> Pbinop(o,mvp pe1, mvp pe2)
  | Pconst(c)         -> Pconst(c)

and map_params_var ~f v =
  { v with Var.ty = map_params_ty ~f v.Var.ty }

and map_params_ty ~f ty =
  match ty with
  | TInvalid | Bty(_) -> ty
  | Arr(n,dim)        -> Arr(n,map_params_dexpr ~f dim)

and map_params_dexpr ~f de =
  let mvp = map_params_dexpr ~f in
  match de with
  | Patom(p)          -> Patom(map_params_param ~f p)
  | Pbinop(o,pe1,pe2) -> Pbinop(o,mvp pe1, mvp pe2)
  | Pconst(c)         -> Pconst(c)

let rec map_params_pcond ~f pc =
  let mvpc = map_params_pcond ~f in
  let mvpe = map_params_pexpr ~f in
  match pc with
  | Pbool(_)        -> pc
  | Pnot(pc)        -> Pnot(mvpc pc)
  | Pbop(o,pc1,pc2) -> Pbop(o,mvpc pc1, mvpc pc2)
  | Pcmp(o,pe1,pe2) -> Pcmp(o,mvpe pe1, mvpe pe2)

let map_params_src ~f = function
  | Imm(i,pe) -> Imm(i,map_params_pexpr ~f pe)
  | Src(d)    -> Src(map_params_rdest ~f d)

let map_params_fcond_or_pcond ~f = function
  | Fcond(fc) -> Fcond(fc)
  | Pcond(pc) -> Pcond(map_params_pcond ~f pc)

let map_params_base_instr ~f lbi =
  let mvd = map_params_dest ~f in
  let mvds = List.map ~f:mvd in
  let mvs = map_params_src ~f in
  let mvss = List.map ~f:mvs in
  let bi = lbi.L.l_val in
  let bi =
    match bi with
    | Comment(_)        -> bi
    | Assgn(d,s,at)     -> Assgn(mvd d, mvs s, at)
    | Op(o,ds,ss)       -> Op(o,mvds ds, mvss ss)
    | Call(fn,ds,ss,di) -> Call(fn,mvds ds, mvss ss,di)
  in
  { L.l_loc = lbi.L.l_loc; L.l_val = bi }

let rec map_params_instr linstr ~f =
  let mvbi = map_params_base_instr ~f in
  let mvs = map_params_stmt ~f in
  let mvc = map_params_fcond_or_pcond ~f in
  let mvsd = map_params_sdest ~f in
  let mvp = map_params_pexpr ~f in
  let instr = 
    match linstr.L.l_val with
    | Block(bis,i)      -> Block(List.map ~f:mvbi bis,i)
    | If(c,s1,s2,i)     -> If(mvc c,mvs s1,mvs s2,i)
    | For(sd,lb,ub,s,i) -> For(mvsd sd,mvp lb,mvp ub,mvs s,i)
    | While(wt,fc,s,i)  -> While(wt,fc,mvs s,i)
  in
  { L.l_val = instr; L.l_loc = linstr.L.l_loc }

and map_params_stmt stmt ~f =
  List.map stmt ~f:(map_params_instr ~f)

let map_params_func ~f fd =
  { f_body      = map_params_stmt ~f fd.f_body;
    f_arg       = List.map ~f:(map_params_var ~f) fd.f_arg;
    f_ret       = List.map ~f:(map_params_var ~f) fd.f_ret;
    f_call_conv = fd.f_call_conv;
  }

let map_params_named_func ~f nf =
  { nf_name = nf.nf_name;
    nf_func = map_params_func ~f nf.nf_func }

let map_params_modul ~f modul fname =
  map_named_func ~f:(map_params_named_func ~f) modul fname

let map_params_modul_all ~f modul =
  List.map ~f:(map_params_named_func ~f) modul

(* ** Map function over all type occurences
 * ------------------------------------------------------------------------ *)

let rec map_tys_patom ~f:(f : ty -> ty) pa =
  match pa with
  | Pparam(p) -> Pparam(map_tys_param ~f p)
  | Pvar(v)   -> Pvar(map_tys_var ~f v)

and map_tys_param ~f:(f : ty -> ty) p =
  { p with Param.ty = map_tys_ty ~f p.Param.ty }

and map_tys_idx ~f:(f : ty -> ty) i =
  match i with
  | Ipexpr(pe) -> Ipexpr(map_tys_pexpr ~f pe)
  | Ivar(v)    -> Ivar(map_tys_var ~f v)

and map_tys_rdest ~f rd =
  match rd with
  | Sdest(sd)  -> Sdest(map_tys_sdest ~f sd)
  | Mem(sd,pe) -> Mem(map_tys_sdest ~f sd, map_tys_pexpr ~f pe)

and map_tys_dest ~f d =
  match d with
  | Ignore(_) -> d
  | Rdest(rd) -> Rdest(map_tys_rdest ~f rd)

and map_tys_sdest ~f sd =
  { d_var = map_tys_var ~f sd.d_var
  ; d_idx = Option.map ~f:(map_tys_idx ~f) sd.d_idx
  ; d_loc = sd.d_loc }
    
and map_tys_pexpr pe ~f:(f : ty -> ty) =
  let mvp = map_tys_pexpr ~f in
  let mva = map_tys_patom ~f in
  match pe with
  | Patom(pa)         -> Patom(mva pa)
  | Pbinop(o,pe1,pe2) -> Pbinop(o,mvp pe1, mvp pe2)
  | Pconst(c)         -> Pconst(c)

and map_tys_var ~f:(f : ty -> ty) v =
  { v with Var.ty = f v.Var.ty }

and map_tys_ty ~f:(f : ty -> ty) ty =
  match ty with
  | TInvalid | Bty(_) -> f ty
  | Arr(n,dim)        -> f (Arr(n,map_tys_dexpr ~f dim))

and map_tys_dexpr ~f:(f : ty -> ty) de =
  let mtd = map_tys_dexpr ~f in
  let mtp = map_tys_param ~f in
  match de with
  | Patom(pa)         -> Patom(mtp pa)
  | Pbinop(o,pe1,pe2) -> Pbinop(o,mtd pe1, mtd pe2)
  | Pconst(c)         -> Pconst(c)

let rec map_tys_pcond ~f:(f : ty -> ty) pc =
  let mvpc = map_tys_pcond ~f in
  let mvpe = map_tys_pexpr ~f in
  match pc with
  | Pbool(_)        -> pc
  | Pnot(pc)        -> Pnot(mvpc pc)
  | Pbop(o,pc1,pc2) -> Pbop(o,mvpc pc1,mvpc pc2)
  | Pcmp(o,pe1,pe2) -> Pcmp(o,mvpe pe1,mvpe pe2)

let map_tys_src ~f:(f : ty -> ty) = function
  | Imm(i,pe) -> Imm(i,map_tys_pexpr ~f pe)
  | Src(d)    -> Src(map_tys_rdest ~f d)

let map_tys_fcond ~f fc =
  { fc with fc_var = map_tys_var ~f fc.fc_var }

let map_tys_fcond_or_pcond ~f = function
  | Fcond(fc) -> Fcond(map_tys_fcond ~f fc)
  | Pcond(pc) -> Pcond(map_tys_pcond ~f pc)

let map_tys_base_instr ~f:(f : ty -> ty) lbi =
  let mvd  = map_tys_dest ~f in
  let mvds = List.map ~f:mvd in
  let mvs  = map_tys_src ~f in
  let mvss = List.map ~f:mvs in
  let bi = lbi.L.l_val in
  let bi =
    match bi with
    | Comment(_)        -> bi
    | Assgn(d,s,at)     -> Assgn(mvd d, mvs s, at)
    | Op(o,ds,ss)       -> Op(o,mvds ds, mvss ss)
    | Call(fn,ds,ss,di) -> Call(fn,mvds ds, mvss ss,di)
  in
  { L.l_loc = lbi.L.l_loc; L.l_val = bi }

let rec map_tys_instr linstr ~f:(f : ty -> ty) =
  let mvbi = map_tys_base_instr ~f in
  let mvs = map_tys_stmt ~f in
  let mvc = map_tys_fcond_or_pcond ~f in
  let mvsd = map_tys_sdest ~f in
  let mvp = map_tys_pexpr ~f in
  let instr = 
    match linstr.L.l_val with
    | Block(bis,i)      -> Block(List.map ~f:mvbi bis,i)
    | If(c,s1,s2,i)     -> If(mvc c,mvs s1,mvs s2,i)
    | For(sd,lb,ub,s,i) -> For(mvsd sd,mvp lb,mvp ub,mvs s,i)
    | While(wt,fc,s,i)  -> While(wt,fc,mvs s,i)
  in
  { L.l_val = instr; L.l_loc = linstr.L.l_loc }

and map_tys_stmt stmt ~f:(f : ty -> ty) =
  List.map stmt ~f:(map_tys_instr ~f)

let map_tys_func ~f:(f : ty -> ty) fd =
  { f_body      = map_tys_stmt ~f fd.f_body;
    f_arg       = List.map ~f:(map_tys_var ~f) fd.f_arg;
    f_ret       = List.map ~f:(map_tys_var ~f) fd.f_ret;
    f_call_conv = fd.f_call_conv;
  }

let map_tys_named_func ~f nf =
  { nf_name = nf.nf_name;
    nf_func = map_tys_func ~f nf.nf_func }

let map_tys_modul ~f:(f : ty -> ty) modul fname =
  map_named_func ~f:(map_tys_named_func ~f) modul fname

let map_tys_modul_all ~f:(f : ty -> ty) modul =
  List.map ~f:(map_tys_named_func ~f) modul

(* ** Map function over all destinations
 * ------------------------------------------------------------------------ *)


let map_sdests_rdest ~f rd =
  match rd with
  | Mem(sd,pe) -> Mem(f sd, pe)
  | Sdest(sd)  -> Sdest(f sd)


let map_sdests_dest ~f d =
  match d with
  | Ignore(_) -> d
  | Rdest(rd) -> Rdest(map_sdests_rdest ~f rd)

let map_sdests_src ~f = function
  | Imm(i,pe) -> Imm(i,pe)
  | Src(d)    -> Src(map_sdests_rdest ~f d)

let map_sdests_base_instr ~f lbi =
  let msd = map_sdests_dest ~f in
  let msds = List.map ~f:(map_sdests_dest ~f) in
  let mss = map_sdests_src ~f in
  let msss = List.map ~f:mss in
  let bi = lbi.L.l_val in
  let bi =
    match bi with
    | Comment(_)        -> bi
    | Assgn(d,s,at)     -> Assgn(msd d, mss s, at)
    | Op(o,ds,ss)       -> Op(o,msds ds, msss ss)
    | Call(fn,ds,ss,di) -> Call(fn,msds ds, msss ss,di)
  in
  { L.l_loc = lbi.L.l_loc; L.l_val = bi }

let rec map_sdests_instr linstr ~f =
  let msbi = map_sdests_base_instr ~f in
  let mss = map_sdests_stmt ~f in
  let instr = 
    match linstr.L.l_val with
    | Block(bis,i)      -> Block(List.map ~f:msbi bis,i)
    | If(c,s1,s2,i)     -> If(c,mss s1,mss s2,i)
    | For(sd,lb,ub,s,i) -> For(f sd,lb,ub,mss s,i)
    | While(wt,fc,s,i)  -> While(wt,fc,mss s,i)
  in
  { L.l_val = instr; L.l_loc = linstr.L.l_loc }

and map_sdests_stmt stmt ~f =
  List.map stmt ~f:(map_sdests_instr ~f)

let map_sdests_func ~f fd =
  { f_body      = map_sdests_stmt ~f fd.f_body;
    f_arg       = fd.f_arg;
    f_ret       = fd.f_ret;
    f_call_conv = fd.f_call_conv;
  }

let map_dests_named_func ~f nf =
  { nf_name = nf.nf_name;
    nf_func = map_sdests_func ~f nf.nf_func; }

let map_dests_modul ~f modul fname =
  map_named_func ~f:(map_dests_named_func ~f) modul fname

let map_dests_modul_all ~f modul =
  List.map ~f:(map_dests_named_func ~f) modul



(**  ----------------------------------------------------------------- *)

module Mp = Param.Map

let psubst_param tbl p = 
  match Mp.find tbl p with 
  | None -> Patom p 
  | Some e -> e 

let rec pexpr_of_dexpr e = 
  match e with
  | Patom p         -> Patom (Pparam p)
  | Pbinop(o,e1,e2) -> Pbinop(o, pexpr_of_dexpr e1, pexpr_of_dexpr e2)
  | Pconst i        -> Pconst i

let rec psubst_dexpr tbl e =
  match e with
  | Patom p         -> psubst_param tbl p
  | Pbinop(o,e1,e2) -> Pbinop(o, psubst_dexpr tbl e1, psubst_dexpr tbl e2)
  | Pconst _        -> e

let psubst_ty tbl ty =
  match ty with
  | Param.Bty _        -> ty
  | Param.Arr (ty, e) -> Param.Arr(ty, psubst_dexpr tbl e)
  | Param.TInvalid    -> ty

let psubst_var tbl v =
  { v with Var.ty = psubst_ty tbl v.Var.ty }

let rec psubst_pexpr tbl e =
  match e with
  | Patom (Pparam p) -> pexpr_of_dexpr (psubst_param tbl p)
  | Patom (Pvar x)   -> Patom (Pvar (psubst_var tbl x))
  | Pbinop (o,e1,e2) -> Pbinop(o, psubst_pexpr tbl e1, psubst_pexpr tbl e2)
  | Pconst _         -> e 

let rec psubst_pcond tbl e =
  match e with
  | Pbool _ -> e
  | Pnot e  -> Pnot (psubst_pcond tbl e)
  | Pbop(o,e1,e2) -> Pbop(o,psubst_pcond tbl e1, psubst_pcond tbl e2)
  | Pcmp(o,e1,e2) -> Pcmp(o,psubst_pexpr tbl e1, psubst_pexpr tbl e2)

let psubst_idx tbl = function
  | Ipexpr e -> Ipexpr (psubst_pexpr tbl e)
  | Ivar   x -> Ivar   (psubst_var tbl x)

let psubst_sdest tbl d = 
  { d with d_var = psubst_var tbl d.d_var;
           d_idx = Option.map ~f:(psubst_idx tbl) d.d_idx }

let psubst_rdest tbl d =
  match d with
  | Mem(s,e) -> Mem(psubst_sdest tbl s, psubst_pexpr tbl e)
  | Sdest s  -> Sdest (psubst_sdest tbl s)

let psubst_dest tbl d = 
  match d with
  | Ignore _ -> d
  | Rdest r  -> Rdest (psubst_rdest tbl r)

let psubst_src tbl s = 
  match s with
  | Src s -> Src (psubst_rdest tbl s)
  | Imm(i, e) -> Imm(i, psubst_pexpr tbl e)

let psubst_fcond tbl f = 
  {f with fc_var = psubst_var tbl f.fc_var}

let psubst_fcond_or_pcond tbl = function
  | Fcond f -> Fcond (psubst_fcond tbl f)
  | Pcond p -> Pcond (psubst_pcond tbl p)

let psubst_binstr tbl = function
  | Assgn(d,s,t) -> Assgn(psubst_dest tbl d, psubst_src tbl s, t)
  | Op(o,d,s) -> 
    Op(o, List.map ~f:(psubst_dest tbl) d, List.map ~f:(psubst_src tbl) s)
  | Call(fn, d, s, t) ->
    Call(fn, List.map ~f:(psubst_dest tbl) d, List.map ~f:(psubst_src tbl) s, t)
  | Comment s -> Comment s

let rec psubst_instr tbl = function
  | Block(c,i) -> 
    let f i = { i with L.l_val = psubst_binstr tbl i.L.l_val } in
    Block(List.map ~f c, i)
  | If(t,c1,c2,i) ->
    If(psubst_fcond_or_pcond tbl t,
       psubst_instrs tbl c1, psubst_instrs tbl c2, i) 
  | For(x,e1,e2,c,i) ->
    For(psubst_sdest tbl x, psubst_pexpr tbl e1, psubst_pexpr tbl e2,
        psubst_instrs tbl c, i)
  | While(wt,t,c,i) ->
    While(wt,psubst_fcond tbl t, psubst_instrs tbl c, i)

and psubst_instrs tbl c = 
  let f i = { i with L.l_val = psubst_instr tbl i.L.l_val } in
  List.map ~f c

let psubst_func tbl f =
  {f with f_body = psubst_instrs tbl f.f_body;
          f_arg = List.map ~f:(psubst_var tbl) f.f_arg;
          f_ret = List.map ~f:(psubst_var tbl) f.f_ret }

let psubst_nfunc tbl f = 
  { f with nf_func = psubst_func tbl f.nf_func }

let psubst_tinfo tbl (stor, ty) = (stor, psubst_ty tbl ty)

let psubst_proto tbl proto = 
  { proto with np_arg_ty = List.map ~f:(psubst_tinfo tbl) proto.np_arg_ty;
               np_ret_ty = List.map ~f:(psubst_tinfo tbl) proto.np_ret_ty; }

let psubst_modul modul = 
  let tbl = 
    List.fold_left modul.mod_params 
      ~init:Mp.empty 
      ~f:(fun m (p,e) -> Mp.add m ~key:p ~data:e) in
  let noparams e = 
    try 
      IL_Iter.iter_params_dexpr ~f:(fun _ -> raise Not_found) e; true
    with Not_found -> false in
  let rec aux tbl n = 
    assert (0 <= n);
    if Mp.for_all tbl ~f:noparams then tbl 
    else
      let tbl = Mp.map tbl ~f:(psubst_dexpr tbl) in
      aux tbl (n-1) in
  let tbl = aux tbl (List.length modul.mod_params) in

  { modul with
    mod_funcs = List.map ~f:(psubst_nfunc tbl) modul.mod_funcs;
    mod_params = [];
    mod_funprotos = List.map ~f:(psubst_proto tbl) modul.mod_funprotos;
  }



      

  
   
  



