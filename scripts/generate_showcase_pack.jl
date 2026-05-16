using CertSDP
using JSON3

const C = CertSDP
const ROOT = normpath(joinpath(@__DIR__, ".."))

term(exponents, coefficient) = C.PolynomialTerm(exponents, coefficient)
poly(pairs) = [term(exponents, coefficient) for (exponents, coefficient) in pairs]
square(variable_count, pairs) = C.SOSSquare(poly(pairs), variable_count)
rstr(value) = value isa AbstractString ? value : C._rational_string(value)

function scaled_square(variable_count, factor, pairs)
    return square(variable_count,
                  [(exponents, factor * coefficient)
                   for (exponents, coefficient) in pairs])
end

function write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.pretty(io, value)
        println(io)
    end
    return path
end

function write_rational_function_entry(entries, relpath, title, variables, target,
                                       numerator_squares, denominator_squares;
                                       group, claim, source)
    path = joinpath(ROOT, relpath)
    mkpath(dirname(path))
    cert = C.RationalFunctionSOSCertificate(Symbol.(variables), poly(target),
                                            numerator_squares,
                                            denominator_squares;
                                            metadata=Dict{Symbol, Any}(:source => source))
    C.write_certificate(path, cert)
    @assert C.verify(cert)
    @assert C.verify_strict(path)
    push!(entries,
          (;
           kind="certificate",
           group,
           title,
           path=relpath,
           certificate_type="rational_function_sos_certificate",
           claim,
           variables,
           numerator_squares=length(numerator_squares),
           denominator_squares=length(denominator_squares),
           exact_check="denominator * polynomial == numerator_sos",
           command="bin/certsdp verify --strict $relpath",))
    return cert
end

function write_positivstellensatz_entry(entries, relpath, title, variables, target,
                                        constraints, terms;
                                        group, claim, source)
    path = joinpath(ROOT, relpath)
    mkpath(dirname(path))
    cert = C.PositivstellensatzCertificate(Symbol.(variables), poly(target),
                                           constraints, terms;
                                           metadata=Dict{Symbol, Any}(:source => source))
    C.write_certificate(path, cert)
    @assert C.verify(cert)
    @assert C.verify_strict(path)
    push!(entries,
          (;
           kind="certificate",
           group,
           title,
           path=relpath,
           certificate_type="positivstellensatz_certificate",
           claim,
           variables,
           constraints=length(constraints),
           multiplier_terms=length(terms),
           exact_check="target == sum sos_multiplier * constraint_product",
           command="bin/certsdp verify --strict $relpath",))
    return cert
end

function write_sostools_lite_entry(entries, relpath, title, variables, basis,
                                   polynomial, gram_matrix;
                                   group, claim)
    source_path = joinpath(ROOT, relpath)
    stem = splitext(basename(relpath))[1]
    base_dir = dirname(source_path)
    problem_rel = joinpath(dirname(relpath), stem * "_sos_gram.json")
    solution_rel = joinpath(dirname(relpath), stem * "_gram_solution.json")
    cert_rel = joinpath(dirname(relpath), stem * "_cert.json")
    write_json(source_path,
               (;
                source_format="sostools_lite",
                variables,
                basis,
                polynomial=[(;
                             exponents=exponents,
                             coefficient=rstr(coefficient),)
                            for (exponents, coefficient) in polynomial],
                gram_matrix=[[rstr(entry) for entry in row]
                             for row in gram_matrix],
                metadata=(;
                          exporter_contract="SOSTOOLS searches; CertSDP certifies exact Gram replay.",
                          claim,),))
    result = C.convert_sostools_lite_json(source_path;
                                          problem_out=joinpath(ROOT, problem_rel),
                                          solution_out=joinpath(ROOT, solution_rel),
                                          cert_out=joinpath(ROOT, cert_rel))
    @assert C.verify_strict(result.cert_out)
    push!(entries,
          (;
           kind="sostools_lite_pipeline",
           group,
           title,
           source_path=relpath,
           problem_path=problem_rel,
           solution_path=solution_rel,
           certificate_path=cert_rel,
           certificate_type="sos_gram_certificate",
           claim,
           variables,
           basis_size=length(basis),
           exact_check="v'Qv coefficient match + exact rational PSD replay",
           command="bin/certsdp convert-sostools $relpath --problem-out /tmp/$(basename(problem_rel)) --solution-out /tmp/$(basename(solution_rel)) --cert-out /tmp/$(basename(cert_rel))",))
    return result
