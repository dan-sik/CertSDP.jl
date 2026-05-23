using CertSDP
using Test

const CERTSDP_TEST_ARGS = Set(String.(ARGS))
const CERTSDP_DEFAULT_TAGS = Set(["essential", "regression", "cli"])
const CERTSDP_ACTIVE_ALL_TAGS = Set(["essential", "regression", "cli",
                                     "command", "validation", "release_smoke",
                                     "docs", "failure", "tooling", "compiler",
                                     "production", "hardgate_real"])
const CERTSDP_SELECTED_TAGS = if isempty(CERTSDP_TEST_ARGS)
    CERTSDP_DEFAULT_TAGS
elseif "certsdp3" in CERTSDP_TEST_ARGS &&
       !isdisjoint(CERTSDP_TEST_ARGS, Set(["all", "full"]))
    union(setdiff(CERTSDP_TEST_ARGS, Set(["all", "full"])),
          setdiff(CERTSDP_ACTIVE_ALL_TAGS,
                  Set(["hardgate_real", "production"])))
elseif !isdisjoint(CERTSDP_TEST_ARGS, Set(["all", "full"]))
    union(setdiff(CERTSDP_TEST_ARGS, Set(["all", "full"])),
          CERTSDP_ACTIVE_ALL_TAGS)
elseif "certsdp3" in CERTSDP_TEST_ARGS
    Set(["certsdp3"])
else
    CERTSDP_TEST_ARGS
end

function certsdp_should_run(tags::String...)
    return any(tag -> tag in CERTSDP_SELECTED_TAGS, tags)
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
    @test CertSDP.package_marker() === :exact_certificate_compiler
    @test CertSDP.package_version() == v"2.1.0"
end

certsdp_include("lmi/rational_core.jl", "essential", "core", "lmi")
certsdp_include("lmi/json_io.jl", "essential", "core", "lmi", "schema")
certsdp_include("verify/rational_psd.jl", "essential", "core", "verifier",
                "regression")
certsdp_include("exactify/exactify_sos.jl", "essential", "exactify", "sos")
certsdp_include("cli/main.jl", "essential", "cli", "command", "release_smoke")
certsdp_include("compiler/regression.jl", "essential", "validation",
                "regression", "compiler")
certsdp_include("benchmark/validation_suite.jl", "validation")
certsdp_include("certify/failure_reports.jl", "failure", "release_smoke")
certsdp_include("release_audit_scripts.jl", "tooling", "release_smoke")
certsdp_include("release_hardening.jl", "release_smoke")
certsdp_include("readme_snippets.jl", "essential", "docs", "release_smoke")
certsdp_include("docs/public_docs.jl", "docs", "release_smoke")
certsdp_include("hardgate_4_0.jl", "hardgate", "contract")
certsdp_include("hardgate_4_0_real_artifacts.jl", "hardgate_real", "release",
                "contract")
certsdp_include("production_gates_2_1.jl", "production")
certsdp_include("certsdp3/runtests_certsdp3.jl", "certsdp3", "validation")
