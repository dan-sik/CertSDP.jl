module CertSDP

using LinearAlgebra: det, dot
using Random: MersenneTwister, shuffle!
using SHA: sha256

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
       import_tssos_artifact,
       certify_tssos_artifact,
       verify_tssos_certificate,
       import_nctssos_artifact,
       certify_nctssos_artifact,
       ExactField,
       NumberField,
       field_hash,
       field_element_string,
       parse_field_element,
       verify_field_element,
       export_sos_decomposition,
       sos_decomposition_text,
       sos_decomposition_latex,
       sos_decomposition_sage,
       sos_decomposition_julia

include("kernel/Kernel.jl")
include("kernel/Debug.jl")
include("exactify/Backends3.jl")
include("schemas/Schemas.jl")
include("reports/Reports.jl")
include("perf/Perf.jl")
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
include("adapters/Adapters.jl")
include("apps/Apps.jl")
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
include("compiler/AbsoluteGateReconstruction.jl")
include("compiler/PerfectGateReconstruction.jl")
include("tooling/ReplayTools.jl")
include("tooling/PaperArtifacts.jl")
include("cli/Main.jl")

const SparseSOSCertificateCandidate = Adapters.SparseSOSCertificateCandidate
const QuantumCertificateCandidate = Adapters.QuantumCertificateCandidate
import_tssos_artifact(args...; kwargs...) =
    Adapters.import_tssos_artifact(args...; kwargs...)
certify_tssos_artifact(args...; kwargs...) =
    Adapters.certify_tssos_artifact(args...; kwargs...)
verify_tssos_certificate(args...; kwargs...) =
    Adapters.verify_tssos_certificate(args...; kwargs...)
tssos_artifact_hash(args...; kwargs...) =
    Adapters.tssos_artifact_hash(args...; kwargs...)
write_tssos_candidate(args...; kwargs...) =
    Adapters.write_tssos_candidate(args...; kwargs...)
import_nctssos_artifact(args...; kwargs...) =
    Adapters.import_nctssos_artifact(args...; kwargs...)
certify_nctssos_artifact(args...; kwargs...) =
    Adapters.certify_nctssos_artifact(args...; kwargs...)
write_nctssos_candidate(args...; kwargs...) =
    Adapters.write_nctssos_candidate(args...; kwargs...)

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
