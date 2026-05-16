using CertSDP
using JuMP

model = GenericModel{Rational{BigInt}}()
@variable(model, X[1:2, 1:2], PSD)

problem = CertSDP.extract_lmi(model)
certificate = CertSDP.RationalCertificate(problem, [1, 0, 1])

@assert verify(certificate)
println("PSD matrix variable extracted as variables ",
        join(String.(CertSDP.variable_symbols(problem)), ", "))
