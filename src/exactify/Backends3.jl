module Exactify3

using ..Kernel

export exactify_layer_marker,
       AlgebraicCandidateBackend,
       MsolveCandidateBackend,
       SageMsolveCandidateBackend,
       FixtureCandidateBackend,
       NullCandidateBackend,
       CandidateSet,
       build_candidate_system,
       solve_candidates,
       candidate_provenance,
       replay_candidate

abstract type AlgebraicCandidateBackend end

struct MsolveCandidateBackend <: AlgebraicCandidateBackend
    executable::Union{Nothing, String}
end

struct SageMsolveCandidateBackend <: AlgebraicCandidateBackend
    executable::Union{Nothing, String}
end

struct FixtureCandidateBackend <: AlgebraicCandidateBackend
    fixture_path::String
end

struct NullCandidateBackend <: AlgebraicCandidateBackend end

struct CandidateSet
    status::Symbol
    candidates::Vector{Any}
    provenance::Dict{Symbol, Any}
end

exactify_layer_marker() = :certsdp3_untrusted_candidate_generation

build_candidate_system(problem, obligations=nothing; metadata=Dict{Symbol, Any}()) =
    Dict{Symbol, Any}(:problem => problem,
                      :obligations => obligations,
                      :metadata => Dict{Symbol, Any}(metadata))

function solve_candidates(system, backend::FixtureCandidateBackend)::CandidateSet
    if !isfile(backend.fixture_path)
        return CandidateSet(:unavailable,
                            Any[],
                            Dict{Symbol, Any}(:backend => :fixture,
                                              :fixture_path => backend.fixture_path))
    end
    cert = try
        Kernel.parse_certificate_json_v3(read(backend.fixture_path, String);
                                         strict=true)
    catch err
        return CandidateSet(:parse_failed,
                            Any[],
                            Dict{Symbol, Any}(:backend => :fixture,
                                              :fixture_path => backend.fixture_path,
                                              :message => sprint(showerror, err)))
    end
    return CandidateSet(:finite,
                        Any[cert],
                        Dict{Symbol, Any}(:backend => :fixture,
                                          :fixture_path => backend.fixture_path,
                                          :system_hash => _candidate_system_hash(system)))
end

function solve_candidates(system, ::NullCandidateBackend)::CandidateSet
    return CandidateSet(:unavailable,
                        Any[],
                        Dict{Symbol, Any}(:backend => :null,
                                          :system_hash => _candidate_system_hash(system)))
end

function solve_candidates(system, backend::MsolveCandidateBackend)::CandidateSet
    return CandidateSet(:unavailable,
                        Any[],
                        Dict{Symbol, Any}(:backend => :msolve,
                                          :executable => backend.executable,
                                          :system_hash => _candidate_system_hash(system)))
end

function solve_candidates(system, backend::SageMsolveCandidateBackend)::CandidateSet
    return CandidateSet(:unavailable,
                        Any[],
                        Dict{Symbol, Any}(:backend => :sage_msolve,
                                          :executable => backend.executable,
                                          :system_hash => _candidate_system_hash(system)))
end

candidate_provenance(set::CandidateSet) = set.provenance

function replay_candidate(candidate, obligations=nothing)
    if candidate isa Kernel.V3Certificate
        return Kernel.verify_certificate(candidate)
    end
    return Kernel.DiagnosticReport(false,
                                   :A,
                                   :exactify_candidate,
                                   :candidate_replay,
                                   "exactify candidate is not a CertSDP v3 certificate",
                                   :candidate_payload,
                                   nothing,
                                   nothing,
                                   nothing,
                                   nothing,
                                   nothing,
                                   nothing,
                                   Dict{Symbol, Any}(:obligations => string(obligations)))
end

function _candidate_system_hash(system)
    return Kernel._sha256_payload((; system=string(typeof(system))))
end

end
