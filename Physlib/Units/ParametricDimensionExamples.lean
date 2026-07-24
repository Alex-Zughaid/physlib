/-
Copyright (c) 2026 Nicolas Rouquette. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Nicolas Rouquette
-/
module

public import Physlib.Units.WithDim.Basic
/-!

# Examples: parametric dimensions and comparing dimensioned quantities

`Dimension B` is parameterised by a basis `B` of base dimensions. This module
illustrates two consequences.

## Comparing a length with a velocity times a time

A recurring question is how to compare a quantity of dimension `length` with a
product of a quantity of dimension `length / time` and a quantity of dimension
`time`. The two dimensions are *equal*, but this equality is a **group
cancellation law** on the rational exponents — it holds *propositionally*, never
*definitionally*:

* `(L𝓭 / T𝓭) * T𝓭 = L𝓭` cannot be closed by `rfl`: cancellation is not a
  reduction rule.
* nor by `decide`: the exponents are rational, so the kernel has nothing to
  evaluate.

Consequently `WithDim ((L𝓭 / T𝓭) * T𝓭) ℝ` and `WithDim L𝓭 ℝ` are genuinely
different types, and a bare `x = v * t` is a type error. The bridge is
`WithDim.cast`, whose default argument discharges the propositional dimension
equality automatically, so the comparison is a one-liner. This is not a
limitation of the representation: no representation of `Dimension` makes the
equality definitional, so a cast on a proven equality is the correct idiom.

## A non-standard basis

Because `Dimension` is parametric, the same dimensional algebra and the same
`cast`-based comparison are available over *any* basis — not just the physical
`LTMCTDimensionBase`. The unit-scaling layer (`UnitChoices`, `dimScale`) is not needed
for either the algebra or the comparison, so neither is referenced here.

This module is illustrative and should not be imported by other modules.

-/

@[expose] public section

open Dimension

namespace ParametricDimensionExamples

/-- The dimension equality `(length / time) · time = length` holds
propositionally, by cancellation of the rational exponents. -/
example : (L𝓭 / T𝓭) * T𝓭 = L𝓭 := by ext; simp

/-- The dimensions are equal, but the two `WithDim` *types* are not
definitionally equal, so `WithDim.cast` bridges them. Its default argument proves
`(L𝓭 / T𝓭) * T𝓭 = L𝓭` with no manual proof. -/
noncomputable example (v : WithDim (L𝓭 / T𝓭) ℝ) (t : WithDim T𝓭 ℝ) : WithDim L𝓭 ℝ :=
  (v * t).cast

/-- The end-to-end comparison: a length equals a velocity times a time, once the
product is cast to the length dimension. -/
example (x : WithDim L𝓭 ℝ) (v : WithDim (L𝓭 / T𝓭) ℝ) (t : WithDim T𝓭 ℝ) : Prop :=
  x = (v * t).cast

/-!
## The same comparison over a non-standard basis

A basis with two base dimensions of its own — `bit` and `symbol` — that
`LTMCTDimensionBase` does not have. Nothing in the standard units system is involved.
-/

/-- A basis of information-theoretic base dimensions. -/
inductive Info
  /-- The information base dimension (bits). -/
  | bit
  /-- The symbol base dimension. -/
  | symbol

/-- The `bit` base dimension. -/
def bitDim : Dimension Info := ⟨fun | .bit => 1 | .symbol => 0⟩

/-- The `symbol` base dimension. -/
def symbolDim : Dimension Info := ⟨fun | .bit => 0 | .symbol => 1⟩

/-- Cancellation works identically over the non-standard basis. -/
example : (bitDim / symbolDim) * symbolDim = bitDim := by ext; simp

/-- And so does the `cast`-based comparison: an information content equals an
information rate (`bit / symbol`) times a number of symbols. -/
example (x : WithDim bitDim ℝ) (r : WithDim (bitDim / symbolDim) ℝ)
    (n : WithDim symbolDim ℝ) : Prop :=
  x = (r * n).cast

end ParametricDimensionExamples
