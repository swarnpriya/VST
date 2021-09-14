Require Import VST.floyd.base2.
Require Import VST.floyd.client_lemmas.
Import compcert.lib.Maps.

Arguments align !n !amount / .
Arguments Z.max !n !m / .

Definition plain_member (m: member) : Prop :=
 match m with Member_plain _ _ => True | _ => False end.

Definition plain_members : members->Prop := Forall plain_member.

Definition field_type i m :=
  match Ctypes.field_type i m with
  | Errors.OK t => t
  | _ => Tvoid
  end.

Definition field_offset env i m :=
  match Ctypes.field_offset env i m with
  | Errors.OK (ofs, Full) => ofs
  | _ => 0
  end.

Fixpoint field_offset_next_rec (env:composite_env) i m ofs sz :=
  match m with
  | nil => 0
  | m1 :: m0 =>
    match m0 with
    | nil => sz
    | m2 :: _ =>
      if ident_eq i (name_member m1)
      then align (ofs + @Ctypes.sizeof env (type_member m1)) (@Ctypes.alignof env (type_member m2))
      else field_offset_next_rec env i m0 (align (ofs + @Ctypes.sizeof env (type_member m1)) (@Ctypes.alignof env (type_member m2))) sz
    end
  end.

Definition field_offset_next (env:composite_env) i m sz := field_offset_next_rec env i m 0 sz.

Definition in_members i (m: members): Prop :=
  In i (map name_member m).

Definition members_no_replicate (m: members) : bool :=
  compute_list_norepet (map name_member m).

Definition compute_in_members id (m: members): bool :=
  id_in_list id (map name_member m).

Lemma compute_in_members_true_iff: forall i m, compute_in_members i m = true <-> in_members i m.
Proof.
  intros.
  unfold compute_in_members.
  destruct (id_in_list i (map name_member m)) eqn:HH;
  [apply id_in_list_true in HH | apply id_in_list_false in HH].
  + unfold in_members.
    tauto.
  + unfold in_members; split; [congruence | tauto].
Qed.

Lemma compute_in_members_false_iff: forall i m,
  compute_in_members i m = false <-> ~ in_members i m.
Proof.
  intros.
  pose proof compute_in_members_true_iff i m.
  rewrite <- H; clear H.
  destruct (compute_in_members i m); split; congruence.
Qed.

Ltac destruct_in_members i m :=
  let H := fresh "H" in
  destruct (compute_in_members i m) eqn:H;
    [apply compute_in_members_true_iff in H |
     apply compute_in_members_false_iff in H].

Lemma in_members_dec: forall i m, {in_members i m} + {~ in_members i m}.
Proof.
  intros.
  destruct_in_members i m; [left | right]; auto.
Qed.

Lemma in_members_field_type: forall i m,
  plain_members m ->
  in_members i m ->
  In (Member_plain i (field_type i m)) m.
Proof.
  unfold members_no_replicate, field_type.
  intros.
  induction m as [| [|]]; [ | inv H; specialize (IHm H4) .. ].
  - contradiction H0.
  -  simpl in *. destruct H0.
     + subst. left. rewrite if_true by auto. auto. 
     + if_tac. subst; auto. right. apply IHm; auto.
  - contradiction.
Qed.

Lemma field_offset_field_type_match: forall cenv i m,
  plain_members m ->
  match Ctypes.field_offset cenv i m, Ctypes.field_type i m with
  | Errors.OK (_, Full), Errors.OK _ => True
  | Errors.Error _, Errors.Error _ => True
  | _, _ => False
  end.
Proof.
  intros.
  unfold Ctypes.field_offset.
  remember 0 as pos; clear Heqpos.
  revert pos; induction m; intros.
  + simpl. auto.
  + inv H. specialize (IHm H3).
      simpl. if_tac. subst i.
      destruct a; simpl. auto.
      inv H2.
      apply IHm.
Qed.

Lemma field_type_in_members: forall i m,
  match Ctypes.field_type i m with
  | Errors.Error _ => ~ in_members i m
  | _ => in_members i m
  end.
