Require Import msl.is_prop_lemma.
Require Import floyd.base.
Require Import floyd.assert_lemmas.
Require Import floyd.client_lemmas.
Require Import floyd.nested_field_lemmas.
Opaque alignof.

Local Open Scope logic.

Arguments align !n !amount / .
Arguments Z.max !n !m / .

(******************************************

Basic lemmas about local_facts, isptr, offset_zero

******************************************)

Lemma local_facts_isptr: forall P (p: val), P p |-- !! isptr p -> P p = !! (isptr p) && P p.
Proof.
  intros.
  apply pred_ext.
  + apply andp_right.
    exact H.
    cancel.
  + apply andp_left2.
    cancel.
Qed.

Lemma local_facts_offset_zero: forall P, (forall p, P p |-- !! isptr p) -> (forall p, P p = P (offset_val Int.zero p)).
Proof.
  intros.
  pose proof (H p).
  pose proof (H Vundef).
  destruct p; simpl in *; apply pred_ext; normalize.
  + eapply derives_trans. exact H0. normalize.
  + eapply derives_trans. exact H1. normalize.
  + eapply derives_trans. exact H0. normalize.
  + eapply derives_trans. exact H1. normalize.
  + eapply derives_trans. exact H0. normalize.
  + eapply derives_trans. exact H1. normalize.
Qed.

(******************************************

To prove memory_block_mapsto_

******************************************)

Definition by_value_non_volatile t :=
  match t with
  | Tint _ _ a => attr_volatile a = false
  | Tlong _ a => attr_volatile a = false
  | Tfloat _ a => attr_volatile a = false
  | Tpointer _ a => attr_volatile a = false
  | _ => False
  end.

Lemma access_mode_by_value_non_volatile: forall t, by_value_non_volatile t -> exists ch, access_mode t = By_value ch.
Proof.
  intros.
  assert (forall ch', exists ch, By_value ch' = By_value ch).
    intros. exists ch'. reflexivity.
  destruct t; inversion H; simpl.
  - destruct i, s; apply H0.
  - apply H0.
  - destruct f; apply H0.
  - apply H0.
Qed.

(* It might be useful to prove memory_block_mapsto *)
Lemma repr_unsigned: forall i, Int.repr (Int.unsigned i) = i.
Proof.
  intros.
  apply Int.eqm_repr_eq.
  apply Int.eqm_refl.
Qed.

(*
Lemma unsigned_repr: forall i, Int.unsigned (Int.repr i) = i.
Proof.
  intros.
SearchAbout Int.unsigned Int.repr.
*)
(*
Lemma at_offset'_zero:
  forall P, 
    (forall v, P (offset_val (Int.repr 0) v) = P v) ->
  forall ofs v,
    at_offset' P ofs (offset_val (Int.repr 0) v) = at_offset' P ofs v.
Proof.
  intros.
  repeat rewrite at_offset'_eq. 
  rewrite offset_offset_val. rewrite Int.add_zero_l. auto. auto.
  f_equal.  rewrite offset_offset_val. reflexivity.
Qed.
*)

