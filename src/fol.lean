/- A development of first-order logic in Lean.

* The object theory uses classical logic
* We use de Bruijn variables.
* We use a deep embedding of the logic, i.e. the type of terms and formulas is inductively defined.
* There is no well-formedness predicate; all elements of type "term" are well-formed.
-/

import .to_mathlib tactic.squeeze data.quot

open nat set
universe variables u v

local notation h :: t  := dvector.cons h t
local notation `[` l:(foldr `, ` (h t, dvector.cons h t) dvector.nil `]`:0) := l

namespace fol

/- realizers of variables are just maps ℕ → S. We need some operations on them -/

def subst_realize {S : Type u} (v : ℕ → S) (x : S) (n k : ℕ) : S :=
if k < n then v k else if n < k then v (k - 1) else x

notation v `[`:95 x ` // `:95 n `]`:0 := fol.subst_realize v x n

@[simp] lemma subst_realize_lt {S : Type u} (v : ℕ → S) (x : S) {n k : ℕ} (H : k < n) : 
  v[x // n] k = v k :=
by simp only [H, subst_realize, if_true, eq_self_iff_true]

@[simp] lemma subst_realize_gt {S : Type u} (v : ℕ → S) (x : S) {n k : ℕ} (H : n < k) : 
  v[x // n] k = v (k-1) :=
have h : ¬(k < n), from lt_asymm H,
by simp only [*, subst_realize, if_true, eq_self_iff_true, if_false]

@[simp] lemma subst_realize_var_eq {S : Type u} (v : ℕ → S) (x : S) (n : ℕ) : v[x // n] n = x :=
by simp only [subst_realize, lt_irrefl, eq_self_iff_true, if_false]

lemma subst_realize_congr {S : Type u} {v v' : ℕ → S} (hv : ∀k, v k = v' k) (x : S) (n k : ℕ) : 
 v [x // n] k = v' [x // n] k :=
by apply lt_by_cases k n; intro h; 
   simp only [*, subst_realize_lt, subst_realize_gt, subst_realize_var_eq, eq_self_iff_true]

lemma subst_realize2 {S : Type u} (v : ℕ → S) (x x' : S) (n₁ n₂ k : ℕ) :
  v [x' // n₁ + n₂] [x // n₁] k = v [x // n₁] [x' // n₁ + n₂ + 1] k :=
begin
    apply lt_by_cases k n₁; intro h,
    { have : k < n₁ + n₂, from lt_of_le_of_lt (k.le_add_right n₂) (add_lt_add_right h n₂),
      have : k < n₁ + n₂ + 1, from lt.step this,
      simp only [*, fol.subst_realize_lt, eq_self_iff_true] },
    { have : k < n₂ + (k + 1), from nat.lt_add_left _ _ n₂ (lt.base k),
      subst h, simp [*, -add_comm] },
    apply lt_by_cases k (n₁ + n₂ + 1); intro h',
    { have : k - 1 < n₁ + n₂, from (nat.sub_lt_right_iff_lt_add (one_le_of_lt h)).2 h', 
      simp [*, -add_comm, -add_assoc] },
    { subst h', simp [h, -add_comm, -add_assoc] },
    { have : n₁ + n₂ < k - 1, from nat.lt_sub_right_of_add_lt h', 
      have : n₁ < k - 1, from lt_of_le_of_lt (n₁.le_add_right n₂) this,
      simp only [*, fol.subst_realize_gt, eq_self_iff_true] }
end

lemma subst_realize2_0 {S : Type u} (v : ℕ → S) (x x' : S) (n k : ℕ) :
  v [x' // n] [x // 0] k = v [x // 0] [x' // n + 1] k :=
let h := subst_realize2 v x x' 0 n k in by simp only [zero_add] at h; exact h

lemma subst_realize_irrel {S : Type u} {v₁ v₂ : ℕ → S} {n : ℕ} (hv : ∀k < n, v₁ k = v₂ k) (x : S)
  {k : ℕ} (hk : k < n + 1) : v₁[x // 0] k = v₂[x // 0] k :=
begin
  cases k, refl, have h : 0 < succ k, from zero_lt_succ k, simp [h, hv k (lt_of_succ_lt_succ hk)]
end

lemma lift_subst_realize_cancel {S : Type u} (v : ℕ → S) (k : ℕ) : 
  (λn, v (n + 1))[v 0 // 0] k = v k :=
begin
  cases k, refl, have h : 0 < succ k, from zero_lt_succ k, simp [h],
end

lemma subst_fin_realize_eq {S : Type u} {n} {v₁ : dvector S n} {v₂ : ℕ → S} 
  (hv : ∀k (hk : k < n), v₁.nth k hk = v₂ k) (x : S) (k : ℕ) (hk : k < n+1) : 
    (x::v₁).nth k hk = v₂[x // 0] k :=
begin
  cases k, refl, 
  have h : 0 < succ k, from zero_lt_succ k, 
  have h' : (0 : fin (n+1)).val < (fin.mk (succ k) hk).val, from h, 
  rw [subst_realize_gt v₂ x h, dvector.nth], apply hv 
end

structure Language : Type (u+1) := 
(functions : ℕ → Type u) (relations : ℕ → Type u)

def Language.constants (L : Language) := L.functions 0

variable (L : Language.{u})

/- preterm L l is a partially applied term. if applied to n terms, it becomes a term.
* Every element of preterm L 0 is a well-formed term. 
* We use this encoding to avoid mutual or nested inductive types, since those are not too convenient to work with in Lean. -/
inductive preterm : ℕ → Type u
| var {} : ∀ (k : ℕ), preterm 0
| func : ∀ {l : ℕ} (f : L.functions l), preterm l
| app : ∀ {l : ℕ} (t : preterm (l + 1)) (s : preterm 0), preterm l
export preterm

@[reducible] def term := preterm L 0

variable {L}
prefix `&`:max := fol.preterm.var

@[simp] def apps : ∀{l}, preterm L l → dvector (term L) l → term L
| _ t []       := t
| _ t (t'::ts) := apps (app t t') ts

-- @[simp] def rev_apps : ∀{l l'}, preterm L (l+l) → dvector (term L) l' → preterm L l
-- | _ _ t []       := sorry
-- | l _ t (@dvector.cons _ l' t' ts) := app (@rev_apps (l+1) l' t ts) t'

@[simp] lemma apps_zero (t : term L) (ts : dvector (term L) 0) : apps t ts = t :=
by cases ts; refl

def term_of_function {l} (f : L.functions l) : arity (term L) (term L) l :=
arity.of_dvector_map $ apps (func f)

@[elab_as_eliminator] def term.rec {C : term L → Sort v}
  (hvar : ∀(k : ℕ), C &k)
  (hfunc : Π {l} (f : L.functions l) (ts : dvector (term L) l) (ih_ts : ∀t, ts.pmem t → C t), 
    C (apps (func f) ts)) : ∀(t : term L), C t :=
have h : ∀{l} (t : preterm L l) (ts : dvector (term L) l) (ih_ts : ∀s, ts.pmem s → C s), 
  C (apps t ts),
begin
  intros, induction t; try {rw ts.zero_eq},
  { apply hvar }, 
  { apply hfunc t_f ts ih_ts }, 
  { apply t_ih_t (t_s::ts), intros t ht, 
    cases ht, 
    { induction ht, apply t_ih_s ([]), intros s hs, cases hs },
    { exact ih_ts t ht }},
end,
λt, h t ([]) (by intros s hs; cases hs)

@[elab_as_eliminator] def term.elim {C : Type v}
  (hvar : ∀(k : ℕ), C)
  (hfunc : Π {{l}} (f : L.functions l) (ts : dvector (term L) l) (ih_ts : dvector C l), C) : 
  ∀(t : term L), C :=
have h : ∀{l} (t : preterm L l) (ts : dvector (term L) l) (ih_ts : dvector C l), C,
begin
  intros, induction t; try {rw ts.zero_eq},
  { apply hvar t }, 
  { apply hfunc t_f ts ih_ts }, 
  { apply t_ih_t (t_s::ts) (t_ih_s ([]) ([])::ih_ts) },
end,
λt, h t ([]) ([])

-- @[elab_as_eliminator] def term.elim_beta {C : Type v}
--   (hvar : ∀(k : ℕ), C)
--   (hfunc : Π {{l}} (f : L.functions l) (ts : dvector (term L) l) (ih_ts : dvector C l), C) : 
--   ∀{l} (f : L.functions l) (ts : dvector (term L) l), 
--   @term.elim L C hvar hfunc (apps (func f) ts) = hfunc f ts (ts.map $ @term.elim L C hvar hfunc) :=
-- have h : ∀{l l'} (f : L.functions (l+l')) (ts' : dvector (term L) l') (ts : dvector (term L) l) (ih_ts : dvector C l),
--   @term.elim L C hvar hfunc (apps (apps' (func f) ts') ts) = hfunc f (ts'.append ts) 
--   ((ts'.append ts).map $ @term.elim L C hvar hfunc),
-- begin
--   intros, induction l generalizing l'; try {rw ts.zero_eq},
--   { simp, },
-- end,
-- λt, h t ([]) ([])


/- lift_term_at _ t n m raises variables in t which are at least m by n -/
@[simp] def lift_term_at : ∀ {l}, preterm L l → ℕ → ℕ → preterm L l
| _ &k          n m := if m ≤ k then &(k+n) else &k
| _ (func f)    n m := func f
| _ (app t₁ t₂) n m := app (lift_term_at t₁ n m) (lift_term_at t₂ n m)

notation t ` ↑' `:90 n ` # `:90 m:90 := fol.lift_term_at t n m -- input ↑ with \u or \upa

@[reducible] def lift_term {l} (t : preterm L l) (n : ℕ) : preterm L l := t ↑' n # 0
infix ` ↑ `:100 := fol.lift_term -- input ↑' with \u or \upa
@[reducible, simp] def lift_term1 {l} (t : preterm L l) : preterm L l := t ↑ 1

@[simp] lemma lift_term_def {l} (t : preterm L l) (n : ℕ) : t ↑' n # 0 = t ↑ n := by refl

lemma lift_term_at_inj : ∀ {l} {t t' : preterm L l} {n m : ℕ}, t ↑' n # m = t' ↑' n # m → t = t'
| _ &k &k' n m h := 
  by by_cases h₁ : m ≤ k; by_cases h₂ : m ≤ k'; simp [h₁, h₂] at h;
     congr;[assumption, skip, skip, assumption]; exfalso; try {apply h₁}; 
     try {apply h₂}; subst h; apply le_trans (by assumption) (le_add_right _ _)
| _ &k (func f')            n m h := by by_cases h' : m ≤ k; simp [h'] at h; contradiction
| _ &k (app t₁' t₂')        n m h := by by_cases h' : m ≤ k; simp [h'] at h; contradiction
| _ (func f) &k'            n m h := by by_cases h' : m ≤ k'; simp [h'] at h; contradiction
| _ (func f) (func f')      n m h := h
| _ (func f) (app t₁' t₂')  n m h := by cases h
| _ (app t₁ t₂) &k'         n m h := by by_cases h' : m ≤ k'; simp [h'] at h; contradiction
| _ (app t₁ t₂) (func f')   n m h := by cases h
| _ (app t₁ t₂) (app t₁' t₂') n m h := 
  begin injection h, congr; apply lift_term_at_inj; assumption end

@[simp] lemma lift_term_at_zero : ∀ {l} (t : preterm L l) (m : ℕ), t ↑' 0 # m = t
| _ &k          m := by simp
| _ (func f)    m := by refl
| _ (app t₁ t₂) m := by dsimp; congr; apply lift_term_at_zero

@[simp] lemma lift_term_zero {l} (t : preterm L l) : t ↑ 0 = t := lift_term_at_zero t 0

/- the following lemmas simplify iterated lifts, depending on the size of m' -/
lemma lift_term_at2_small : ∀ {l} (t : preterm L l) (n n') {m m'}, m' ≤ m → 
  (t ↑' n # m) ↑' n' # m' = (t ↑' n' # m') ↑' n # (m + n')
| _ &k          n n' m m' H := 
  begin 
    by_cases h : m ≤ k,
    { have h₁ : m' ≤ k := le_trans H h,
      have h₂ : m' ≤ k + n, from le_trans h₁ (k.le_add_right n),
      simp [*, -add_assoc, -add_comm], simp },
    { have h₁ : ¬m + n' ≤ k + n', from λ h', h (le_of_add_le_add_right h'),
      have h₂ : ¬m + n' ≤ k, from λ h', h₁ (le_trans h' (k.le_add_right n')),
      by_cases h' : m' ≤ k; simp [*, -add_comm, -add_assoc] }
  end
| _ (func f)    n n' m m' H := by refl
| _ (app t₁ t₂) n n' m m' H := 
  begin dsimp; congr1; apply lift_term_at2_small; assumption end

lemma lift_term_at2_medium : ∀ {l} (t : preterm L l) {n} (n') {m m'}, m ≤ m' → m' ≤ m+n → 
  (t ↑' n # m) ↑' n' # m' = t ↑' (n+n') # m
| _ &k          n n' m m' H₁ H₂ := 
  begin 
    by_cases h : m ≤ k,
    { have h₁ : m' ≤ k + n, from le_trans H₂ (add_le_add_right h n), simp [*, -add_comm], },
    { have h₁ : ¬m' ≤ k, from λ h', h (le_trans H₁ h'), simp [*, -add_comm, -add_assoc] }
  end
| _ (func f)    n n' m m' H₁ H₂ := by refl
| _ (app t₁ t₂) n n' m m' H₁ H₂ := 
  begin dsimp; congr1; apply lift_term_at2_medium; assumption end

lemma lift_term2_medium {l} (t : preterm L l) {n} (n') {m'} (h : m' ≤ n) :
  (t ↑ n) ↑' n' # m' = t ↑ (n+n') :=
lift_term_at2_medium t n' m'.zero_le (by simp*)

lemma lift_term2 {l} (t : preterm L l) (n n') : (t ↑ n) ↑ n' = t ↑ (n+n') :=
lift_term2_medium t n' n.zero_le

lemma lift_term_at2_eq {l} (t : preterm L l) (n n' m : ℕ) : 
  (t ↑' n # m) ↑' n' # (m+n) = t ↑' (n+n') # m :=
lift_term_at2_medium t n' (m.le_add_right n) (le_refl _)

lemma lift_term_at2_large {l} (t : preterm L l) {n} (n') {m m'} (H : m + n ≤ m') : 
  (t ↑' n # m) ↑' n' # m' = (t ↑' n' # (m'-n)) ↑' n # m :=
have H₁ : n ≤ m', from le_trans (n.le_add_left m) H,
have H₂ : m ≤ m' - n, from nat.le_sub_right_of_add_le H,
begin rw fol.lift_term_at2_small t n' n H₂, rw [nat.sub_add_cancel], exact H₁ end

@[simp] lemma lift_term_var0 (n : ℕ) : &0 ↑ n = (&n : term L) := 
by have h : 0 ≤ 0 := le_refl 0; rw [←lift_term_def]; simp [h, -lift_term_def]

/- subst_term t s n substitutes s for (&n) and reduces the level of all variables above n by 1 -/
def subst_term : ∀ {l}, preterm L l → term L → ℕ → preterm L l
| _ &k          s n := subst_realize var (s ↑ n) n k
| _ (func f)    s n := func f
| _ (app t₁ t₂) s n := app (subst_term t₁ s n) (subst_term t₂ s n)

notation t `[`:max s ` // `:95 n `]`:0 := fol.subst_term t s n

@[simp] lemma subst_term_var_lt (s : term L) {k n : ℕ} (H : k < n) : &k[s // n] = &k :=
by simp only [H, fol.subst_term, fol.subst_realize_lt, eq_self_iff_true]

@[simp] lemma subst_term_var_gt (s : term L) {k n : ℕ} (H : n < k) : &k[s // n] = &(k-1) :=
by simp only [H, fol.subst_term, fol.subst_realize_gt, eq_self_iff_true]

@[simp] lemma subst_term_var_eq (s : term L) (n : ℕ) : &n[s // n] = s ↑' n # 0 :=
by simp [subst_term]

lemma subst_term_var0 (s : term L) : &0[s // 0] = s := by simp

@[simp] lemma subst_term_func {l} (f : L.functions l) (s : term L) (n : ℕ) : 
  (func f)[s // n] = func f :=
by refl

@[simp] lemma subst_term_app {l} (t₁ : preterm L (l+1)) (t₂ s : term L) (n : ℕ) : 
  (app t₁ t₂)[s // n] = app (t₁[s // n]) (t₂[s // n]) :=
by refl

@[simp] lemma subst_term_apps {l} (t : preterm L l) (ts : dvector (term L) l) (s : term L) (n : ℕ) : 
  (apps t ts)[s // n] = apps (t[s // n]) (ts.map $ λx, x[s // n]) :=
begin
  induction ts generalizing t, refl, apply ts_ih (app t ts_x)
end

/- the following lemmas simplify first lifting and then substituting, depending on the size
  of the substituted variable -/
lemma lift_at_subst_term_large : ∀{l} (t : preterm L l) (s : term L) {n₁} (n₂) {m}, m ≤ n₁ →
 (t ↑' n₂ # m)[s // n₁+n₂] = (t [s // n₁]) ↑' n₂ # m
| _ &k          s n₁ n₂ m h :=
  begin
    apply lt_by_cases k n₁; intro h₂,
    { have : k < n₁ + n₂, from lt_of_le_of_lt (k.le_add_right n₂) (by simp*),
      by_cases m ≤ k; simp* },
    { subst h₂, simp [*, lift_term2_medium] },
    { have h₂ : m < k, by apply lt_of_le_of_lt; assumption,
      have : m ≤ k - 1, from nat.le_sub_right_of_add_le (succ_le_of_lt h₂),
      have : m ≤ k, from le_of_lt h₂,
      have : 1 ≤ k, from one_le_of_lt h₂,
      simp [*, nat.add_sub_swap this n₂, -add_assoc, -add_comm] }
  end
| _ (func f)    s n₁ n₂ m h := rfl
| _ (app t₁ t₂) s n₁ n₂ m h := by simp*

lemma lift_subst_term_large {l} (t : preterm L l) (s : term L) (n₁ n₂) :
  (t ↑ n₂)[s // n₁+n₂] = (t [s // n₁]) ↑ n₂ :=
lift_at_subst_term_large t s n₂ n₁.zero_le

lemma lift_subst_term_large' {l} (t : preterm L l) (s : term L) (n₁ n₂) :
  (t ↑ n₂)[s // n₂+n₁] = (t [s // n₁]) ↑ n₂ :=
by rw [add_comm]; apply lift_subst_term_large

lemma lift_at_subst_term_medium : ∀{l} (t : preterm L l) (s : term L) {n₁ n₂ m}, m ≤ n₂ → 
  n₂ ≤ m + n₁ → (t ↑' n₁+1 # m)[s // n₂] = t ↑' n₁ # m
| _ &k          s n₁ n₂ m h₁ h₂ := 
  begin 
    by_cases h : m ≤ k,
    { have h₃ : n₂ < k + (n₁ + 1), from lt_succ_of_le (le_trans h₂ (add_le_add_right h _)), 
      simp [*, add_sub_cancel_right] },
    { have h₃ : k < n₂, from lt_of_lt_of_le (lt_of_not_ge h) h₁, simp* }
  end
| _ (func f)    s n₁ n₂ m h₁ h₂ := rfl
| _ (app t₁ t₂) s n₁ n₂ m h₁ h₂ := by simp*

lemma lift_subst_term_medium {l} (t : preterm L l) (s : term L) (n₁ n₂) :
  (t ↑ ((n₁ + n₂) + 1))[s // n₁] = t ↑ (n₁ + n₂) :=
lift_at_subst_term_medium t s n₁.zero_le (by rw [zero_add]; exact n₁.le_add_right n₂)

lemma lift_at_subst_term_eq {l} (t : preterm L l) (s : term L) (n : ℕ) : (t ↑' 1 # n)[s // n] = t :=
begin rw [lift_at_subst_term_medium t s, lift_term_at_zero]; refl end

@[simp] lemma lift_term1_subst_term {l} (t : preterm L l) (s : term L) : (t ↑ 1)[s // 0] = t :=
lift_at_subst_term_eq t s 0

lemma lift_at_subst_term_small : ∀{l} (t : preterm L l) (s : term L) (n₁ n₂ m), 
 (t ↑' n₁ # (m + n₂ + 1))[s ↑' n₁ # m // n₂] = (t [s // n₂]) ↑' n₁ # (m + n₂)
| _ &k          s n₁ n₂ m := 
  begin
    by_cases h : m + n₂ + 1 ≤ k,
    { change m + n₂ + 1 ≤ k at h, 
      have h₂ : n₂ < k := lt_of_le_of_lt (le_add_left n₂ m) (lt_of_succ_le h),
      have h₃ : n₂ < k + n₁ := by apply nat.lt_add_right; exact h₂, 
      have h₄ : m + n₂ ≤ k - 1 := nat.le_sub_right_of_add_le h, 
      simp [*, -add_comm, -add_assoc, nat.add_sub_swap (one_le_of_lt h₂)] },
    { change ¬(m + n₂ + 1 ≤ k) at h, 
      apply lt_by_cases k n₂; intro h₂,
      { have h₃ : ¬(m + n₂ ≤ k) := λh', not_le_of_gt h₂ (le_trans (le_add_left n₂ m) h'),
        simp [h, h₂, h₃, -add_comm, -add_assoc] },
      { subst h₂, 
        have h₃ : ¬(k + m + 1 ≤ k) := by rw [add_comm k m]; exact h,
        simp [h, h₃, -add_comm, -add_assoc], 
        exact lift_term_at2_small _ _ _ m.zero_le },
      { have h₃ : ¬(m + n₂ ≤ k - 1) := 
          λh', h $ (nat.le_sub_right_iff_add_le $ one_le_of_lt h₂).mp h',
        simp [h, h₂, h₃, -add_comm, -add_assoc] }}
  end
| _ (func f)    s n₁ n₂ m := rfl
| _ (app t₁ t₂) s n₁ n₂ m := by simp [*, -add_assoc, -add_comm]

lemma subst_term2 : ∀{l} (t : preterm L l) (s₁ s₂ : term L) (n₁ n₂),
  t [s₁ // n₁] [s₂ // n₁ + n₂] = t [s₂ // n₁ + n₂ + 1] [s₁[s₂ // n₂] // n₁]
| _ &k          s₁ s₂ n₁ n₂ :=
  begin -- can we use subst_realize2 here?
    apply lt_by_cases k n₁; intro h,
    { have : k < n₁ + n₂, from lt_of_le_of_lt (k.le_add_right n₂) (by simp*),
      have : k < n₁ + n₂ + 1, from lt.step this,
      simp only [*, eq_self_iff_true, fol.subst_term_var_lt] },
    { have : k < k + (n₂ + 1), from lt_succ_of_le (le_add_right _ n₂),
      subst h, simp [*, lift_subst_term_large', -add_comm] },
    apply lt_by_cases k (n₁ + n₂ + 1); intro h',
    { have : k - 1 < n₁ + n₂, from (nat.sub_lt_right_iff_lt_add (one_le_of_lt h)).2 h', 
      simp [*, -add_comm, -add_assoc] },
    { subst h', simp [h, lift_subst_term_medium, -add_comm, -add_assoc] },
    { have : n₁ + n₂ < k - 1, from nat.lt_sub_right_of_add_lt h', 
      have : n₁ < k - 1, from lt_of_le_of_lt (n₁.le_add_right n₂) this,
      simp only [*, eq_self_iff_true, fol.subst_term_var_gt] }
  end
| _ (func f)    s₁ s₂ n₁ n₂ := rfl
| _ (app t₁ t₂) s₁ s₂ n₁ n₂ := by simp*

lemma subst_term2_0 {l} (t : preterm L l) (s₁ s₂ : term L) (n) :
  t [s₁ // 0] [s₂ // n] = t [s₂ // n + 1] [s₁[s₂ // n] // 0] :=
let h := subst_term2 t s₁ s₂ 0 n in by simp only [zero_add] at h; exact h

lemma lift_subst_term_cancel : ∀{l} (t : preterm L l) (n : ℕ), (t ↑' 1 # (n+1))[&0 // n] = t
| _ &k          n :=
  begin
    apply lt_by_cases n k; intro h, 
    { change n+1 ≤ k at h, have h' : n < k+1, from lt.step (lt_of_succ_le h), simp [h, h'] }, 
    { have h' : ¬(k+1 ≤ k), from not_succ_le_self k, simp [h, h'] },
    { have h' : ¬(n+1 ≤ k) := not_le_of_lt (lt.step h), simp [h, h'] }
  end
| _ (func f)    n := rfl
| _ (app t₁ t₂) n := by dsimp; simp [*]


/- Probably useful facts about substitution which we should add when needed:
(forall M N i j k, ( M [ j ← N] ) ↑' k # (j+i) = (M ↑' k # (S (j+i))) [ j ← (N ↑' k # i ) ])
subst_travers : (forall M N P n, (M [← N]) [n ← P] = (M [n+1 ← P])[← N[n← P]])
erasure_lem3 : (forall n m t, m>n->#m = (#m ↑' 1 # (S n)) [n ← t]). 
lift_is_lift_sublemma : forall j v, j<v->exists w,#v=w↑1#j. 
lift_is_lift : (forall N A n i j,N ↑' i # n=A ↑' 1 # j -> j<n -> exists M,N=M ↑' 1 # j)
subst_is_lift : (forall N T A n j, N [n ← T]=A↑' 1#j->j<n->exists M,N=M↑' 1#j)
-/

/- preformula l is a partially applied formula. if applied to n terms, it becomes a formula. 
  * We only have implication as binary connective. Since we use classical logic, we can define
    the other connectives from implication and falsum. 
  * Similarly, universal quantification is our only quantifier. 
  * We could make `falsum` and `equal` into elements of rel. However, if we do that, then we cannot make the interpretation of them in a model definitionally what we want.
-/
variable (L)
inductive preformula : ℕ → Type u
| falsum {} : preformula 0
| equal (t₁ t₂ : term L) : preformula 0
| rel {l : ℕ} (R : L.relations l) : preformula l
| apprel {l : ℕ} (f : preformula (l + 1)) (t : term L) : preformula l
| imp (f₁ f₂ : preformula 0) : preformula 0
| all (f : preformula 0) : preformula 0
export preformula
@[reducible] def formula := preformula L 0
variable {L}

notation `⊥` := fol.preformula.falsum -- input: \bot
infix ` ≃ `:88 := fol.preformula.equal -- input \~- or \simeq
infix ` ⟹ `:62 := fol.preformula.imp -- input \==>
prefix `∀'`:110 := fol.preformula.all
def not (f : formula L) : formula L := imp f ⊥
prefix `∼`:max := fol.not -- input \~, the ASCII character ~ has too low precedence
notation `⊤` := ∼⊥ -- input: \top
def and (f₁ f₂ : formula L) : formula L := ∼(f₁ ⟹ ∼f₂)
infixr ` ⊓ ` := fol.and -- input: \sqcap
def or (f₁ f₂ : formula L) : formula L := ∼f₁ ⟹ f₂
infixr ` ⊔ ` := fol.or -- input: \sqcup
def biimp (f₁ f₂ : formula L) : formula L := (f₁ ⟹ f₂) ⊓ (f₂ ⟹ f₁)
infix ` ⇔ `:61 := fol.biimp -- input \<=>
def ex (f : formula L) : formula L := ∼ ∀' ∼f
prefix `∃'`:110 := fol.ex

def apps_rel : ∀{l} (f : preformula L l) (ts : dvector (term L) l), formula L
| 0     f []      := f
| (n+1) f (t::ts) := apps_rel (apprel f t) ts

@[simp] lemma apps_rel_zero (f : formula L) (ts : dvector (term L) 0) : apps_rel f ts = f :=
by cases ts; refl

-- lemma apps_rel_ne_falsum {l} {R : L.relations l} {ts : dvector (term L) l} : 
--   apps_rel (rel R) ts ≠ ⊥ :=
-- by induction l; cases ts; [{cases ts_xs, intro h, injection h}, apply l_ih]

-- lemma apps_rel_ne_falsum {l} {f : preformula L (l+1)} {ts : dvector (term L) (l+1)} : 
--   apps_rel f ts ≠ ⊥ :=
-- by induction l; cases ts; [{cases ts_xs, intro h, injection h}, apply l_ih]
-- lemma apps_rel_ne_equal {l} {f : preformula L (l+1)} {ts : dvector (term L) (l+1)} 
--   {t₁ t₂ : term L} : apps_rel f ts ≠ t₁ ≃ t₂ :=
-- by induction l; cases ts; [{cases ts_xs, intro h, injection h}, apply l_ih]
-- lemma apps_rel_ne_imp {l} {f : preformula L (l+1)} {ts : dvector (term L) (l+1)} 
--   {f₁ f₂ : formula L} : apps_rel f ts ≠ f₁ ⟹ f₂ :=
-- by induction l; cases ts; [{cases ts_xs, intro h, injection h}, apply l_ih]
-- lemma apps_rel_ne_all {l} {f : preformula L (l+1)} {ts : dvector (term L) (l+1)} 
--   {f' : formula L} : apps_rel f ts ≠ ∀' f' :=
-- by induction l; cases ts; [{cases ts_xs, intro h, injection h}, apply l_ih]

def formula_of_relation {l} (R : L.relations l) : arity (term L) (formula L) l :=
arity.of_dvector_map $ apps_rel (rel R)

@[elab_as_eliminator] def formula.rec {C : formula L → Sort v}
  (hfalsum : C ⊥)
  (hequal : Π (t₁ t₂ : term L), C (t₁ ≃ t₂))
  (hrel : Π {l} (R : L.relations l) (ts : dvector (term L) l), C (apps_rel (rel R) ts))
  (himp : Π {{f₁ f₂ : formula L}} (ih₁ : C f₁) (ih₂ : C f₂), C (f₁ ⟹ f₂))
  (hall : Π {{f : formula L}} (ih : C f), C (∀' f)) : ∀f, C f :=
have h : ∀{l} (f : preformula L l) (ts : dvector (term L) l), C (apps_rel f ts),
begin
  intros, induction f; try {rw ts.zero_eq},
  exact hfalsum, apply hequal, apply hrel, apply f_ih (f_t::ts),
  exact himp (f_ih_f₁ ([])) (f_ih_f₂ ([])), exact hall (f_ih ([]))
end,
λ f, h f ([])

@[simp] def lift_formula_at : ∀ {l}, preformula L l → ℕ → ℕ → preformula L l
| _ falsum       n m := falsum
| _ (t₁ ≃ t₂)    n m := lift_term_at t₁ n m ≃ lift_term_at t₂ n m
| _ (rel R)      n m := rel R
| _ (apprel f t) n m := apprel (lift_formula_at f n m) (lift_term_at t n m)
| _ (f₁ ⟹ f₂)   n m := lift_formula_at f₁ n m ⟹ lift_formula_at f₂ n m
| _ (∀' f)       n m := ∀' lift_formula_at f n (m+1)

notation f ` ↑' `:90 n ` # `:90 m:90 := fol.lift_formula_at f n m -- input ↑' with \upa

@[reducible] def lift_formula {l} (f : preformula L l) (n : ℕ) : preformula L l := f ↑' n # 0
infix ` ↑ `:100 := fol.lift_formula -- input ↑' with \upa
@[reducible, simp] def lift_formula1 {l} (f : preformula L l) : preformula L l := f ↑ 1

@[simp] lemma lift_formula_def {l} (f : preformula L l) (n : ℕ) : f ↑' n # 0 = f ↑ n := by refl
@[simp] lemma lift_formula1_not (n : ℕ) (f : formula L) : ∼f ↑ n  = ∼(f ↑ n) := by refl

lemma lift_formula_at_inj {l} {f f' : preformula L l} {n m : ℕ} (H : f ↑' n # m = f' ↑' n # m) : 
  f = f' :=
begin
  induction f generalizing m; cases f'; injection H,
  { simp only [lift_term_at_inj h_1, lift_term_at_inj h_2, eq_self_iff_true, and_self] },
  { simp only [f_ih h_1, lift_term_at_inj h_2, eq_self_iff_true, and_self] },
  { simp only [f_ih_f₁ h_1, f_ih_f₂ h_2, eq_self_iff_true, and_self] },
  { simp only [f_ih h_1, eq_self_iff_true] }
end

@[simp] lemma lift_formula_at_zero : ∀ {l} (f : preformula L l) (m : ℕ), f ↑' 0 # m = f
| _ falsum       m := by refl
| _ (t₁ ≃ t₂)    m := by simp
| _ (rel R)      m := by refl
| _ (apprel f t) m := by simp; apply lift_formula_at_zero
| _ (f₁ ⟹ f₂)   m := by dsimp; congr1; apply lift_formula_at_zero
| _ (∀' f)       m := by simp; apply lift_formula_at_zero

/- the following lemmas simplify iterated lifts, depending on the size of m' -/
lemma lift_formula_at2_small : ∀ {l} (f : preformula L l) (n n') {m m'}, m' ≤ m → 
  (f ↑' n # m) ↑' n' # m' = (f ↑' n' # m') ↑' n # (m + n')
| _ falsum       n n' m m' H := by refl
| _ (t₁ ≃ t₂)    n n' m m' H := by simp [lift_term_at2_small, H]
| _ (rel R)      n n' m m' H := by refl
| _ (apprel f t) n n' m m' H := 
  by simp [lift_term_at2_small, H, -add_comm]; apply lift_formula_at2_small; assumption
| _ (f₁ ⟹ f₂)   n n' m m' H := by dsimp; congr1; apply lift_formula_at2_small; assumption
| _ (∀' f)       n n' m m' H :=
  by simp [lift_term_at2_small, H, lift_formula_at2_small f n n' (add_le_add_right H 1)]

lemma lift_formula_at2_medium : ∀ {l} (f : preformula L l) (n n') {m m'}, m ≤ m' → m' ≤ m+n → 
  (f ↑' n # m) ↑' n' # m' = f ↑' (n+n') # m
| _ falsum       n n' m m' H₁ H₂ := by refl
| _ (t₁ ≃ t₂)    n n' m m' H₁ H₂ := by simp [*, lift_term_at2_medium]
| _ (rel R)      n n' m m' H₁ H₂ := by refl
| _ (apprel f t) n n' m m' H₁ H₂ := by simp [*, lift_term_at2_medium, -add_comm]
| _ (f₁ ⟹ f₂)   n n' m m' H₁ H₂ := by simp*
| _ (∀' f)       n n' m m' H₁ H₂ :=
  have m' + 1 ≤ (m + 1) + n, from le_trans (add_le_add_right H₂ 1) (by simp), by simp*

lemma lift_formula_at2_eq {l} (f : preformula L l) (n n' m : ℕ) : 
  (f ↑' n # m) ↑' n' # (m+n) = f ↑' (n+n') # m :=
lift_formula_at2_medium f n n' (m.le_add_right n) (le_refl _)

lemma lift_formula_at2_large {l} (f : preformula L l) (n n') {m m'} (H : m + n ≤ m') : 
  (f ↑' n # m) ↑' n' # m' = (f ↑' n' # (m'-n)) ↑' n # m :=
have H₁ : n ≤ m', from le_trans (n.le_add_left m) H,
have H₂ : m ≤ m' - n, from nat.le_sub_right_of_add_le H,
begin rw lift_formula_at2_small f n' n H₂, rw [nat.sub_add_cancel], exact H₁ end

@[simp] def subst_formula : ∀ {l}, preformula L l → term L → ℕ → preformula L l
| _ falsum       s n := falsum
| _ (t₁ ≃ t₂)    s n := subst_term t₁ s n ≃ subst_term t₂ s n
| _ (rel R)      s n := rel R
| _ (apprel f t) s n := apprel (subst_formula f s n) (subst_term t s n)
| _ (f₁ ⟹ f₂)   s n := subst_formula f₁ s n ⟹ subst_formula f₂ s n
| _ (∀' f)       s n := ∀' subst_formula f s (n+1)

notation f `[`:95 s ` // `:95 n `]`:0 := fol.subst_formula f s n

lemma subst_formula_equal (t₁ t₂ s : term L) (n : ℕ) :
  (t₁ ≃ t₂)[s // n] = t₁[s // n] ≃ (t₂[s // n]) :=
by refl

@[simp] lemma subst_formula_biimp (f₁ f₂ : formula L) (s : term L) (n : ℕ) :
  (f₁ ⇔ f₂)[s // n] = f₁[s // n] ⇔ (f₂[s // n]) :=
by refl

@[simp] lemma subst_formula_apps_rel {l} (f : preformula L l) (ts : dvector (term L) l) (s : term L) 
  (n : ℕ): (apps_rel f ts)[s // n] = apps_rel (f[s // n]) (ts.map $ λx, x[s // n]) :=
begin
  induction ts generalizing f, refl, apply ts_ih (apprel f ts_x)
end

lemma lift_at_subst_formula_large : ∀{l} (f : preformula L l) (s : term L) {n₁} (n₂) {m}, m ≤ n₁ →
  (f ↑' n₂ # m)[s // n₁+n₂] = (f [s // n₁]) ↑' n₂ # m
| _ falsum       s n₁ n₂ m h := by refl
| _ (t₁ ≃ t₂)    s n₁ n₂ m h := by simp [*, lift_at_subst_term_large]
| _ (rel R)      s n₁ n₂ m h := by refl
| _ (apprel f t) s n₁ n₂ m h := by simp [*, lift_at_subst_term_large]
| _ (f₁ ⟹ f₂)   s n₁ n₂ m h := by simp*
| _ (∀' f)       s n₁ n₂ m h := 
  by have := lift_at_subst_formula_large f s n₂ (add_le_add_right h 1); simp at this; simp*

lemma lift_subst_formula_large {l} (f : preformula L l) (s : term L) {n₁ n₂} :
  (f ↑ n₂)[s // n₁+n₂] = (f [s // n₁]) ↑ n₂ :=
lift_at_subst_formula_large f s n₂ n₁.zero_le

lemma lift_subst_formula_large' {l} (f : preformula L l) (s : term L) {n₁ n₂} :
  (f ↑ n₂)[s // n₂+n₁] = (f [s // n₁]) ↑ n₂ :=
by rw [add_comm]; apply lift_subst_formula_large

lemma lift_at_subst_formula_medium : ∀{l} (f : preformula L l) (s : term L) {n₁ n₂ m}, m ≤ n₂ → 
  n₂ ≤ m + n₁ → (f ↑' n₁+1 # m)[s // n₂] = f ↑' n₁ # m
| _ falsum       s n₁ n₂ m h₁ h₂ := by refl
| _ (t₁ ≃ t₂)    s n₁ n₂ m h₁ h₂ := by simp [*, lift_at_subst_term_medium]
| _ (rel R)      s n₁ n₂ m h₁ h₂ := by refl
| _ (apprel f t) s n₁ n₂ m h₁ h₂ := by simp [*, lift_at_subst_term_medium]
| _ (f₁ ⟹ f₂)   s n₁ n₂ m h₁ h₂ := by simp*
| _ (∀' f)       s n₁ n₂ m h₁ h₂ := 
  begin
    have h : n₂ + 1 ≤ (m + 1) + n₁, from le_trans (add_le_add_right h₂ 1) (by simp),
    have := lift_at_subst_formula_medium f s (add_le_add_right h₁ 1) h, 
    simp only [fol.subst_formula, fol.lift_formula_at] at this, simp*
  end

lemma lift_subst_formula_medium {l} (f : preformula L l) (s : term L) (n₁ n₂) :
  (f ↑ ((n₁ + n₂) + 1))[s // n₁] = f ↑ (n₁ + n₂) :=
lift_at_subst_formula_medium f s n₁.zero_le (by rw [zero_add]; exact n₁.le_add_right n₂)

lemma lift_at_subst_formula_eq {l} (f : preformula L l) (s : term L) (n : ℕ) : 
  (f ↑' 1 # n)[s // n] = f :=
begin rw [lift_at_subst_formula_medium f s, lift_formula_at_zero]; refl end

@[simp] lemma lift_formula1_subst {l} (f : preformula L l) (s : term L) : (f ↑ 1)[s // 0] = f :=
lift_at_subst_formula_eq f s 0

lemma lift_at_subst_formula_small : ∀{l} (f : preformula L l) (s : term L) (n₁ n₂ m), 
 (f ↑' n₁ # (m + n₂ + 1))[s ↑' n₁ # m // n₂] = (f [s // n₂]) ↑' n₁ # (m + n₂)
| _ falsum       s n₁ n₂ m := by refl
| _ (t₁ ≃ t₂)    s n₁ n₂ m := 
    by dsimp; simp only [lift_at_subst_term_small, eq_self_iff_true, and_self]
| _ (rel R)      s n₁ n₂ m := by refl
| _ (apprel f t) s n₁ n₂ m := 
    by dsimp; simp only [*, lift_at_subst_term_small, eq_self_iff_true, and_self]
| _ (f₁ ⟹ f₂)   s n₁ n₂ m := 
    by dsimp; simp only [*, lift_at_subst_term_small, eq_self_iff_true, and_self]
| _ (∀' f)       s n₁ n₂ m := 
    by have := lift_at_subst_formula_small f s n₁ (n₂+1) m; dsimp; simp at this ⊢; exact this

lemma lift_at_subst_formula_small0 {l} (f : preformula L l) (s : term L) (n₁ m) :
 (f ↑' n₁ # (m + 1))[s ↑' n₁ # m // 0] = (f [s // 0]) ↑' n₁ # m :=
lift_at_subst_formula_small f s n₁ 0 m

lemma subst_formula2 : ∀{l} (f : preformula L l) (s₁ s₂ : term L) (n₁ n₂),
  f [s₁ // n₁] [s₂ // n₁ + n₂] = f [s₂ // n₁ + n₂ + 1] [s₁[s₂ // n₂] // n₁]
| _ falsum       s₁ s₂ n₁ n₂ := by refl
| _ (t₁ ≃ t₂)    s₁ s₂ n₁ n₂ := by simp [*, subst_term2]
| _ (rel R)      s₁ s₂ n₁ n₂ := by refl
| _ (apprel f t) s₁ s₂ n₁ n₂ := by simp [*, subst_term2]
| _ (f₁ ⟹ f₂)   s₁ s₂ n₁ n₂ := by simp*
| _ (∀' f)       s₁ s₂ n₁ n₂ := 
  by simp*; rw [add_comm n₂ 1, ←add_assoc, subst_formula2 f s₁ s₂ (n₁ + 1) n₂]; simp

lemma subst_formula2_zero {l} (f : preformula L l) (s₁ s₂ : term L) (n) :
  f [s₁ // 0] [s₂ // n] = f [s₂ // n + 1] [s₁[s₂ // n] // 0] :=
let h := subst_formula2 f s₁ s₂ 0 n in by simp only [fol.subst_formula, zero_add] at h; exact h

lemma lift_subst_formula_cancel : ∀{l} (f : preformula L l) (n : ℕ), (f ↑' 1 # (n+1))[&0 // n] = f
| _ falsum       n := by refl
| _ (t₁ ≃ t₂)    n := by simp [*, lift_subst_term_cancel]
| _ (rel R)      n := by refl
| _ (apprel f t) n := by simp [*, lift_subst_term_cancel]
| _ (f₁ ⟹ f₂)   n := by simp*
| _ (∀' f)       n := by simp*

@[simp] def count_quantifiers : ∀ {l}, preformula L l → ℕ
| _ falsum       := 0
| _ (t₁ ≃ t₂)    := 0
| _ (rel R)      := 0
| _ (apprel f t) := 0
| _ (f₁ ⟹ f₂)   := count_quantifiers f₁ + count_quantifiers f₂
| _ (∀' f)       := count_quantifiers f + 1

@[simp] def count_quantifiers_succ {l} (f : preformula L (l+1)) : count_quantifiers f = 0 :=
by cases f; refl

@[simp] lemma count_quantifiers_subst : ∀ {l} (f : preformula L l) (s : term L) (n : ℕ),
  count_quantifiers (f[s // n]) = count_quantifiers f
| _ falsum       s n := by refl
| _ (t₁ ≃ t₂)    s n := by refl
| _ (rel R)      s n := by refl
| _ (apprel f t) s n := by refl
| _ (f₁ ⟹ f₂)   s n := by simp*
| _ (∀' f)       s n := by simp*

/- Provability
* to decide: should Γ be a list or a set (or finset)?
* We use natural deduction as our deduction system, since that is most convenient to work with.
* All rules are motivated to work well with backwards reasoning.
-/
inductive prf : set (formula L) → formula L → Type u
| axm     {Γ A} (h : A ∈ Γ) : prf Γ A
| impI    {Γ : set $ formula L} {A B} (h : prf (insert A Γ) B) : prf Γ (A ⟹ B)
| impE    {Γ} (A) {B} (h₁ : prf Γ (A ⟹ B)) (h₂ : prf Γ A) : prf Γ B
| falsumE {Γ : set $ formula L} {A} (h : prf (insert ∼A Γ) ⊥) : prf Γ A
| allI    {Γ A} (h : prf (lift_formula1 '' Γ) A) : prf Γ (∀' A)
| allE₂   {Γ} A t (h : prf Γ (∀' A)) : prf Γ (A[t // 0])
| ref     (Γ t) : prf Γ (t ≃ t)
| subst₂  {Γ} (s t f) (h₁ : prf Γ (s ≃ t)) (h₂ : prf Γ (f[s // 0])) : prf Γ (f[t // 0])

export prf
infix ` ⊢ `:51 := fol.prf -- input: \|- or \vdash

def provable (T : set $ formula L) (f : formula L) := nonempty (T ⊢ f)
infix ` ⊢' `:51 := fol.provable -- input: \|- or \vdash

def allE {Γ} (A : formula L) (t) {B} (H₁ : Γ ⊢ ∀' A) (H₂ : A[t // 0] = B) : Γ ⊢ B :=
by induction H₂; exact allE₂ A t H₁

def subst {Γ} {s t} (f₁ : formula L) {f₂} (H₁ : Γ ⊢ s ≃ t) (H₂ : Γ ⊢ f₁[s // 0]) 
  (H₃ : f₁[t // 0] = f₂) : Γ ⊢ f₂ :=
by induction H₃; exact subst₂ s t f₁ H₁ H₂

def axm1 {Γ : set (formula L)} {A : formula L} : insert A Γ ⊢ A := by apply axm; left; refl
def axm2 {Γ : set (formula L)} {A B : formula L} : insert A (insert B Γ) ⊢ B := 
by apply axm; right; left; refl

def weakening {Γ Δ} {f : formula L} (H₁ : Γ ⊆ Δ) (H₂ : Γ ⊢ f) : Δ ⊢ f :=
begin
  induction H₂ generalizing Δ,
  { apply axm, exact H₁ H₂_h, },
  { apply impI, apply H₂_ih, apply insert_subset_insert, apply H₁ },
  { apply impE, apply H₂_ih_h₁, assumption, apply H₂_ih_h₂, assumption },
  { apply falsumE, apply H₂_ih, apply insert_subset_insert, apply H₁ },
  { apply allI, apply H₂_ih, apply image_subset _ H₁ },
  { apply allE₂, apply H₂_ih, assumption },
  { apply ref },
  { apply subst₂, apply H₂_ih_h₁, assumption, apply H₂_ih_h₂, assumption },
end

def prf_lift {Γ} {f : formula L} (n m : ℕ) (H : Γ ⊢ f) : (λf', f' ↑' n # m) '' Γ ⊢ f ↑' n # m :=
begin
  induction H generalizing m,
  { apply axm, apply mem_image_of_mem _ H_h },
  { apply impI, have h := @H_ih m, rw [image_insert_eq] at h, exact h },
  { apply impE, apply H_ih_h₁, apply H_ih_h₂ },
  { apply falsumE, have h := @H_ih m, rw [image_insert_eq] at h, exact h },
  { apply allI, rw [←image_comp], have h := @H_ih (m+1), rw [←image_comp] at h, 
    apply cast _ h, congr1, apply image_congr', intro f', symmetry,
    exact lift_formula_at2_small f' _ _ m.zero_le },
  { apply allE _ _ (H_ih m), apply lift_at_subst_formula_small0 },
  { apply ref },
  { apply subst _ (H_ih_h₁ m), 
    { have h := @H_ih_h₂ m, rw [←lift_at_subst_formula_small0] at h, exact h},
    rw [lift_at_subst_formula_small0] },
end

def substitution {Γ} {f : formula L} {t n} (H : Γ ⊢ f) : (λx, x[t // n]) '' Γ ⊢ f[t // n] :=
begin
  induction H generalizing n,
  { apply axm, apply mem_image_of_mem _ H_h },
  { apply impI, have h := @H_ih n, rw [image_insert_eq] at h, exact h },
  { apply impE, apply H_ih_h₁, apply H_ih_h₂ },
  { apply falsumE, have h := @H_ih n, rw [image_insert_eq] at h, exact h },
  { apply allI, rw [←image_comp], have h := @H_ih (n+1), rw [←image_comp] at h, 
    apply cast _ h, congr1, apply image_congr', intro,
    apply lift_subst_formula_large },
  { apply allE _ _ H_ih, symmetry, apply subst_formula2_zero },
  { apply ref },
  { apply subst _ H_ih_h₁, { have h := @H_ih_h₂ n, rw [subst_formula2_zero] at h, exact h}, 
    rw [subst_formula2_zero] },
end

def weakening1 {Γ} {f₁ f₂ : formula L} (H : Γ ⊢ f₂) : insert f₁ Γ ⊢ f₂ :=
weakening (subset_insert f₁ Γ) H

def weakening2 {Γ} {f₁ f₂ f₃ : formula L} (H : insert f₁ Γ ⊢ f₂) : insert f₁ (insert f₃ Γ) ⊢ f₂ :=
weakening (insert_subset_insert (subset_insert _ Γ)) H

def deduction {Γ} {A B : formula L} (H : Γ ⊢ A ⟹ B) : insert A Γ ⊢ B :=
impE A (weakening1 H) axm1

def exfalso {Γ} {A : formula L} (H : Γ ⊢ falsum) : Γ ⊢ A :=
falsumE (weakening1 H)

def notI {Γ} {A : formula L} (H : Γ ⊢ A ⟹ falsum) : Γ ⊢ ∼ A :=
  by {rw[not], assumption}

def andI {Γ} {f₁ f₂ : formula L} (H₁ : Γ ⊢ f₁) (H₂ : Γ ⊢ f₂) : Γ ⊢ f₁ ⊓ f₂ :=
begin 
  apply impI, apply impE f₂,
  { apply impE f₁, apply axm1, exact weakening1 H₁ },
  { exact weakening1 H₂ }
end

def andE1 {Γ f₁} (f₂ : formula L) (H : Γ ⊢ f₁ ⊓ f₂) : Γ ⊢ f₁ :=
begin 
  apply falsumE, apply impE _ (weakening1 H), apply impI, apply exfalso,
  apply impE f₁; [apply axm2, apply axm1]
end

def andE2 {Γ} (f₁ : formula L) {f₂} (H : Γ ⊢ f₁ ⊓ f₂) : Γ ⊢ f₂ :=
begin apply falsumE, apply impE _ (weakening1 H), apply impI, apply axm2 end

def orI1 {Γ} {A B : formula L} (H : Γ ⊢ A) : Γ ⊢ A ⊔ B :=
begin apply impI, apply exfalso, refine impE _ _ (weakening1 H), apply axm1 end

def orI2 {Γ} {A B : formula L} (H : Γ ⊢ B) : Γ ⊢ A ⊔ B :=
impI $ weakening1 H

def orE {Γ} {A B C : formula L} (H₁ : Γ ⊢ A ⊔ B) (H₂ : insert A Γ ⊢ C) (H₃ : insert B Γ ⊢ C) : 
  Γ ⊢ C :=
begin
  apply falsumE, apply impE C, { apply axm1 },
  apply impE B, { apply impI, exact weakening2 H₃ },
  apply impE _ (weakening1 H₁),
  apply impI (impE _ axm2 (weakening2 H₂))
end

def biimpI {Γ} {f₁ f₂ : formula L} (H₁ : insert f₁ Γ ⊢ f₂) (H₂ : insert f₂ Γ ⊢ f₁) : Γ ⊢ f₁ ⇔ f₂ :=
by apply andI; apply impI; assumption

def biimpE1 {Γ} {f₁ f₂ : formula L} (H : Γ ⊢ f₁ ⇔ f₂) : insert f₁ Γ ⊢ f₂ := deduction (andE1 _ H)
def biimpE2 {Γ} {f₁ f₂ : formula L} (H : Γ ⊢ f₁ ⇔ f₂) : insert f₂ Γ ⊢ f₁ := deduction (andE2 _ H)

def exI {Γ f} (t : term L) (H : Γ ⊢ f [t // 0]) : Γ ⊢ ∃' f :=
begin
  apply impI, 
  apply impE (f[t // 0]) _ (weakening1 H),
  apply allE₂ ∼f t axm1,
end

def exE {Γ} {f₁ f₂ : formula L} (t : term L) (H₁ : Γ ⊢ ∃' f₁) 
  (H₂ : insert f₁ (lift_formula1 '' Γ) ⊢ lift_formula1 f₂) : Γ ⊢ f₂ :=
begin
  apply falsumE, apply impE _ (weakening1 H₁), apply allI, apply impI, 
  rw [image_insert_eq], apply impE _ axm2, apply weakening2 H₂
end

def ex_not_of_not_all {Γ} {f : formula L} (H : Γ ⊢ ∼ ∀' f) : Γ ⊢ ∃' ∼ f :=
begin
  apply falsumE, apply impE _ (weakening1 H), apply allI, apply falsumE,
  rw [image_insert_eq], apply impE _ axm2, apply exI &0,
  rw [lift_subst_formula_cancel], exact axm1
end

def not_and_self {Γ : set (formula L)} {f : formula L} (H : Γ ⊢ f ⊓ ∼f) : Γ ⊢ ⊥ :=
impE f (andE2 f H) (andE1 ∼f H)

-- def andE1 {Γ f₁} (f₂ : formula L) (H : Γ ⊢ f₁ ⊓ f₂) : Γ ⊢ f₁ :=
def symm {Γ} {s t : term L} (H : Γ ⊢ s ≃ t) : Γ ⊢ t ≃ s :=
begin 
  apply subst (&0 ≃ s ↑ 1) H; rw [subst_formula_equal, lift_term1_subst_term, subst_term_var0],
  apply ref
end

def trans {Γ} {t₁ t₂ t₃ : term L} (H : Γ ⊢ t₁ ≃ t₂) (H' : Γ ⊢ t₂ ≃ t₃) : Γ ⊢ t₁ ≃ t₃ :=
begin 
  apply subst (t₁ ↑ 1 ≃ &0) H'; rw [subst_formula_equal, lift_term1_subst_term, subst_term_var0],
  exact H
end

def congr {Γ} {t₁ t₂ : term L} (s : term L) (H : Γ ⊢ t₁ ≃ t₂) : Γ ⊢ s[t₁ // 0] ≃ s[t₂ // 0] :=
begin 
  apply subst (s[t₁ // 0] ↑ 1 ≃ s) H, 
  { rw [subst_formula_equal, lift_term1_subst_term], apply ref },
  { rw [subst_formula_equal, lift_term1_subst_term] }
end

def app_congr {Γ} {t₁ t₂ : term L} (s : preterm L 1) (H : Γ ⊢ t₁ ≃ t₂) : Γ ⊢ app s t₁ ≃ app s t₂ :=
begin 
  have h := congr (app (s ↑ 1) &0) H, simp at h, exact h
end

def apprel_congr {Γ} {t₁ t₂ : term L} (f : preformula L 1) (H : Γ ⊢ t₁ ≃ t₂)
  (H₂ : Γ ⊢ apprel f t₁) : Γ ⊢ apprel f t₂ :=
begin 
  apply subst (apprel (f ↑ 1) &0) H; simp, exact H₂
end

def imp_trans {Γ} {f₁ f₂ f₃ : formula L} (H₁ : Γ ⊢ f₁ ⟹ f₂) (H₂ : Γ ⊢ f₂ ⟹ f₃) : Γ ⊢ f₁ ⟹ f₃ :=
begin
  apply impI, apply impE _ (weakening1 H₂), apply impE _ (weakening1 H₁) axm1
end

def biimp_refl (Γ : set (formula L)) (f : formula L) : Γ ⊢ f ⇔ f :=
by apply biimpI; apply axm1

def biimp_trans {Γ} {f₁ f₂ f₃ : formula L} (H₁ : Γ ⊢ f₁ ⇔ f₂) (H₂ : Γ ⊢ f₂ ⇔ f₃) : Γ ⊢ f₁ ⇔ f₃ :=
begin
  apply andI; apply imp_trans, 
  apply andE1 _ H₁, apply andE1 _ H₂, apply andE2 _ H₂, apply andE2 _ H₁
end

def equal_preterms (T : set (formula L)) {l} (t₁ t₂ : preterm L l) : Type u :=
∀(ts : dvector (term L) l), T ⊢ apps t₁ ts ≃ apps t₂ ts

def equal_preterms_app {T : set (formula L)} {l} {t t' : preterm L (l+1)} {s s' : term L} 
  (Ht : equal_preterms T t t') (Hs : T ⊢ s ≃ s') : equal_preterms T (app t s) (app t' s') :=
begin
  intro xs,
  apply trans (Ht (xs.cons s)),
  have h := congr (apps (t' ↑ 1) (&0 :: xs.map lift_term1)) Hs, 
  simp [dvector.map_congr (λt, lift_term1_subst_term t s')] at h,
  exact h
end

@[refl] def equal_preterms_refl (T : set (formula L)) {l} (t : preterm L l) : equal_preterms T t t :=
λxs, ref T (apps t xs)

def equiv_preformulae (T : set (formula L)) {l} (f₁ f₂ : preformula L l) : Type u :=
∀(ts : dvector (term L) l), T ⊢ apps_rel f₁ ts ⇔ apps_rel f₂ ts

def equiv_preformulae_apprel {T : set (formula L)} {l} {f f' : preformula L (l+1)} {s s' : term L} 
  (Ht : equiv_preformulae T f f') (Hs : T ⊢ s ≃ s') : 
    equiv_preformulae T (apprel f s) (apprel f' s') :=
begin
  intro xs, 
  apply biimp_trans (Ht (xs.cons s)),
  apply subst (apps_rel (f' ↑ 1) ((s :: xs).map lift_term1) ⇔ 
               apps_rel (f' ↑ 1) (&0 :: xs.map lift_term1)) Hs; 
    simp [dvector.map_congr (λt, lift_term1_subst_term t s')],
  apply biimp_refl, refl
end

@[refl] def equiv_preformulae_refl (T : set (formula L)) {l} (f : preformula L l) : 
  equiv_preformulae T f f :=
λxs, biimp_refl T (apps_rel f xs)

def impI' {Γ : set $ formula L} {A B} (h : insert A Γ ⊢' B) : Γ ⊢' (A ⟹ B) := h.map impI
def impE' {Γ} (A : formula L) {B} (h₁ : Γ ⊢' A ⟹ B) (h₂ : Γ ⊢' A) : Γ ⊢' B := h₁.map2 (impE _) h₂
def falsumE' {Γ : set $ formula L} {A} (h : insert ∼A Γ ⊢' ⊥ ) : Γ ⊢' A := h.map falsumE
def allI' {Γ} {A : formula L} (h : lift_formula1 '' Γ ⊢' A) : Γ ⊢' ∀' A := h.map allI
def allE' {Γ} (A : formula L) (t) {B} (H₁ : Γ ⊢' ∀' A) (H₂ : A[t // 0] = B) : Γ ⊢' B :=
H₁.map (λx, allE _ _ x H₂)
def allE₂' {Γ} {A} {t : term L} (h : Γ ⊢' ∀' A) : Γ ⊢' A[t // 0] := h.map (λx, allE _ _ x rfl)
def ref' (Γ) (t : term L) : Γ ⊢' (t ≃ t) := ⟨ref Γ t⟩
def subst' {Γ} {s t} (f₁ : formula L) {f₂} (H₁ : Γ ⊢' s ≃ t) (H₂ : Γ ⊢' f₁[s // 0]) 
  (H₃ : f₁[t // 0] = f₂) : Γ ⊢' f₂ := 
H₁.map2 (λx y, subst _ x y H₃) H₂
def subst₂' {Γ} (s t) (f : formula L) (h₁ : Γ ⊢' s ≃ t) (h₂ : Γ ⊢' f[s // 0]) : Γ ⊢' f[t // 0] := 
h₁.map2 (subst₂ _ _ _) h₂

def weakening' {Γ Δ} {f : formula L} (H₁ : Γ ⊆ Δ) (H₂ : Γ ⊢' f) : Δ ⊢' f := H₂.map $ weakening H₁
def weakening1' {Γ} {f₁ f₂ : formula L} (H : Γ ⊢' f₂) : insert f₁ Γ ⊢' f₂ := H.map weakening1
def weakening2' {Γ} {f₁ f₂ f₃ : formula L} (H : insert f₁ Γ ⊢' f₂) : insert f₁ (insert f₃ Γ) ⊢' f₂ :=
H.map weakening2

lemma apprel_congr' {Γ} {t₁ t₂ : term L} (f : preformula L 1) (H : Γ ⊢ t₁ ≃ t₂) :
  Γ ⊢' apprel f t₁ ↔ Γ ⊢' apprel f t₂ :=
⟨nonempty.map $ apprel_congr f H, nonempty.map $ apprel_congr f $ symm H⟩

lemma prf_all_iff {Γ : set (formula L)} {f} : Γ ⊢' ∀' f ↔ lift_formula1 '' Γ ⊢' f :=
begin
  split,
  { intro H, rw [←lift_subst_formula_cancel f 0], 
    apply allE₂', apply H.map (prf_lift 1 0) },
  { exact allI' }
end

lemma iff_of_biimp {Γ} {f₁ f₂ : formula L} (H : Γ ⊢' f₁ ⇔ f₂) : Γ ⊢' f₁ ↔ Γ ⊢' f₂ :=
⟨impE' _ $ H.map (andE1 _), impE' _ $ H.map (andE2 _)⟩ 

/- model theory -/

/- an L-structure is a type S with interpretations of the functions and relations on S -/
variable (L)
structure Structure :=
(carrier : Type u) 
(fun_map : ∀{n}, L.functions n → dvector carrier n → carrier)
(rel_map : ∀{n}, L.relations n → dvector carrier n → Prop) 
variable {L}
instance has_coe_Structure : has_coe_to_sort (@fol.Structure L) :=
⟨Type u, Structure.carrier⟩

/- realization of terms -/
@[simp] def realize_term {S : Structure L} (v : ℕ → S) : 
  ∀{l} (t : preterm L l) (xs : dvector S l), S.carrier
| _ &k          xs := v k
| _ (func f)    xs := S.fun_map f xs
| _ (app t₁ t₂) xs := realize_term t₁ $ realize_term t₂ ([])::xs

lemma realize_term_congr {S : Structure L} {v v' : ℕ → S} (h : ∀n, v n = v' n) : 
  ∀{l} (t : preterm L l) (xs : dvector S l), realize_term v t xs = realize_term v' t xs
| _ &k          xs := h k
| _ (func f)    xs := by refl
| _ (app t₁ t₂) xs := by dsimp; rw [realize_term_congr t₁, realize_term_congr t₂]

lemma realize_term_subst {S : Structure L} (v : ℕ → S) : ∀{l} (n : ℕ) (t : preterm L l) 
  (s : term L) (xs : dvector S l), realize_term (v[realize_term v (s ↑ n) ([]) // n]) t xs = realize_term v (t[s // n]) xs
| _ n &k          s [] := 
  by apply lt_by_cases k n; intro h;[simp [h], {subst h; simp}, simp [h]]
| _ n (func f)    s xs := by refl
| _ n (app t₁ t₂) s xs := by dsimp; simp*

lemma realize_term_subst_lift {S : Structure L} (v : ℕ → S) (x : S) (m : ℕ) : ∀{l} (t : preterm L l)
  (xs : dvector S l), realize_term (v [x // m]) (t ↑' 1 # m) xs = realize_term v t xs
| _ &k          [] := 
  begin 
    by_cases h : m ≤ k, 
    { have : m < k + 1, from lt_succ_of_le h, simp* },
    { have : k < m, from lt_of_not_ge h, simp* }
  end
| _ (func f)    xs := by refl
| _ (app t₁ t₂) xs := by simp*

/- realization of formulas -/
@[simp] def realize_formula {S : Structure L} : ∀{l}, (ℕ → S) → preformula L l → dvector S l → Prop
| _ v falsum       xs := false
| _ v (t₁ ≃ t₂)    xs := realize_term v t₁ xs = realize_term v t₂ xs
| _ v (rel R)      xs := S.rel_map R xs
| _ v (apprel f t) xs := realize_formula v f $ realize_term v t ([])::xs
| _ v (f₁ ⟹ f₂)   xs := realize_formula v f₁ xs → realize_formula v f₂ xs
| _ v (∀' f)       xs := ∀(x : S), realize_formula (v [x // 0]) f xs

lemma realize_formula_congr {S : Structure L} : ∀{l} {v v' : ℕ → S} (h : ∀n, v n = v' n) 
  (f : preformula L l) (xs : dvector S l), realize_formula v f xs ↔ realize_formula v' f xs
| _ v v' h falsum       xs := by refl
| _ v v' h (t₁ ≃ t₂)    xs := by simp [realize_term_congr h]
| _ v v' h (rel R)      xs := by refl
| _ v v' h (apprel f t) xs := by simp [realize_term_congr h]; rw [realize_formula_congr h]
| _ v v' h (f₁ ⟹ f₂)   xs := by dsimp; rw [realize_formula_congr h, realize_formula_congr h]
| _ v v' h (∀' f)       xs := 
  by apply forall_congr; intro x; apply realize_formula_congr; intro n; 
     apply subst_realize_congr h

lemma realize_formula_subst {S : Structure L} : ∀{l} (v : ℕ → S) (n : ℕ) (f : preformula L l) 
  (s : term L) (xs : dvector S l), realize_formula (v[realize_term v (s ↑ n) ([]) // n]) f xs ↔ realize_formula v (f[s // n]) xs
| _ v n falsum       s xs := by refl
| _ v n (t₁ ≃ t₂)    s xs := by simp [realize_term_subst]
| _ v n (rel R)      s xs := by refl
| _ v n (apprel f t) s xs := by simp [realize_term_subst]; rw realize_formula_subst
| _ v n (f₁ ⟹ f₂)   s xs := by apply imp_congr; apply realize_formula_subst
| _ v n (∀' f)       s xs := 
  begin 
    apply forall_congr, intro x, rw [←realize_formula_subst], apply realize_formula_congr, 
    intro k, rw [subst_realize2_0, ←realize_term_subst_lift v x 0, lift_term_def, lift_term2]
  end

lemma realize_formula_subst0 {S : Structure L} {l} (v : ℕ → S) (f : preformula L l) (s : term L) (xs : dvector S l) :
  realize_formula (v[realize_term v s ([]) // 0]) f xs ↔ realize_formula v (f[s // 0]) xs :=
by have h := realize_formula_subst v 0 f s; simp at h; exact h xs

lemma realize_formula_subst_lift {S : Structure L} : ∀{l} (v : ℕ → S) (x : S) (m : ℕ) 
  (f : preformula L l) (xs : dvector S l), realize_formula (v [x // m]) (f ↑' 1 # m) xs = realize_formula v f xs
| _ v x m falsum       xs := by refl
| _ v x m (t₁ ≃ t₂)    xs := by simp [realize_term_subst_lift]
| _ v x m (rel R)      xs := by refl
| _ v x m (apprel f t) xs := by simp [realize_term_subst_lift]; rw realize_formula_subst_lift
| _ v x m (f₁ ⟹ f₂)   xs := by apply imp_eq_congr; apply realize_formula_subst_lift
| _ v x m (∀' f)       xs := 
  begin 
    apply forall_eq_congr, intro x', 
    rw [realize_formula_congr (subst_realize2_0 _ _ _ _), realize_formula_subst_lift]
  end

/- the following definitions of provability and satisfiability are not exactly how you normally define them, since we define it for formulae instead of sentences. If all the formulae happen to be sentences, then these definitions are equivalent to the normal definitions (the realization of closed terms and sentences are independent of the realizer v). 
 -/
def all_prf (T T' : set (formula L)) := ∀{{f}}, f ∈ T' → T ⊢ f
infix ` ⊢ `:51 := fol.all_prf -- input: |- or \vdash

def satisfied_in (S : Structure L) (f : formula L) := ∀(v : ℕ → S), realize_formula v f ([])
infix ` ⊨ `:51 := fol.satisfied_in -- input using \|= or \vDash, but not using \models 

def all_satisfied_in (S : Structure L) (T : set (formula L)) := ∀{{f}}, f ∈ T → S ⊨ f
infix ` ⊨ `:51 := fol.all_satisfied_in -- input using \|= or \vDash, but not using \models 

def satisfied (T : set (formula L)) (f : formula L) := 
∀(S : Structure L) (v : ℕ → S), (∀f' ∈ T, realize_formula v (f' : formula L) ([])) → 
  realize_formula v f ([])

infix ` ⊨ `:51 := fol.satisfied -- input using \|= or \vDash, but not using \models 

def all_satisfied (T T' : set (formula L)) := ∀{{f}}, f ∈ T' → T ⊨ f
infix ` ⊨ `:51 := fol.all_satisfied -- input using \|= or \vDash, but not using \models 

def satisfied_in_trans {S : Structure L} {T : set (formula L)} {f : formula L} (H' : S ⊨ T) (H : T ⊨ f) :
  S ⊨ f :=
λv, H S v $ λf' hf', H' hf' v

def all_satisfied_in_trans  {S : Structure L} {T T' : set (formula L)} (H' : S ⊨ T) (H : T ⊨ T') :
  S ⊨ T' :=
λf hf, satisfied_in_trans H' $ H hf

def satisfied_of_mem {T : set (formula L)} {f : formula L} (hf : f ∈ T) : T ⊨ f :=
λS v h, h f hf

def all_satisfied_of_subset {T T' : set (formula L)} (h : T' ⊆ T) : T ⊨ T' :=
λf hf, satisfied_of_mem $ h hf

def satisfied_trans {T₁ T₂ : set (formula L)} {f : formula L} (H' : T₁ ⊨ T₂) (H : T₂ ⊨ f) : T₁ ⊨ f :=
λS v h, H S v $ λf' hf', H' hf' S v h

def all_satisfied_trans {T₁ T₂ T₃ : set (formula L)} (H' : T₁ ⊨ T₂) (H : T₂ ⊨ T₃) : T₁ ⊨ T₃ :=
λf hf, satisfied_trans H' $ H hf

def satisfied_weakening {T T' : set (formula L)} (H : T ⊆ T') {f : formula L} (HT : T ⊨ f) : T' ⊨ f :=
λS v h, HT S v $ λf' hf', h f' $ H hf'

/- soundness for a set of formulae -/
lemma formula_soundness {Γ : set (formula L)} {A : formula L} (H : Γ ⊢ A) : Γ ⊨ A :=
begin
  intro S, induction H; intros v h,
  { apply h, apply H_h },
  { intro ha, apply H_ih, intros f hf, induction hf, { subst hf, assumption }, apply h f hf },
  { exact H_ih_h₁ v h (H_ih_h₂ v h) },
  { apply classical.by_contradiction, intro ha, 
    apply H_ih v, intros f hf, induction hf, { cases hf, exact ha }, apply h f hf },
  { intro x, apply H_ih, intros f hf, cases (mem_image _ _ _).mp hf with f' hf', induction hf', 
    induction hf'_right, rw [realize_formula_subst_lift v x 0 f'], exact h f' hf'_left },
  { rw [←realize_formula_subst0], apply H_ih v h (realize_term v H_t ([])) },
  { dsimp, refl },
  { have h' := H_ih_h₁ v h, dsimp at h', rw [←realize_formula_subst0, ←h', realize_formula_subst0],
    apply H_ih_h₂ v h },
end

/- sentences and theories -/
variable (L)
inductive bounded_preterm (n : ℕ) : ℕ → Type u
| bd_var {} : ∀ (k : fin n), bounded_preterm 0
| bd_func {} : ∀ {l : ℕ} (f : L.functions l), bounded_preterm l
| bd_app : ∀ {l : ℕ} (t : bounded_preterm (l + 1)) (s : bounded_preterm 0), bounded_preterm l
export bounded_preterm

def bounded_term    (n)   := bounded_preterm L n 0
def closed_preterm  (l)   := bounded_preterm L 0 l
def closed_term           := closed_preterm L 0
variable {L}

prefix `&`:max := bd_var
def bd_const {n} (c : L.constants) : bounded_term L n := bd_func c

@[simp] def bd_apps {n} : ∀{l}, bounded_preterm L n l → dvector (bounded_term L n) l → 
  bounded_term L n
| _ t []       := t
| _ t (t'::ts) := bd_apps (bd_app t t') ts

namespace bounded_preterm
@[simp] protected def fst {n} : ∀{l}, bounded_preterm L n l → preterm L l
| _ &k         := &k.1
| _ (bd_func f)  := func f
| _ (bd_app t s) := app (fst t) (fst s)

local attribute [extensionality] fin.eq_of_veq
@[extensionality] protected def eq {n} : ∀{l} {t₁ t₂ : bounded_preterm L n l} (h : t₁.fst = t₂.fst),
  t₁ = t₂
| _ &k &k'                        h := by injection h with h'; congr1; ext; exact h'
| _ &k (bd_func f')               h := by injection h
| _ &k (bd_app t₁' t₂')           h := by injection h
| _ (bd_func f) &k'               h := by injection h
| _ (bd_func f) (bd_func f')      h := by injection h with h'; rw h'
| _ (bd_func f) (bd_app t₁' t₂')  h := by injection h
| _ (bd_app t₁ t₂) &k'            h := by injection h
| _ (bd_app t₁ t₂) (bd_func f')   h := by injection h
| _ (bd_app t₁ t₂) (bd_app t₁' t₂') h := by injection h with h₁ h₂; congr1; apply eq; assumption

@[simp] protected def cast {n m} (h : n ≤ m) : ∀ {l} (t : bounded_preterm L n l), 
  bounded_preterm L m l
| _ &k           := &(k.cast_le h)
| _ (bd_func f)  := bd_func f
| _ (bd_app t s) := bd_app t.cast s.cast

protected def cast_eq {n m l} (h : n = m) (t : bounded_preterm L n l) : bounded_preterm L m l :=
t.cast $ le_of_eq h

protected def cast1 {n l} (t : bounded_preterm L n l) : bounded_preterm L (n+1) l :=
t.cast $ n.le_add_right 1

@[simp] lemma cast_fst {n m} (h : n ≤ m) : ∀ {l} (t : bounded_preterm L n l), (t.cast h).fst = t.fst
| _ &k           := by refl
| _ (bd_func f)  := by refl
| _ (bd_app t s) := by dsimp; simp [cast_fst]

@[simp] lemma cast_eq_fst {n m l} (h : n = m) (t : bounded_preterm L n l) : 
  (t.cast_eq h).fst = t.fst := t.cast_fst _
@[simp] lemma cast1_fst {n l} (t : bounded_preterm L n l) : 
  t.cast1.fst = t.fst := t.cast_fst _

end bounded_preterm

namespace closed_preterm

protected def cast0 (n) {l} (t : closed_preterm L l) : bounded_preterm L n l :=
t.cast n.zero_le

@[simp] lemma cast0_fst {n l : ℕ} (t : closed_preterm L l) : 
  (t.cast0 n).fst = t.fst :=
cast_fst _ _

end closed_preterm

@[elab_as_eliminator] def bounded_term.rec {n} {C : bounded_term L n → Sort v}
  (hvar : ∀(k : fin n), C &k)
  (hfunc : Π {l} (f : L.functions l) (ts : dvector (bounded_term L n) l) 
    (ih_ts : ∀t, ts.pmem t → C t), C (bd_apps (bd_func f) ts)) : 
  ∀(t : bounded_term L n), C t :=
have h : ∀{l} (t : bounded_preterm L n l) (ts : dvector (bounded_term L n) l) 
  (ih_ts : ∀s, ts.pmem s → C s), C (bd_apps t ts),
begin
  intros, induction t; try {rw ts.zero_eq},
  { apply hvar }, 
  { apply hfunc t_f ts ih_ts }, 
  { apply t_ih_t (t_s::ts), intros t ht, 
    cases ht, 
    { induction ht, apply t_ih_s ([]), intros s hs, cases hs },
    { exact ih_ts t ht }},
end,
λt, h t ([]) (by intros s hs; cases hs)

lemma lift_bounded_term_irrel {n : ℕ} : ∀{l} (t : bounded_preterm L n l) (n') {m : ℕ}
  (h : n ≤ m), t.fst ↑' n' # m = t.fst
| _ &k           n' m h := 
  have h' : ¬(m ≤ k.1), from not_le_of_lt (lt_of_lt_of_le k.2 h), by simp [h']
| _ (bd_func f)  n' m h := by refl
| _ (bd_app t s) n' m h := by simp [lift_bounded_term_irrel t n' h, lift_bounded_term_irrel s n' h]

@[simp] def realize_bounded_term {S : Structure L} {n} (v : dvector S n) : 
  ∀{l} (t : bounded_preterm L n l) (xs : dvector S l), S.carrier
| _ &k             xs := v.nth k.1 k.2
| _ (bd_func f)    xs := S.fun_map f xs
| _ (bd_app t₁ t₂) xs := realize_bounded_term t₁ $ realize_bounded_term t₂ ([])::xs

@[reducible] def realize_closed_term (S : Structure L) (t : closed_term L) : S :=
realize_bounded_term ([]) t ([])

lemma realize_bounded_term_eq {S : Structure L} {n} {v₁ : dvector S n} {v₂ : ℕ → S}
  (hv : ∀k (hk : k < n), v₁.nth k hk = v₂ k) : ∀{l} (t : bounded_preterm L n l)
  (xs : dvector S l), realize_bounded_term v₁ t xs = realize_term v₂ t.fst xs
| _ &k             xs := hv k.1 k.2
| _ (bd_func f)    xs := by refl
| _ (bd_app t₁ t₂) xs := by dsimp; simp [realize_bounded_term_eq]

lemma realize_bounded_term_irrel' {S : Structure L} {n n'} {v₁ : dvector S n} {v₂ : dvector S n'} 
  (h : ∀m (hn : m < n) (hn' : m < n'), v₁.nth m hn = v₂.nth m hn')
  {l} (t : bounded_preterm L n l) (t' : bounded_preterm L n' l) 
  (ht : t.fst = t'.fst) (xs : dvector S l) : 
  realize_bounded_term v₁ t xs = realize_bounded_term v₂ t' xs :=
begin
  induction t; cases t'; injection ht with ht₁ ht₂,
  { simp, cases t'_1; dsimp at ht₁, subst ht₁, exact h t.val t.2 t'_1_is_lt },
  { subst ht₁, refl },
  { simp [t_ih_t t'_t ht₁, t_ih_s t'_s ht₂] }
end

lemma realize_bounded_term_irrel {S : Structure L} {n} {v₁ : dvector S n}
  (t : bounded_term L n) (t' : closed_term L) (ht : t.fst = t'.fst) (xs : dvector S 0) :
  realize_bounded_term v₁ t xs = realize_closed_term S t' :=
by cases xs; exact realize_bounded_term_irrel' 
  (by intros m hm hm'; exfalso; exact not_lt_zero m hm') t t' ht ([])

@[simp] def lift_bounded_term_at {n} : ∀{l} (t : bounded_preterm L n l) (n' m : ℕ), 
  bounded_preterm L (n + n') l
| _ &k             n' m := if m ≤ k.1 then &(k.add_nat n') else &(k.cast_le $ n.le_add_right n')
| _ (bd_func f)    n' m := bd_func f
| _ (bd_app t₁ t₂) n' m := bd_app (lift_bounded_term_at t₁ n' m) $ lift_bounded_term_at t₂ n' m

notation t ` ↑' `:90 n ` # `:90 m:90 := fol.lift_bounded_term_at t n m -- input ↑ with \u or \upa

@[reducible] def lift_bounded_term {n l} (t : bounded_preterm L n l) (n' : ℕ) : 
  bounded_preterm L (n + n') l := t ↑' n' # 0
infix ` ↑ `:100 := fol.lift_bounded_term -- input ↑' with \u or \upa

@[reducible, simp] def lift_bounded_term1 {n' l} (t : bounded_preterm L n' l) : 
  bounded_preterm L (n'+1) l := 
t ↑ 1

@[simp] lemma lift_bounded_term_fst {n} : ∀{l} (t : bounded_preterm L n l) (n' m : ℕ), 
  (t ↑' n' # m).fst = t.fst ↑' n' # m
| _ &k             n' m := by by_cases h : m ≤ k.1; simp [h, -add_comm]; refl
| _ (bd_func f)    n' m := by refl
| _ (bd_app t₁ t₂) n' m := by simp [lift_bounded_term_fst]

-- @[simp] def lift_closed_term_at : ∀{l} (t : closed_preterm L l) (n' m : ℕ), 
--   bounded_preterm L n' l
-- | _ &k             n' m := if m ≤ k then _ else &(k.cast_le $ n.le_add_right n')
-- | _ (bd_func f)    n' m := bd_func f
-- | _ (bd_app t₁ t₂) n' m := bd_app (lift_bounded_term_at t₁ n' m) $ lift_bounded_term_at t₂ n' m


-- def lift_bounded_term_at0 {n m l} {t : preterm L l} (ht : bounded_term 0 t) : bounded_term n (t ↑' n # m) :=
-- by have := lift_bounded_term_at n m ht; rw [zero_add] at this; exact this

/-- this is t[s//n] for bounded formulae-/
def subst_bounded_term {n n'} : ∀{l} (t : bounded_preterm L (n+n'+1) l)  
  (s : bounded_term L n'), bounded_preterm L (n+n') l
| _ &k             s := 
  if h : k.1 < n then &⟨k.1, lt_of_lt_of_le h $ n.le_add_right n'⟩ else 
  if h' : n < k.1 then &⟨k.1-1, (nat.sub_lt_right_iff_lt_add $ one_le_of_lt h').mpr k.2⟩ else 
  (s ↑ n).cast $ le_of_eq $ add_comm n' n
| _ (bd_func f)    s := bd_func f
| _ (bd_app t₁ t₂) s := bd_app (subst_bounded_term t₁ s) (subst_bounded_term t₂ s)

@[simp] lemma subst_bounded_term_var_lt {n n'} (s : bounded_term L n') (k : fin (n+n'+1)) 
  (h : k.1 < n) : (subst_bounded_term &k s).fst = &k.1 :=
by simp [h, fol.subst_bounded_term]

@[simp] lemma subst_bounded_term_var_gt {n n'} (s : bounded_term L n') (k : fin (n+n'+1)) 
  (h : n < k.1) : (subst_bounded_term &k s).fst = &(k.1-1) :=
have h' : ¬(k.1 < n), from lt_asymm h,
by simp [h, h', fol.subst_bounded_term]

@[simp] lemma subst_bounded_term_var_eq {n n'} (s : bounded_term L n') (k : fin (n+n'+1)) 
  (h : k.1 = n) : (subst_bounded_term &k s).fst = s.fst ↑ n :=
have h₂ : ¬(k.1 < n), from λh', lt_irrefl _ $ lt_of_lt_of_le h' $ le_of_eq h.symm,
have h₃ : ¬(n < k.1), from λh', lt_irrefl _ $ lt_of_lt_of_le h' $ le_of_eq h,
by simp [subst_bounded_term, h₂, h₃]

@[simp] lemma subst_bounded_term_bd_app {n n' l} (t₁ : bounded_preterm L (n+n'+1) (l+1)) 
  (t₂ : bounded_term L (n+n'+1)) (s : bounded_term L n') : 
  subst_bounded_term (bd_app t₁ t₂) s = bd_app (subst_bounded_term t₁ s) (subst_bounded_term t₂ s) :=
by refl

@[simp] lemma subst_bounded_term_fst {n n'} : ∀{l} (t : bounded_preterm L (n+n'+1) l)
  (s : bounded_term L n'), (subst_bounded_term t s).fst = t.fst[s.fst//n]
| _ &k             s := by apply lt_by_cases k.1 n; intro h; simp [h]
| _ (bd_func f)    s := by refl
| _ (bd_app t₁ t₂) s := by simp*

-- @[simp] lemma subst_bounded_term_var_eq' {n n'} (s : bounded_term L n') (h : n < n+n'+1) : 
--   (subst_bounded_term &⟨n, h⟩ s).fst = s.fst ↑ n :=
-- by simp [subst_bounded_term]

def subst0_bounded_term {n l} (t : bounded_preterm L (n+1) l)
  (s : bounded_term L n) : bounded_preterm L n l :=
(subst_bounded_term (t.cast_eq $ (n+1).zero_add.symm) s).cast_eq $ n.zero_add

notation t `[`:max s ` /0]`:0 := fol.subst0_bounded_term t s

@[simp] lemma subst0_bounded_term_fst {n l} (t : bounded_preterm L (n+1) l)
  (s : bounded_term L n) : t[s/0].fst = t.fst[s.fst//0] :=
by simp [subst0_bounded_term]

def substmax_bounded_term {n l} (t : bounded_preterm L (n+1) l)
  (s : closed_term L) : bounded_preterm L n l :=
subst_bounded_term (by exact t) s

@[simp] lemma substmax_bounded_term_bd_app {n l} (t₁ : bounded_preterm L (n+1) (l+1)) 
  (t₂ : bounded_term L (n+1)) (s : closed_term L) : 
  substmax_bounded_term (bd_app t₁ t₂) s = 
  bd_app (substmax_bounded_term t₁ s) (substmax_bounded_term t₂ s) :=
by refl

def substmax_eq_subst0_term {l} (t : bounded_preterm L 1 l) (s : closed_term L) :
  t[s/0] = substmax_bounded_term t s :=
by ext; simp [substmax_bounded_term]

def substmax_var_lt {n} (k : fin (n+1)) (s : closed_term L) (h : k.1 < n) :
  substmax_bounded_term &k s = &⟨k.1, h⟩ :=
by ext; simp [substmax_bounded_term, h]

def substmax_var_eq {n} (k : fin (n+1)) (s : closed_term L) (h : k.1 = n) :
  substmax_bounded_term &k s = s.cast0 n :=
begin
  ext, simp [substmax_bounded_term, h], 
  dsimp only [lift_term], rw [lift_bounded_term_irrel s _ (le_refl _)]
end

def bounded_term_of_function {l n} (f : L.functions l) : 
  arity (bounded_term L n) (bounded_term L n) l :=
arity.of_dvector_map $ bd_apps (bd_func f)

@[simp] lemma realize_bounded_term_bd_app {S : Structure L}
  {n l} (t : bounded_preterm L n (l+1)) (s : bounded_term L n) (xs : dvector S n) 
  (xs' : dvector S l) :
  realize_bounded_term xs (bd_app t s) xs' = 
  realize_bounded_term xs t (realize_bounded_term xs s ([])::xs') :=
by refl

@[simp] lemma realize_closed_term_bd_apps {S : Structure L}
  {l} (t : closed_preterm L l) (ts : dvector (closed_term L) l) :
  realize_closed_term S (bd_apps t ts) = 
  realize_bounded_term ([]) t (ts.map (λt', realize_bounded_term ([]) t' ([]))) :=
begin
  induction ts generalizing t, refl, apply ts_ih (bd_app t ts_x)
end

--⟨t.fst[s.fst // n], bounded_term_subst_closed t.snd s.snd⟩


lemma realize_bounded_term_bd_apps {S : Structure L}
  {n l} (xs : dvector S n) (t : bounded_preterm L n l) (ts : dvector (bounded_term L n) l) :
  realize_bounded_term xs (bd_apps t ts) ([]) =
  realize_bounded_term xs t (ts.map (λt, realize_bounded_term xs t ([]))) :=
begin
  induction ts generalizing t, refl, apply ts_ih (bd_app t ts_x)
end

/- this is the same as realize_bounded_term, we should probably have a common generalization of this definition -/
-- @[simp] def substitute_bounded_term {n n'} (v : dvector (bounded_term n') n) : 
--   ∀{l} (t : bounded_term L n l, bounded_preterm L n' l
-- | _ _ &k          := v.nth k hk
-- | _ _ (bd_func f)             := bd_func f
-- | _ _ (bd_app t₁ t₂) := bd_app (substitute_bounded_term ht₁) $ substitute_bounded_term ht₂

-- def substitute_bounded_term {n n' l} (t : bounded_preterm L n l) 
--   (v : dvector (bounded_term n') n) : bounded_preterm L n' l :=
-- substitute_bounded_term v t.snd


variable (L)
inductive bounded_preformula : ℕ → ℕ → Type u
| bd_falsum {} {n} : bounded_preformula n 0
| bd_equal {n} (t₁ t₂ : bounded_term L n) : bounded_preformula n 0
| bd_rel {n l : ℕ} (R : L.relations l) : bounded_preformula n l
| bd_apprel {n l} (f : bounded_preformula n (l + 1)) (t : bounded_term L n) : bounded_preformula n l
| bd_imp {n} (f₁ f₂ : bounded_preformula n 0) : bounded_preformula n 0
| bd_all {n} (f : bounded_preformula (n+1) 0) : bounded_preformula n 0

export bounded_preformula

@[reducible] def bounded_formula    (n : ℕ)   := bounded_preformula L n 0
@[reducible] def presentence        (l : ℕ)   := bounded_preformula L 0 l
@[reducible] def sentence                     := presentence L 0
variable {L}

notation `⊥` := fol.bounded_preformula.bd_falsum -- input: \bot
infix ` ≃ `:88 := fol.bounded_preformula.bd_equal -- input \~- or \simeq
infix ` ⟹ `:62 := fol.bounded_preformula.bd_imp -- input \==>
def bd_not {n} (f : bounded_formula L n) : bounded_formula L n := f ⟹ ⊥
prefix `∼`:max := fol.bd_not -- input \~, the ASCII character ~ has too low precedence
def bd_and {n} (f₁ f₂ : bounded_formula L n) : bounded_formula L n := ∼(f₁ ⟹ ∼f₂)
infixr ` ⊓ ` := fol.bd_and -- input: \sqcap
def bd_or {n} (f₁ f₂ : bounded_formula L n) : bounded_formula L n := ∼f₁ ⟹ f₂
infixr ` ⊔ ` := fol.bd_or -- input: \sqcup
def bd_biimp {n} (f₁ f₂ : bounded_formula L n) : bounded_formula L n := (f₁ ⟹ f₂) ⊓ (f₂ ⟹ f₁)
infix ` ⇔ `:61 := fol.bd_biimp -- input \<=>
prefix `∀'`:110 := fol.bounded_preformula.bd_all
def bd_ex {n} (f : bounded_formula L (n+1)) : bounded_formula L n := ∼ (∀' (∼ f))
prefix `∃'`:110 := fol.bd_ex

def bd_apps_rel : ∀{n l} (f : bounded_preformula L n l) (ts : dvector (bounded_term L n) l),
  bounded_formula L n
| _ _ f []      := f
| _ _ f (t::ts) := bd_apps_rel (bd_apprel f t) ts

@[simp] lemma bd_apps_rel_zero {n} (f : bounded_formula L n) (ts : dvector (bounded_term L n) 0) : 
  bd_apps_rel f ts = f :=
by cases ts; refl

namespace bounded_preformula
@[simp] protected def fst : ∀{n l}, bounded_preformula L n l → preformula L l
| _ _ bd_falsum       := ⊥
| _ _ (t₁ ≃ t₂)       := t₁.fst ≃ t₂.fst
| _ _ (bd_rel R)      := rel R
| _ _ (bd_apprel f t) := apprel f.fst t.fst
| _ _ (f₁ ⟹ f₂)      := f₁.fst ⟹ f₂.fst
| _ _ (∀' f)          := ∀' f.fst

local attribute [extensionality] fin.eq_of_veq
@[extensionality] protected def eq {n l} {f₁ f₂ : bounded_preformula L n l} (h : f₁.fst = f₂.fst) :
  f₁ = f₂ :=
begin
  induction f₁; cases f₂; injection h with h₁ h₂,
  { refl }, 
  { congr1; apply bounded_preterm.eq; assumption },
  { rw h₁ },
  { congr1, exact f₁_ih h₁, exact bounded_preterm.eq h₂ },
  { congr1, exact f₁_ih_f₁ h₁, exact f₁_ih_f₂ h₂ },
  { rw [f₁_ih h₁] }
end

@[simp] protected def cast : ∀ {n m l} (h : n ≤ m)  (f : bounded_preformula L n l), 
  bounded_preformula L m l
| _ _ _ h bd_falsum       := bd_falsum
| _ _ _ h (t₁ ≃ t₂)       := t₁.cast h ≃ t₂.cast h
| _ _ _ h (bd_rel R)      := bd_rel R
| _ _ _ h (bd_apprel f t) := bd_apprel (f.cast h) $ t.cast h
| _ _ _ h (f₁ ⟹ f₂)      := f₁.cast h ⟹ f₂.cast h
| _ _ _ h (∀' f)          := ∀' f.cast (succ_le_succ h)

protected def cast_eq {n m l} (h : n = m) (f : bounded_preformula L n l) : bounded_preformula L m l :=
f.cast $ le_of_eq h

protected def cast1 {n l} (f : bounded_preformula L n l) : bounded_preformula L (n+1) l :=
f.cast $ n.le_add_right 1

@[simp] lemma cast_fst : ∀ {l n m} (h : n ≤ m) (f : bounded_preformula L n l), 
  (f.cast h).fst = f.fst
| _ _ _ h bd_falsum       := by refl
| _ _ _ h (t₁ ≃ t₂)       := by simp
| _ _ _ h (bd_rel R)      := by refl
| _ _ _ h (bd_apprel f t) := by simp*
| _ _ _ h (f₁ ⟹ f₂)      := by simp*
| _ _ _ h (∀' f)          := by simp*

@[simp] lemma cast_eq_fst {l n m} (h : n = m) (f : bounded_preformula L n l) : 
  (f.cast_eq h).fst = f.fst := f.cast_fst _
@[simp] lemma cast1_fst {l n} (f : bounded_preformula L n l) : 
  f.cast1.fst = f.fst := f.cast_fst _

end bounded_preformula

namespace presentence

protected def cast0 {l} (n) (f : presentence L l) : bounded_preformula L n l :=
f.cast n.zero_le

@[simp] lemma cast0_fst {l} (n) (f : presentence L l) : 
  (f.cast0 n).fst = f.fst := f.cast_fst _

end presentence

lemma lift_bounded_formula_irrel : ∀{n l} (f : bounded_preformula L n l) (n') {m : ℕ}
  (h : n ≤ m), f.fst ↑' n' # m = f.fst
| _ _ bd_falsum       n' m h := by refl
| _ _ (t₁ ≃ t₂)       n' m h := by simp [lift_bounded_term_irrel _ _ h]
| _ _ (bd_rel R)      n' m h := by refl
| _ _ (bd_apprel f t) n' m h := by simp [*, lift_bounded_term_irrel _ _ h]
| _ _ (f₁ ⟹ f₂)      n' m h := by simp*
| _ _ (∀' f)          n' m h := by simp*

lemma lift_sentence_irrel (f : sentence L) : f.fst ↑ 1 = f.fst :=
lift_bounded_formula_irrel f 1 $ le_refl 0

@[simp] def realize_bounded_formula {S : Structure L} : 
  ∀{n l} (v : dvector S n) (f : bounded_preformula L n l) (xs : dvector S l), Prop
| _ _ v bd_falsum       xs := false
| _ _ v (t₁ ≃ t₂)       xs := realize_bounded_term v t₁ xs = realize_bounded_term v t₂ xs
| _ _ v (bd_rel R)      xs := S.rel_map R xs
| _ _ v (bd_apprel f t) xs := realize_bounded_formula v f $ realize_bounded_term v t ([])::xs
| _ _ v (f₁ ⟹ f₂)      xs := realize_bounded_formula v f₁ xs →  realize_bounded_formula v f₂ xs
| _ _ v (∀' f)          xs := ∀(x : S), realize_bounded_formula (x::v) f xs

@[reducible] def realize_sentence (S : Structure L) (f : sentence L) : Prop :=
realize_bounded_formula ([] : dvector S 0) f ([])

lemma realize_bounded_formula_iff {S : Structure L} : ∀{n} {v₁ : dvector S n} {v₂ : ℕ → S}
  (hv : ∀k (hk : k < n), v₁.nth k hk = v₂ k) {l} (t : bounded_preformula L n l)
  (xs : dvector S l), realize_bounded_formula v₁ t xs ↔ realize_formula v₂ t.fst xs
| _ _ _ hv _ bd_falsum       xs := by refl
| _ _ _ hv _ (t₁ ≃ t₂)       xs := by apply eq.congr; apply realize_bounded_term_eq hv
| _ _ _ hv _ (bd_rel R)      xs := by refl
| _ _ _ hv _ (bd_apprel f t) xs := 
  by simp [realize_bounded_term_eq hv, realize_bounded_formula_iff hv]
| _ _ _ hv _ (f₁ ⟹ f₂)      xs := 
  by simp [realize_bounded_formula_iff hv]
| _ _ _ hv _ (∀' f)          xs :=
  begin 
    apply forall_congr, intro x, apply realize_bounded_formula_iff,
    intros k hk, cases k, refl, apply hv
  end

@[simp] def lift_bounded_formula_at : ∀{n l} (f : bounded_preformula L n l) (n' m : ℕ), 
  bounded_preformula L (n + n') l
| _ _ bd_falsum       n' m := ⊥ 
| _ _ (t₁ ≃ t₂)       n' m := t₁ ↑' n' # m ≃ t₂ ↑' n' # m
| _ _ (bd_rel R)      n' m := bd_rel R
| _ _ (bd_apprel f t) n' m := bd_apprel (lift_bounded_formula_at f n' m) $ t ↑' n' # m
| _ _ (f₁ ⟹ f₂)      n' m := lift_bounded_formula_at f₁ n' m ⟹ lift_bounded_formula_at f₂ n' m
| _ _ (∀' f)          n' m := ∀' (lift_bounded_formula_at f n' (m+1)).cast (le_of_eq $ succ_add _ _)

notation f ` ↑' `:90 n ` # `:90 m:90 := fol.lift_bounded_formula_at f n m -- input ↑ with \u or \upa

@[reducible] def lift_bounded_formula {n l} (f : bounded_preformula L n l) (n' : ℕ) : 
  bounded_preformula L (n + n') l := f ↑' n' # 0
infix ` ↑ `:100 := fol.lift_bounded_formula -- input ↑' with \u or \upa

@[reducible, simp] def lift_bounded_formula1 {n' l} (f : bounded_preformula L n' l) : 
  bounded_preformula L (n'+1) l := 
f ↑ 1

@[simp] lemma lift_bounded_formula_fst : ∀{n l} (f : bounded_preformula L n l) (n' m : ℕ), 
  (f ↑' n' # m).fst = f.fst ↑' n' # m
| _ _ bd_falsum       n' m := by refl
| _ _ (t₁ ≃ t₂)       n' m := by simp
| _ _ (bd_rel R)      n' m := by refl
| _ _ (bd_apprel f t) n' m := by simp*
| _ _ (f₁ ⟹ f₂)      n' m := by simp*
| _ _ (∀' f)          n' m := by simp*

def formula_below {n n' l} (f : bounded_preformula L (n+n'+1) l)  
  (s : bounded_term L n') : bounded_preformula L (n+n') l :=
begin
  have : {f' : preformula L l // f.fst = f' } := ⟨f.fst, rfl⟩, 
  cases this with f' pf, induction f' generalizing n; cases f; injection pf with pf₁ pf₂,
  { exact ⊥ },
  { exact subst_bounded_term f_t₁ s ≃ subst_bounded_term f_t₂ s },
  { exact bd_rel f_R },
  { exact bd_apprel (f'_ih f_f pf₁) (subst_bounded_term f_t s) },
  { exact f'_ih_f₁ f_f₁ pf₁ ⟹ f'_ih_f₂ f_f₂ pf₂ },
  { refine ∀' (f'_ih (f_f.cast_eq $ congr_arg succ $ (succ_add n n').symm) $ 
      (f_f.cast_eq_fst _).trans pf₁).cast_eq (succ_add n n') }  
end

@[simp] def subst_bounded_formula : ∀{n n' n'' l} (f : bounded_preformula L n'' l)  
  (s : bounded_term L n') (h : n+n'+1 = n''), bounded_preformula L (n+n') l
| _ _ _ _ bd_falsum       s rfl := ⊥ 
| _ _ _ _ (t₁ ≃ t₂)       s rfl := subst_bounded_term t₁ s ≃ subst_bounded_term t₂ s
| _ _ _ _ (bd_rel R)      s rfl := bd_rel R
| _ _ _ _ (bd_apprel f t) s rfl := bd_apprel (subst_bounded_formula f s rfl) (subst_bounded_term t s)
| _ _ _ _ (f₁ ⟹ f₂)      s rfl := subst_bounded_formula f₁ s rfl ⟹ subst_bounded_formula f₂ s rfl
| _ _ _ _ (∀' f)          s rfl := 
  ∀' (subst_bounded_formula f s $ by simp [succ_add]).cast_eq (succ_add _ _)

@[simp] def subst_bounded_formula_fst : ∀{n n' n'' l} (f : bounded_preformula L n'' l)  
  (s : bounded_term L n') (h : n+n'+1 = n''),
  (subst_bounded_formula f s h).fst = f.fst[s.fst//n]
| _ _ _ _ bd_falsum       s rfl := by refl
| _ _ _ _ (t₁ ≃ t₂)       s rfl := by simp
| _ _ _ _ (bd_rel R)      s rfl := by refl
| _ _ _ _ (bd_apprel f t) s rfl := by simp*
| _ _ _ _ (f₁ ⟹ f₂)      s rfl := by simp*
| _ _ _ _ (∀' f)          s rfl := by simp*

lemma realize_bounded_formula_irrel' {S : Structure L} {n n'} {v₁ : dvector S n} {v₂ : dvector S n'} 
  (h : ∀m (hn : m < n) (hn' : m < n'), v₁.nth m hn = v₂.nth m hn')
  {l} (f : bounded_preformula L n l) (f' : bounded_preformula L n' l) 
  (hf : f.fst = f'.fst) (xs : dvector S l) : 
  realize_bounded_formula v₁ f xs ↔ realize_bounded_formula v₂ f' xs :=
begin
  induction f generalizing n'; cases f'; injection hf with hf₁ hf₂,
  { refl },
  { simp [realize_bounded_term_irrel' h f_t₁ f'_t₁ hf₁,
          realize_bounded_term_irrel' h f_t₂ f'_t₂ hf₂] },
  { rw [hf₁], refl },
  { simp [realize_bounded_term_irrel' h f_t f'_t hf₂, f_ih _ h f'_f hf₁] },
  { apply imp_congr, apply f_ih_f₁ _ h _ hf₁, apply f_ih_f₂ _ h _ hf₂ },
  { apply forall_congr, intro x, apply f_ih _ _ _ hf₁, intros,
    cases m, refl, apply h }
end

lemma realize_bounded_formula_irrel {S : Structure L} {n} {v₁ : dvector S n}
  (f : bounded_formula L n) (f' : sentence L) (hf : f.fst = f'.fst) (xs : dvector S 0) :
  realize_bounded_formula v₁ f xs ↔ realize_sentence S f' :=
by cases xs; exact realize_bounded_formula_irrel' 
  (by intros m hm hm'; exfalso; exact not_lt_zero m hm') f f' hf ([])

def bounded_formula_of_relation {l n} (f : L.relations l) : 
  arity (bounded_term L n) (bounded_formula L n) l :=
arity.of_dvector_map $ bd_apps_rel (bd_rel f)

@[elab_as_eliminator] def bounded_preformula.rec1 {C : Πn l, bounded_preformula L (n+1) l → Sort v}
  (H0 : Π {n}, C n 0 ⊥)
  (H1 : Π {n} (t₁ t₂ : bounded_term L (n+1)), C n 0 (t₁ ≃ t₂))
  (H2 : Π {n l : ℕ} (R : L.relations l), C n l (bd_rel R))
  (H3 : Π {n l : ℕ} (f : bounded_preformula L (n+1) (l + 1)) (t : bounded_term L (n+1)) 
    (ih : C n (l + 1) f), C n l (bd_apprel f t))
  (H4 : Π {n} (f₁ f₂ : bounded_formula L (n+1)) (ih₁ : C n 0 f₁) (ih₂ : C n 0 f₂), C n 0 (f₁ ⟹ f₂))
  (H5 : Π {n} (f : bounded_formula L (n+2)) (ih : C (n+1) 0 f), C n 0 (∀' f)) :
  ∀{{n l : ℕ}} (f : bounded_preformula L (n+1) l), C n l f :=
let C' : Πn l, bounded_preformula L n l → Sort v :=
λn, match n with
| 0     := λ l f, punit
| (k+1) := C k
end in
begin
  have : ∀{{n l}} (f : bounded_preformula L n l), C' n l f,
  { intros n l, 
    refine bounded_preformula.rec _ _ _ _ _ _; clear n l; intros; cases n; try {exact punit.star},
    apply H0, apply H1, apply H2, apply H3 _ _ ih, apply H4 _ _ ih_f₁ ih_f₂, apply H5 _ ih },
  intros n l f, apply this f
end

@[elab_as_eliminator] def bounded_formula.rec1 {C : Πn, bounded_formula L (n+1) → Sort v}
  (hfalsum : Π {n}, C n ⊥)
  (hequal : Π {n} (t₁ t₂ : bounded_term L (n+1)), C n (t₁ ≃ t₂))
  (hrel : Π {n l : ℕ} (R : L.relations l) (ts : dvector (bounded_term L (n+1)) l), 
    C n (bd_apps_rel (bd_rel R) ts))
  (himp : Π {n} {f₁ f₂ : bounded_formula L (n+1)} (ih₁ : C n f₁) (ih₂ : C n f₂), C n (f₁ ⟹ f₂))
  (hall : Π {n} {f : bounded_formula L (n+2)} (ih : C (n+1) f), C n (∀' f)) 
  {{n : ℕ}} (f : bounded_formula L (n+1)) : C n f :=
have h : ∀{n l} (f : bounded_preformula L (n+1) l) (ts : dvector (bounded_term L (n+1)) l), 
  C n (bd_apps_rel f ts),
begin
  refine bounded_preformula.rec1 _ _ _ _ _ _; intros; try {rw ts.zero_eq},
  apply hfalsum, apply hequal, apply hrel, apply ih (t::ts),
  exact himp (ih₁ ([])) (ih₂ ([])), exact hall (ih ([]))
end,
h f ([])

@[elab_as_eliminator] def bounded_formula.rec {C : Πn, bounded_formula L n → Sort v}
  (hfalsum : Π {n}, C n ⊥)
  (hequal : Π {n} (t₁ t₂ : bounded_term L n), C n (t₁ ≃ t₂))
  (hrel : Π {n l : ℕ} (R : L.relations l) (ts : dvector (bounded_term L n) l), 
    C n (bd_apps_rel (bd_rel R) ts))
  (himp : Π {n} {f₁ f₂ : bounded_formula L n} (ih₁ : C n f₁) (ih₂ : C n f₂), C n (f₁ ⟹ f₂))
  (hall : Π {n} {f : bounded_formula L (n+1)} (ih : C (n+1) f), C n (∀' f)) : 
  ∀{{n : ℕ}} (f : bounded_formula L n), C n f :=
have h : ∀{n l} (f : bounded_preformula L n l) (ts : dvector (bounded_term L n) l), 
  C n (bd_apps_rel f ts),
begin
  intros, induction f; try {rw ts.zero_eq},
  apply hfalsum, apply hequal, apply hrel, apply f_ih (f_t::ts),
  exact himp (f_ih_f₁ ([])) (f_ih_f₂ ([])), exact hall (f_ih ([]))
end,
λn f, h f ([])

@[simp] def substmax_bounded_formula {n l} (f : bounded_preformula L (n+1) l) (s : closed_term L) :
  bounded_preformula L n l :=
by apply subst_bounded_formula f s rfl

-- @[simp] lemma substmax_bounded_formula_bd_falsum {n} (s : closed_term L) :
--   substmax_bounded_formula (⊥ : bounded_formula L (n+1)) s = ⊥ := by refl
-- @[simp] lemma substmax_bounded_formula_bd_rel {n l} (R : L.relations l) (s : closed_term L) :
--   substmax_bounded_formula (bd_rel R : bounded_preformula L (n+1) l) s = bd_rel R := by refl
-- @[simp] lemma substmax_bounded_formula_bd_apprel {n l} (f : bounded_preformula L (n+1) (l+1))
--   (t : bounded_term L (n+1)) (s : closed_term L) :
--   substmax_bounded_formula (bd_apprel f t) s = 
--   bd_apprel (substmax_bounded_formula f s) (substmax_bounded_term t s) := by refl
-- @[simp] lemma substmax_bounded_formula_bd_imp {n} (f₁ f₂ : bounded_formula L (n+1)) 
--   (s : closed_term L) :
--   substmax_bounded_formula (f₁ ⟹ f₂) s = 
--   substmax_bounded_formula f₁ s ⟹ substmax_bounded_formula f₂ s := by refl
@[simp] lemma substmax_bounded_formula_bd_all {n} (f : bounded_formula L (n+2)) 
  (s : closed_term L) :
  substmax_bounded_formula (∀' f) s = ∀' substmax_bounded_formula f s := by ext; simp

lemma substmax_bounded_formula_bd_apps_rel {n l} (f : bounded_preformula L (n+1) l) 
  (t : closed_term L) (ts : dvector (bounded_term L (n+1)) l) :
  substmax_bounded_formula (bd_apps_rel f ts) t = 
  bd_apps_rel (substmax_bounded_formula f t) (ts.map $ λt', substmax_bounded_term t' t) :=
begin
  induction ts generalizing f, refl, apply ts_ih (bd_apprel f ts_x)
end

def subst0_bounded_formula {n l} (f : bounded_preformula L (n+1) l) (s : bounded_term L n) :
  bounded_preformula L n l :=
(subst_bounded_formula f s $ zero_add (n+1)).cast_eq $ zero_add n

notation f `[`:max s ` /0]`:0 := fol.subst0_bounded_formula f s

@[simp] lemma subst0_bounded_formula_fst {n l} (f : bounded_preformula L (n+1) l)
  (s : bounded_term L n) : (subst0_bounded_formula f s).fst = f.fst[s.fst//0] :=
by simp [subst0_bounded_formula]

def substmax_eq_subst0_formula {l} (f : bounded_preformula L 1 l) (t : closed_term L) :
  f[t/0] = substmax_bounded_formula f t :=
by ext; simp [substmax_bounded_formula]


-- def subst0_sentence {n l} (f : bounded_preformula L (n+1) l) (t : closed_term L) :
--   bounded_preformula L n l :=
-- f [bounded_term_of_closed_term t/0]


infix ` ⊨ `:51 := fol.realize_sentence -- input using \|= or \vDash, but not using \models 

@[simp] lemma realize_sentence_false {S : Structure L} : S ⊨ (⊥ : sentence L) ↔ false :=
by refl
@[simp] lemma realize_sentence_imp {S : Structure L} {f₁ f₂ : sentence L} : 
  S ⊨ f₁ ⟹ f₂ ↔ (S ⊨ f₁ → S ⊨ f₂) :=
by refl
@[simp] lemma realize_sentence_not {S : Structure L} {f : sentence L} : S ⊨ ∼f ↔ ¬ S ⊨ f :=
by refl
@[simp] lemma realize_sentence_and {S : Structure L} {f₁ f₂ : sentence L} :
  S ⊨ f₁ ⊓ f₂ ↔ (S ⊨ f₁ ∧ S ⊨ f₂) :=
begin
  have : S ⊨ f₁ ∧ S ⊨ f₂ ↔ ¬(S ⊨ f₁ → ¬ S ⊨ f₂),
    split,
      {intro H, fapply not.intro, tauto},
      {intro H, have := @not.elim _ (S ⊨ f₁) H, finish},
  rw[this], refl
end

@[simp] lemma realize_sentence_all {S : Structure L} {f : bounded_formula L 1} :
  (S ⊨ ∀'f) ↔ ∀ x : S, realize_bounded_formula([x]) f([]) :=
by refl

lemma realize_bounded_formula_bd_apps_rel {S : Structure L}
  {n l} (xs : dvector S n) (f : bounded_preformula L n l) (ts : dvector (bounded_term L n) l) :
  realize_bounded_formula xs (bd_apps_rel f ts) ([]) ↔ 
  realize_bounded_formula xs f (ts.map (λt, realize_bounded_term xs t ([]))) :=
begin
  induction ts generalizing f, refl, apply ts_ih (bd_apprel f ts_x)
end

-- lemma realize_sentence_bd_apps_rel' {S : Structure L}
--   {l} (f : presentence L l) (ts : dvector (closed_term L) l) :
--   S ⊨ bd_apps_rel f ts ↔ realize_bounded_formula ([]) f (ts.map $ realize_closed_term S) :=
-- realize_bounded_formula_bd_apps_rel ([]) f ts

lemma realize_bd_apps_rel {S : Structure L}
  {l} (R : L.relations l) (ts : dvector (closed_term L) l) :
  S ⊨ bd_apps_rel (bd_rel R) ts ↔ S.rel_map R (ts.map $ realize_closed_term S) :=
by apply realize_bounded_formula_bd_apps_rel ([]) (bd_rel R) ts

lemma realize_sentence_equal {S : Structure L} (t₁ t₂ : closed_term L) :
  S ⊨ t₁ ≃ t₂ ↔ realize_closed_term S t₁ = realize_closed_term S t₂  :=
by refl

lemma realize_sentence_iff {S : Structure L} (v : ℕ → S) (f : sentence L) : 
  realize_sentence S f ↔ realize_formula v f.fst ([]) :=
realize_bounded_formula_iff (λk hk, by exfalso; exact not_lt_zero k hk) f _

lemma realize_sentence_of_satisfied_in {S : Structure L} [HS : nonempty S] {f : sentence L} 
  (H : S ⊨ f.fst) : S ⊨ f :=
begin unfreezeI, induction HS with x, exact (realize_sentence_iff (λn, x) f).mpr (H _) end

lemma satisfied_in_of_realize_sentence {S : Structure L} {f : sentence L} (H : S ⊨ f) : S ⊨ f.fst :=
λv, (realize_sentence_iff v f).mp H

lemma realize_sentence_iff_satisfied_in {S : Structure L} [HS : nonempty S] {f : sentence L} :
  S ⊨ f ↔ S ⊨ f.fst  :=
⟨satisfied_in_of_realize_sentence, realize_sentence_of_satisfied_in⟩

/- theories -/

variable (L)
@[reducible] def Theory := set $ sentence L
variable {L}

@[reducible] def Theory.fst (T : Theory L) : set (formula L) := bounded_preformula.fst '' T

def sprf (T : Theory L) (f : sentence L) := T.fst ⊢ f.fst
infix ` ⊢ `:51 := fol.sprf -- input: \|- or \vdash

def sprovable (T : Theory L) (f : sentence L) := T.fst ⊢' f.fst
infix ` ⊢' `:51 := fol.sprovable -- input: \|- or \vdash

def saxm {T : Theory L} {A : sentence L} (H : A ∈ T) : T ⊢ A := 
by apply axm; apply mem_image_of_mem _ H

def simpI {T : Theory L} {A B : sentence L} (H : insert A T ⊢ B) : T ⊢ A ⟹ B := 
begin
  apply impI, simp[sprf, Theory.fst, image_insert_eq] at H, assumption
end

@[reducible] lemma fst_commutes_with_imp {T : Theory L} (A B : sentence L) : (A ⟹ B).fst = A.fst ⟹ B.fst := by refl

def sfalsumE {T : Theory L} {A : sentence L} (H : insert ∼A T ⊢ bd_falsum) : T ⊢ A :=
begin
  apply falsumE, simp[sprf, Theory.fst, image_insert_eq] at H, assumption
end

def snotI {T : Theory L} {A : sentence L} (H : T ⊢ A ⟹ bd_falsum) : T ⊢ ∼A :=
begin
  apply notI, simp[sprf, Theory.fst, image_insert_eq] at H, assumption
end

def sandI {T : Theory L} {A B : sentence L} (H1 : T ⊢ A) (H2 : T ⊢ B) : T ⊢ A ⊓ B :=
by exact andI H1 H2

def snot_and_self {T : Theory L} {A : sentence L} (H : T ⊢ A ⊓ ∼ A) : T ⊢ bd_falsum :=
by exact not_and_self H

def sprovable_of_provable {T : Theory L} {f : sentence L} (h : T.fst ⊢ f.fst) : T ⊢ f := h
def provable_of_sprovable {T : Theory L} {f : sentence L} (h : T ⊢ f) : T.fst ⊢ f.fst := h

-- def sprovable_of_sprovable_lift_at {T : Theory L} (n m : ℕ) {f : formula L} (h : T.fst ⊢ f ↑' n # m) :
--   T.fst ⊢ f := 
-- sorry

-- def sprovable_of_sprovable_lift {T : Theory L} {f : formula L} (h : T.fst ⊢ f ↑ 1) : T.fst ⊢ f := 
-- sprovable_of_sprovable_lift_at 1 0 h

def sprovable_lift {T : Theory L} {f : formula L} (h : T.fst ⊢ f) : T.fst ⊢ f ↑ 1 := 
begin
  have := prf_lift 1 0 h, dsimp [Theory.fst] at this, 
  rw [←image_comp, image_congr' lift_sentence_irrel] at this, exact this
end

def all_sprovable (T T' : Theory L) := ∀(f ∈ T'), T ⊢ f
infix ` ⊢ `:51 := fol.all_sprovable -- input: \|- or \vdash

def all_realize_sentence (S : Structure L) (T : Theory L) := ∀{{f}}, f ∈ T → S ⊨ f
infix ` ⊨ `:51 := fol.all_realize_sentence -- input using \|= or \vDash, but not using \models 

def ssatisfied (T : Theory L) (f : sentence L) := 
∀{{S : Structure L}}, nonempty S → S ⊨ T → S ⊨ f

infix ` ⊨ `:51 := fol.ssatisfied -- input using \|= or \vDash, but not using \models 

def all_ssatisfied (T T' : Theory L) := ∀(f ∈ T'), T ⊨ f
infix ` ⊨ `:51 := fol.all_ssatisfied -- input using \|= or \vDash, but not using \models 

def satisfied_of_ssatisfied {T : Theory L} {f : sentence L} (H : T ⊨ f) : T.fst ⊨ f.fst :=
begin
  intros S v hT, rw [←realize_sentence_iff], apply H ⟨ v 0 ⟩,
  intros f' hf', rw [realize_sentence_iff v], apply hT, apply mem_image_of_mem _ hf'
end

def ssatisfied_of_satisfied {T : Theory L} {f : sentence L} (H : T.fst ⊨ f.fst) : T ⊨ f :=
begin
  intros S hS hT, induction hS with s, rw [realize_sentence_iff (λ_, s)], apply H,
  intros f' hf', rcases hf' with ⟨f', ⟨hf', h⟩⟩, induction h, rw [←realize_sentence_iff],
  exact hT hf'
end

def all_satisfied_of_all_ssatisfied {T T' : Theory L} (H : T ⊨ T') : T.fst ⊨ T'.fst :=
begin intros f hf, rcases hf with ⟨f, ⟨hf, rfl⟩⟩, apply satisfied_of_ssatisfied (H f hf) end

def all_ssatisfied_of_all_satisfied {T T' : Theory L} (H : T.fst ⊨ T'.fst) : T ⊨ T' :=
begin intros f hf, apply ssatisfied_of_satisfied, apply H, exact mem_image_of_mem _ hf end

def satisfied_iff_ssatisfied {T : Theory L} {f : sentence L} : T ⊨ f ↔ T.fst ⊨ f.fst :=
⟨satisfied_of_ssatisfied, ssatisfied_of_satisfied⟩

def all_satisfied_sentences_iff {T T' : Theory L} : T ⊨ T' ↔ T.fst ⊨ T'.fst :=
⟨all_satisfied_of_all_ssatisfied, all_ssatisfied_of_all_satisfied⟩

def ssatisfied_snot {S : Structure L} {f : sentence L} (hS : ¬(S ⊨ f)) : S ⊨ ∼ f := 
by exact hS

def Model (T : Theory L) : Type (u+1) := Σ' (S : Structure L), S ⊨ T

lemma soundness {T : Theory L} {A : sentence L} (H : T ⊢ A) : T ⊨ A :=
ssatisfied_of_satisfied $ formula_soundness H

def is_consistent (T : Theory L) := ¬(T ⊢' (⊥ : sentence L))

protected def is_consistent.intro {T : Theory L} (H : ¬ T ⊢' (⊥ : sentence L)) : is_consistent T :=
H

protected def is_consistent.elim {T : Theory L} (H : is_consistent T) : ¬ T ⊢' (⊥ : sentence L)
| H' := H H'

def is_complete (T : Theory L) := 
is_consistent T ∧ ∀(f : sentence L), f ∈ T ∨ ∼ f ∈ T

def mem_of_sprf {T : Theory L} (H : is_complete T) {f : sentence L} (Hf : T ⊢ f) : f ∈ T :=
begin 
  cases H.2 f, exact h, exfalso, apply H.1, constructor, refine impE _ _ Hf, apply saxm h
end

def mem_of_sprovable {T : Theory L} (H : is_complete T) {f : sentence L} (Hf : T ⊢' f) : f ∈ T :=
by destruct Hf; exact mem_of_sprf H

def sprovable_of_sprovable_or {T : Theory L} (H : is_complete T) {f₁ f₂ : sentence L}
  (H₂ : T ⊢' f₁ ⊔ f₂) : (T ⊢' f₁) ∨ T ⊢' f₂ :=
begin
  cases H.2 f₁ with h h, { left, exact ⟨saxm h⟩ },
  cases H.2 f₂ with h' h', { right, exact ⟨saxm h'⟩ },
  exfalso, destruct H₂, intro H₂, apply H.1, constructor,
  apply orE H₂; refine impE _ _ axm1; apply weakening1; apply axm; 
    [exact mem_image_of_mem _ h, exact mem_image_of_mem _ h']
end

def impI_of_is_complete {T : Theory L} (H : is_complete T) {f₁ f₂ : sentence L}
  (H₂ : T ⊢' f₁ → T ⊢' f₂) : T ⊢' f₁ ⟹ f₂ :=
begin
  apply impI', cases H.2 f₁, 
  { apply weakening1', apply H₂, exact ⟨saxm h⟩ },
  apply falsumE', apply weakening1',
  apply impE' _ (weakening1' ⟨by apply saxm h⟩) ⟨axm1⟩
end

def notI_of_is_complete {T : Theory L} (H : is_complete T) {f : sentence L}
  (H₂ : ¬T ⊢' f) : T ⊢' ∼f :=
begin
  apply @impI_of_is_complete _ T H f ⊥,
  intro h, exfalso, exact H₂ h
end

def has_enough_constants (T : Theory L) :=
∃(C : Π(f : bounded_formula L 1), L.constants), 
∀(f : bounded_formula L 1), T ⊢' ∃' f ⟹ f[bd_const (C f)/0]

def find_counterexample_of_henkin {T : Theory L} (H₁ : is_complete T) (H₂ : has_enough_constants T) 
  (f : bounded_formula L 1) (H₃ : ¬ T ⊢' ∀' f) : ∃(t : closed_term L), T ⊢' ∼ f[t/0] :=
begin
  induction H₂ with C HC, 
  refine ⟨bd_const (C (∼ f)), _⟩, dsimp [sprovable] at HC,
  apply (HC _).map2 (impE _),
  apply nonempty.map ex_not_of_not_all, apply notI_of_is_complete H₁ H₃
end

variables (T : Theory L) (H₁ : is_complete T) (H₂ : has_enough_constants T)
def term_rel (t₁ t₂ : closed_term L) : Prop := T ⊢' t₁ ≃ t₂

def term_setoid : setoid $ closed_term L := 
⟨term_rel T, λt, ⟨ref _ _⟩, λt t' H, H.map symm, λt₁ t₂ t₃ H₁ H₂, H₁.map2 trans H₂⟩
local attribute [instance] term_setoid

def term_model' : Type u :=
quotient $ term_setoid T
-- set_option pp.all true
-- #print term_setoid
-- set_option trace.class_instances true

def term_model_fun' {l} (t : closed_preterm L l) (ts : dvector (closed_term L) l) : term_model' T :=
@quotient.mk _ (term_setoid T) $ bd_apps t ts

-- def equal_preterms_trans {T : set (formula L)} : ∀{l} {t₁ t₂ t₃ : preterm L l} 
--   (h₁₂ : equal_preterms T t₁ t₂) (h₂₃ : equal_preterms T t₂ t₃), equal_preterms T t₁ t₃ 

variable {T}
def term_model_fun_eq {l} (t t' : closed_preterm L (l+1)) (x x' : closed_term L)
  (Ht : equal_preterms T.fst t.fst t'.fst) (Hx : T ⊢ x ≃ x') (ts : dvector (closed_term L) l) : 
  term_model_fun' T (bd_app t x) ts = term_model_fun' T (bd_app t' x') ts :=
begin
  induction ts generalizing x x',
  { apply quotient.sound, refine ⟨trans (app_congr t.fst Hx) _⟩, apply Ht ([x'.fst]) }, 
  { apply ts_ih, apply equal_preterms_app Ht Hx, apply ref }
end

variable (T)
def term_model_fun {l} (t : closed_preterm L l) (ts : dvector (term_model' T) l) : term_model' T :=
begin
  refine ts.quotient_lift (term_model_fun' T t) _, clear ts,
  intros ts ts' hts,
  induction hts,
  { refl },
  { apply (hts_ih _).trans, induction hts_hx with h, apply term_model_fun_eq,
    refl, exact h }
end

def term_model_rel' {l} (f : presentence L l) (ts : dvector (closed_term L) l) : Prop :=
T ⊢' bd_apps_rel f ts

variable {T}
def term_model_rel_iff {l} (f f' : presentence L (l+1)) (x x' : closed_term L)
  (Ht : equiv_preformulae T.fst f.fst f'.fst) (Hx : T ⊢ x ≃ x') (ts : dvector (closed_term L) l) : 
  term_model_rel' T (bd_apprel f x) ts ↔ term_model_rel' T (bd_apprel f' x') ts :=
begin
  induction ts generalizing x x',
  { apply iff.trans (apprel_congr' f.fst Hx), 
    apply iff_of_biimp, have := Ht ([x'.fst]), exact ⟨this⟩ }, 
  { apply ts_ih, apply equiv_preformulae_apprel Ht Hx, apply ref }
end

variable (T)
def term_model_rel {l} (f : presentence L l) (ts : dvector (term_model' T) l) : Prop :=
begin
  refine ts.quotient_lift (term_model_rel' T f) _, clear ts,
  intros ts ts' hts,
  induction hts,
  { refl },
  { apply (hts_ih _).trans, induction hts_hx with h, apply propext, apply term_model_rel_iff,
    refl, exact h }
end

def term_model : Structure L :=
⟨term_model' T, 
 λn, term_model_fun T ∘ bd_func, 
 λn, term_model_rel T ∘ bd_rel⟩

@[reducible] def term_mk : closed_term L → term_model T :=
@quotient.mk _ $ term_setoid T

-- lemma realize_bounded_preterm_term_model {l n} (ts : dvector (closed_term L) l) 
--   (t : bounded_preterm L l n) (ts' : dvector (closed_term L) n) :
--   realize_bounded_term (ts.map term_mk) t (ts'.map term_mk) = 
--   (term_mk _) :=
-- begin
--   induction t with t ht,
--   sorry
-- end

-- dsimp [term_model, Structure.rel_map, term_model_rel], 
--     rw [ts.map_congr realize_closed_term_term_model, dvector.quotient_beta], refl

variable {T}
lemma realize_closed_preterm_term_model {l} (ts : dvector (closed_term L) l) (t : closed_preterm L l) : 
  realize_bounded_term ([]) t (ts.map $ term_mk T) = (term_mk T (bd_apps t ts)) :=
begin
  induction t,
  { apply t.fin_zero_elim },
  { apply dvector.quotient_beta },
  { rw [realize_bounded_term_bd_app],
    have := t_ih_s ([]), dsimp at this, rw this, 
    apply t_ih_t (t_s::ts) }
end

@[simp] lemma realize_closed_term_term_model (t : closed_term L) :
  realize_closed_term (term_model T) t = term_mk T t :=
by apply realize_closed_preterm_term_model ([]) t
/- below we try to do this directly using bounded_term.rec -/
-- begin
--   revert t, refine bounded_term.rec _ _; intros,
--   { apply k.fin_zero_elim },
--   --{ apply dvector.quotient_beta },
--   { 
    
--     --exact dvector.quotient_beta _ _ ts,
--     rw [realize_bounded_term_bd_app],
--     have := t_ih_s ([]), dsimp at this, rw this, 
--     apply t_ih_t (t_s::ts) }
-- end


lemma realize_subst_preterm {S : Structure L} {n l} (t : bounded_preterm L (n+1) l)
  (xs : dvector S l) (s : closed_term L) (v : dvector S n) :
  realize_bounded_term v (substmax_bounded_term t s) xs =
  realize_bounded_term (v.concat (realize_closed_term S s)) t xs :=
begin
  induction t, 
  { by_cases h : t.1 < n,
    { rw [substmax_var_lt t s h], dsimp,
      simp only [dvector.map_nth, dvector.concat_nth _ _ _ _ h] },
    { have h' := le_antisymm (le_of_lt_succ t.2) (le_of_not_gt h), simp [h'],
      rw [substmax_var_eq t s h'], 
      apply realize_bounded_term_irrel, simp }},
  { refl }, 
  { dsimp, rw [substmax_bounded_term_bd_app], dsimp, rw [t_ih_s ([]), t_ih_t] }
end

lemma realize_subst_term {S : Structure L} {n} (v : dvector S n) (s : closed_term L) 
  (t : bounded_term L (n+1))  :
  realize_bounded_term v (substmax_bounded_term t s) ([]) =
  realize_bounded_term (v.concat (realize_closed_term S s)) t ([]) :=
by apply realize_subst_preterm t ([]) s v

lemma realize_subst_formula (S : Structure L) {n} (f : bounded_formula L (n+1))
  (t : closed_term L) (v : dvector S n) :
  realize_bounded_formula v (substmax_bounded_formula f t) ([]) ↔
  realize_bounded_formula (v.concat (realize_closed_term S t)) f ([]) :=
begin
  revert n f v, refine bounded_formula.rec1 _ _ _ _ _; intros,
  { simp },
  { apply eq.congr, exact realize_subst_term v t t₁, exact realize_subst_term v t t₂ },
  { rw [substmax_bounded_formula_bd_apps_rel, realize_bounded_formula_bd_apps_rel, 
        realize_bounded_formula_bd_apps_rel], 
    simp [ts.map_congr (realize_subst_term _ _)] }, 
  { apply imp_congr, apply ih₁ v, apply ih₂ v },
  { simp, apply forall_congr, intro x, apply ih (x::v) }
end

lemma realize_subst_formula0 (S : Structure L) (f : bounded_formula L 1) (t : closed_term L) :
  S ⊨ f[t/0] ↔ realize_bounded_formula ([realize_closed_term S t]) f ([]) :=
iff.trans (by rw [substmax_eq_subst0_formula]) (by apply realize_subst_formula S f t ([]))

lemma term_model_subst0 (f : bounded_formula L 1) (t : closed_term L) :
  term_model T ⊨ f[t/0] ↔ realize_bounded_formula ([term_mk T t]) f ([]) :=
(realize_subst_formula0 (term_model T) f t).trans (by simp)

include H₂
instance nonempty_term_model : nonempty $ term_model T :=
begin
  induction H₂ with C, exact ⟨term_mk T (bd_const (C (&0 ≃ &0)))⟩
end

include H₁
def term_model_ssatisfied_iff : ∀{n l} (f : presentence L l) 
  (ts : dvector (closed_term L) l) (h : count_quantifiers f.fst < n),
  T ⊢' bd_apps_rel f ts ↔ term_model T ⊨ bd_apps_rel f ts :=
begin
  intro n, refine nat.strong_induction_on n _, clear n,
  intros n n_ih l f ts hn,
  have : {f' : preformula L l // f.fst = f' } := ⟨f.fst, rfl⟩, 
  cases this with f' hf, induction f'; cases f; injection hf with hf₁ hf₂,
  { simp, exact H₁.1.elim },
  { simp, refine iff.trans _ (realize_sentence_equal f_t₁ f_t₂).symm, simp [term_mk], refl },
  { refine iff.trans _ (realize_bd_apps_rel _ _).symm, 
    dsimp [term_model, term_model_rel], 
    rw [ts.map_congr realize_closed_term_term_model, dvector.quotient_beta], refl },
  { apply f'_ih f_f (f_t::ts) _ hf₁, simp at hn ⊢, exact hn },
  { have ih₁ := f'_ih_f₁ f_f₁ ([]) (lt_of_le_of_lt (nat.le_add_right _ _) hn) hf₁,
    have ih₂ := f'_ih_f₂ f_f₂ ([]) (lt_of_le_of_lt (nat.le_add_left _ _) hn) hf₂, cases ts,
    split; intro h,
    { intro h₁, apply ih₂.mp, apply h.map2 (impE _), refine ih₁.mpr h₁ },
    { simp at h, simp at ih₁, rw [←ih₁] at h, simp at ih₂, rw [←ih₂] at h,
      exact impI_of_is_complete H₁ h }},
  { cases ts, split; intro h,
    { simp at h ⊢,
      apply quotient.ind, intro t, 
      apply (term_model_subst0 f_f t).mp,
      cases n with n, { exfalso, exact not_lt_zero _ hn },
      refine (n_ih n (lt.base n) (f_f[t/0]) ([]) _).mp (h.map _),
      simp, exact lt_of_succ_lt_succ hn,
      rw [bd_apps_rel_zero, subst0_bounded_formula_fst],
      exact allE₂ _ _ },
    { apply classical.by_contradiction, intro H,
      cases find_counterexample_of_henkin H₁ H₂ f_f H with t ht,
      apply H₁.left, apply impE' _ ht,
      cases n with n, { exfalso, exact not_lt_zero _ hn },
      refine (n_ih n (lt.base n) (f_f[t/0]) ([]) _).mpr _,
      { simp, exact lt_of_succ_lt_succ hn },
      exact (term_model_subst0 f_f t).mpr (h (term_mk T t)) }},
end

def term_model_ssatisfied : term_model T ⊨ T :=
begin
  intros f hf, apply (term_model_ssatisfied_iff H₁ H₂ f ([]) (lt.base _)).mp, exact ⟨saxm hf⟩
end

-- completeness for complete theories with enough constants
lemma completeness' {f : sentence L} (H : T ⊨ f) : T ⊢' f :=
begin
  apply (term_model_ssatisfied_iff H₁ H₂ f ([]) (lt.base _)).mpr,
  apply H, exact fol.nonempty_term_model H₂, 
  apply term_model_ssatisfied H₁ H₂,
end
omit H₁ H₂

def Th (S : Structure L) : Theory L := { f : sentence L | S ⊨ f }

lemma realize_sentence_Th (S : Structure L) : S ⊨ Th S :=
λf hf, hf

lemma is_complete_Th (S : Structure L) (HS : nonempty S) : is_complete (Th S) :=
⟨λH, by cases H; apply soundness H HS (realize_sentence_Th S), λ(f : sentence L), classical.em (S ⊨ f)⟩

/- maybe define 
presburger_arithmetic := Th (Z,+,0)
true_arithmetic := (ℕ, +, ⬝, 0, 1)
-/

end fol