Proof.
  intros.
  unfold in_members.
  induction m.
  + simpl; tauto.
  + simpl.
     if_tac.
    - left; subst; auto.
    - destruct (Ctypes.field_type i m).
      * right; auto.
      * intro HH; destruct HH; [congruence | tauto].
Qed.

Section COMPOSITE_ENV.
Context {cs: compspecs}.

Ltac solve_field_offset_type i m PLAIN :=
  let H := fresh "H" in
  let Hty := fresh "H" in
  let Hofs := fresh "H" in
  let t := fresh "t" in
  let ofs := fresh "ofs" in
  assert (H := field_offset_field_type_match cenv_cs i m PLAIN);
  destruct (Ctypes.field_offset cenv_cs i m) as [[ofs [|]]|?] eqn:Hofs, (Ctypes.field_type i m) as [t|?] eqn:Hty;
   [clear H | inversion H | inversion H | inversion H | inversion H | clear H ].

Lemma complete_legal_cosu_member: forall (cenv : composite_env) (id : ident) (t : type) (m : members),
  In (Member_plain id t) m -> @composite_complete_legal_cosu_type cenv m = true -> @complete_legal_cosu_type cenv t = true.
Proof.
  intros.
  induction m.
  + inv H.
  + destruct H. subst.
    - 
      simpl in H0.
      rewrite andb_true_iff in H0; tauto.
    - apply IHm; auto.
      simpl in H0.
      rewrite andb_true_iff in H0; tauto.
Qed.         

Lemma complete_legal_cosu_type_field_type: forall id i
  (PLAIN: plain_members (co_members (get_co id))),
  in_members i (co_members (get_co id)) ->
  complete_legal_cosu_type (field_type i (co_members (get_co id))) = true.
Proof.
  unfold get_co.
  intros.
  destruct (cenv_cs ! id) as [co |] eqn:CO.
  + apply in_members_field_type in H; auto.
    pose proof cenv_legal_su _ _ CO.
    eapply complete_legal_cosu_member; eauto.
  + inversion H.
Qed.

Lemma align_compatible_rec_Tstruct_inv': forall id
  (PLAIN: plain_members (co_members (get_co id)))
  a ofs,
  align_compatible_rec cenv_cs (Tstruct id a) ofs ->
  forall i,
  in_members i (co_members (get_co id)) ->
  align_compatible_rec cenv_cs (field_type i (co_members (get_co id)))
    (ofs + field_offset cenv_cs i (co_members (get_co id))).
Proof.
  unfold get_co.
  intros.
  destruct (cenv_cs ! id) as [co |] eqn:CO.
  + eapply align_compatible_rec_Tstruct_inv with (i0 := i); try eassumption.
    - unfold field_type.
      induction (co_members co).
      * inv H0.
      * simpl; if_tac; auto.
        apply IHm. inv PLAIN; auto.
        destruct H0; [simpl in H0; congruence | auto].
    - unfold field_offset, Ctypes.field_offset.
      generalize 0 at 1 2.
      induction (co_members co); intros.
      * inv H0.
      * unfold field_offset_rec; fold field_offset_rec.
        inv PLAIN. destruct a0; try contradiction. simpl.
        if_tac; auto.
        apply IHm; auto.
        destruct H0; [simpl in H0; congruence | auto].
  + inv H0.
Qed.

Lemma align_compatible_rec_Tunion_inv': forall id a ofs,
  align_compatible_rec cenv_cs (Tunion id a) ofs ->
  forall i,
  in_members i (co_members (get_co id)) ->
  align_compatible_rec cenv_cs (field_type i (co_members (get_co id))) ofs.
Proof.
  unfold get_co.
  intros.
  destruct (cenv_cs ! id) as [co |] eqn:CO.
  + eapply align_compatible_rec_Tunion_inv with (i0 := i); try eassumption.
    unfold field_type.
    induction (co_members co).
    - inv H0.
    - simpl; if_tac; auto.
      apply IHm.
      destruct H0; [simpl in H0; congruence | auto].
  + inv H0.
Qed.

Lemma field_offset_aligned: forall i m,
  (alignof (field_type i m) | field_offset cenv_cs i m).