Lemma FF_orp: forall {A: Type} `{NatDed A} (P: A), FF || P = P.
Proof.
  intros.
  apply pred_ext.
  + apply orp_left.
    apply FF_left.
    apply derives_refl.
  + apply orp_right2.
    apply derives_refl.
Qed.

Lemma mapsto__exp_address_mapsto:
  forall sh t b i_ofs ch,
   access_mode t = By_value ch ->
   by_value_non_volatile t -> 
   mapsto_ sh t (Vptr b i_ofs) = EX  v2' : val,
             address_mapsto ch v2' (Share.unrel Share.Lsh sh)
               (Share.unrel Share.Rsh sh) (b, (Int.unsigned i_ofs)).
Proof.
  intros.
  unfold mapsto_, mapsto.
  rewrite H.
  destruct (type_is_volatile t) eqn:HH.
  - unfold type_is_volatile in HH.
    rewrite H in HH.
    destruct t; try destruct a; try destruct attr_volatile, attr_alignas; try inversion H0; try inversion HH.
  - assert (!!(tc_val t Vundef) = @FF mpred Nveric) by (destruct t; reflexivity).
    rewrite H1.
    rewrite FF_andp, FF_orp.
    assert (!!(Vundef = Vundef) = @TT mpred Nveric) by (apply pred_ext; normalize).
    rewrite H2.
    rewrite TT_andp.
    reflexivity.
Qed.

Fixpoint list_address_mapsto ch vs rsh sh b ofs :=
  match vs with
  | nil => emp
  | v :: vs' => address_mapsto ch v rsh sh (b, Int.unsigned (Int.repr ofs)) * list_address_mapsto ch vs' rsh sh b (ofs + 1)
  end.

Fixpoint list_address_mapsto' ch vs rsh sh b ofs bls:=
  match vs, bls with
  | nil, nil => emp
  | nil, _ => FF
  | _, nil => FF
  | v :: vs', bl :: bls' =>
    (!! (length bl = Memdata.size_chunk_nat ch  /\ Memdata.decode_val ch bl = v /\ (Memdata.align_chunk ch | Int.unsigned (Int.repr ofs)))  && allp (res_predicates.jam (adr_range_dec (b, Int.unsigned (Int.repr ofs)) (Memdata.size_chunk ch))
    (fun loc => res_predicates.yesat compcert_rmaps.R.NoneP (compcert_rmaps.VAL (nth (nat_of_Z (snd loc - Int.unsigned (Int.repr ofs))) bl Memdata.Undef)) rsh sh loc) res_predicates.noat)) * list_address_mapsto' ch vs' rsh sh b (ofs + 1) bls'
  end.

Lemma memory_block'_list_address_mapsto: forall sh n b ofs, memory_block' sh n b ofs = EX vs: list val, (!! (length vs = n)) && list_address_mapsto Mint8unsigned vs (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh) b ofs.
Proof.
  intros.
  apply pred_ext; revert ofs; induction n; intros.
  + apply (exp_right nil).
    simpl.
    normalize.
  + simpl.
    erewrite mapsto__exp_address_mapsto; [|reflexivity|simpl; reflexivity].
    eapply derives_trans; [apply sepcon_derives; [apply derives_refl| exact (IHn (ofs + 1))]|].
    normalize.
    apply (exp_right (x :: v2')).
    simpl.
    normalize.
  + normalize. 
    destruct vs; simpl; [normalize | inversion H].
  + normalize.
    destruct vs; simpl; inversion H.
    erewrite mapsto__exp_address_mapsto; [|reflexivity|simpl; reflexivity].
    apply sepcon_derives. 
    - apply (exp_right v).
      normalize.
    - rewrite H1. eapply derives_trans; [| exact (IHn (ofs + 1))].
      apply (exp_right vs).
      normalize.
Qed.

Lemma list_address_mapsto_list_address_mapsto': forall ch vs rsh sh b ofs, list_address_mapsto ch vs rsh sh b ofs = EX bls:_, list_address_mapsto' ch vs rsh sh b ofs bls.
Proof.
  intros.
  revert ofs.
  induction vs; intros.
  + simpl.
    apply pred_ext.
    - apply (exp_right nil), derives_refl.
    - apply exp_left; intros; destruct x; normalize.
  + simpl.
    unfold address_mapsto, res_predicates.address_mapsto.      
    change (@predicates_hered.exp compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@exp mpred Nveric).
    change (@predicates_hered.andp compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@andp mpred Nveric).
    change (@predicates_hered.prop compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@prop mpred Nveric).
    change (@predicates_hered.allp compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@allp mpred Nveric).
    apply pred_ext.
    - rewrite IHvs.
      normalize.
      apply (exp_right (x :: bl)).
      normalize.
    - rewrite IHvs.
      normalize. destruct bls as [|x bl]; normalize.
      apply (exp_right bl). cancel. apply (exp_right x).
      normalize.
Qed.

Definition bl_to_bls bl := map (fun x:Memdata.memval => x :: nil) bl.
Definition bls_to_bl bls := fold_right (@app Memdata.memval) nil bls.

Definition list_address_mapsto'_Mint8unsigned: forall vs rsh sh b ofs bls,
  list_address_mapsto' Mint8unsigned vs rsh sh b ofs bls
  |-- !!(length (bls_to_bl bls) = length bls) && !!(length bls = length vs).
Proof.
  intros.
  revert bls ofs.
  induction vs; intros; destruct bls; simpl.
  + normalize.
  + normalize.
  + normalize.
  + unfold Memdata.size_chunk_nat, nat_of_Z, bls_to_bl.
    rewrite app_length.
    simpl.
    replace (Pos.to_nat 1) with 1%nat by reflexivity.
    normalize.
    rewrite H.
    simpl.
    assert ((!!(S (length (fold_right (app (A:=Memdata.memval)) nil bls)) =
          S (length bls) /\ S (length bls) = S (length vs))) =
            (!!(True /\ (S (length (fold_right (app (A:=Memdata.memval)) nil bls)) =
          S (length bls) /\ S (length bls) = S (length vs)))))
    by (rewrite prop_and; apply pred_ext; normalize).
    change (@predicates_hered.pred compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with mpred.
    rewrite H1; clear H1.
    apply saturate_aux20; [normalize |].
    eapply derives_trans; [apply IHvs| normalize].
Qed.

Lemma allp_forall: forall A P Q (x:A), (forall x:A, (P x = Q)) -> (allp P = Q).
Proof.
  intros.
  apply pred_ext.
  + apply (allp_left _ x).
    rewrite H.
    apply derives_refl.
  + apply allp_right.
    intros.
    rewrite H.
    apply derives_refl.
Qed.

Lemma allp_andp: forall P Q, allp (P && Q) = allp P && allp Q.
Proof.
  intros.
  apply pred_ext.
  + apply andp_right; apply allp_derives; intros;
    simpl; [apply andp_left1|apply andp_left2]; apply derives_refl.
  + apply allp_right; intros.
    simpl; apply andp_right; [apply andp_left1|apply andp_left2];
    apply (allp_left _ v); apply derives_refl.
Qed.

Lemma allp_jam_merge: forall f g h P 
  (decf: forall l, {f l} + {~ f l})
  (decg: forall l, {g l} + {~ g l})
  (decfg: forall l, {h l} + {~ h l}),
  (forall l, f l \/ g l <-> h l) ->
  (forall l, ~ (f l /\ g l)) ->
  predicates_hered.allp (res_predicates.jam decfg P res_predicates.noat) =
  predicates_hered.allp (res_predicates.jam decf P res_predicates.noat) *
  predicates_hered.allp (res_predicates.jam decg P res_predicates.noat).
Proof.
  intros.
  apply pred_ext;
  change derives with (@predicates_hered.derives compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap);
  change sepcon with predicates_sl.sepcon.
  + unfold predicates_hered.derives, predicates_sl.sepcon, predicates_hered.allp. simpl.
    intros.
    (*compcert_rmaps.RML.rmap_valid*)
    (*compcert_rmaps.RML.resource_at_approx*)
    remember (fun l => if (decf l) 
          then compcert_rmaps.RML.R.resource_at a l
          else compcert_rmaps.R.NO Share.bot) as funn.
    pose proof compcert_rmaps.RML.make_rmap funn.
    assert (compcert_rmaps.R.AV.valid (base.compose compcert_rmaps.R.res_option funn)).
      subst.
      pose proof compcert_rmaps.RML.rmap_valid a.
      unfold base.compose, compcert_rmaps.R.res_option in *. simpl.
      admit.
    admit.
  + admit.
Qed.

Lemma allp_jam_range_rec: forall b ofs n P,
  n > 0 ->
  allp (res_predicates.jam (adr_range_dec (b, ofs) n) P res_predicates.noat) =
  allp (res_predicates.jam (adr_range_dec (b, ofs) 1) P res_predicates.noat) *
  allp (res_predicates.jam (adr_range_dec (b, ofs + 1) (n - 1)) P res_predicates.noat).
Proof.
  intros.
  change allp with (@predicates_hered.allp compcert_rmaps.RML.R.rmap compcert_rmaps.R.ag_rmap address).
  apply allp_jam_merge;
  intros;
  destruct l;
  simpl adr_range;
  [split|unfold not]; intros.
  + destruct H0; destruct H0; (split; [subst; reflexivity | omega]).
  + destruct H0.
    subst.
    pose proof zle (ofs + 1) z.
    destruct H0; [right|left]; (split; [reflexivity|omega]).
  + destruct H0.
    omega.
Qed.

Lemma allp_jam_range_basic: forall b ofs P,
  allp (res_predicates.jam (adr_range_dec (b, ofs) 0) P res_predicates.noat) = emp.
Proof.
  intros.
  assert ((res_predicates.jam (adr_range_dec (b, ofs) 0) P res_predicates.noat) =
    res_predicates.noat).
    extensionality.  
    apply res_predicates.jam_false.
    unfold not.
    unfold adr_range; intros.
    destruct x.
    destruct H.
    omega.
  rewrite H.
  change emp with predicates_sl.emp.
  change allp with (@predicates_hered.allp compcert_rmaps.RML.R.rmap compcert_rmaps.R.ag_rmap address).
  apply res_predicates.allp_noat_emp.
Qed.

Lemma add_andp_to_left: forall P Q R, P |-- Q -> P && Q |-- R -> P |-- R.
Proof.
  intros.
  eapply derives_trans; [| exact H0].
  apply andp_right; normalize.
Qed.

Lemma address_mapsto_list_address_mapsto_Mint8unsigned:
  forall ch rsh sh b ofs, (Memdata.align_chunk ch | ofs) -> 
  EX v:val, address_mapsto ch v rsh sh (b, ofs) = 
  EX vs:list val, !! (length vs = Memdata.size_chunk_nat ch) && list_address_mapsto Mint8unsigned vs rsh sh b ofs.
Proof.
  intros.
  unfold address_mapsto, res_predicates.address_mapsto.
  change (@predicates_hered.exp compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@exp mpred Nveric).
  change (@predicates_hered.andp compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@andp mpred Nveric).
  change (@predicates_hered.prop compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@prop mpred Nveric).
  change (@predicates_hered.allp compcert_rmaps.RML.R.rmap
           compcert_rmaps.R.ag_rmap) with (@allp mpred Nveric).
  replace (fun vs => !!(length vs = Memdata.size_chunk_nat ch) && list_address_mapsto Mint8unsigned vs rsh sh b ofs) with
         (fun vs => !!(length vs = Memdata.size_chunk_nat ch) && EX bls: _, list_address_mapsto' Mint8unsigned vs rsh sh b ofs bls) by
    (extensionality vs;
     rewrite <- (list_address_mapsto_list_address_mapsto' Mint8unsigned vs rsh sh b ofs);
     reflexivity).
  apply pred_ext.
  + normalize.
    apply (exp_right (map (fun bl => Memdata.decode_val Mint8unsigned bl) (bl_to_bls bl))).
    apply andp_right; [apply prop_right; unfold bl_to_bls; repeat rewrite map_length; exact H0|].
    apply (exp_right (bl_to_bls bl)).
    rewrite Memdata.size_chunk_conv in *.
    forget (Memdata.size_chunk_nat ch) as n.
    clear H ch.
    revert n H0 ofs; induction bl; intros.
    - subst n. simpl in *.
      rewrite allp_jam_range_basic. apply derives_refl.
    - simpl. assert (HH: (1 | Int.Z_mod_modulus ofs)) by apply Z.divide_1_l. normalize. clear HH.
      rewrite allp_jam_range_rec; [| simpl in H0; omega].
      apply sepcon_derives.
      * apply allp_derives; intros.
        admit.
      * pose proof (IHbl (length bl)) eq_refl (ofs + 1); clear IHbl.
        replace (Z.of_nat n - 1) with (Z.of_nat (length bl)).
        admit.
        subst n. simpl length. rewrite Nat2Z.inj_succ. omega.
  + normalize.
    apply (exp_right (Memdata.decode_val ch (bls_to_bl bls))).
    apply (exp_right (bls_to_bl bls)).
    pose proof list_address_mapsto'_Mint8unsigned vs rsh sh b ofs bls.
    eapply add_andp_to_left; [exact H1|clear H1].
    normalize.
    rewrite H1, H2.
    apply andp_right; [apply prop_right; repeat split|]; [exact H0 | exact H |].
    rewrite Memdata.size_chunk_conv.
    forget (Memdata.size_chunk_nat ch) as n.
    clear H H1 H2.
    revert ofs n vs H0; induction bls; intros; destruct vs; simpl in *.
    - subst n; simpl.
      rewrite allp_jam_range_basic.
      normalize.
    - normalize.
    - normalize.
    - normalize. change (Memdata.size_chunk_nat Mint8unsigned) with (1%nat) in H.
      clear H1.
      rewrite (allp_jam_range_rec _ _ (Z.of_nat n)); [| simpl in H0; omega].
      apply sepcon_derives.
      * admit.
      * (*pose proof list_address_mapsto'_Mint8unsigned vs rsh sh b (ofs + 1) bls.
        eapply add_andp_to_left; [exact H1|clear H1].
        normalize.*)
        pose proof IHbls (ofs + 1) (length vs) vs eq_refl as HH.
        eapply derives_trans; [exact HH|clear HH].
        admit.
Qed.

Lemma align_chunk_alignof: forall t ch, access_mode t = By_value ch -> legal_alignas_type t = true -> alignof t = Memdata.align_chunk ch.
Proof.
Transparent alignof.
  intros.
  destruct t; inversion H.
  - unfold legal_alignas_type in H0.
    simpl in H0.
    destruct i, s; inversion H2; simpl;
    destruct (attr_alignas a); try inversion H0; reflexivity.
  - unfold legal_alignas_type in H0.
    simpl in H0.
    destruct s; inversion H2; simpl;
    destruct (attr_alignas a); try inversion H0; admit. (* Tlong uncompatible problem *)
  - unfold legal_alignas_type in H0.
    simpl in H0.
    destruct f; inversion H2; simpl;
    destruct (attr_alignas a); try inversion H0; reflexivity.
  - unfold legal_alignas_type in H0.
    simpl in H0.
    inversion H2; simpl;
    destruct (attr_alignas a); try inversion H0; reflexivity.
Opaque alignof.
Qed.

Lemma size_chunk_sizeof: forall t ch, access_mode t = By_value ch -> sizeof t = Memdata.size_chunk ch.
Proof.
  intros.
  destruct t; inversion H.
  - destruct i, s; inversion H1; reflexivity.
  - destruct s; inversion H1; reflexivity.
  - destruct f; inversion H1; reflexivity.
  - inversion H1; reflexivity.
Qed.

Lemma memory_block_mapsto_:
  forall n sh t b i_ofs, 
   by_value_non_volatile t ->
   legal_alignas_type t = true ->
   (alignof t | Int.unsigned i_ofs) ->
   Int.unsigned n = sizeof t ->
   memory_block sh n (Vptr b i_ofs) = mapsto_ sh t (Vptr b i_ofs).
Proof.
  intros.
  unfold memory_block.
  rewrite memory_block'_list_address_mapsto.
  destruct (access_mode_by_value_non_volatile t H) as [ch ?].
  erewrite mapsto__exp_address_mapsto; [|exact H3|exact H].
  rewrite address_mapsto_list_address_mapsto_Mint8unsigned; 
    [| erewrite align_chunk_alignof in H1; [exact H1| exact H3| exact H0]].
  unfold Memdata.size_chunk_nat.
  erewrite size_chunk_sizeof in H2; [| exact H3].
  rewrite H2.
  reflexivity.
Qed.

(******************************************

Lemmas about mapsto and mapsto_.

Other lemmas has been proved elsewhere:

mapsto_local_facts: forall (sh : Share.t) (t : type) (v1 v2 : val),
  mapsto sh t v1 v2 |-- !!isptr v1

mapsto__local_facts: forall (sh : Share.t) (t : type) (v1 : val),
  mapsto_ sh t v1 |-- !!isptr v1

******************************************)

Lemma mapsto_mapsto_: forall sh t v v', mapsto sh t v v' |-- mapsto_ sh t v.
Proof. unfold mapsto_; intros.
  normalize.
  unfold mapsto.
  destruct (access_mode t); auto.
  destruct (type_is_volatile t); try apply FF_left.
  destruct v; auto.
  apply orp_left.
  apply orp_right2.
  apply andp_left2.
  apply andp_right. apply prop_right; auto.
  apply exp_right with v'; auto.
  normalize.
  apply orp_right2. apply exp_right with v2'.
  normalize.
Qed.
Hint Resolve mapsto_mapsto_ : cancel.

Lemma mapsto_offset_zero:
  forall sh t v1 v2, 
    mapsto sh t (offset_val (Int.repr 0) v1) v2 =
    mapsto sh t v1 v2.
Proof.
  intros.
  change (mapsto sh t (offset_val (Int.repr 0) v1) v2) with ((fun v0 => mapsto sh t v0 v2) (offset_val Int.zero v1)).
  rewrite <- local_facts_offset_zero.
  reflexivity.
  intros.
  apply mapsto_local_facts.  
Qed.

Lemma mapsto__offset_zero:
  forall sh t v1, 
    mapsto_ sh t (offset_val (Int.repr 0) v1) =
    mapsto_ sh t v1.
Proof.
  unfold mapsto_.
  intros.
  apply mapsto_offset_zero.
Qed.

Lemma mapsto_isptr: forall sh t v1 v2, mapsto sh t v1 v2 = !! (isptr v1) && mapsto sh t v1 v2.
Proof.
  intros.
  change (mapsto sh t v1 v2) with ((fun v1 => mapsto sh t v1 v2) v1).
  rewrite <- local_facts_isptr.
  reflexivity.
  apply mapsto_local_facts.
Qed.

Lemma mapsto__isptr: forall sh t v1, mapsto_ sh t v1 = !! (isptr v1) && mapsto_ sh t v1.
Proof.
  intros.
  unfold mapsto_. apply mapsto_isptr.
Qed.

(******************************************

Lemmas about memory_block

******************************************)

Lemma memory_block_zero: forall sh b z, memory_block sh (Int.repr 0) (Vptr b z) = emp.
Proof.
  intros. unfold memory_block.
  change (Int.repr 0) with Int.zero.
  rewrite Int.unsigned_zero.
  change (nat_of_Z 0) with (0%nat).
  unfold memory_block'.
  reflexivity.
Qed.
Hint Rewrite memory_block_zero: norm.

Lemma memory_block_local_facts: forall sh n p, memory_block sh n p |-- !! (isptr p).
Proof.
  intros.
  destruct p; simpl; normalize.
Qed.

Lemma memory_block_offset_zero:
  forall sh n v, memory_block sh n (offset_val Int.zero v) = memory_block sh n v.
Proof.
  intros.
  rewrite <- local_facts_offset_zero.
  reflexivity.
  apply memory_block_local_facts.
Qed.

Lemma memory_block_isptr: forall sh n p, memory_block sh n p = !!(isptr p) && memory_block sh n p.
Proof.
  intros.
  rewrite <- local_facts_isptr.
  reflexivity.
  apply memory_block_local_facts.
Qed.

Global Opaque memory_block.

(******************************************

Definition of reptype.

reptype is not defined in a quite beautiful way now. However, there seems no
better choice. The situation is explained at the end of this file. When Coq
releases a new version in the future, maybe we can rewrite it in a better way.

******************************************)

Scheme type_mut := Induction for type Sort Prop
with typelist_mut := Induction for typelist Sort Prop
with fieldlist_mut := Induction for fieldlist Sort Prop.

Fixpoint is_Fnil (fld: fieldlist) : bool :=
  match fld with
  | Fnil => true
  | Fcons id ty fld' => false
  end.

Fixpoint reptype (ty: type) : Type :=
  match ty with
  | Tvoid => unit
  | Tint _ _ _ => val
  | Tlong _ _ => val
  | Tfloat _ _ => val
  | Tpointer t1 a => val
  | Tarray t1 sz a => list (reptype t1)
  | Tfunction t1 t2 _ => unit
  | Tstruct id fld a => reptype_structlist fld
  | Tunion id fld a => reptype_unionlist fld
  | Tcomp_ptr id a => val
  end
with reptype_structlist (fld: fieldlist) : Type :=
  match fld with
  | Fnil => unit
  | Fcons id ty fld' => 
    if is_Fnil fld' 
      then reptype ty
      else prod (reptype ty) (reptype_structlist fld')
  end
with reptype_unionlist (fld: fieldlist) : Type :=
  match fld with
  | Fnil => unit
  | Fcons id ty fld' => 
    if is_Fnil fld' 
      then reptype ty
      else sum (reptype ty) (reptype_unionlist fld')
  end.

Fixpoint reptype' (ty: type) : Type :=
  match ty with
  | Tvoid => unit
  | Tint _ _ _ => int
  | Tlong _ _ => Int64.int
  | Tfloat _ _ => float
  | Tpointer t1 a => val
  | Tarray t1 sz a => list (reptype' t1)
  | Tfunction t1 t2 _ => unit
  | Tstruct id fld a => reptype'_structlist fld
  | Tunion id fld a => reptype'_unionlist fld
  | Tcomp_ptr id a => val
  end
with reptype'_structlist (fld: fieldlist) : Type :=
  match fld with
  | Fnil => unit
  | Fcons id ty fld' => 
    if is_Fnil fld' 
      then reptype' ty
      else prod (reptype' ty) (reptype'_structlist fld')
  end
with reptype'_unionlist (fld: fieldlist) : Type :=
  match fld with
  | Fnil => unit
  | Fcons id ty fld' => 
    if is_Fnil fld' 
      then reptype' ty
      else sum (reptype' ty) (reptype'_unionlist fld')
  end.

Fixpoint repinj (t: type): reptype' t -> reptype t :=
  match t as t0 return (reptype' t0 -> reptype t0) with
  | Tvoid => id
  | Tint _ _ _ => Vint
  | Tlong _ _ => Vlong
  | Tfloat _ _ => Vfloat
  | Tpointer _ _ => id
  | Tarray t0 _ _ => (map (repinj t0))
  | Tfunction _ _ _ => id
  | Tstruct _ f _ => (repinj_structlist f)
  | Tunion _ f _ => (repinj_unionlist f)
  | Tcomp_ptr _ _ => id
  end
with repinj_structlist (fld: fieldlist) : reptype'_structlist fld -> reptype_structlist fld :=
  match fld as f return (reptype'_structlist f -> reptype_structlist f) with
  | Fnil => id
  | Fcons _ t fld0 =>
    (if is_Fnil fld0  as b0
      return
        (is_Fnil fld0 = b0 ->
         (if b0
          then reptype' t
          else (reptype' t * reptype'_structlist fld0)%type) ->
         if b0 then reptype t else (reptype t * reptype_structlist fld0)%type)
     then fun _ : is_Fnil fld0 = true => repinj t
     else
      fun (_ : is_Fnil fld0 = false)
        (v : reptype' t * reptype'_structlist fld0) =>
      (repinj t (fst v), repinj_structlist fld0 (snd v))) eq_refl
  end
with repinj_unionlist (fld: fieldlist) : reptype'_unionlist fld -> reptype_unionlist fld :=
  match fld as f return (reptype'_unionlist f -> reptype_unionlist f) with
  | Fnil => id
  | Fcons _ t fld0 =>
    (if is_Fnil fld0  as b0
      return
        (is_Fnil fld0 = b0 ->
         (if b0
          then reptype' t
          else sum (reptype' t) (reptype'_unionlist fld0)) ->
         if b0 then reptype t else sum (reptype t) (reptype_unionlist fld0))
     then fun _ : is_Fnil fld0 = true => repinj t
     else
      fun (_ : is_Fnil fld0 = false) (v : sum (reptype' t) (reptype'_unionlist fld0)) =>
      match v with
      | inl v1 => inl (repinj t v1)
      | inr v2 => inr (repinj_unionlist fld0 v2)
      end) eq_refl
  end.

Fixpoint default_val (t: type) : reptype t :=
  match t as t0 return (reptype t0) with
  | Tvoid => tt
  | Tint _ _ _ => Vundef
  | Tlong _ _ => Vundef
  | Tfloat _ _ => Vundef
  | Tpointer _ _ => Vundef
  | Tarray t0 _ _ => nil
  | Tfunction _ _ _ => tt
  | Tstruct _ f _ => struct_default_val f
  | Tunion _ f _ => union_default_val f
  | Tcomp_ptr _ _ => Vundef
  end
with struct_default_val flds : reptype_structlist flds :=
  match flds as f return (reptype_structlist f) with
  | Fnil => tt
  | Fcons _ t flds0 =>
     if is_Fnil flds0 as b
      return  (if b then reptype t else (reptype t * reptype_structlist flds0)%type)
     then default_val t
     else (default_val t, struct_default_val flds0)
  end
with union_default_val flds : reptype_unionlist flds :=
  match flds as f return (reptype_unionlist f) with
  | Fnil => tt
  | Fcons _ t flds0 =>
     if is_Fnil flds0 as b
      return  (if b then reptype t else (reptype t + reptype_unionlist flds0)%type)
     then default_val t
     else inl (default_val t)
  end.

Lemma int_add_repr_0_l: forall i, Int.add (Int.repr 0) i = i.
Proof. intros. apply Int.add_zero_l. Qed.
Lemma int_add_repr_0_r: forall i, Int.add i (Int.repr 0) = i.
Proof. intros. apply Int.add_zero. Qed.
Hint Rewrite int_add_repr_0_l int_add_repr_0_r : norm.

(*
Lemma field_at__offset_zero:
  forall sh ty id v, 
   field_at_ sh ty id (offset_val (Int.repr 0) v) =
   field_at_ sh ty id v.
Proof.
 unfold field_at_; intros.
 destruct v; try solve [simpl; auto].
 simpl offset_val. rewrite int_add_repr_0_r. reflexivity.
Qed.
Hint Rewrite field_at__offset_zero: norm.
*)

(******************************************

Definition of all at_offsets.

at_offset is the elementary definition. but it is not good for computation. As
a result, users should not unfold at_offset' into at_offset. And all useful 
lemmas about at_offset' will be proved here. 

at_offset2 is defined on at_offset'. Users should unfold at_offset2 and prove
lemmas on the level of at_offset'.

******************************************)

Definition at_offset (z: Z) (P: val -> mpred) : val -> mpred :=
 fun v => P (offset_val (Int.repr z) v).

Arguments at_offset z P v : simpl never.

Definition at_offset' (P: val -> mpred) (z: Z)  : val -> mpred :=
 match z with Z0 => P | _ => at_offset z P end.

Definition at_offset2 {T} (f: val -> T -> mpred) pos (v2: T) := 
           at_offset' (fun v => f v v2) pos.

Lemma at_offset'_eq: forall P z v,
  P (offset_val (Int.repr 0) v) = P v ->
  at_offset' P z v = P (offset_val (Int.repr z) v).
Proof.
intros.
unfold at_offset'.
destruct z; auto.
Qed.

Lemma lifted_at_offset'_eq: forall (P: val -> mpred) z v,
  (forall p, P ((offset_val (Int.repr 0)) p) = P p) ->
  `(at_offset' P z) v = `P (`(offset_val (Int.repr z)) v).
Proof.
  intros.
  unfold liftx, lift in *. simpl in *.
  extensionality p.
  apply at_offset'_eq.
  apply H.
Qed.

Lemma at_offset'_eq2: forall pos pos' P, 
  (forall p, P (offset_val (Int.repr 0) p) = P p) -> 
  forall p, at_offset' P (pos + pos') p = at_offset' P pos' (offset_val (Int.repr pos) p).
