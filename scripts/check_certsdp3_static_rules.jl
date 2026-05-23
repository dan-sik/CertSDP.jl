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

function main()
    failures = String[]
    production_dirs = ["src/kernel", "src/perf", "src/apps", "src/schemas",
                       "src/reports", "src/adapters", "src/exactify"]
    forbidden_words = r"TODO|FIXME|STUB|not implemented|placeholder"
    for dir in production_dirs
        for file in each_source_file(joinpath(ROOT, dir))
            text = read(file, String)
            occursin(forbidden_words, text) &&
                push!(failures, "forbidden marker in $file")
            if occursin(r"Float64|BigFloat|eigvals|eig\(|svd|isapprox|≈", text) &&
               !occursin("CERTSDP_NUMERIC_DIAGNOSTIC_ONLY", text)
                push!(failures, "numeric verifier token without diagnostic justification in $file")
            end
            if occursin(r"(?<![A-Za-z0-9_])Matrix\(", text) &&
               occursin("src/kernel", file)
                push!(failures, "possible densification token Matrix(...) in $file")
            end
        end
    end

    for test_file in each_source_file(joinpath(ROOT, "test", "certsdp3"))
        text = read(test_file, String)
        occursin("@test_skip", text) && push!(failures, "@test_skip in $test_file")
        occursin("@test_broken", text) && push!(failures, "@test_broken in $test_file")
    end

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
            push!(failures, "schema $schema still contains reserved_for placeholder")
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