Proof.
  intros.
 unfold field_offset. unfold field_type.
  destruct (Ctypes.field_offset cenv_cs i m) as [[? [|]]|] eqn:?H.
  destruct (Ctypes.field_type i m) eqn:?H.
 apply (field_offset_aligned cenv_cs i m _ _ H H0).
 apply Z.divide_1_l.
 apply Z.divide_0_r.
 apply Z.divide_0_r.
Qed.

Lemma alignof_composite_hd_divide: forall m1 m
  (PLAIN: plain_members (m1::m)),
  (alignof (type_member m1) | alignof_composite cenv_cs (m1 :: m)).
Proof.
  intros.
  inv PLAIN.
  destruct (alignof_composite_two_p cenv_cs (m1 :: m)) as [M H0].
  destruct m1; inv H1.
  simpl.
  destruct (alignof_two_p t) as [N H].
  assert (alignof t <= alignof_composite cenv_cs (Member_plain id t :: m)) by apply Z.le_max_l.
  fold (alignof t) in H.
  rewrite H in *.
  simpl in *.
  rewrite H0 in *.
  exact (power_nat_divide N M H1).
Qed.

Lemma alignof_composite_tl_divide: forall m1 m
  (PLAIN: plain_members (m1::m)),
   (alignof_composite cenv_cs m | alignof_composite cenv_cs (m1 :: m)).
Proof.
  intros.
  destruct (alignof_composite_two_p cenv_cs m) as [N ?].
  destruct (alignof_composite_two_p cenv_cs (m1 :: m)) as [M ?].
  inv PLAIN. destruct m1; inv H3.
  assert (alignof_composite cenv_cs m <= alignof_composite cenv_cs (Member_plain id t :: m)) by (apply Z.le_max_r).
  rewrite H in *.
  rewrite H0 in *.
  exact (power_nat_divide N M H1).
Qed.

Lemma alignof_field_type_divide_alignof: forall i m
  (PLAIN: plain_members m),
  in_members i m ->
  (alignof (field_type i m) | alignof_composite cenv_cs m).
Proof.
  intros.
  unfold field_type.
  induction m. 
  + inversion H.
  + unfold in_members in H; simpl in H.
    simpl Ctypes.field_type.
    if_tac.
    - apply alignof_composite_hd_divide; auto.
    - eapply Z.divide_trans.
      * inv PLAIN. apply IHm; auto.
        destruct H; [congruence | auto].
      * apply alignof_composite_tl_divide; auto.
Qed.

(* if sizeof Tvoid = 0, this lemma can be nicer. *)
Lemma field_offset_in_range: forall i m
  (PLAIN: plain_members m),
  in_members i m ->
  0 <= field_offset cenv_cs i m /\ field_offset cenv_cs i m + sizeof (field_type i m) <= sizeof_struct cenv_cs m.
Proof.
  intros.
  unfold field_offset, field_type.
  solve_field_offset_type i m PLAIN.
  + eapply field_offset_in_range; eauto.
  + pose proof field_type_in_members i m.
    rewrite H1 in H0.
    tauto.
Qed.

(* if sizeof Tvoid = 0, this lemma can be nicer. *)
Lemma sizeof_union_in_members: forall i m,
  in_members i m ->
  sizeof (field_type i m) <= sizeof_union cenv_cs m.