Proof.
  intros.
  rewrite at_offset'_eq; [| apply H].
  rewrite at_offset'_eq; [| apply H].
  unfold offset_val.
  destruct p; auto.
  rewrite int_add_assoc1.
  reflexivity.
Qed.

Lemma at_offset_derives: forall P Q, P |-- Q -> forall pos, at_offset' P pos |-- at_offset' Q pos.
Proof.
  intros.
  go_lower.
  unfold at_offset', at_offset. destruct pos; apply H.
Qed.

(******************************************

Definitions of spacer and withspacer

******************************************)

Definition spacer (sh: share) (pos: Z) (alignment: Z) : val -> mpred :=
  if Z.eq_dec  (align pos alignment - pos) 0
  then fun _ => emp
  else
   at_offset' (memory_block sh (Int.repr (align pos alignment - pos))) pos.

Arguments spacer sh pos alignment / _ .

Definition withspacer sh (pos: Z) (alignment: Z) : (val -> mpred) -> val -> mpred :=
   match align pos alignment - pos with
   | Z0 => fun P => P
   | _ => fun P => spacer sh pos alignment * P
   end.

Lemma withspacer_spacer: forall sh pos alignment P,
   withspacer sh pos alignment P = spacer sh pos alignment * P.
Proof.
  intros.
 extensionality v.
 unfold withspacer, spacer.
 destruct (align pos alignment - pos); auto.
 rewrite if_true by auto.
 simpl. rewrite emp_sepcon. auto.
Qed.

Lemma spacer_offset_zero:
  forall sh pos n v, spacer sh pos n (offset_val (Int.repr 0) v) = spacer sh pos n v.
Proof.
  intros;
  unfold spacer.
  destruct (Z.eq_dec (align pos n - pos) 0);  auto.
  repeat rewrite at_offset'_eq; 
  try rewrite offset_offset_val; try  rewrite Int.add_zero_l; auto.
  apply memory_block_offset_zero.
Qed.