end

function motzkin_affine(entries; relpath, group, source)
    variables = ["x", "y"]
    n = length(variables)
    target = [([4, 2], 1 // 1), ([2, 4], 1 // 1), ([2, 2], -3 // 1),
              ([0, 0], 1 // 1)]
    numerator = [
        square(n, [([3, 1], 1 // 1), ([1, 3], 1 // 1), ([1, 1], -2 // 1)]),
        square(n, [([4, 1], 1 // 1), ([2, 3], 1 // 1), ([2, 1], -2 // 1)]),
        square(n, [([3, 2], 1 // 1), ([1, 4], 1 // 1), ([1, 2], -2 // 1)]),
        square(n, [([2, 0], 1 // 1), ([0, 2], -1 // 1)]),
    ]
    denominator = [square(n, [([2, 0], 1 // 1), ([0, 2], 1 // 1)])]
    return write_rational_function_entry(entries, relpath,
                                         "Motzkin affine Hilbert-17 certificate",
                                         variables, target, numerator,
                                         denominator;
                                         group,
                                         claim="M(x,y) >= 0, nonnegative but not polynomial SOS",
                                         source)
end

function motzkin_homogeneous(entries; relpath, group, source)
    variables = ["x", "y", "z"]
    n = length(variables)
    target = [([4, 2, 0], 1 // 1), ([2, 4, 0], 1 // 1),
              ([0, 0, 6], 1 // 1), ([2, 2, 2], -3 // 1)]
    numerator = [
        square(n,
               [([3, 1, 1], 1 // 1), ([1, 3, 1], 1 // 1),
                ([1, 1, 3], -2 // 1)]),
        square(n,
               [([4, 1, 0], 1 // 1), ([2, 3, 0], 1 // 1),
                ([2, 1, 2], -2 // 1)]),
        square(n,
               [([3, 2, 0], 1 // 1), ([1, 4, 0], 1 // 1),
                ([1, 2, 2], -2 // 1)]),
        square(n, [([2, 0, 3], 1 // 1), ([0, 2, 3], -1 // 1)]),
    ]
    denominator = [square(n, [([2, 0, 0], 1 // 1), ([0, 2, 0], 1 // 1)])]
    return write_rational_function_entry(entries, relpath,
                                         "Homogeneous Motzkin ternary sextic",
                                         variables, target, numerator,
                                         denominator;
                                         group,
                                         claim="homogeneous Motzkin form >= 0, outside polynomial SOS",
                                         source)
end

function choi_lam_cyclic_sextic(entries; relpath, group, source)
    variables = ["x", "y", "z"]
    n = length(variables)
    target = [([4, 2, 0], 1 // 1), ([0, 4, 2], 1 // 1),
              ([2, 0, 4], 1 // 1), ([2, 2, 2], -3 // 1)]
    half_blocks = [
        [([2, 2, 0], 1 // 1), ([2, 0, 2], -1 // 1)],
        [([0, 2, 2], 1 // 1), ([2, 2, 0], -1 // 1)],
        [([2, 0, 2], 1 // 1), ([0, 2, 2], -1 // 1)],
    ]
    numerator = [
        square(n, [([3, 1, 0], 1 // 1), ([1, 1, 2], -1 // 1)]),
        square(n, [([0, 3, 1], 1 // 1), ([2, 1, 1], -1 // 1)]),
        square(n, [([1, 0, 3], 1 // 1), ([1, 2, 1], -1 // 1)]),
    ]
    for block in half_blocks
        push!(numerator, scaled_square(n, 1 // 2, block))
        push!(numerator, scaled_square(n, 1 // 2, block))
    end
    denominator = [
        square(n, [([1, 0, 0], 1 // 1)]),
        square(n, [([0, 1, 0], 1 // 1)]),
        square(n, [([0, 0, 1], 1 // 1)]),
    ]
    return write_rational_function_entry(entries, relpath,
                                         "Choi-Lam cyclic sextic denominator SOS",
                                         variables, target, numerator,
                                         denominator;
                                         group,
                                         claim="Choi-Lam cyclic sextic >= 0, non-SOS form certified after multiplying by x^2+y^2+z^2",
                                         source)
end

function choi_lam_quartic(entries; relpath, group, source)
    variables = ["w", "x", "y", "z"]
    n = length(variables)
    target = [([4, 0, 0, 0], 1 // 1), ([0, 2, 2, 0], 1 // 1),
              ([0, 0, 2, 2], 1 // 1), ([0, 2, 0, 2], 1 // 1),
              ([1, 1, 1, 1], -4 // 1)]
    q = [([3, 0, 0, 0], 1 // 1), ([0, 1, 1, 1], -1 // 1)]
    numerator = [
        square(n, q),
        square(n, q),
        scaled_square(n, 2 // 1, q),
        scaled_square(n, 1 // 2,
                      [([2, 1, 0, 0], 2 // 1), ([1, 0, 1, 1], -4 // 1),
                       ([0, 1, 2, 0], 1 // 1), ([0, 1, 0, 2], 1 // 1)]),
        scaled_square(n, 1 // 2,
                      [([2, 0, 1, 0], 2 // 1), ([1, 1, 0, 1], -4 // 1),
                       ([0, 0, 1, 2], 1 // 1), ([0, 2, 1, 0], 1 // 1)]),
        scaled_square(n, 1 // 2,
                      [([2, 0, 0, 1], 2 // 1), ([1, 1, 1, 0], -4 // 1),
                       ([0, 2, 0, 1], 1 // 1), ([0, 0, 2, 1], 1 // 1)]),
    ]
    b_blocks = [
        [([0, 1, 2, 0], 1 // 1), ([0, 1, 0, 2], -1 // 1)],
        [([0, 0, 1, 2], 1 // 1), ([0, 2, 1, 0], -1 // 1)],
        [([0, 2, 0, 1], 1 // 1), ([0, 0, 2, 1], -1 // 1)],
    ]
    for block in b_blocks
        for _ in 1:3
            push!(numerator, scaled_square(n, 1 // 2, block))
        end
    end
    denominator = [
        square(n, [([1, 0, 0, 0], 1 // 1)]),
        square(n, [([1, 0, 0, 0], 1 // 1)]),
        square(n, [([1, 0, 0, 0], 2 // 1)]),
        square(n, [([0, 1, 0, 0], 1 // 1)]),
        square(n, [([0, 0, 1, 0], 1 // 1)]),
        square(n, [([0, 0, 0, 1], 1 // 1)]),
    ]
    return write_rational_function_entry(entries, relpath,
                                         "Choi-Lam quaternary quartic denominator SOS",
                                         variables, target, numerator,
                                         denominator;
                                         group,
                                         claim="Choi-Lam quartic >= 0, non-SOS form certified with a rational-function SOS identity",
                                         source)
end

function robinson_threshold_perturbation(entries; relpath, group, source)
    variables = ["x", "y", "z"]
    n = length(variables)
    target = [([6, 0, 0], 9 // 8), ([0, 6, 0], 9 // 8),
              ([0, 0, 6], 9 // 8),
              ([4, 2, 0], -1 // 1), ([2, 4, 0], -1 // 1),
              ([4, 0, 2], -1 // 1), ([2, 0, 4], -1 // 1),
              ([0, 4, 2], -1 // 1), ([0, 2, 4], -1 // 1),
              ([2, 2, 2], 3 // 1)]
    qx = [([3, 0, 0], 3 // 4), ([1, 2, 0], -1 // 2),
          ([1, 0, 2], -1 // 2)]
    qy = [([0, 3, 0], 3 // 4), ([0, 1, 2], -1 // 2),
          ([2, 1, 0], -1 // 2)]
    qz = [([0, 0, 3], 3 // 4), ([2, 0, 1], -1 // 2),
          ([0, 2, 1], -1 // 2)]
    numerator = [square(n, qx), square(n, qx), square(n, qy), square(n, qy),
                 square(n, qz), square(n, qz)]
    denominator = [square(n, [([0, 0, 0], 1 // 1)])]
    return write_rational_function_entry(entries, relpath,
                                         "Robinson-family beta=1/8 SOS threshold replay",
                                         variables, target, numerator,
                                         denominator;
                                         group,
                                         claim="Robinson ternary sextic plus the exact 1/8 diagonal perturbation at the SOS threshold",
                                         source)
end

function hilbert17_dense_protocol(entries)
    variables = ["x", "y", "z"]
    n = length(variables)
    d = [([0, 0, 0], 1 // 1), ([2, 0, 0], 1 // 1), ([0, 2, 0], 1 // 1),
         ([0, 0, 2], 1 // 1)]
    target = [([0, 0, 0], 1 // 1), ([2, 0, 0], 2 // 1),
              ([0, 2, 0], 2 // 1), ([0, 0, 2], 2 // 1),
              ([4, 0, 0], 1 // 1), ([0, 4, 0], 1 // 1),
              ([0, 0, 4], 1 // 1), ([2, 2, 0], 2 // 1),
              ([2, 0, 2], 2 // 1), ([0, 2, 2], 2 // 1)]
    numerator = [
        square(n, d),
        square(n, [([exponents[1] + 1, exponents[2], exponents[3]], coefficient)
                   for (exponents, coefficient) in d]),
        square(n, [([exponents[1], exponents[2] + 1, exponents[3]], coefficient)
                   for (exponents, coefficient) in d]),
        square(n, [([exponents[1], exponents[2], exponents[3] + 1], coefficient)
                   for (exponents, coefficient) in d]),
    ]
    denominator = [
        square(n, [([0, 0, 0], 1 // 1)]),
        square(n, [([1, 0, 0], 1 // 1)]),
        square(n, [([0, 1, 0], 1 // 1)]),
        square(n, [([0, 0, 1], 1 // 1)]),
    ]
    return write_rational_function_entry(entries,
                                         "showcases/hilbert17/dense_denominator_protocol.json",
                                         "Dense denominator protocol control",
                                         variables, target, numerator,
                                         denominator;
                                         group="hilbert17",
                                         claim="(1+x^2+y^2+z^2)^2 >= 0 replayed through a nontrivial rational-function SOS denominator",
                                         source="hilbert17_protocol_showcase")
end

function hilbert17_minimal_univariate(entries)
    variables = ["x"]
    n = length(variables)
    target = [([2], 1 // 1), ([0], 1 // 1)]
    numerator = [square(n, [([2], 1 // 1), ([0], 1 // 1)])]
    denominator = [square(n, [([1], 1 // 1)]), square(n, [([0], 1 // 1)])]
    return write_rational_function_entry(entries,
                                         "showcases/hilbert17/x2_plus_1_minimal.json",
                                         "Minimal univariate rational-function SOS",
                                         variables, target, numerator,
                                         denominator;
                                         group="hilbert17",
                                         claim="x^2+1 >= 0 with denominator_sos * p == numerator_sos",
                                         source="hilbert17_protocol_showcase")
end

function putinar_pack(entries)
    variables = ["x", "y"]
    n = length(variables)
    constraints = [
        C.NamedPolynomial("gx", poly([([0, 0], 1 // 1), ([2, 0], -1 // 1)])),
        C.NamedPolynomial("gy", poly([([0, 0], 1 // 1), ([0, 2], -1 // 1)])),
    ]
    terms = [
        C.PositivstellensatzTerm("y2_times_gx", ["gx"],
                                 [square(n, [([0, 1], 1 // 1)])]),
        C.PositivstellensatzTerm("one_times_gy", ["gy"],
                                 [square(n, [([0, 0], 1 // 1)])]),
    ]
    write_positivstellensatz_entry(entries,
                                   "showcases/putinar/box_1_minus_x2y2.json",
                                   "Box Putinar certificate for 1 - x^2 y^2",
                                   variables,
                                   [([0, 0], 1 // 1), ([2, 2], -1 // 1)],
                                   constraints, terms;
                                   group="putinar",
                                   claim="-1 <= x,y <= 1 implies 1 - x^2 y^2 >= 0",
                                   source="putinar_showcase")

    constraints = [
        C.NamedPolynomial("disk", poly([([0, 0], 1 // 1), ([2, 0], -1 // 1),
                                        ([0, 2], -1 // 1)])),
    ]
    terms = [
        C.PositivstellensatzTerm("sigma0", String[],
                                 [square(n, [([0, 0], 1 // 2)]),
                                  square(n, [([0, 0], 1 // 2)]),
                                  square(n, [([0, 0], 1 // 2)]),
                                  square(n,
                                         [([2, 0], 1 // 2), ([0, 2], -1 // 2)])]),
        C.PositivstellensatzTerm("archimedean_disk_multiplier", ["disk"],
                                 [square(n, [([0, 0], 1 // 2)]),
                                  square(n, [([1, 0], 1 // 2)]),
                                  square(n, [([0, 1], 1 // 2)])]),
    ]
    write_positivstellensatz_entry(entries,
                                   "showcases/putinar/unit_disk_1_minus_x2y2.json",
                                   "Unit disk Putinar certificate",
                                   variables,
                                   [([0, 0], 1 // 1), ([2, 2], -1 // 1)],
                                   constraints, terms;
                                   group="putinar",
                                   claim="x^2 + y^2 <= 1 implies 1 - x^2 y^2 >= 0",
                                   source="putinar_showcase")

    variables = ["x"]
    n = length(variables)
    constraints = [C.NamedPolynomial("unit_interval",
                                     poly([([0], 1 // 1), ([2], -1 // 1)]))]
    terms = [C.PositivstellensatzTerm("one_plus_x2_multiplier",
                                      ["unit_interval"],
                                      [square(n, [([0], 1 // 1)]),
                                       square(n, [([1], 1 // 1)])])]
    write_positivstellensatz_entry(entries,
                                   "showcases/putinar/interval_1_minus_x4.json",
                                   "Interval Putinar certificate for 1 - x^4",
                                   variables,
                                   [([0], 1 // 1), ([4], -1 // 1)],
                                   constraints, terms;
                                   group="putinar",
                                   claim="-1 <= x <= 1 implies 1 - x^4 >= 0",
                                   source="putinar_showcase")

    variables = ["x", "y"]
    n = length(variables)
    constraints = [
        C.NamedPolynomial("x_nonnegative", poly([([1, 0], 1 // 1)])),
        C.NamedPolynomial("y_nonnegative", poly([([0, 1], 1 // 1)])),
        C.NamedPolynomial("simplex_wall",
                          poly([([0, 0], 1 // 1), ([1, 0], -1 // 1),
                                ([0, 1], -1 // 1)])),
    ]
    terms = [C.PositivstellensatzTerm("schmudgen_edge_product",
                                      ["x_nonnegative", "simplex_wall"],
                                      [square(n, [([0, 0], 1 // 1)])])]
    write_positivstellensatz_entry(entries,
                                   "showcases/putinar/simplex_edge_product.json",
                                   "Simplex Schmuedgen product certificate",
                                   variables,
                                   [([1, 0], 1 // 1), ([2, 0], -1 // 1),
                                    ([1, 1], -1 // 1)],
                                   constraints, terms;
                                   group="putinar",
                                   claim="x >= 0, y >= 0, x+y <= 1 implies x(1-x-y) >= 0",
                                   source="schmuedgen_showcase")

    constraints = [
        C.NamedPolynomial("inner_radius",
                          poly([([2, 0], 1 // 1), ([0, 2], 1 // 1),
                                ([0, 0], -1 // 1)])),
        C.NamedPolynomial("outer_radius",
                          poly([([0, 0], 4 // 1), ([2, 0], -1 // 1),
                                ([0, 2], -1 // 1)])),
    ]
    terms = [C.PositivstellensatzTerm("annulus_product",
                                      ["inner_radius", "outer_radius"],
                                      [square(n, [([0, 0], 1 // 1)])])]
    write_positivstellensatz_entry(entries,
                                   "showcases/putinar/annulus_product_barrier.json",
                                   "Annulus Schmuedgen product certificate",
                                   variables,
                                   [([2, 0], 5 // 1), ([0, 2], 5 // 1),
                                    ([4, 0], -1 // 1), ([0, 4], -1 // 1),
                                    ([2, 2], -2 // 1), ([0, 0], -4 // 1)],
                                   constraints, terms;
                                   group="putinar",
                                   claim="1 <= x^2+y^2 <= 4 implies (x^2+y^2-1)(4-x^2-y^2) >= 0",
                                   source="schmuedgen_showcase")
end

function sostools_pack(entries)
    write_sostools_lite_entry(entries,
                              "showcases/sostools/sostools_lite_xy_square.json",
                              "SOSTOOLS-lite positive polynomial replay",
                              ["x", "y"],
                              [[1, 0], [0, 1]],
                              [([2, 0], 1 // 1), ([1, 1], 2 // 1),
                               ([0, 2], 1 // 1)],
                              [["1", "1"], ["1", "1"]];
                              group="sostools",
                              claim="p=(x+y)^2 exported as an exact Gram candidate")

    write_sostools_lite_entry(entries,
                              "showcases/sostools/sostools_lite_rank1_positive_polynomial.json",
                              "Rank-one positive polynomial decomposition",
                              ["x", "y", "z"],
                              [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]],
                              [([0, 0, 0], 1 // 1), ([2, 0, 0], 1 // 1),
                               ([0, 2, 0], 1 // 1), ([0, 0, 2], 1 // 1),
                               ([1, 0, 0], 2 // 1), ([0, 1, 0], 2 // 1),
                               ([0, 0, 1], 2 // 1), ([1, 1, 0], 2 // 1),
                               ([1, 0, 1], 2 // 1), ([0, 1, 1], 2 // 1)],
                              [["1", "1", "1", "1"],
                               ["1", "1", "1", "1"],
                               ["1", "1", "1", "1"],
                               ["1", "1", "1", "1"]];
                              group="sostools",
                              claim="p=(1+x+y+z)^2 from a rank-one Gram matrix")

    write_sostools_lite_entry(entries,
                              "showcases/sostools/sostools_lite_lyapunov_decay.json",
                              "Lyapunov decay SOS replay",
                              ["x", "y"],
                              [[1, 0], [0, 1]],
                              [([2, 0], 2 // 1), ([0, 2], 4 // 1)],
                              [["2", "0"], ["0", "4"]];
                              group="sostools",
                              claim="-dV/dt = 2x^2 + 4y^2 for a linear stable system")

    write_sostools_lite_entry(entries,
                              "showcases/sostools/sostools_lite_quartic_bound.json",
                              "Polynomial optimization bound replay",
                              ["x", "y"],
                              [[0, 0], [1, 0], [0, 1], [2, 0], [0, 2]],
                              [([0, 0], 1 // 1), ([2, 0], 1 // 1),
                               ([0, 2], 1 // 1), ([4, 0], 1 // 1),
                               ([0, 4], 1 // 1)],
                              [["1", "0", "0", "0", "0"],
                               ["0", "1", "0", "0", "0"],
                               ["0", "0", "1", "0", "0"],
                               ["0", "0", "0", "1", "0"],
                               ["0", "0", "0", "0", "1"]];
                              group="sostools",
                              claim="x^4 + y^4 + x^2 + y^2 + 1 >= 1-style Gram replay")

    write_sostools_lite_entry(entries,
                              "showcases/sostools/sostools_lite_dense_cross_quartic.json",
                              "Dense cross-term quartic Gram replay",
                              ["x", "y"],
                              [[2, 0], [1, 1], [0, 2]],
                              [([4, 0], 1 // 1), ([3, 1], 2 // 1),
                               ([2, 2], 3 // 1), ([1, 3], 2 // 1),
                               ([0, 4], 1 // 1)],
                              [["1", "1", "1"],
                               ["1", "1", "1"],
                               ["1", "1", "1"]];
                              group="sostools",
                              claim="p=(x^2+xy+y^2)^2 with dense Gram coupling")

end

function main()
    entries = Any[]

    motzkin_affine(entries;
                   relpath="showcases/non_sos_classics/motzkin_affine_rational_function_sos.json",
                   group="non_sos_classics",
                   source="non_sos_classics_showcase")
    motzkin_affine(entries;
                   relpath="showcases/motzkin/motzkin_rational_function_sos.json",
                   group="legacy_aliases",
                   source="motzkin_showcase")
    motzkin_homogeneous(entries;
                        relpath="showcases/non_sos_classics/motzkin_homogeneous_rational_function_sos.json",
                        group="non_sos_classics",
                        source="non_sos_classics_showcase")
    choi_lam_cyclic_sextic(entries;
                           relpath="showcases/non_sos_classics/choi_lam_cyclic_sextic_rational_function_sos.json",
                           group="non_sos_classics",
                           source="non_sos_classics_showcase")
    choi_lam_quartic(entries;
                     relpath="showcases/non_sos_classics/choi_lam_quartic_rational_function_sos.json",
                     group="non_sos_classics",
                     source="non_sos_classics_showcase")
    robinson_threshold_perturbation(entries;
                                    relpath="showcases/non_sos_classics/robinson_threshold_perturbation_rational_sos.json",
                                    group="non_sos_classics",
                                    source="non_sos_classics_showcase")

    hilbert17_minimal_univariate(entries)
    hilbert17_dense_protocol(entries)
    motzkin_affine(entries;
                   relpath="showcases/hilbert17/motzkin_affine_hilbert17.json",
                   group="hilbert17",
                   source="hilbert17_protocol_showcase")
    choi_lam_cyclic_sextic(entries;
                           relpath="showcases/hilbert17/choi_lam_cyclic_sextic_hilbert17.json",
                           group="hilbert17",
                           source="hilbert17_protocol_showcase")
    choi_lam_quartic(entries;
                     relpath="showcases/hilbert17/choi_lam_quartic_hilbert17.json",
                     group="hilbert17",
                     source="hilbert17_protocol_showcase")

    putinar_pack(entries)
    sostools_pack(entries)

    groups = [
        (;
         id="non_sos_classics",
         title="Nonnegative but non-polynomial-SOS classics",
         description="Motzkin, Choi-Lam, and Robinson-family artifacts replay exact positive-polynomial certificates over rational data.",),
        (;
         id="hilbert17",
         title="Hilbert 17 rational-function SOS protocol",
         description="Data-only numerator_sos / denominator_sos certificates; strict verification checks SOS blocks and one polynomial identity.",),
        (;
         id="putinar",
         title="Putinar and Schmuedgen compact-domain certificates",
         description="Constrained polynomial inequalities encoded as SOS multipliers attached to named constraint products.",),
        (;
         id="sostools",
         title="SOSTOOLS-style exact replay bridge",
         description="Neutral SOSTOOLS-lite Gram exports converted into CertSDP certificates and independently replayed.",),
    ]
    manifest = (;
                showcase_manifest_version="1.0",
                generated_by="scripts/generate_showcase_pack.jl",
                verifier_boundary="strict exact replay only; solver logs and floating-point residuals are not trusted",
                total_artifacts=length(entries),
                certificate_artifacts=count(entry -> entry.kind == "certificate",
                                            entries),
                sostools_pipeline_artifacts=count(entry -> entry.kind ==
                                                  "sostools_lite_pipeline",
                                                  entries),
                groups,
                artifacts=entries,)
    write_json(joinpath(ROOT, "showcases", "manifest.json"), manifest)
    println("wrote ", length(entries), " showcase artifacts")
end

main()
