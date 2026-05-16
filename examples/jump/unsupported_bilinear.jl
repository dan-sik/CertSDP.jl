using CertSDP
using JuMP
import MathOptInterface as MOI

model = GenericModel{Rational{BigInt}}()
@variable(model, x)
@variable(model, y)
@constraint(model, [x * y, 0, 1] in MOI.PositiveSemidefiniteConeTriangle(2))

try
    CertSDP.extract_lmi(model)
catch err
    @assert err isa ArgumentError
    println(err)
end
