import Lake
open Lake DSL

require verso from git "https://github.com/leanprover/verso" @ "main"

package «monthly-diffs-doc» where

@[default_target]
lean_lib MonthlyDoc where
  roots := #[`MonthlyDoc]

@[default_target]
lean_exe monthlydoc where
  root := `Main
  supportInterpreter := true
