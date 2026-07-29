import VersoManual
import MonthlyDoc

open Verso.Genre Manual

def config : RenderConfig := {
  emitTeX := true
  emitHtmlSingle := .no
  emitHtmlMulti := .no
}

def main := manualMain (%doc MonthlyDoc) (config := config)
