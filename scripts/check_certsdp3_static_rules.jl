#!/usr/bin/env julia

const ROOT = normpath(joinpath(@__DIR__, ".."))

function each_source_file(dir)
    files = String[]
    isdir(dir) || return files
    for (root, _, names) in walkdir(dir)
        for name in names
            endswith(name, ".jl") && push!(files, joinpath(root, name))
        end
    end
    return files
end

function rel(path)
    return relpath(path, ROOT)
end

function line_has_diagnostic_justification(lines, index)
    window_start = max(1, index - 2)
    return any(i -> occursin("CERTSDP_NUMERIC_DIAGNOSTIC_ONLY", lines[i]),
               window_start:index)
end

function scan_forbidden_markers!(failures)
    production_dirs = ["src/kernel", "src/perf", "src/apps", "src/schemas",
                       "src/reports", "src/adapters", "src/exactify"]
    forbidden_words = r"TODO|FIXME|STUB|not implemented|placeholder"
    for dir in production_dirs
        for file in each_source_file(joinpath(ROOT, dir))
            text = read(file, String)
            occursin(forbidden_words, text) &&
                push!(failures, "forbidden marker in $(rel(file))")
        end
    end
end

function scan_trusted_path!(failures)
    trusted_files = [
        "src/kernel/Kernel.jl",
        "src/kernel/TrustedKernel.jl",
        "src/kernel/CertificateDAG.jl",
        "src/kernel/StrictSchema.jl",
        "src/kernel/ExactArithmeticSafety.jl",
        "src/kernel/SparseBlockChordal.jl",
        "src/kernel/PSDProofs.jl",
        "src/kernel/SOSProofs.jl",
        "src/kernel/NCQuantumProofs.jl",
        "src/kernel/AlgebraicFields.jl",
        "src/kernel/CanonicalHash.jl",
    ]
    forbidden_numeric = [
        r"\bFloat64\b",
        r"\bBigFloat\b",
        r"\bisapprox\b",
        r"\beigvals\b",
        r"\beigen\b",
        r"\bsvd\b",
        r"\bcholesky\b",
        r"≈",
    ]
    forbidden_acceptance = [
        r"solver_status",
        r"status\s*==\s*:?[Oo]ptimal",
        r"status\s*==\s*\"optimal\"",
        r"\"accepted\"\s*=>\s*true",
        r":accepted\s*=>\s*true",
        r"certificate_valid",
    ]
    for file_rel in trusted_files
        file = joinpath(ROOT, file_rel)
        isfile(file) || begin
            push!(failures, "trusted path file missing: $file_rel")
            continue
        end
        lines = split(read(file, String), '\n')
        in_forbidden_key_declaration = false
        for (index, line) in enumerate(lines)
            occursin("FORBIDDEN_TRUST_KEYS", line) &&
                (in_forbidden_key_declaration = true)
            for pattern in forbidden_numeric
                if occursin(pattern, line) &&
                   !line_has_diagnostic_justification(lines, index)
                    push!(failures,
                          "numeric fallback token in trusted path $file_rel:$index")
                end
            end
            if occursin(r"(?<![A-Za-z0-9_])Matrix\(", line)
                push!(failures,
                      "possible densification token Matrix(...) in trusted path $file_rel:$index")
            end
            if occursin(r"\brand\b", line) || occursin(r"\btime\(\)", line)
                push!(failures,
                      "nondeterministic token in trusted path $file_rel:$index")
            end
            for pattern in forbidden_acceptance
                occursin(pattern, line) &&
                    !in_forbidden_key_declaration &&
                    push!(failures,
                          "forbidden acceptance token in trusted path $file_rel:$index")
            end
            occursin(r"catch[^\\n]*return\s+true", line) &&
                push!(failures,
                      "catch-return-true pattern in trusted path $file_rel:$index")
            in_forbidden_key_declaration && occursin("])", line) &&
                (in_forbidden_key_declaration = false)
        end
    end
end

function scan_tests!(failures)
    allowlist = joinpath(ROOT, "test", "ALLOWLIST_BROKEN_TESTS.toml")
    allowlisted = isfile(allowlist) ? read(allowlist, String) : ""
    for test_file in each_source_file(joinpath(ROOT, "test", "certsdp3"))
        text = read(test_file, String)
        if occursin("@test_skip", text) && !occursin(rel(test_file), allowlisted)
            push!(failures, "@test_skip in $(rel(test_file))")
        end
        if occursin("@test_broken", text) && !occursin(rel(test_file), allowlisted)
            push!(failures, "@test_broken in $(rel(test_file))")
        end
    end
end

function scan_schemas!(failures)
    required_schemas = [
        "certsdp_certificate_v3.schema.json",
        "certsdp_problem_v3.schema.json",
        "certsdp_sparse_lmi_v3.schema.json",
        "certsdp_sos_v3.schema.json",
        "certsdp_nc_quantum_v3.schema.json",
        "certsdp_report_v3.schema.json",
    ]
    for schema in required_schemas
        schema_path = joinpath(ROOT, "schemas", schema)
        isfile(schema_path) ||
            push!(failures, "missing schema $schema")
        isfile(schema_path) || continue
        schema_text = read(schema_path, String)
        occursin("reserved_for", schema_text) &&
            push!(failures, "schema $schema still contains reserved_for marker")
        occursin("\"additionalProperties\": false", schema_text) ||
            push!(failures, "schema $schema does not visibly fail closed")
    end

    certificate_schema = joinpath(ROOT, "schemas",
                                  "certsdp_certificate_v3.schema.json")
    if isfile(certificate_schema)
        text = read(certificate_schema, String)
        for family in ["block_native_algebraic", "primal_dual_optimality",
                       "farkas_infeasibility", "sparse_sos",
                       "quantum_bound", "symmetry_reduction"]
            occursin(family, text) ||
                push!(failures,
                      "certificate schema missing family branch $family")
        end
    end
end

function scan_cli_help!(failures)
    output = read(joinpath(ROOT, "src", "cli", "Main.jl"), String) *
             read(joinpath(ROOT, "src", "apps", "Apps.jl"), String)
    for token in ["replay", "diagnose", "schema validate", "import tssos",
                  "import nctssos", "certify", "bundle", "version"]
        occursin(token, output) ||
            push!(failures, "CLI help missing `$token`")
    end
end

function main()
    failures = String[]
    scan_forbidden_markers!(failures)
    scan_trusted_path!(failures)
    scan_tests!(failures)
    scan_schemas!(failures)
    try
        scan_cli_help!(failures)
    catch err
        push!(failures, "CLI help smoke check failed: $(sprint(showerror, err))")
    end

    println("CERTSDP3_STATIC_RULES")
    if isempty(failures)
        println("result: PASS")
        return 0
    end
    println("result: FAIL")
    for failure in failures
        println("failure: ", failure)
    end
    return 1
end

exit(main())
