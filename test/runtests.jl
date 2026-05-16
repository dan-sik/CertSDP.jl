using CertSDP
using Test

const CERTSDP_TEST_ARGS = Set(String.(ARGS))
const CERTSDP_RUN_ALL = isempty(CERTSDP_TEST_ARGS) || "all" in CERTSDP_TEST_ARGS

function certsdp_should_run(tags::String...)
    return CERTSDP_RUN_ALL || any(tag -> tag in CERTSDP_TEST_ARGS, tags)
end

function certsdp_include(path::AbstractString, tags::String...)
    certsdp_should_run(tags...) && include(path)
    return nothing
end

# Internal package tests intentionally exercise non-exported implementation
# pieces. Those names stay outside the public compatibility surface, so the
# test harness imports them explicitly without widening `using CertSDP`.
for name in names(CertSDP; all=true)
    text = String(name)
    (occursin("#", text) || startswith(text, "_")) && continue
    name in (:CertSDP, :eval, :include) && continue
    isdefined(@__MODULE__, name) && continue
    @eval const $(name) = getproperty(CertSDP, $(QuoteNode(name)))
end

@testset "CertSDP package skeleton" begin
    @test isdefined(CertSDP, :package_marker)
    @test CertSDP.package_marker() === :validation_release
    @test CertSDP.package_version() == v"1.0.0"
end

certsdp_include("lmi/rational_core.jl", "core", "lmi")
certsdp_include("lmi/json_io.jl", "core", "lmi", "schema")
certsdp_include("lmi/sdpa_io.jl", "lmi", "schema", "release_smoke")
certsdp_include("lmi/jump_moi_integration.jl", "lmi", "optional")
certsdp_include("verify/rational_psd.jl", "core", "verifier", "adversarial")
certsdp_include("verify/algebraic_psd.jl", "verifier", "adversarial")
certsdp_include("certificates/rational_certificate.jl", "core", "verifier",
                "adversarial")
certsdp_include("certificates/algebraic_certificate.jl", "verifier",
                "adversarial")
certsdp_include("algebraic/algebraic_numbers.jl", "algebraic", "verifier",
                "adversarial")
certsdp_include("algebraic/sign_tests.jl", "algebraic", "verifier",
                "adversarial")
certsdp_include("algebraic/polynomial_system.jl", "algebraic")
certsdp_include("numeric/approx_solution.jl", "numeric")
certsdp_include("systems/incidence_builder.jl", "algebraic")
certsdp_include("backends/msolve_backend.jl", "backend")
certsdp_include("certify/certifier.jl", "certifier")
certsdp_include("sos/sos_gram.jl", "sos", "verifier", "adversarial")
certsdp_include("sos/positive_certificates.jl", "sos", "verifier",
                "release_smoke")
certsdp_include("cli/main.jl", "cli", "release_smoke")
certsdp_include("benchmark/validation_suite.jl", "validation", "release_smoke")
certsdp_include("certify/failure_reports.jl", "failure", "release_smoke")
certsdp_include("performance/performance_caching.jl", "performance")
certsdp_include("tooling_reproducibility.jl", "tooling", "release_smoke")
certsdp_include("release_audit_scripts.jl", "tooling", "release_smoke")
certsdp_include("validation_budget.jl", "validation", "release_smoke")
certsdp_include("adversarial/verifier_hardening.jl", "adversarial")
certsdp_include("adversarial/strict_trust_boundary.jl", "adversarial")
certsdp_include("release_hardening.jl", "release_smoke")
certsdp_include("schema_v1.jl", "schema", "release_smoke")
certsdp_include("public_api_schema.jl", "schema", "release_smoke")
certsdp_include("readme_snippets.jl", "docs", "release_smoke")
certsdp_include("lmi/multiblock_certificates.jl", "lmi", "validation")
certsdp_include("algebraic_robustness.jl", "algebraic")
certsdp_include("numerical_oracle_workflow.jl", "numeric")
certsdp_include("docs/public_docs.jl", "docs", "release_smoke")
