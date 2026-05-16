module CertSDP

using LinearAlgebra: det, dot

# The v1.0 compatibility surface is deliberately small. Everything else in this
# module is internal unless promoted in docs/API_STABILITY.md.
export LMIProblem,
       BlockLMIProblem,
       certify,
       verify,
       diagnose,
       read_problem,
       write_problem,
       read_certificate,
       write_certificate,
       certify_sos,
       verify_sos,
       export_sos_decomposition,
       sos_decomposition_text,
       sos_decomposition_latex,
       sos_decomposition_sage,
       sos_decomposition_julia

include("input/LMIProblem.jl")
include("input/JSONParser.jl")
include("input/SDPAParser.jl")
include("numeric/ApproxSolution.jl")
include("performance/Performance.jl")
include("capabilities/ResourceProfiles.jl")
include("algebraic/AlgebraicNumbers.jl")
include("algebraic/AlgebraicLMI.jl")
include("algebraic/SignTests.jl")
include("algebraic/PolynomialSystem.jl")
include("certify/Results.jl")
include("backends/AlgebraicBackend.jl")
include("backends/MsolveBackend.jl")
include("systems/IncidenceBuilder.jl")
include("verify/VerifyPSD.jl")
include("certificates/RationalCertificate.jl")
include("certificates/AlgebraicCertificate.jl")
include("sos/SOSGram.jl")
include("sos/PositiveCertificates.jl")
include("certify/Certifier.jl")
include("benchmark/Benchmarks.jl")
include("input/SchemaV1.jl")
include("verify/StrictVerifier.jl")
include("tooling/ReplayTools.jl")
include("cli/Main.jl")

"""
package_marker() -> Symbol

Return the current release-line marker.
"""
package_marker() = :validation_release

"""
    package_version() -> VersionNumber

Return the CertSDP package version for the current release.
"""
package_version() = v"1.0.0"

end
