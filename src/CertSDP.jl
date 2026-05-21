module CertSDP

using LinearAlgebra: det, dot
using Random: MersenneTwister, shuffle!

# The stable public surface is deliberately small. The exact certificate
# compiler internals stay module-qualified unless promoted in docs/API_STABILITY.md.
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
include("sos/AlgebraicSOSGram.jl")
include("adapters/ExternalAdapters.jl")
include("nc/WordAlgebra.jl")
include("nc/NCSOSGram.jl")
include("proof/ProofObligations.jl")
include("certify/Certifier.jl")
include("exactify/Exactify.jl")
include("benchmark/Benchmarks.jl")
include("input/SchemaV1.jl")
include("verify/StrictVerifier.jl")
include("compiler/ExactCertificateCompiler.jl")
include("compiler/RealArtifactReconstruction.jl")
include("compiler/FinalArtifactReconstruction.jl")
include("tooling/ReplayTools.jl")
include("tooling/PaperArtifacts.jl")
include("cli/Main.jl")

"""
package_marker() -> Symbol

Return the current release-line marker.
"""
package_marker() = :exact_certificate_compiler

"""
    package_version() -> VersionNumber

Return the CertSDP package version for the current release.
"""
package_version() = v"2.1.0"

end