Lemma withspacer_add:
  forall sh pos pos' alignment P p,
  (alignment | pos) ->
  withspacer sh (pos + pos') alignment (fun p0 => P (offset_val (Int.repr pos) p)) p = 
  withspacer sh pos' alignment P (offset_val (Int.repr pos) p).
Proof.
  intros.
  rewrite withspacer_spacer.
  rewrite withspacer_spacer.
  simpl.
  replace (align (pos + pos') alignment) with (pos + align pos' alignment) by
    (rewrite <- divide_add_align; [reflexivity | exact H]).
  replace (pos + align pos' alignment - (pos + pos')) with (align pos' alignment - pos') by omega.
  if_tac; [reflexivity|].
  repeat (rewrite at_offset'_eq; [|apply memory_block_offset_zero]).
  replace (offset_val (Int.repr (pos + pos')) p) with
          (offset_val (Int.repr pos') (offset_val (Int.repr pos) p)).
  reflexivity.
  destruct p; simpl; try reflexivity.
  rewrite int_add_assoc1.
  reflexivity.
Qed.

Definition alignof_hd (fld: fieldlist) : Z :=
  match fld with
  | Fnil => 1
  | Fcons _ t _ => alignof t
  end.

Lemma alignof_hd_divide: forall f, (alignof_hd f | alignof_fields f).
Proof.
  intros.
  destruct f.
  + simpl. apply Z.divide_refl.
  + simpl alignof_hd. apply alignof_fields_hd_divide.
Qed.

Lemma alignof_hd_pos: forall f, alignof_hd f > 0.
Proof.
  intros.
  destruct f; simpl.
  omega.
  apply alignof_pos.
Qed.

(************************************************

Definition of data_at 

************************************************)

(************************************************

Always assume in arguments of data_at', array_at', sfieldlist_at', ufieldlist_
at' has argument pos with alignment criterian. So, spacers are only added after
fields of structs or unions.

A new array_at' is used here. But it worths discussion which version is better.

Personally, I don't know why "function" case looks like this. I just copy it
from previous version.

************************************************)

Definition type_id_env: Type := PTree.t type.
Definition empty_ti: type_id_env := @PTree.empty type.

Definition singleton_ti t: type_id_env :=
  match t with
  | Tstruct i _ _ => PTree.set i t empty_ti
  | Tunion i _ _ => PTree.set i t empty_ti
  | _ => empty_ti
  end.

Definition look_up_ident_default (i: ident) (e: type_id_env) : type :=
  match PTree.get i e with
  | Some res => res
  | None => Tvoid
  end.

Fixpoint array_at' (sh: Share.t) (t: type) (length: Z) (P: Z -> reptype t -> val -> mpred) (pos: Z) (v: list (reptype t)) : val -> mpred :=
match v with
| nil => if (Zeq_bool length 0) then fun _ => emp else FF
| hd :: tl => (P pos hd) * (array_at' sh t (length - 1) P (pos + sizeof t) tl)
end.

Fixpoint data_at' (sh: Share.t) (e: type_id_env) (t1: type): Z -> reptype t1 -> val -> mpred :=
  match t1 as t return (Z -> reptype t -> val -> mpred) with
  | Tvoid => at_offset2 (fun v _ => memory_block sh (Int.repr (sizeof t1)) v)
  | Tarray t z a => array_at' sh t z (data_at' sh e t)
  | Tfunction t t0 _ => at_offset2 (fun v _ => memory_block sh (Int.repr (sizeof t1)) v)
  | Tstruct i f a => sfieldlist_at' sh e (alignof t1) f
  | Tunion i f a => ufieldlist_at' sh e (alignof t1) f
  | Tcomp_ptr i a => at_offset2 (mapsto sh (Tpointer (look_up_ident_default i e) a))
  | _ => at_offset2 (mapsto sh t1) (* All these C types are by value types *)
  end
with sfieldlist_at' (sh: Share.t) (e: type_id_env) (alignment: Z) (flds: fieldlist) : Z -> reptype_structlist flds -> val -> mpred :=
  fun (pos: Z) =>
  match flds as f return reptype_structlist f -> val -> mpred with
  | Fnil => fun _ p => !!(isptr p) && emp (* empty struct case *)
  | Fcons i t flds0 =>
    fun v : reptype_structlist (Fcons i t flds0) =>
      (if is_Fnil flds0 as b
        return
          (is_Fnil flds0 = b ->
           (if b
            then reptype t
            else (reptype t * reptype_structlist flds0)%type) -> val -> mpred)
       then
        fun (_ : is_Fnil flds0 = true) (v0 : reptype t) =>
          withspacer sh (pos + sizeof t) alignment (data_at' sh e t pos v0)
       else
        fun (_ : is_Fnil flds0 = false) (v0 : (reptype t * reptype_structlist flds0)%type) =>
          withspacer sh (pos + sizeof t) (alignof_hd flds0) (data_at' sh e t pos (fst v0)) *
          (sfieldlist_at' sh e alignment flds0 (align (pos + sizeof t) (alignof_hd flds0)) (snd v0)))
    eq_refl v
  end
with ufieldlist_at' (sh: Share.t) (e: type_id_env) (alignment: Z) (flds: fieldlist) (pos: Z) {struct flds}: reptype_unionlist flds -> val -> mpred :=
  match flds as f return (reptype_unionlist f -> val -> mpred) with
  | Fnil => fun _ p => !!(isptr p) && emp (* empty union case *)
  | Fcons i t flds0 => 
    fun v : reptype_unionlist (Fcons i t flds0) =>
      (if is_Fnil flds0 as b
        return
          (is_Fnil flds0 = b ->
           (if b
            then reptype t
            else (reptype t + reptype_unionlist flds0)%type) -> val -> mpred)
       then
        fun (_ : is_Fnil flds0 = true) (v0 : reptype t) =>
          withspacer sh (pos + sizeof t) alignment (data_at' sh e t pos v0)
       else
        fun (_ : is_Fnil flds0 = false) (v0 : (reptype t + reptype_unionlist flds0)%type) =>
          match v0 with
          | inl v_hd => 
            withspacer sh (pos + sizeof t) alignment (data_at' sh e t pos v_hd)
          | inr v_tl =>
            ufieldlist_at' sh e alignment flds0 pos v_tl
          end)
    eq_refl v
  end.

Definition data_at (sh: Share.t) (t: type) := data_at' sh empty_ti t 0.

Definition data_at_ (sh: Share.t) (t: type) := data_at sh t (default_val _).

Lemma offset_val_preserve_isptr: forall p pos, !! (isptr (offset_val pos p)) |-- !! (isptr p).
Proof.
  intros.
  destruct p; simpl; apply derives_refl.
Qed.

Lemma at_offset2_preserve_local_facts: forall {A: Type} P pos (v: A), (forall p, P p v |-- !!(isptr p)) -> (forall p, at_offset2 P pos v p |-- !!(isptr p)).
Proof.
  intros.
  unfold at_offset2, at_offset', at_offset.
  destruct pos.
  + exact (H p).
  + eapply derives_trans. exact (H _). apply offset_val_preserve_isptr.
  + eapply derives_trans. exact (H _). apply offset_val_preserve_isptr.
Qed.

Lemma withspacer_preserve_local_facts: forall sh pos alignment P, (forall p, P p |-- !! (isptr p)) -> (forall p, withspacer sh pos alignment P p |-- !! (isptr p)).
Proof.
  intros.
  rewrite withspacer_spacer.
  simpl; rewrite sepcon_comm. 
  apply (right_is_prop (!!isptr p) (P p) _); [apply prop_is_prop|].
  apply H.
Qed.

Lemma data_at'_local_facts:
  forall sh e t pos v p, data_at' sh e t pos v p |-- !!(isptr p).
Proof.
  intros.
  revert p.
  apply (type_mut (fun (t: type) => forall pos v p, (data_at' sh e t pos v p |-- !!(isptr p))) (fun _ => True) (fun flds => (forall alignment pos v p, sfieldlist_at' sh e alignment flds pos v p |-- !!(isptr p)) /\ (forall alignment pos v p, ufieldlist_at' sh e alignment flds pos v p |-- !!(isptr p)))); intros; auto; simpl; 
  try (apply at_offset2_preserve_local_facts; intros; apply mapsto_local_facts);
  try (apply at_offset2_preserve_local_facts; intros; apply memory_block_local_facts).
  + admit. (* Array case *)
  + destruct H. apply H. (* struct case *)
  + destruct H. apply H0. (* union case *)
  + split; intros. (* Fnil case of fieldlist induction *)
    - normalize.
    - destruct (Zeq_bool alignment 0); normalize.
  + destruct H0. split; intros.
    - destruct (is_Fnil).
      * apply withspacer_preserve_local_facts; intros. apply H.
      * apply (right_is_prop (!!isptr p) ( withspacer sh (pos0 + sizeof t0) (alignof_hd f)
     (data_at' sh e t0 pos0 (fst v0)) p)); [apply prop_is_prop|].
        apply withspacer_preserve_local_facts; intros. apply H.
    - destruct (is_Fnil).
      * apply withspacer_preserve_local_facts; intros. apply H.
      * destruct v0; [apply withspacer_preserve_local_facts; intros; apply H | apply H1].
Qed.

Lemma data_at'_isptr:
  forall sh e t pos v p, data_at' sh e t pos v p = !!(isptr p) && data_at' sh e t pos v p.
Proof. intros. rewrite <- local_facts_isptr. reflexivity. apply data_at'_local_facts. Qed.

Lemma data_at'_offset_zero:
  forall sh e t pos v p, data_at' sh e t pos v p = data_at' sh e t pos v (offset_val (Int.repr 0) p).
Proof. intros. rewrite <- local_facts_offset_zero. reflexivity. apply data_at'_local_facts. Qed.

Lemma data_at_local_facts: forall sh t v p, data_at sh t v p |-- !!(isptr p).
Proof. intros. unfold data_at. apply data_at'_local_facts. Qed.

Lemma data_at_isptr: forall sh t v p, data_at sh t v p = !!(isptr p) && data_at sh t v p.
Proof. intros. unfold data_at. apply data_at'_isptr. Qed.

Lemma data_at_offset_zero: forall sh t v p, data_at sh t v p = data_at sh t v (offset_val (Int.repr 0) p).
Proof. intros. unfold data_at. apply data_at'_offset_zero. Qed.

Lemma data_at__local_facts: forall sh t p, data_at_ sh t p |-- !!(isptr p).
Proof. intros. unfold data_at_. apply data_at_local_facts. Qed.

Lemma data_at__isptr: forall sh t p, data_at_ sh t p = !!(isptr p) && data_at_ sh t p.
Proof. intros. unfold data_at_. apply data_at_isptr. Qed.

Lemma data_at__offset_zero: forall sh t p, data_at_ sh t p = data_at_ sh t (offset_val (Int.repr 0) p).
Proof. intros. unfold data_at_. apply data_at_offset_zero. Qed.

Lemma data_at'_lemma: forall (sh: Share.t) (e1 e2: type_id_env) (t: type), data_at' sh e1 t = data_at' sh e2 t.
Proof.
  intros.
  apply (type_mut (fun t => data_at' sh e1 t = data_at' sh e2 t) (fun _ => True) (fun flds => forall alignment: Z, sfieldlist_at' sh e1 alignment flds = sfieldlist_at' sh e2 alignment flds /\ ufieldlist_at' sh e1 alignment flds = ufieldlist_at' sh e2 alignment flds)); intros; try reflexivity. (* Happily, Tcomp_ptr case is solved by reflexivity automatically. *)
  + simpl. rewrite H. reflexivity. (* About array *)
  + simpl. destruct (H (alignof (Tstruct i f a))). exact H0. (* About struct *)
  + simpl. destruct (H (alignof (Tstruct i f a))). exact H1. (* About union *)
  + simpl. split; reflexivity.  (* Fnil case of fieldlist induction *)
  + destruct (H0 alignment). simpl. split. (* Fcons case of fieldlist induction *)
    rewrite H, H1. reflexivity.
    rewrite H, H2. reflexivity.
Qed.

Lemma lower_sepcon_val':
  forall (P Q: val->mpred) v, 
  ((P*Q) v) = (P v * Q v).
Proof. reflexivity. Qed.

Lemma data_at'_data_at: forall sh t v pos, (no_nested_alignas_type t = true) -> (alignof t | pos) -> data_at' sh empty_ti t pos v = at_offset' (data_at sh t v) pos.
Proof.
  intros.
  extensionality p.
  rewrite at_offset'_eq; [| rewrite <- data_at_offset_zero; reflexivity].
  unfold data_at.
  replace (data_at' sh empty_ti t pos) with (data_at' sh empty_ti t (pos + 0)) by
    (replace (pos + 0) with pos by omega; reflexivity).
  apply (type_mut 
         (fun t => forall pos', 
                   no_nested_alignas_type t = true ->
                   (alignof t | pos) -> 
                   (alignof t | pos') -> 
                   forall v p, data_at' sh empty_ti t (pos + pos') v p =
                   data_at' sh empty_ti t pos' v (offset_val (Int.repr pos) p))
         (fun _ => True)
         (fun f => forall pos' alignment,
                   nested_fields_pred no_alignas_type f = true ->
                   (alignof_fields f | alignment) -> 
                   (alignment | pos) -> 
                   ((alignof_hd f | pos') -> 
                   forall v p, sfieldlist_at' sh empty_ti alignment f (pos + pos') v p = 
                   sfieldlist_at' sh empty_ti alignment f pos' v (offset_val (Int.repr pos) p)) /\
                   ((alignof_fields f | pos') -> 
                   forall v p, ufieldlist_at' sh empty_ti alignment f (pos + pos') v p = 
                   ufieldlist_at' sh empty_ti alignment f pos' v (offset_val (Int.repr pos) p)))); intros;
    try assumption;
    try constructor;
    try (simpl;
         unfold at_offset2;
         rewrite at_offset'_eq2; [reflexivity |];
         try apply memory_block_offset_zero;
         try (intros; apply mapsto_offset_zero)).
  + admit. (* array case *)
  + simpl.
    assert (alignof_fields f | alignof (Tstruct i f a)).
      rewrite no_nested_alignas_type_Tstruct; [apply Z.divide_refl | exact H2].
    assert (alignof_hd f | pos').
      eapply Z.divide_trans; [apply alignof_hd_divide |].
      eapply Z.divide_trans; [exact H5 | exact H4].
    unfold no_nested_alignas_type in H2.
    simpl in H2.
    rewrite andb_true_iff in H2.
    destruct H2 as [_ ?].
    destruct (H1 pos' (alignof (Tstruct i f a)) H2 H5 H3) as [? _].
    apply (H7 H6).
  + simpl.
    assert (alignof_fields f | alignof (Tunion i f a)).
      rewrite no_nested_alignas_type_Tunion; [apply Z.divide_refl | exact H2].
    assert (alignof_fields f | pos').
      rewrite no_nested_alignas_type_Tunion in H4. exact H4. exact H2.
    unfold no_nested_alignas_type in H2.
    simpl in H2.
    rewrite andb_true_iff in H2.
    destruct H2 as [_ ?].
    destruct (H1 pos' (alignof (Tstruct i f a)) H2 H5 H3) as [_ ?].
    apply (H7 H6).
  + intros.
    simpl. normalize.
  + intros.
    simpl. normalize.
  + intros.
    assert (alignof t0 | pos); [
      eapply Z.divide_trans; [|exact H5];
      eapply Z.divide_trans; [|exact H4];
      apply alignof_fields_hd_divide |].
    assert (alignof t0 | pos'); [
      eapply Z.divide_trans; [|exact H6];
      simpl alignof_hd; apply Z.divide_refl |].
    simpl in H3.
    apply andb_true_iff in H3; destruct H3 as [? ?].
    destruct (is_Fnil f) eqn:Hf; intros; revert v0; simpl; rewrite Hf; intros.
    * rewrite <- (withspacer_add _ _ _ _ _ _ H5).
      repeat rewrite withspacer_spacer.
      repeat rewrite lower_sepcon_val'.
      rewrite <- (H1 pos' H3 H7 H8).
      rewrite Zplus_assoc_reverse.
      reflexivity.
    * erewrite <- withspacer_add; [|
        eapply Z.divide_trans; [|exact H5];
        eapply Z.divide_trans; [|exact H4];
        eapply Z.divide_trans; [apply alignof_hd_divide | apply alignof_fields_tl_divide]].
      repeat rewrite withspacer_spacer.
      repeat rewrite lower_sepcon_val'.
      rewrite <- (H1 pos' H3 H7 H8).
      assert (alignof_fields f | alignment); [
        eapply Z.divide_trans; [|exact H4];
        apply alignof_fields_tl_divide |].
      assert (alignof_hd f | (align (pos' + sizeof t0) (alignof_hd f))); [
        apply align_divides; apply alignof_hd_pos |].
      destruct (H2 (align (pos' + sizeof t0) (alignof_hd f))alignment H9 H10 H5) as [? _].
      rewrite Zplus_assoc_reverse.
      replace (align (pos + (pos' + sizeof t0)) (alignof_hd f))  with (pos + align (pos' + sizeof t0) (alignof_hd f)); [ rewrite (H12  H11); reflexivity |].
      apply divide_add_align.
      eapply Z.divide_trans; [apply alignof_hd_divide|].
      eapply Z.divide_trans; [exact H10 | exact H5].
  + intros.
    assert (alignof t0 | pos); [
      eapply Z.divide_trans; [|exact H5];
      eapply Z.divide_trans; [|exact H4];
      apply alignof_fields_hd_divide |].
    assert (alignof t0 | pos'); [
      eapply Z.divide_trans; [apply alignof_fields_hd_divide |exact H6]|].
    assert (alignof_fields f | pos').
      eapply Z.divide_trans; [apply alignof_fields_tl_divide |exact H6].
    simpl in H3.
    apply andb_true_iff in H3; destruct H3 as [? ?].
    destruct (is_Fnil f) eqn:Hf; intros; revert v0; simpl; rewrite Hf; intros; [|destruct v0].
    * rewrite <- (withspacer_add _ _ _ _ _ _ H5).
      repeat rewrite withspacer_spacer.
      repeat rewrite lower_sepcon_val'.
      rewrite <- (H1 pos' H3 H7 H8).
      rewrite Zplus_assoc_reverse.
      reflexivity.
    * erewrite <- withspacer_add; [| exact H5].
      repeat rewrite withspacer_spacer.
      repeat rewrite lower_sepcon_val'.
      rewrite Zplus_assoc_reverse.
      rewrite <- (H1 pos' H3 H7 H8).
      reflexivity.
    * assert (alignof_fields f | alignment); [
        eapply Z.divide_trans; [|exact H4];
        apply alignof_fields_tl_divide |]. 
      destruct (H2 pos' alignment H10 H11 H5) as [_ ?].
      rewrite (H12 H9).
      reflexivity.
  + apply Z.divide_0_r.
Qed.

Lemma data_at_data_at_ :
  forall sh t v p, data_at sh t v p |-- data_at_ sh t p.
Proof.
  intros.
  unfold data_at_, data_at.
  remember 0 as pos.
  assert (alignof t | pos).
    subst pos.
    apply Zdivide_0.
  apply (type_mut 
    (fun t => forall pos v, data_at' sh empty_ti t pos v p |-- data_at' sh empty_ti t pos (default_val t) p) (fun t => True)
    (fun f => (forall alignment pos v, sfieldlist_at' sh empty_ti alignment f pos v p |-- sfieldlist_at' sh empty_ti alignment f pos (struct_default_val f) p) /\ forall alignment pos v, ufieldlist_at' sh empty_ti alignment f pos v p |-- ufieldlist_at' sh empty_ti alignment f pos (union_default_val f) p));
  intros; simpl;
  try (apply derives_refl; reflexivity);
  try (unfold at_offset2; eapply derives_trans; 
    [apply at_offset_derives; go_lower; apply mapsto_mapsto_; reflexivity |
    unfold mapsto_; apply derives_refl; reflexivity]);
  try tauto.
  + admit. (* array case *)
  + destruct H0 as [? _].
    apply H0.
  + destruct H0 as [_ ?].
    apply H0.
  + split; intros; apply derives_refl.
  + split; intros; destruct (is_Fnil f).
    * repeat rewrite withspacer_spacer.
      repeat rewrite lower_sepcon_val'.
      cancel.
    * apply sepcon_derives.
      - repeat rewrite withspacer_spacer.
        repeat rewrite lower_sepcon_val'.
        cancel.
      - destruct H1 as [? _].
        apply H1.
    * repeat rewrite withspacer_spacer.
      repeat rewrite lower_sepcon_val'.
      cancel.
    * simpl default_val. destruct v0.
      - repeat rewrite withspacer_spacer.
        repeat rewrite lower_sepcon_val'.
        cancel.
      - admit. (* Here, we need the help from memory_block and mapsto_ lemmas. *)
Qed.

Hint Resolve data_at_data_at_.


(************************************************

Definition of nested_reptype_structlist, nested_data_at, nested_sfieldlist_at

************************************************)

Fixpoint nested_reptype_structlist (ids: list ident) (t: type) (fld: fieldlist) : Type :=
  match fld with
  | Fnil => unit
  | Fcons i _ fld' =>
    if (is_Fnil fld')
    then reptype (nested_field_type2 (i :: ids) t)
    else prod (reptype (nested_field_type2 (i :: ids) t)) (nested_reptype_structlist ids t fld')
  end.

Fixpoint nested_reptype_unionlist (ids: list ident) (t: type) (fld: fieldlist) : Type :=
  match fld with
  | Fnil => unit
  | Fcons i _ fld' => sum (reptype (nested_field_type2 (i :: ids) t)) (nested_reptype_unionlist ids t fld')
  end.

Lemma nested_reptype_lemma: forall ids t t0, nested_field_type ids t = Some t0 -> reptype t0 = reptype (nested_field_type2 ids t).
Proof.
  unfold nested_field_type, nested_field_type2.
  intros.
  destruct (nested_field_rec ids t) as [(ofs', t')|] eqn:HH.
  + inversion H.
    reflexivity.
  + inversion H.
Qed.

(*

Lemma fieldlist_no_replicate_mid_criteria: forall f1 i t f2, fieldlist_no_replicate (fieldlist_app f1 (Fcons i t f2)) = (negb (fieldlist_in i f1) && negb (fieldlist_in i f2) && fieldlist_no_replicate (fieldlist_app f1 f2))%bool.
Proof.
  intros.
  induction f1; simpl.
  + reflexivity.
  + rewrite IHf1.
    destruct (Pos.eqb i i0) eqn:?; simpl.
    - apply andb_false_intro1.
      apply Pos.eqb_eq in Heqb.
      subst i0.
      destruct (fieldlist_in i (Fcons i t f2)) eqn:HH.
      * rewrite fieldlist_app_in, HH.
        destruct (fieldlist_in i f1); reflexivity.
      * simpl in HH; rewrite (Pos.eqb_refl) in HH.
        inversion HH.
    - rewrite fieldlist_app_in. simpl.
      rewrite Pos.eqb_sym in Heqb.
      rewrite Heqb.
      rewrite fieldlist_app_in.
      destruct (fieldlist_in i0 f1), (fieldlist_in i0 f2), (fieldlist_in i f1), (fieldlist_in i f2);
         reflexivity.
Qed.

Lemma fieldlist_no_replicate_app_comm: forall f1 f2, fieldlist_no_replicate (fieldlist_app f1 f2) = true -> fieldlist_no_replicate (fieldlist_app f2 f1) = true.
Proof.
  intros.
  induction f1.
  + simpl in *. rewrite fieldlist_app_Fnil. exact H.
  + rewrite fieldlist_no_replicate_mid_criteria.
    simpl in H.
    rewrite fieldlist_app_in in H.
    destruct (fieldlist_in i f1), (fieldlist_in i f2), (fieldlist_no_replicate (fieldlist_app f1 f2)), 
      (fieldlist_no_replicate (fieldlist_app f2 f1));
      firstorder.
Qed.

*)

Lemma nested_reptype_structlist_lemma: forall ids t i f' f a ofs, nested_field_rec ids t = Some (ofs, Tstruct i (fieldlist_app f' f) a) -> nested_legal_fieldlist t = true -> reptype_structlist f = nested_reptype_structlist ids t f.
Proof.
  intros.
  assert (nested_field_type2 ids t = Tstruct i (fieldlist_app f' f) a).
    unfold nested_field_type2. rewrite H. reflexivity.
  apply (nested_field_type2_nest_pred eq_refl ids), nested_pred_atom_pred in H0. 
  rewrite H1 in H0; clear H1.
  revert f' H H0; induction f; intros.
  + reflexivity.
  + simpl. pose proof field_type_mid _ _ _ _ H0.
    destruct f.
    - simpl. 
      apply nested_reptype_lemma.
      unfold nested_field_type.
      simpl.
      rewrite H.
      solve_field_offset_type i0 (fieldlist_app f' (Fcons i0 t0 Fnil)); inversion H1.
      reflexivity.
    - destruct (is_Fnil (Fcons i1 t1 f)) eqn:Heq; [simpl in Heq; congruence| clear Heq].
      rewrite (nested_reptype_lemma (i0 :: ids) t t0).
      rewrite fieldlist_app_Fcons in H0, H.
      rewrite (IHf _ H H0).
      reflexivity.
      * unfold nested_field_type.
        simpl.
        rewrite H.
        solve_field_offset_type i0 (fieldlist_app f' (Fcons i0 t0 (Fcons i1 t1 f)));
        inversion H1; reflexivity.
Qed.

Lemma nested_reptype_structlist_lemma2: forall ids t i f a, nested_field_type2 ids t = Tstruct i f a -> nested_legal_fieldlist t = true -> reptype (nested_field_type2 ids t) = nested_reptype_structlist ids t f.
Proof.
  intros.
  rewrite H. simpl.
  unfold nested_field_type2 in H.
  valid_nested_field_rec ids t H.
  apply (nested_reptype_structlist_lemma _ _ i Fnil f a ofs); simpl; [|exact H0].
  unfold nested_field_type2 in H.
  unfold nested_field_type.
  valid_nested_field_rec ids t H; inversion H1.
  subst.
  reflexivity.
Qed.

(*
Lemma nested_reptype_unionlist_lemma: forall ids t i f a, nested_field_type ids t = Some (Tunion i f a) -> fieldlist_no_replicate f = true -> reptype_unionlist f = nested_reptype_unionlist ids t f.
Proof.
  unfold nested_field_type.
  intros.
  destruct (nested_field_rec ids t) as [(ofs', t')|] eqn:HH; inversion H; clear H.
  subst t'.
  remember f as f'; rewrite Heqf' in HH, H0.
  assert (Hprefix: exists f'', fieldlist_app f'' f' = f). exists Fnil. subst f'. reflexivity.
  clear Heqf'.
  induction f'.
  + reflexivity.
  + destruct Hprefix as [f'' ?]. rewrite <- H in H0.
    pose proof field_type_with_witness _ _ _ _ H0.
    simpl. destruct f'.
    - simpl. 
      rewrite (nested_reptype_lemma (i0 :: ids) t t0); [reflexivity|].
      unfold nested_field_type.
      simpl.
      rewrite HH.
      pose proof field_offset_field_type_match i0 f as Hmatch.
      destruct (field_offset i0 f), (field_type i0 f) eqn:Heq; try inversion Hmatch; clear Hmatch; subst f; rewrite H1 in Heq; inversion Heq; reflexivity.
    - destruct (is_Fnil (Fcons i1 t1 f')) eqn:Heq; [simpl in Heq; congruence| clear Heq].
      rewrite (nested_reptype_lemma (i0 :: ids) t t0).
      rewrite IHf'.
      reflexivity.
      * exists (fieldlist_app f'' (Fcons i0 t0 Fnil)).
        rewrite <- fieldlist_app_Fcons.
        exact H.
      * unfold nested_field_type.
        simpl.
        rewrite HH.
      pose proof field_offset_field_type_match i0 f as Hmatch.
      destruct (field_offset i0 f), (field_type i0 f) eqn:Heq; try inversion Hmatch; clear Hmatch; subst f; rewrite H1 in Heq; inversion Heq; reflexivity.
Qed.

Lemma nested_reptype_unionlist_lemma2: forall ids t i f a, nested_field_type2 ids t = Tunion i f a -> fieldlist_no_replicate f = true -> reptype (nested_field_type2 ids t) = nested_reptype_unionlist ids t f.
Proof.
  intros.
  rewrite H.
  assert (nested_field_type ids t = Some (Tunion i f a)).
  unfold nested_field_type, nested_field_type2 in *.
  destruct (nested_field_rec ids t) as [(?, ?)|].
  rewrite H. reflexivity.
  inversion H.
  simpl.
  apply (nested_reptype_unionlist_lemma _ _ i f a); assumption.
Qed.
*)

Definition nested_data_at (sh: Share.t) (ids: list ident) (t1: type) (v: reptype (nested_field_type2 ids t1)) : val -> mpred := data_at' sh empty_ti (nested_field_type2 ids t1) (nested_field_offset2 ids t1) v.

Definition nested_data_at_ (sh: Share.t) (ids: list ident) (t1: type) : val -> mpred := nested_data_at sh ids t1 (default_val (nested_field_type2 ids t1)).

Fixpoint nested_sfieldlist_at (sh: Share.t) (ids: list ident) (t1: type) (flds: fieldlist) (v: nested_reptype_structlist ids t1 flds) : val -> mpred := 
  match flds as f return (nested_reptype_structlist ids t1 f -> val -> mpred) with
  | Fnil => fun _ p => (!! isptr p) && emp
  | Fcons i t flds0 =>
    fun (v : nested_reptype_structlist ids t1 (Fcons i t flds0)) =>
      (if is_Fnil flds0 as b
        return
          (is_Fnil flds0 = b ->
           (if b
            then reptype (nested_field_type2 (i :: ids) t1)
            else ((reptype (nested_field_type2 (i :: ids) t1) *
        nested_reptype_structlist ids t1 flds0)%type)) -> val -> mpred)
       then
        fun (_ : is_Fnil flds0 = true) (v0: reptype (nested_field_type2 (i :: ids) t1)) =>
          withspacer sh (nested_field_offset2 (i :: ids) t1 + sizeof (nested_field_type2 (i :: ids) t1)) (alignof (nested_field_type2 ids t1)) (nested_data_at sh (i :: ids) t1 v0)
       else
        fun (_ : is_Fnil flds0 = false) (v0: ((reptype (nested_field_type2 (i :: ids) t1) *
        nested_reptype_structlist ids t1 flds0)%type)) =>
          withspacer sh (nested_field_offset2 (i :: ids) t1 + sizeof (nested_field_type2 (i :: ids) t1)) (alignof_hd flds0) (nested_data_at sh (i :: ids) t1 (fst v0)) *
          (nested_sfieldlist_at sh ids t1 flds0 (snd v0)))
   eq_refl v
  end v.

Lemma nested_data_at_Tstruct: forall sh ids t i f a v1 v2 (H1: nested_field_type2 ids t = Tstruct i f a) (H2: nested_legal_fieldlist t = true), (eq_rect _ (fun x => x) v1 _ (nested_reptype_structlist_lemma2 _ _ _ _ _ H1 H2)  = v2) -> no_nested_alignas_type t = true -> nested_data_at sh ids t v1 = nested_sfieldlist_at sh ids t f v2.
Proof.
  intros.
  remember (nested_reptype_structlist_lemma2 ids t i f a H1 H2) as Heq; clear HeqHeq.
  unfold nested_data_at.
  unfold nested_field_type2, nested_field_offset2 in *.
  valid_nested_field_rec ids t H1. subst t0.
  revert Heq v1 H; simpl (reptype (Tstruct i f a)); simpl data_at'; intros.
  destruct f; [reflexivity|].
  pose proof nested_field_rec_hd _ _ _ _ _ _ _ _ H3.
  change (Tstruct i (Fcons i0 t0 f) a) with (Tstruct i (fieldlist_app Fnil (Fcons i0 t0 f)) a).
  change (Fcons i0 t0 f) with (fieldlist_app Fnil (Fcons i0 t0 f)) in H2, H3.
  remember ofs as ofs0; rewrite Heqofs0 in H3; clear Heqofs0.
  remember Fnil as f'; clear Heqf'.
  revert ofs0 f' i0 t0 v1 v2 Heq H H2 H3 H1; induction f; intros.
  + simpl.
    unfold nested_data_at.
    revert Heq v1 v2 H.
    simpl reptype_structlist. simpl nested_reptype_structlist.
    unfold nested_field_offset2, nested_field_type2.
    rewrite H3. rewrite H1.
    intros.
    unfold eq_rect_r in H. rewrite <- eq_rect_eq in H. rewrite H. reflexivity.
  + assert (is_Fnil (Fcons i0 t0 f) = false) by reflexivity.
    remember (Fcons i0 t0 f) as f''.
    revert v1 v2 Heq H.
    simpl reptype_structlist. simpl nested_reptype_structlist.
    simpl sfieldlist_at'. simpl nested_sfieldlist_at.
    rewrite H4; intros.
    extensionality p.
    assert (Heq_fst: reptype t1 = reptype (nested_field_type2 (i1 :: ids) t)).
      unfold nested_field_type2; rewrite H1; reflexivity.
    assert (Heq_snd: reptype_structlist f'' = nested_reptype_structlist ids t f'').
      rewrite fieldlist_app_Fcons in H3.
      apply (nested_reptype_structlist_lemma ids t i _ _ a _ H3 H2).
    assert (H_fst: eq_rect_r (fun x : Type => x) (fst v2) Heq_fst = fst v1).
      revert v1 v2 Heq H. rewrite Heq_fst, Heq_snd. intros. 
      unfold eq_rect_r in *. rewrite <- eq_rect_eq in *. rewrite H. reflexivity.
    assert (H_snd: eq_rect _ (fun x : Type => x) (snd v1) _ Heq_snd = snd v2).
      clear H_fst. revert v1 v2 Heq H. rewrite Heq_fst, Heq_snd. intros. 
      unfold eq_rect_r in *. rewrite <- eq_rect_eq in *. rewrite H. reflexivity.
    remember (fst v1) as fst_v1; clear Heqfst_v1.
    remember (snd v1) as snd_v1; clear Heqsnd_v1.
    remember (fst v2) as fst_v2; clear Heqfst_v2.
    remember (snd v2) as snd_v2; clear Heqsnd_v2.
    clear H Heq v1 v2.
    revert fst_v2 snd_v2 Heq_fst Heq_snd H_fst H_snd.
    simpl reptype_structlist. simpl nested_reptype_structlist.
    unfold nested_data_at.
    unfold nested_field_offset2, nested_field_type2.
    rewrite H1. intros.
    unfold eq_rect_r in H_fst. rewrite <- eq_rect_eq in H_fst. rewrite H_fst.
    subst f''.
    assert (nested_field_rec (i0 :: ids) t = Some (align (ofs0 + sizeof t1) (alignof_hd (Fcons i0 t0 f)), t0)); [simpl alignof_hd; apply (nested_field_rec_mid i1 t1 i0 t0 ids t i f' f a ofs ofs0 H0 H2 H3 H1)|].
    rewrite fieldlist_app_Fcons in *.
    rewrite (IHf _ _ _ _ _ _ Heq_snd H_snd H2 H3 H).
    reflexivity.
Qed.

Lemma data_at_nested_data_at: forall sh t, data_at sh t = nested_data_at sh nil t.
Proof. intros. reflexivity. Qed.

Lemma nested_data_at_data_at: forall sh ids t v, no_nested_alignas_type t = true -> nested_data_at sh ids t v = at_offset' (data_at sh (nested_field_type2 ids t) v) (nested_field_offset2 ids t).
Proof.
  intros.
  unfold nested_data_at.
  rewrite data_at'_data_at.
  reflexivity.
  apply (nested_field_type2_nest_pred eq_refl).
  exact H.
  apply nested_field_offset2_type2_divide.
  exact H.
Qed.

Lemma nested_data_at_nested_data_at_: forall sh ids t v, no_nested_alignas_type t = true -> nested_data_at sh ids t v |-- nested_data_at_ sh ids t.
Proof.
  intros.
  unfold nested_data_at_.
  repeat (rewrite nested_data_at_data_at; [|exact H]).
  go_lower.
  repeat (rewrite at_offset'_eq; [| rewrite <- data_at_offset_zero; reflexivity]).
  eapply derives_trans.
  apply data_at_data_at_.
  unfold data_at_.
  apply derives_refl.
Qed.

Hint Resolve nested_data_at_nested_data_at_.

(*
Lemma field_at_offset_zero:
  forall sh ty id v v', 
   field_at sh ty id v' (offset_val (Int.repr 0) v) =
   field_at sh ty id v' v.
Proof.
 intros.
 destruct v; try solve [simpl; auto].
 simpl offset_val. rewrite int_add_repr_0_r. reflexivity.
Qed.
Hint Rewrite field_at_offset_zero: norm.
*)

(********************************************

The following part is for unfold_field_at tactic.

********************************************)

Lemma lower_sepcon_val:
  forall (P Q: val->environ->mpred) v, 
  ((P*Q) v) = (P v * Q v).
Proof. reflexivity. Qed.

Definition opaque_sepcon := @sepcon (val->mpred) _ _.
Global Opaque opaque_sepcon.
Definition opaque_emp := @emp (val->mpred) _ _.
Global Opaque opaque_emp.

Lemma distribute_envtrans:
  forall A (P Q: A -> mpred) (J: environ -> A),
   @liftx (Tarrow A (LiftEnviron mpred)) 
   (@sepcon (A -> mpred) _ _ P Q) J = 
   (@liftx (Tarrow A (LiftEnviron mpred)) P J 
    * @liftx (Tarrow A (LiftEnviron mpred)) Q J ).
Proof. reflexivity. Qed.
Hint Rewrite distribute_envtrans: norm.

Lemma distribute_envtrans0:
  forall (P Q: mpred),
   @liftx (LiftEnviron mpred)
   (@sepcon mpred _ _ P Q) = 
   @liftx (LiftEnviron mpred) P *
   @liftx (LiftEnviron mpred) Q.
Proof. intros. reflexivity. Qed.
Hint Rewrite distribute_envtrans0: norm.

Lemma distribute_lifted_sepcon:
 forall A F G v,
  (@sepcon (A -> mpred) _ _ F G v) = @sepcon mpred _ _ (F v) (G v).
Proof. reflexivity. Qed.

Lemma lift_at_offset_mapsto: forall pos sh t v p, `(at_offset pos (fun p0 : val => mapsto sh t p0 v)) p = `(mapsto sh t) (`(offset_val (Int.repr pos)) p) `v.
Proof. intros. reflexivity. Qed.

Lemma at_offset_mapsto: forall pos sh t v p, (at_offset pos (fun p0 : val => mapsto sh t p0 v)) p = (mapsto sh t) (offset_val (Int.repr pos) p) v.
Proof. intros. reflexivity. Qed.

Lemma lift_mapsto: forall sh t v p, `(fun p0 : val => mapsto sh t p0 v) p = `(mapsto sh t) p `v.
Proof. intros. reflexivity. Qed.

Lemma lift_at_offset_memory_block: forall pos sh len p, `(at_offset pos (memory_block sh len)) p = `(memory_block sh len) (`(offset_val (Int.repr pos)) p).
Proof. intros. reflexivity. Qed.

Lemma at_offset_memory_block: forall pos sh len p, (at_offset pos (memory_block sh len)) p = (memory_block sh len) (offset_val (Int.repr pos) p).
Proof. intros. reflexivity. Qed.

Lemma lift_at_offset_data_at: forall pos sh t v p, `(at_offset pos (data_at sh t v)) p = `(data_at sh t v) (`(offset_val (Int.repr pos)) p).
Proof. intros. reflexivity. Qed.

Lemma at_offset_data_at: forall pos sh t v p, (at_offset pos (data_at sh t v)) p = (data_at sh t v) (offset_val (Int.repr pos) p).
Proof. intros. reflexivity. Qed.

Ltac unfold_field_at' H := 
   erewrite nested_data_at_Tstruct in H; 
    [|instantiate (2:= eq_refl); instantiate (2:= eq_refl); rewrite <- eq_rect_eq; reflexivity
    | reflexivity];
   unfold nested_sfieldlist_at, withspacer in H.

Ltac floyd_simpl T H MA TAC :=
   try unfold T in H;  (* need "try" in case T is not just a simple identifier *)
   TAC H;
   change sepcon with opaque_sepcon in H; 
   change (@emp (val->mpred) _ _) with opaque_emp in H; 
   simpl in H;
   (* can't use "@sepcon (val->mpred) _ _" with implicit arguments in next two lines,
     otherwise trigger Coq bug 2997 if there are evars in context *)
   change @opaque_sepcon with (@sepcon (val -> mpred) (@LiftNatDed val mpred Nveric)
  (@LiftSepLog val mpred Nveric Sveric)) in H;
   change @opaque_emp with (@emp (val->mpred) (@LiftNatDed val mpred Nveric)
  (@LiftSepLog val mpred Nveric Sveric)) in H;
(*
   repeat
    match type of H with
    | appcontext [(nested_data_at ?sh ?ids ?t Vundef)] =>
     change (nested_data_at sh ids t Vundef) with (?????) in H
    end;
    fold tuint in H; fold tint in H;
*)
   try fold T in H,MA; (* need "try" in case T is not just a simple identifier *)
   repeat rewrite positive_nat_Z in H;
   repeat rewrite sepcon_emp in H || rewrite emp_sepcon in H;
   repeat rewrite distribute_lifted_sepcon in H;
   repeat rewrite distribute_envtrans in H;
   repeat rewrite distribute_envtrans0 in H;
   repeat rewrite lift_at_offset_mapsto in H;
   repeat rewrite lift_mapsto in H;
   repeat rewrite lift_at_offset_memory_block in H;
   repeat rewrite at_offset_mapsto in H;
   repeat rewrite at_offset_memory_block in H;
   subst MA;
   repeat rewrite distribute_lifted_sepcon;
   repeat rewrite distribute_envtrans;
   repeat rewrite distribute_envtrans0;
   repeat flatten_sepcon_in_SEP;
   simpl @fst; simpl @snd; simpl align; simpl Z.max.

Definition opaque_nested_data_at := nested_data_at.
Global Opaque opaque_nested_data_at.

Definition opaque_data_at := data_at.
Global Opaque opaque_data_at.

Lemma opaque_nda1: nested_data_at = opaque_nested_data_at.
Proof. reflexivity. Qed.

Lemma opaque_nda2: data_at = opaque_data_at.
Proof. intros. reflexivity. Qed.

Ltac unfold_field_at N :=
  match N with
  | S O =>
    let H := fresh "H" in let MA := fresh "MA" in
    pattern nested_data_at at 1;
    rewrite opaque_nda1;
    match goal with 
    | |- appcontext [`(opaque_nested_data_at ?SH ?IDS ?T ?v) ?p] =>
           remember (`(opaque_nested_data_at SH IDS T v) p) as MA eqn:H in |-*; 
           rewrite <- opaque_nda1 in H;
           try floyd_simpl T H MA unfold_field_at';
           try subst MA
    | |- appcontext [(opaque_nested_data_at ?SH ?IDS ?T ?v) ?p] =>
           remember ((opaque_nested_data_at SH IDS T v) p) as MA eqn:H in |-*; 
           rewrite <- opaque_nda1 in H;
           try floyd_simpl T H MA unfold_field_at';
           try subst MA
    end
  | S ?n' => 
    let H := fresh "H" in let MA := fresh "MA" in
    pattern nested_data_at at 1;
    rewrite opaque_nda1;
    remember opaque_nested_data_at as MA eqn:H in |- * ;
    unfold_field_at n';
    rewrite <- opaque_nda1 in H;
    subst MA
  end.

Ltac unfold_data_at N :=
  match N with
  | S O =>
    let H := fresh "H" in let MA := fresh "MA" in
    pattern data_at at 1;
    rewrite opaque_nda2;
    match goal with 
    | |- appcontext [`(opaque_data_at ?SH ?T ?v) ?p] =>
           remember (`(opaque_data_at SH T v) p) as MA eqn:H in |-*; 
           rewrite <- opaque_nda2 in H;
           rewrite data_at_nested_data_at in H;
           try floyd_simpl T H MA unfold_field_at';
           try subst MA
    | |- appcontext [(opaque_data_at ?SH ?T ?v) ?p] =>
           remember ((opaque_data_at SH T v) p) as MA eqn:H in |-*; 
           rewrite <- opaque_nda2 in H;
           rewrite data_at_nested_data_at in H;
           try floyd_simpl T H MA unfold_field_at';
           try subst MA
    end
  | S ?n' => 
    let H := fresh "H" in let MA := fresh "MA" in
    pattern data_at at 1;
    rewrite opaque_nda2;
    remember opaque_data_at as MA eqn:H in |- * ;
    unfold_data_at n';
    rewrite <- opaque_nda2 in H;
    subst MA
  end.

(********************************************

The following part is for simpl_data_at tactic

********************************************)

Ltac simpl_data_at' H := 
  unfold data_at_, data_at, data_at', withspacer, at_offset', at_offset2, align, Z.max in H.

Ltac simpl_data_at :=
  repeat (
    let H := fresh "H" in let MA := fresh "MA" in
    try unfold data_at_;
    match goal with 
    | |- appcontext [`(nested_data_at ?SH ?IDS ?T ?v) ?p] =>
           remember (`(nested_data_at SH IDS T v) p) as MA eqn:H in |-*; 
           rewrite nested_data_at_data_at in H;
           floyd_simpl T H MA simpl_data_at'
    | |- appcontext [(nested_data_at ?SH ?IDS ?T ?v) ?p] =>
           remember ((nested_data_at SH IDS T v) p) as MA eqn:H in |-*; 
           rewrite nested_data_at_data_at in H;
           floyd_simpl T H MA simpl_data_at'
    | |- appcontext [nested_data_at ?SH ?IDS ?T] =>
           remember (nested_data_at SH IDS T) as MA eqn:H in |-*; 
           rewrite nested_data_at_data_at in H;
           floyd_simpl T H MA simpl_data_at'
    | |- appcontext [`(data_at ?SH ?T ?v) ?p] =>
           remember (`(data_at SH T v) p) as MA eqn:H in |-*; 
           floyd_simpl T H MA simpl_data_at'
    | |- appcontext [(data_at ?SH ?T ?v) ?p] =>
           remember ((data_at SH T v) p) as MA eqn:H in |-*; 
           floyd_simpl T H MA simpl_data_at'
    | |- appcontext [data_at ?SH ?T] =>
           remember (data_at SH T) as MA eqn:H in |-*; 
           floyd_simpl T H MA simpl_data_at'
    end).

(**********************************************

Here, we need to think about how to use array in examples.

**********************************************)

(*
Definition array_at (t: type) (sh: Share.t) (f: Z -> reptype t) (lo hi: Z)
                                   (v: val) : mpred :=
           !! isptr v && rangespec lo hi (fun i => data_at sh t  (f i) (add_ptr_int t v i)).

Definition array_at_ t sh lo hi := array_at t sh (fun _ => default_val t) lo hi.
*)

Lemma data_at_tint: forall sh v2 v1,
  data_at sh tint v2 v1 = mapsto sh tint v1 v2.
Proof.
  intros. reflexivity. 
Qed.

Fixpoint typecount (t: type) : nat :=
  match t with
  | Tstruct _ f _ => S (typecount_fields f)
  | Tarray t' _ _ => S (typecount t')
  | _ => 1%nat
  end
with typecount_fields (f: fieldlist) : nat :=
  match f with
  | Fnil => 1%nat
  | Fcons _ t f' => (typecount t + typecount_fields f')%nat
  end.

Lemma  typecount_fields_pos: forall f, (typecount_fields f > 0)%nat.
Proof.
  induction f; simpl; intros. auto.
  omega.
Qed.

Lemma typecount_pos: forall t, (typecount t > 0)%nat.
Proof.
  destruct t; simpl; auto; omega.
Qed.

(*
(****** It is not used anywhere else. *********)

Definition fields_mapto_ sh pos t f v :=
  structfieldsof sh t f pos pos (struct_default_val f) v.

Lemma fields_mapto__offset_zero:
  forall sh pos t f v, fields_mapto_ sh pos t f (offset_val (Int.repr 0) v) =
                           fields_mapto_ sh pos t f v.
Proof.
  Admitted.
Qed.
*)

Lemma spacer_memory_block:
  forall sh pos a v, isptr v -> 
 spacer sh pos a v = memory_block sh (Int.repr (align pos a - pos)) (offset_val (Int.repr pos) v).
Proof.
  intros.
  destruct v; inv H.
  unfold spacer.
  destruct (Z.eq_dec (align pos a - pos) 0);
  try solve [rewrite e; simpl offset_val; rewrite memory_block_zero; auto].
  unfold at_offset'.
  destruct pos; auto.
  unfold offset_val; rewrite Int.add_zero; auto.
Qed.

Definition no_attr (a: attr) :=
  andb (negb (attr_volatile a))
  match attr_alignas a with  None => true | _ => false end.

Definition no_attr_e: forall a, no_attr a = true -> a=noattr.
Proof.
  intros. destruct a. destruct attr_volatile; inv H.
  destruct attr_alignas; inv H1.
  reflexivity.
Qed.

Fixpoint no_attr_type (t: type) : bool :=
  match t with 
  | Tint _ _ a => no_attr a
  | Tlong _ a => no_attr a
  | Tfloat _ a => no_attr a
  | Tpointer _ a => no_attr a
  | Tarray t _ a => andb (no_attr_type t) (no_attr a)
  | Tstruct _ flds a => andb (no_attr_fields flds)  (no_attr a)
  | Tunion _ flds a => andb (no_attr_fields flds)  (no_attr a)
  | Tcomp_ptr _ a =>  no_attr a
  | _ => true
  end
with no_attr_fields (f: fieldlist) : bool :=
  match f with 
  | Fnil => true 
  | Fcons _ t f' => andb (no_attr_type t) (no_attr_fields f')
  end.

Lemma no_attr_type_nonvol: forall t, no_attr_type t = true -> type_is_volatile t = false.
Proof.
  intros. destruct t; simpl in *; try apply no_attr_e in H; subst; simpl; try reflexivity.
  destruct i,s; reflexivity. destruct f; reflexivity.
Qed.

Lemma align_1: forall n, align n 1 = n.
Proof.  intros; unfold align. rewrite Z.div_1_r. rewrite Z.mul_1_r. omega.
Qed.

Lemma memory_block_typed': forall sh e pos ty b ofs, 
  no_attr_type ty = true ->
  spacer sh pos (alignof ty) (Vptr b ofs) *
  memory_block sh (Int.repr (sizeof ty)) (offset_val (Int.repr (align pos (alignof ty))) (Vptr b ofs) )
  = data_at' sh e ty pos (default_val ty) (Vptr b ofs).
(*with memory_block_fields: forall sh pos t fld b ofs,
 no_attr_fields fld = true ->
  spacer sh (sizeof_struct fld pos) (alignof_fields fld) (Vptr b ofs) 
  * memory_block sh (Int.repr (sizeof_struct fld pos)) (Vptr b ofs)
  =   memory_block sh (Int.repr pos) (Vptr b ofs) * fields_mapto_ sh pos t fld (Vptr b ofs).
*)
Proof.
  Admitted.

Lemma memory_block_typed: 
 forall sh ty, 
  no_attr_type ty = true ->
   memory_block sh (Int.repr (sizeof ty)) = data_at_ sh ty.
Proof.
intros.
extensionality v.
rewrite memory_block_isptr.
rewrite data_at__isptr.
destruct v; simpl; normalize.
unfold data_at_, data_at; rewrite <- memory_block_typed'; auto.
unfold spacer.
rewrite align_0 by (apply alignof_pos).
simpl. rewrite emp_sepcon.
rewrite Int.add_zero. auto.
Qed.

Lemma var_block_data_at_:
  forall  sh id t, 
  no_attr_type t = true ->
 var_block sh (id, t) = 
   !!(sizeof t <= Int.max_unsigned) &&
            `(data_at_ sh t) (eval_var id t).
Proof.
intros; extensionality rho.
unfold_lift.
rewrite <- memory_block_typed by auto.
unfold var_block.
simpl. unfold_lift.
rewrite memory_block_isptr.
destruct (eval_var id t rho); simpl; normalize.
Qed.

(*****************************************************

Lemma array_at_local_facts:
 forall t sh f lo hi v,
    array_at t sh f lo hi v |-- !! isptr v.
Proof.
 intros.
 unfold array_at; normalize.
Qed.

Hint Resolve array_at_local_facts : saturate_local.

Lemma array_at__local_facts:
 forall t sh lo hi v,
    array_at_ t sh lo hi v |-- !! isptr v.
Proof.
 intros.
 apply array_at_local_facts; auto.
Qed.

Hint Resolve array_at__local_facts : saturate_local.

*****************************************************)

(************************************************

reptype is not defined in a quite beautiful way because of the if operation 
inside it. However, due to the following limitations, the current definition
is the best available choice.

1. We want a compact representation of reptype result and a compact form of
expansion of data_at, i.e. no unit in reptype result of non-empty struct and
no emp clause existing in the expansion of data_at. So, vst does not use the
following simplest approach.

  match fld with
  | Fnil => unit
  | Fcons id ty fld' => prod (reptype ty) (reptype_structlist fld')
  end

2. If using struct recursive definition in reptype like this, in which reptype
recursively is called on 1st level match variable fld' but not any 2nd level 
stuff.

  match fld with
  | Fnil => unit
  | Fcons id ty fld' => 
    match fld' as fld0 return Type with
    | Fnil => reptype ty
    | Fcons id0 ty0 fld0' => prod (reptype ty) (reptype_structlist fld')
    end
  end

or like this

  match fld with
  | Fnil => unit
  | Fcons id ty Fnil => reptype ty
  | Fcons id ty fld' => prod (reptype ty) (reptype_structlist fld')
  end

Then, we would be forced to do type casting when defining data_at. In detail,
match command will destruct a fieldlist into "Fnil", "Fcons _ Fnil _" and
"Fcons _ (Fcons i t f) _", then an equivalence between (Fcons i t f) and fld'
is needed.

3. If reptype is recursively called on (Fcons i t f), we have to use well-found
recursive but not structure recursive. However, Coq does not allow users to use 
well-found recursive on manual recursive functions.

4. If reptype is defined in a well-type recursive style (thus, it has to be non-
manually recursive) (this definition code is long; thus I put it afterwards), 
a match command does not do enough type calculation. As a result, explicit type
casting is needed again, i.e. the following piece of code does not compile. 

  Function test (t: type) (v: reptype t) {measure hry t}: nat :=
    match t as t0 return reptype t0 -> nat with
    | Tvoid => fun (v: unit) => 0%nat
    | Tarray t1 sz a => fun (v: list (reptype t1)) => 2%nat
    | _ => fun _ => 1%nat
    end v.

Though, computation by "Eval compute in" or "simpl" works quite well.

5. Another choice is start induction from the 2nd element but not the 1st
element. However, neither one of the following definition works. The former 
choice requires explicit type casting when defining data_at. The latter choice
does not compile itself.

  Fixpoint reptype (ty: type) : Type :=
    match ty with
    | ...
    | Tstruct id Fnil a => unit
    | Tstruct id (Fcons i t fld) a => reptype_structlist_cons (reptype t) fld
    end
  with reptype_structlist_cons (T: Type) (fld: fieldlist): Type :=
    match fld with
    | Fnil => T
    | Fcons i t fld' => prod T (reptype_structlist_cons (reptype t) fld')
    end.

  Fixpoint reptype (ty: type) : Type :=
    match ty with
    | ...
    | Tstruct id Fnil a => unit
    | Tstruct id (Fcons i t fld) a => reptype_structlist_cons t fld
    end
  with reptype_structlist_cons (t: type) (fld: fieldlist): Type :=
    match fld with
    | Fnil => T
    | Fcons i ty fld' => prod (reptype t) (reptype_structlist_cons ty fld')
    end.


(* (**** Code of Choice 4 ****)
Open Scope nat.

Fixpoint hry (t: type) : nat :=
  match t with
  | Tvoid => 0
  | Tint _ _ _ => 0
  | Tlong _ _ => 0
  | Tfloat _ _ => 0
  | Tpointer t1 a => 0
  | Tarray t1 sz a => (hry t1) + 1
  | Tfunction t1 t2 => 0
  | Tstruct id fld a => (hry_fields fld) + 1
  | Tunion id fld a => (hry_fields fld) + 1
  | Tcomp_ptr id a => 0
  end
with hry_fields (fld: fieldlist): nat :=
  match fld with
  | Fnil => 0
  | Fcons i t fld' => (hry t) + (hry_fields fld') + 1
  end.

Close Scope nat.

Function reptype (ty: type) {measure hry ty}: Type :=
  match ty with
  | Tvoid => unit
  | Tint _ _ _ => val
  | Tlong _ _ => val
  | Tfloat _ _ => val
  | Tpointer t1 a => val
  | Tarray t1 sz a => list (reptype t1)
  | Tfunction t1 t2 => unit
  | Tstruct id Fnil a => unit
  | Tstruct id (Fcons i t Fnil) a => reptype t
  | Tstruct id (Fcons i t fld) a => prod (reptype t) (reptype (Tstruct id fld a))
  | Tunion id fld a => unit
  | Tcomp_ptr id a => val
  end
.
Proof.
  + intros. 
    simpl.
    omega.
  + intros.
    simpl.
    omega.
  + intros.
    simpl.
    omega.
  + intros. 
    simpl.
    omega.
Defined.

Eval compute in (reptype (Tstruct 2%positive (Fcons 1%positive Tvoid (Fcons 1%positive Tvoid Fnil)) noattr)).

Lemma foo: (reptype (Tstruct 2%positive (Fcons 1%positive Tvoid (Fcons 1%positive Tvoid Fnil)) noattr)) = (unit * unit)%type.
Proof.
  reflexivity.
Qed.
*)


************************************************)

