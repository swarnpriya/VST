Require Import VST.floyd.proofauto.
Require Import VST.progs64.packet_count.
(* The next line is "boilerplate", always required after importing an AST. *)
#[export] Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs.  mk_varspecs prog. Defined.

Local Open Scope logic.

(* An abbreviation for C language type struct xdp_md *)
Definition txdpmd := Tstruct _xdp_md noattr. 
 
(* isptr p means p is not a null pointer, not NULL or Vundef or a floating point number *)
(* data_at assertion says that at addresst p in memory there is a data structure of type 
   t_xdp_md with access-permission (Tsh: top permission) and content v*) 
Lemma data_at_isptr_xdp: forall v p,
  data_at Tsh txdpmd v p |--
  !! isptr p.
Proof.
intros. entailer!.
Qed.
Search Int.add.
Definition packet_count_spec : ident * funspec :=
DECLARE _packet_count 
 WITH v : reptype' txdpmd, p : val, sh : share, gv: globals, c : int
 PRE [ tptr txdpmd ]
  PROP (readable_share sh)
  PARAMS (p) GLOBALS (gv) 
  SEP (data_at sh txdpmd (repinj _ v) p; data_at Ews tint (Vint c) (gv _counter))
 POST [ tint ]
  PROP () RETURN (Vint (Int.repr 2))
  SEP (data_at sh txdpmd (repinj _ v) p; data_at Ews tint (Vint (Int.repr (Int.signed c + Int.signed (Int.repr 1)))) (gv _counter)).

(*
(* API spec for the packet_count.c program *)
Definition packet_count_spec : ident * funspec :=
DECLARE _packet_count
 WITH p: val, 
      ctxdata: Z, 
      ctxdataend: Z, 
      ctxdatameta: Z, 
      ctxingress : Z, 
      ctxrx : Z, 
      ctxegress : Z   (* WITH: quantifies over Coq values that may appear in both pre and post condition *)
 PRE [ tptr txdpmd ]                                      (* PRE: precondition *)
  PROP ()                 (* PROP: list properties which are always true irrespective of program state, forexample the memory is not empty *)
  PARAMS (p)                                              (* PARAM: list the values of C function parameters in order *)
  SEP (data_at Ews txdpmd  (Vint (Int.repr ctxdata), 
                            Vint (Int.repr ctxdataend),
                            Vint (Int.repr ctxdatameta),
                            Vint (Int.repr ctxingress),
                            Vint (Int.repr ctxrx),
                            Vint (Int.repr ctxegress)) p) 
 POST [ tuint ]
  PROP () RETURN (Vint (Int.repr 2))
  SEP (data_at Ews txdpmd  (Vint (Int.repr ctxdata), 
                            Vint (Int.repr ctxdataend),
                            Vint (Int.repr ctxdatameta),
                            Vint (Int.repr ctxingress),
                            Vint (Int.repr ctxrx),
                            Vint (Int.repr ctxegress)) p).*)

Definition Gprog : funspecs := ltac:(with_library prog [packet_count_spec ]).

Lemma body_packet_count : semax_body Vprog Gprog f_packet_count packet_count_spec.
Proof.
start_function.
forward.
forward.
+ entailer!. admit.
+ forward. entailer!. admit.
Admitted.


