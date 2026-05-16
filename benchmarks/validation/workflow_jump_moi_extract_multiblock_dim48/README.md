# Workflow JuMP/MOI Extract Multi-block dim48

Non-SDPA imported workflow case. The benchmark does not ship a hand-written
`problem.json`; instead, the runner executes `source.jl` under the optional
`examples/jump` environment, builds a JuMP `GenericModel{Rational{BigInt}}`
with six affine PSD constraints, extracts the MOI model into a CertSDP block
LMI, certifies the zero rational point, and strict-verifies the generated
blockwise certificate.

The reported source is `jump_moi_extract`.