(* field_offset2_in_range union's version *)
Proof.
  intros.
  unfold in_members in H.
  unfold field_type.
  induction m.
  + inversion H.
  + simpl.
    destruct (ident_eq i (name_member a)).
    - apply Z.le_max_l.
    - simpl in H; destruct H; [congruence |].
     specialize (IHm H).
     fold (sizeof (type_member a)).
     pose proof Z.le_max_r (sizeof (type_member a)) (sizeof_union cenv_cs m).
     lia.
Qed.

(* if sizeof Tvoid = 0, this lemma can be nicer. *)
Lemma field_offset_no_overlap:
  forall i1 i2 m
  (PLAIN: plain_members m),
  i1 <> i2 ->
  in_members i1 m ->
  in_members i2 m ->
  field_offset cenv_cs i1 m + sizeof (field_type i1 m) <= field_offset cenv_cs i2 m \/
  field_offset cenv_cs i2 m + sizeof (field_type i2 m) <= field_offset cenv_cs i1 m.
Proof.
  intros.
  unfold field_offset, field_type.
  pose proof field_type_in_members i1 m.
  pose proof field_type_in_members i2 m.
  solve_field_offset_type i1 m PLAIN;
  solve_field_offset_type i2 m PLAIN; try tauto.
 pose proof (field_offset_no_overlap _ _ _ _ _ _ _ _ _ _ H6 H5 H8 H7 H).
  unfold layout_start, layout_width, bitsizeof in H4. unfold sizeof. lia.
Qed.

Lemma not_in_members_field_type: forall i m,
  ~ in_members i m ->
  field_type i m = Tvoid.
Proof.
  unfold in_members, field_type.
  intros.
  induction m.
  + reflexivity.
  + simpl in H.
    simpl.
    destruct (ident_eq i (name_member a)) as [HH | HH]; pose proof (@eq_sym ident i (name_member a)); tauto.
Qed.

Lemma not_in_members_field_offset: forall i m,
  ~ in_members i m ->
  field_offset cenv_cs i m = 0.
Proof.
  unfold in_members, field_offset, Ctypes.field_offset.
  intros.
  generalize 0 at 1.
  induction m; intros.
  + reflexivity.
  + simpl in H.
    simpl.
    destruct (ident_eq i _) as [HH | HH]; pose proof (@eq_sym ident i (name_member a)); [tauto |].
    apply IHm. tauto.
Qed.

Lemma align_bitalign: (* copied from veric/align_mem.v *)
  forall z a, a > 0 ->
    align z a = align (z * 8) (a * 8) / 8.
Proof.
clear.
intros.  unfold align.
rewrite Z.mul_assoc.
rewrite Z.div_mul by congruence.
f_equal.
transitivity ((z + a - 1)*8 / (a*8)).
rewrite Z.div_mul_cancel_r by lia; auto.
rewrite! Z.add_sub_swap.
rewrite Z.mul_add_distr_r.
assert (H0: ((z - 1) * 8 + 1*(a * 8)) / (a * 8) = (z * 8 - 1 + 1*(a * 8)) / (a * 8))
 ; [ | rewrite Z.mul_1_l in H0; auto].
rewrite !Z.div_add by lia.
f_equal.
rewrite Z.mul_sub_distr_r.
rewrite Z.mul_1_l.
rewrite (Z.mul_comm a).
rewrite <- !Zdiv.Zdiv_Zdiv by lia.
f_equal.
transitivity (((z-1)*8)/8).
f_equal; lia.
rewrite Z.div_mul by lia.
rewrite <- !(Z.add_opp_r (_ * _)).
rewrite Z.div_add_l by lia.
reflexivity.
Qed.

Lemma field_offset_next_in_range: forall i m sz
  (PLAIN: plain_members m),
  in_members i m ->
  sizeof_struct cenv_cs m <= sz ->
  field_offset cenv_cs i m + sizeof (field_type i m) <=
  field_offset_next cenv_cs i m sz <= sz.
Proof.
  intros.
  destruct m as [| m1 m]; [inversion H |].
  unfold sizeof_struct in H0.
  unfold field_offset, Ctypes.field_offset, field_offset_next, field_type.
  pattern 0 at 4 5; replace 0 with (align (0*8) (alignof (type_member m1))) by (apply align_0, alignof_pos).
  match goal with
  | |- ?A => assert (A /\
                     match field_offset_rec cenv_cs i (m1 :: m) 0 with
                     | Errors.OK _ => True
                     | _ => False
                     end /\
                     match Ctypes.field_type i (m1 :: m) with
                     | Errors.OK _ => True
                     | _ => False
                     end); [| tauto]
  end.
  inv PLAIN. rename H4 into PLAIN. rename H3 into PLAIN1.
  rewrite <- (Z.mul_0_l 8) in H0.
 change (field_offset_rec cenv_cs i (m1::m) 0) with (field_offset_rec cenv_cs i (m1::m) (0*8)).
  revert m1 PLAIN1 H H0; generalize 0.
  induction m as [| m0 m]; intros.
  + destruct (ident_eq i (name_member m1)); [| destruct H; simpl in H; try congruence; tauto].
    subst; simpl.
    rewrite !if_true by auto.
    destruct m1; inv PLAIN1. simpl in *.
    split; [| split]; auto.
    unfold bitalignof, bitsizeof, bytes_of_bits in *.
    split; [ | lia].
    eapply Z.le_trans; try apply H0. clear H0.
    rewrite <- (Z.div_mul (sizeof t) 8) by computable.
    pose proof (sizeof_pos t).
    fold (sizeof t). forget (sizeof t) as s.
    pose proof (Ctypes.alignof_pos t).
    forget (Ctypes.alignof t) as a. 
     unfold align.
    replace (z*8 + a*8 - 1) with ((z*8-1)+1*(a*8)) by lia.
    rewrite Z.div_add by lia.
    replace (((z * 8 - 1) / (a * 8) + 1) * (a * 8)  + s*8 + 7) with (((z * 8 - 1) / (a * 8) + 1) * (a * 8)  + 7 + s*8) by lia.
    rewrite Z.div_add by lia.
    rewrite Z.div_mul by lia.
    apply Zplus_le_compat_r.
    apply Z.div_le_mono. computable. lia.
  + remember (m0::m) as m0'.  simpl in H0 |- *. subst m0'.
     destruct m1; inv PLAIN1. simpl in *.
     if_tac.
    - split; [| split]; auto.
      split.
      * apply align_le, alignof_pos.
      * pose proof sizeof_struct_incr cenv_cs m (align (align z (alignof t0) + sizeof t0)
            (alignof t1) + sizeof t1).
        pose proof sizeof_pos t1.
        unfold expr.sizeof, expr.alignof in *.
        simpl in H0; lia.
    - destruct H as [H | H]; [simpl in H; congruence |].
      specialize (IHm (align z (alignof t0) + sizeof t0) i1 t1 H H0).
        unfold expr.sizeof, expr.alignof in *.
      destruct (field_offset_rec cenv_cs i ((i1, t1) :: m) (align z (Ctypes.alignof t0) + Ctypes.sizeof t0)),
               (field_type i ((i1, t1) :: m));
      try tauto.
Qed.

Lemma Pos_eqb_eq: forall p q: positive, iff (eq (Pos.eqb p q) true) (eq p q).
Proof.
intros.
split.
revert q; induction p; destruct q; simpl; intros; auto; try discriminate.
apply f_equal. apply IHp; auto.
apply f_equal. apply IHp; auto.
intros; subst.
induction q; simpl; auto.
Defined.


(* copied from veric/Clight_lemmas.v; but here Defined instead of Qed  *)
Lemma id_in_list_true: forall i ids, id_in_list i ids = true -> In i ids.
Proof.
 induction ids; simpl; intros. inv H.
 destruct (i =? a)%positive eqn:?.
 apply Pos_eqb_eq in Heqb. left; auto.
 auto.
Defined.


Lemma id_in_list_false: forall i ids, id_in_list i ids = false -> ~In i ids.
Proof.
 intros.
 intro. induction ids. inv H0.
 simpl in *. destruct H0. subst i.
 assert (a =? a = true)%positive.
 apply Pos_eqb_eq. auto. rewrite H0 in H. simpl in H. inv H.
 destruct (i =? a)%positive. simpl in H. inv H.   auto.
Defined.

Lemma members_no_replicate_ind: forall m,
  (members_no_replicate m = true) <->
  match m with
  | nil => True
  | (i0, _) :: m0 => ~ in_members i0 m0 /\ members_no_replicate m0 = true
  end.
Proof.
  intros.
  unfold members_no_replicate.
  destruct m as [| [i t] m]; simpl.
  + assert (true = true) by auto; tauto.
  + destruct (id_in_list i (map fst m)) eqn:HH.
    - apply id_in_list_true in HH.
       split; intros. inv H.  destruct H. elimtype False; apply H.
      apply HH.
    - apply id_in_list_false in HH.
      split; intros. split; auto. destruct H; auto.
Defined.

Lemma map_members_ext: forall A (f f':ident * type -> A) (m: members),
  members_no_replicate m = true ->
  (forall i, in_members i m -> f (i, field_type i m) = f' (i, field_type i m)) ->
  map f m = map f' m.
Proof.
  intros.
  induction m as [| (i0, t0) m].
  + reflexivity.
  + simpl.
    rewrite members_no_replicate_ind in H.
    f_equal.
    - specialize (H0 i0).
      unfold field_type, in_members in H0.
      simpl in H0; if_tac in H0; [| congruence].
      apply H0; auto.
    - apply IHm; [tauto |].
      intros.
      specialize (H0 i).
      unfold field_type, in_members in H0.
      simpl in H0; if_tac in H0; [subst; tauto |].
      apply H0; auto.
Defined.

Lemma in_members_tail_no_replicate: forall i i0 t0 m,
  members_no_replicate ((i0, t0) :: m) = true ->
  in_members i m ->
  i <> i0.
Proof.
  intros.
 destruct (members_no_replicate_ind ((i0,t0)::m)) as [? _].
 apply H1 in H. clear H1.
  intro.
  subst. destruct H. auto.
Defined.

Lemma neq_field_offset_rec_cons: forall env i i0 t0 m z,
  i <> i0 ->
  field_offset_rec env i ((i0, t0) :: m) z =
  field_offset_rec env i m (align z (Ctypes.alignof t0) + Ctypes.sizeof t0).
Proof.
  intros.
  simpl.
  if_tac; [congruence |].
  auto.
Qed.

Lemma neq_field_offset_next_rec_cons: forall env i i0 t0 i1 t1 m z sz,
  i <> i0 ->
  field_offset_next_rec env i ((i0, t0) :: (i1, t1) :: m) z sz =
  field_offset_next_rec env i ((i1, t1) :: m) (align (z +  Ctypes.sizeof t0) (Ctypes.alignof t1)) sz.
Proof.
  intros.
  simpl.
  if_tac; [congruence |].
  auto.
Qed.

Lemma sizeof_struct_0: forall env i m,
  sizeof_struct env 0 m = 0 ->
  in_members i m ->
  Ctypes.sizeof (field_type i m) = 0 /\
  field_offset_next env i m 0 - (field_offset env i m + Ctypes.sizeof (field_type i m)) = 0.
Proof.
  intros.
  unfold field_type, field_offset, Ctypes.field_offset, field_offset_next.
  induction m as [| (i0, t0) m].
  + inversion H0.
  + simpl in H.
    pose proof sizeof_struct_incr env m (align 0 (Ctypes.alignof t0) + Ctypes.sizeof t0).
    pose proof align_le 0 (Ctypes.alignof t0) (Ctypes.alignof_pos _).
    pose proof Ctypes.sizeof_pos t0.
    destruct (ident_eq i i0).
    - simpl in *.
      if_tac; [| congruence].
      replace (Ctypes.sizeof t0) with 0 by lia.
      destruct m as [| (?, ?) m];
      rewrite !align_0 by apply Ctypes.alignof_pos;
      lia.
    - destruct H0; [simpl in H0; congruence |].
      simpl.
      if_tac; [congruence |].
      replace (Ctypes.sizeof t0) with 0 by lia.
      destruct m as [| (?, ?) m]; [inversion H0 |].
      rewrite !align_0 by apply Ctypes.alignof_pos.
      apply IHm; [| auto].
      replace (align 0 (Ctypes.alignof t0) + Ctypes.sizeof t0) with 0 in * by lia.
      auto.
Qed.

Lemma sizeof_union_0: forall env i m,
  sizeof_union env m = 0 ->
  in_members i m ->
  Ctypes.sizeof (field_type i m) = 0.
Proof.
  intros.
  unfold field_type.
  induction m as [| (i0, t0) m].
  + inversion H0.
  + simpl in H.
    destruct (ident_eq i i0).
    - simpl in *.
      if_tac; [| congruence].
      pose proof Ctypes.sizeof_pos t0.
      pose proof Z.le_max_l (Ctypes.sizeof t0) (sizeof_union env m).
      lia.
    - destruct H0; [simpl in H0; congruence |].
      simpl.
      if_tac; [congruence |].
      apply IHm; [| auto].
      pose proof sizeof_union_pos env m.
      pose proof Z.le_max_r (Ctypes.sizeof t0) (sizeof_union env m).
      lia.
Qed.

Definition in_map: forall {A B : Type} (f : A -> B) (l : list A) (x : A),
       In x l -> In (f x) (map f l) :=
fun {A B : Type} (f : A -> B) (l : list A) =>
list_ind (fun l0 : list A => forall x : A, In x l0 -> In (f x) (map f l0))
  (fun (x : A) (H : In x nil) => H)
  (fun (a : A) (l0 : list A)
     (IHl : forall x : A, In x l0 -> In (f x) (map f l0)) (x : A)
     (H : In x (a :: l0)) =>
   or_ind
     (fun H0 : a = x =>
      or_introl (eq_ind_r (fun a0 : A => f a0 = f x) eq_refl H0))
     (fun H0 : In x l0 =>
      or_intror
        ((fun H1 : In x l0 -> In (f x) (map f l0) =>
          (fun H2 : In (f x) (map f l0) => H2) (H1 H0)) (IHl x))) H) l.

Lemma In_field_type: forall it m,
  members_no_replicate m = true ->
  In it m ->
  field_type (fst it) m = snd it.
Proof.
  unfold field_type.
  intros.
  induction m.
  + inversion H0.
  + destruct a, it.
    simpl.
    destruct (ident_eq i0 i).
    - destruct H0; [inversion H0; auto |].
      apply in_map with (f := fst) in H0.
      simpl in H0.
      pose proof in_members_tail_no_replicate _ _ _ _ H H0.
      subst i0. contradiction H1; auto.
    - apply IHm.
       destruct (members_no_replicate_ind ((i,t)::m)) as [? _].
       destruct (H1 H); auto.
      * inversion H0; [| auto].
        inversion H1. subst i0 t0.  contradiction n; auto.
Defined.

End COMPOSITE_ENV.

Lemma members_spec_change_composite' {cs_from cs_to} {CCE: change_composite_env cs_from cs_to}: forall id,
  match (coeq cs_from cs_to) ! id with
  | Some b => test_aux cs_from cs_to b id
  | None => false
  end = true ->
  Forall (fun it => cs_preserve_type cs_from cs_to (coeq _ _) (snd it) = true) (co_members (get_co id)).
Proof.
  intros.
  destruct ((@cenv_cs cs_to) ! id) eqn:?H.
  + pose proof proj1 (coeq_complete _ _ id) (ex_intro _ c H0) as [b ?].
    rewrite H1 in H.
    apply (coeq_consistent _ _ id _ _ H0) in H1.
    unfold test_aux in H.
    destruct b; [| inv H].
    rewrite !H0 in H.
    destruct ((@cenv_cs cs_from) ! id) eqn:?H; [| inv H].
    simpl in H.
    rewrite !andb_true_iff in H.
    unfold get_co.
    rewrite H0.
    clear - H1.
    symmetry in H1.
    induction (co_members c) as [| [i t] ?].
    - constructor.
    - simpl in H1; rewrite andb_true_iff in H1; destruct H1.
      constructor; auto.
  + destruct ((coeq cs_from cs_to) ! id) eqn:?H.
    - pose proof proj2 (coeq_complete _ _ id) (ex_intro _ b H1) as [co ?].
      congruence.
    - inv H.
Qed.

Lemma members_spec_change_composite'' {cs_from cs_to} {CCE: change_composite_env cs_from cs_to}: forall id,
  match (coeq cs_from cs_to) ! id with
  | Some b => test_aux cs_from cs_to b id
  | None => false
  end = true ->
  forall i, cs_preserve_type cs_from cs_to (coeq _ _) (field_type i (co_members (get_co id))) = true.
Proof.
  intros.
  unfold field_type.
  apply members_spec_change_composite' in H.
  induction H as [| [i0 t0] ?]; auto.
  simpl.
  if_tac; auto.
Qed.

Lemma members_spec_change_composite {cs_from cs_to} {CCE: change_composite_env cs_from cs_to}: forall id,
  match (coeq cs_from cs_to) ! id with
  | Some b => test_aux cs_from cs_to b id
  | None => false
  end = true ->
  Forall (fun it => cs_preserve_type cs_from cs_to (coeq _ _) (field_type (fst it) (co_members (get_co id))) = true) (co_members (get_co id)).
Proof.
  intros.
  apply members_spec_change_composite' in H.
  assert (Forall (fun it: ident * type => field_type (fst it) (co_members (get_co id)) = snd it) (co_members (get_co id))).
  1:{
    rewrite Forall_forall.
    intros it ?.
    apply In_field_type; auto.
    apply get_co_members_no_replicate.
  }
  revert H0; generalize (co_members (get_co id)) at 1 3.
  induction H as [| [i t] ?]; constructor.
  + inv H1.
    simpl in *.
    rewrite H4; auto.
  + inv H1.
    auto.
Qed.

(* TODO: we have already proved a related field_offset lemma in veric/change_compspecs.v. But it seems not clear how to use that in an elegant way. *)
Lemma field_offset_change_composite {cs_from cs_to} {CCE: change_composite_env cs_from cs_to}: forall id i,
  match (coeq cs_from cs_to) ! id with
  | Some b => test_aux cs_from cs_to b id
  | None => false
  end = true ->
  field_offset (@cenv_cs cs_from) i (co_members (@get_co cs_to id)) =
  field_offset (@cenv_cs cs_to) i (co_members (@get_co cs_to id)).
Proof.
  intros.
  apply members_spec_change_composite' in H.
  unfold field_offset, Ctypes.field_offset.
  generalize 0 at 1 3.
  induction (co_members (get_co id)) as [| [i0 t0] ?]; intros.
  + auto.
  + simpl.
    inv H.
    if_tac.
    - f_equal.
      apply alignof_change_composite; auto.
    - specialize (IHm H3).
       fold (@alignof cs_from t0) in *. fold (@sizeof cs_from t0) in *.
       fold (@alignof cs_to t0) in *. fold (@sizeof cs_to t0) in *.
      rewrite alignof_change_composite, sizeof_change_composite by auto.
      apply IHm.
Qed.

Lemma field_offset_next_change_composite {cs_from cs_to} {CCE: change_composite_env cs_from cs_to}: forall id i,
  match (coeq cs_from cs_to) ! id with
  | Some b => test_aux cs_from cs_to b id
  | None => false
  end = true ->
  field_offset_next (@cenv_cs cs_from) i (co_members (get_co id)) (co_sizeof (@get_co cs_from id)) =
field_offset_next (@cenv_cs cs_to) i (co_members (get_co id)) (co_sizeof (@get_co cs_to id)).
Proof.
  intros.
  rewrite co_sizeof_get_co_change_composite by auto.
  apply members_spec_change_composite' in H.
  unfold field_offset_next.
  generalize 0.
  destruct H as [| [i0 t0] ? ]; intros; auto.
  simpl in H, H0.
  revert i0 t0 H z.
  induction H0 as [| [i1 t1] ? ]; intros.
  + reflexivity.
  + simpl.
       fold (@alignof cs_from t0) in *. fold (@sizeof cs_from t0) in *.
       fold (@alignof cs_to t0) in *. fold (@sizeof cs_to t0) in *.
       fold (@alignof cs_from t1) in *. fold (@sizeof cs_from t1) in *.
       fold (@alignof cs_to t1) in *. fold (@sizeof cs_to t1) in *.
    if_tac; auto.
    - f_equal; [f_equal |].
      * apply sizeof_change_composite; auto.
      * apply alignof_change_composite; auto.
    - specialize (IHForall i1 t1 H (align (z + sizeof t0) (alignof t1))); simpl in IHForall.
      rewrite (sizeof_change_composite t0) by auto.
      rewrite (alignof_change_composite t1) by auto.
      apply IHForall.
Qed.

Arguments field_type i m / .
Arguments field_offset env i m / .

