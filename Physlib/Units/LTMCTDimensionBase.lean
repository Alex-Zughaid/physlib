/-
Copyright (c) 2025 Joseph Tooby-Smith. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Joseph Tooby-Smith
-/
module

public import Physlib.Units.Dimension
/-!

# PhysLib's default dimension basis

`LTMCTDimensionBase` is PhysLib's default basis of base dimensions — length, time,
mass, charge and temperature. `Dimension LTMCTDimensionBase` is the familiar
five-exponent dimension, and this module provides the concrete API on top of the
generic `Dimension B`:

* the `.length`, `.time`, `.mass`, `.charge`, `.temperature` exponent projections;
* the `ofLTMCTDimensionBase` constructor from five exponents; and
* the named generators `L𝓭`, `T𝓭`, `M𝓭`, `C𝓭`, `Θ𝓭`, shown to be the generic
  `single` base vectors.

This basis is *charge*-based with five generators, so it is deliberately **not** the
SI/ISQ base-quantity set (which takes electric current as base and adds amount of
substance and luminous intensity); see `ISQDimensionBase`.

-/

@[expose] public section

/-- PhysLib's default basis of base dimensions — `length`, `time`, `mass`,
  `charge`, `temperature`. Note this is *charge*-based, so it is not the SI/ISQ
  base-quantity set; see `Dimension`. -/
inductive LTMCTDimensionBase where
  /-- The length base dimension. -/
  | length
  /-- The time base dimension. -/
  | time
  /-- The mass base dimension. -/
  | mass
  /-- The charge base dimension. -/
  | charge
  /-- The temperature base dimension. -/
  | temperature
deriving DecidableEq, Fintype

namespace Dimension

/-!

## The LTMCTDimensionBase projections

The five base-dimension exponents of a `Dimension LTMCTDimensionBase`, provided so that
the familiar `.length`, `.time`, `.mass`, `.charge`, `.temperature` API is available.

-/

/-- The length exponent of a `LTMCTDimensionBase` dimension. -/
def length (d : Dimension LTMCTDimensionBase) : ℚ := d.exponent .length
/-- The time exponent of a `LTMCTDimensionBase` dimension. -/
def time (d : Dimension LTMCTDimensionBase) : ℚ := d.exponent .time
/-- The mass exponent of a `LTMCTDimensionBase` dimension. -/
def mass (d : Dimension LTMCTDimensionBase) : ℚ := d.exponent .mass
/-- The charge exponent of a `LTMCTDimensionBase` dimension. -/
def charge (d : Dimension LTMCTDimensionBase) : ℚ := d.exponent .charge
/-- The temperature exponent of a `LTMCTDimensionBase` dimension. -/
def temperature (d : Dimension LTMCTDimensionBase) : ℚ := d.exponent .temperature

/-- Build a `LTMCTDimensionBase` dimension from its five exponents, in the order
  `⟨length, time, mass, charge, temperature⟩`. -/
def ofLTMCTDimensionBase (length time mass charge temperature : ℚ) : Dimension LTMCTDimensionBase :=
  ⟨fun
    | .length => length
    | .time => time
    | .mass => mass
    | .charge => charge
    | .temperature => temperature⟩

@[simp]
lemma ofLTMCTDimensionBase_length (l t m c θ : ℚ) :
    (ofLTMCTDimensionBase l t m c θ).length = l := rfl

@[simp]
lemma ofLTMCTDimensionBase_time (l t m c θ : ℚ) :
    (ofLTMCTDimensionBase l t m c θ).time = t := rfl

@[simp]
lemma ofLTMCTDimensionBase_mass (l t m c θ : ℚ) :
    (ofLTMCTDimensionBase l t m c θ).mass = m := rfl

@[simp]
lemma ofLTMCTDimensionBase_charge (l t m c θ : ℚ) :
    (ofLTMCTDimensionBase l t m c θ).charge = c := rfl

@[simp]
lemma ofLTMCTDimensionBase_temperature (l t m c θ : ℚ) :
    (ofLTMCTDimensionBase l t m c θ).temperature = θ := rfl

@[simp]
lemma time_mul (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 * d2).time = d1.time + d2.time := rfl

@[simp]
lemma length_mul (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 * d2).length = d1.length + d2.length := rfl

@[simp]
lemma mass_mul (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 * d2).mass = d1.mass + d2.mass := rfl

@[simp]
lemma charge_mul (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 * d2).charge = d1.charge + d2.charge := rfl

@[simp]
lemma temperature_mul (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 * d2).temperature = d1.temperature + d2.temperature := rfl

@[simp]
lemma one_length : (1 : Dimension LTMCTDimensionBase).length = 0 := rfl
@[simp]
lemma one_time : (1 : Dimension LTMCTDimensionBase).time = 0 := rfl

@[simp]
lemma one_mass : (1 : Dimension LTMCTDimensionBase).mass = 0 := rfl

@[simp]
lemma one_charge : (1 : Dimension LTMCTDimensionBase).charge = 0 := rfl

@[simp]
lemma one_temperature : (1 : Dimension LTMCTDimensionBase).temperature = 0 := rfl

@[simp]
lemma inv_length (d : Dimension LTMCTDimensionBase) : d⁻¹.length = -d.length := rfl

