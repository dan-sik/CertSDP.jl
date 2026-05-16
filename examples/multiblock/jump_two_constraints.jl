using CertSDP
using JuMP

model = GenericModel{Rational{BigInt}}()
@variable(model, x)
@variable(model, y)
@constraint(model, [1 + x y; y 3 - x] in PSDCone())
@constraint(model, [2 - y 0; 0 1 + x] in PSDCone())

problem = CertSDP.extract_lmi(model)
result = CertSDP.certify(problem, [0 // 1, 0 // 1])

@assert CertSDP.verify(result)
println("certified ", CertSDP.num_blocks(problem), " PSD blocks")
