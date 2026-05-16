# Algebraic Certifier Quartic dim10 n2

Two-variable quartic incidence pipeline success case. The second variable
enters the LMI coefficient matrix and the approximate seed places it at zero,
so bounded rational rounding still genuinely fails on the quartic coordinate.

The runner starts from the approximate candidate, runs the msolve-backed
incidence certifier, generates an algebraic certificate, and strict-verifies
the result. This is the validation suite's certifier-generated algebraic
success case.