@[simp]
lemma inv_time (d : Dimension LTMCTDimensionBase) : d⁻¹.time = -d.time := rfl

@[simp]
lemma inv_mass (d : Dimension LTMCTDimensionBase) : d⁻¹.mass = -d.mass := rfl

@[simp]
lemma inv_charge (d : Dimension LTMCTDimensionBase) : d⁻¹.charge = -d.charge := rfl

@[simp]
lemma inv_temperature (d : Dimension LTMCTDimensionBase) : d⁻¹.temperature = -d.temperature := rfl

@[simp]
lemma div_length (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 / d2).length = d1.length - d2.length := by
  simp only [length, div_exponent]

@[simp]
lemma div_time (d1 d2 : Dimension LTMCTDimensionBase) : (d1 / d2).time = d1.time - d2.time := by
  simp only [time, div_exponent]

@[simp]
lemma div_mass (d1 d2 : Dimension LTMCTDimensionBase) : (d1 / d2).mass = d1.mass - d2.mass := by
  simp only [mass, div_exponent]

@[simp]
lemma div_charge (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 / d2).charge = d1.charge - d2.charge := by
  simp only [charge, div_exponent]

@[simp]
lemma div_temperature (d1 d2 : Dimension LTMCTDimensionBase) :
    (d1 / d2).temperature = d1.temperature - d2.temperature := by
  simp only [temperature, div_exponent]

@[simp]
lemma npow_length (d : Dimension LTMCTDimensionBase) (n : ℕ) : (d ^ n).length = n • d.length := by
  simp only [length, npow_exponent]

@[simp]
lemma npow_time (d : Dimension LTMCTDimensionBase) (n : ℕ) : (d ^ n).time = n • d.time := by
  simp only [time, npow_exponent]

@[simp]
lemma npow_mass (d : Dimension LTMCTDimensionBase) (n : ℕ) : (d ^ n).mass = n • d.mass := by
  simp only [mass, npow_exponent]

@[simp]
lemma npow_charge (d : Dimension LTMCTDimensionBase) (n : ℕ) : (d ^ n).charge = n • d.charge := by
  simp only [charge, npow_exponent]

@[simp]
lemma npow_temperature (d : Dimension LTMCTDimensionBase) (n : ℕ) :
    (d ^ n).temperature = n • d.temperature := by
  simp only [temperature, npow_exponent]

/-- The dimension corresponding to length. -/
def L𝓭 : Dimension LTMCTDimensionBase := ofLTMCTDimensionBase 1 0 0 0 0

@[simp]
lemma L𝓭_length : L𝓭.length = 1 := by rfl

@[simp]
lemma L𝓭_time : L𝓭.time = 0 := by rfl

@[simp]
lemma L𝓭_mass : L𝓭.mass = 0 := by rfl

@[simp]
lemma L𝓭_charge : L𝓭.charge = 0 := by rfl

@[simp]
lemma L𝓭_temperature : L𝓭.temperature = 0 := by rfl

/-- The dimension corresponding to time. -/
def T𝓭 : Dimension LTMCTDimensionBase := ofLTMCTDimensionBase 0 1 0 0 0

@[simp]
lemma T𝓭_length : T𝓭.length = 0 := by rfl

@[simp]
lemma T𝓭_time : T𝓭.time = 1 := by rfl

@[simp]
lemma T𝓭_mass : T𝓭.mass = 0 := by rfl

@[simp]
lemma T𝓭_charge : T𝓭.charge = 0 := by rfl

@[simp]
lemma T𝓭_temperature : T𝓭.temperature = 0 := by rfl

/-- The dimension corresponding to mass. -/
def M𝓭 : Dimension LTMCTDimensionBase := ofLTMCTDimensionBase 0 0 1 0 0

/-- The dimension corresponding to charge. -/
def C𝓭 : Dimension LTMCTDimensionBase := ofLTMCTDimensionBase 0 0 0 1 0

/-- The dimension corresponding to temperature. -/
def Θ𝓭 : Dimension LTMCTDimensionBase := ofLTMCTDimensionBase 0 0 0 0 1

/-!

## The named generators are the base vectors

Each named generator `L𝓭`, `T𝓭`, … is the generic `single` base vector at the
corresponding base dimension, exhibiting them as instances of the basis-generic API.

-/

lemma L𝓭_eq_single : L𝓭 = single .length := by
  ext b; cases b <;> simp [L𝓭, ofLTMCTDimensionBase, single_exponent]

lemma T𝓭_eq_single : T𝓭 = single .time := by
  ext b; cases b <;> simp [T𝓭, ofLTMCTDimensionBase, single_exponent]

lemma M𝓭_eq_single : M𝓭 = single .mass := by
  ext b; cases b <;> simp [M𝓭, ofLTMCTDimensionBase, single_exponent]

lemma C𝓭_eq_single : C𝓭 = single .charge := by
  ext b; cases b <;> simp [C𝓭, ofLTMCTDimensionBase, single_exponent]

lemma Θ𝓭_eq_single : Θ𝓭 = single .temperature := by
  ext b; cases b <;> simp [Θ𝓭, ofLTMCTDimensionBase, single_exponent]

end Dimension
