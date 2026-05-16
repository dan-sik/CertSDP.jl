using CertSDP
using JuMP
import MathOptInterface as MOI

model = GenericModel{Rational{BigInt}}()
@variable(model, a)
@variable(model, b)
@constraint(model, first_block, [1 + a, b, 3 - a] in
                                MOI.PositiveSemidefiniteConeTriangle(2))
@constraint(model, second_block, [2 - b, 0, 1 + a] in
                                 MOI.PositiveSemidefiniteConeTriangle(2))

problem = CertSDP.extract_lmi(model)
blocks = CertSDP.substitute(problem, [0, 0])

@assert all(CertSDP.verify_psd_rational(block) for block in blocks)
println("extracted ", CertSDP.num_blocks(problem), " PSD blocks with sizes ",
        CertSDP.block_sizes(problem))
println("first JuMP variable mapping: ", problem.metadata[:variables][1])
