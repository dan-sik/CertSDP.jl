using CertSDP
using JuMP

model = GenericModel{Rational{BigInt}}()
@variable(model, x)
@variable(model, y)
@constraint(model, psd_square, [1 + x y; y 2 - x] in PSDCone())

problem = CertSDP.extract_lmi(model)
certificate = CertSDP.RationalCertificate(problem, [0, 0])

@assert verify(certificate)
println("extracted ", CertSDP.matrix_size(problem), "x", CertSDP.matrix_size(problem),
        " LMI with ", CertSDP.num_variables(problem), " CertSDP variables")
