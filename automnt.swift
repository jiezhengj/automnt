#!/usr/bin/env swift
// Sole marketing version source. Build through scripts/build.sh.
let automntVersion = "3.5.1"

#if canImport(AutomntCLI)
import AutomntCLI
#endif
runAutomntCLI()
