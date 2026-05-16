using CertSDP
using DynamicPolynomials
using SumOfSquares

@polyvar x

model = SOSModel()
cref = @constraint(model, x^2 + 1 in SOSCone())

# In a production solve, this Gram matrix may come from SumOfSquares. For this
# exact tutorial example we provide it explicitly, so the CertSDP verifier never
# trusts floating point solver output. Some JuMP/SumOfSquares constraint
# functions still expose Float64 polynomial coefficients, so reconstruction is
# opt-in and followed by exact coefficient matching.
cert = certify_sos(model;
                   gram_matrices=[[1//1 0//1; 0//1 1//1]],
                   reconstruct_floats=true,
                   tolerance=1e-12)

@assert verify_sos(cert)
println(sos_decomposition_text(cert))
