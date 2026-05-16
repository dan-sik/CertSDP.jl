using JSON3

@testset "Adversarial verifier hardening" begin
    ZERO_SHA = "sha256:" * repeat("0", 64)

    function _verifier_constant_lmi(matrix; var::Symbol=:z)
        n = size(matrix, 1)
        return LMIProblem(matrix, [zeros(Rational{BigInt}, n, n)]; vars=[var])
    end

    function _verifier_rational_principal_certificate()
        P = LMIProblem([1 0; 0 1],
                       [[1 0; 0 0],
                        [0 0; 0 1]];
                       vars=[:x, :y],)
        return RationalCertificate(P, [1 // 2, 1 // 3])
    end

    function _verifier_rational_schur_certificate()
        A = Rational{BigInt}[1 0 1
                             0 1 0
                             1 0 1]
        return RationalCertificate(_verifier_constant_lmi(A), [0 // 1];
                                   psd_method=:schur_zero,
                                   pivot_block=[1, 2])
    end

    function _verifier_rational_ldl_certificate()
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x],)
        return RationalCertificate(P, [1 // 1]; psd_method=:ldl)
    end

    function _verifier_algebraic_principal_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 1; 1 0],
                       [[1 0; 0 1]];
                       vars=[:x],)
        return AlgebraicCertificate(P, root, [alpha])
    end

    function _verifier_algebraic_schur_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 0 1
                        0 1 -1
                        1 -1 3],
                       [[1 0 0
                         0 0 1
                         0 1 -3//2]];
                       vars=[:x],)
        return AlgebraicCertificate(P, root, [alpha]; psd_method=:schur_zero,
                                    pivot_block=[1, 2])
    end

    function _verifier_algebraic_ldl_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x],)
        return AlgebraicCertificate(P, root, [alpha]; psd_method=:ldl)
    end

    function _verifier_sos_certificate()
        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([0], 1),
                                          PolynomialTerm([2], 1)])
        return SOSGramCertificate(problem, [1 0; 0 1])
    end

    function _verifier_json_dict(cert)
        return JSON3.read(certificate_json_v1_string(cert), Dict{String, Any})
    end

    function _verifier_json_text(data)
        io = IOBuffer()
        JSON3.pretty(io, data)
        println(io)
        return String(take!(io))
    end

    function _verifier_rehash(cert::RationalCertificate)
        return RationalCertificate(cert.problem, cert.solution, cert.psd_proof,
                                   rational_certificate_hash(cert))
    end

    function _verifier_rehash(cert::AlgebraicCertificate)
        return AlgebraicCertificate(cert.problem, cert.root, cert.solution,
                                    cert.psd_proof,
                                    algebraic_certificate_hash(cert),
                                    cert.provenance)
    end

    function _verifier_rehash(cert::SOSGramCertificate)
        return SOSGramCertificate(cert.problem, cert.gram_matrix,
                                  cert.lmi_certificate,
                                  cert.coefficient_proof,
                                  cert.decomposition,
                                  sos_gram_certificate_hash(cert))
    end

    function _verifier_rehash_json(json_text::AbstractString)
        return certificate_json_v1_string(_verifier_rehash(parse_certificate_json(json_text)))
    end

    function _verifier_mutated_json(mutator, cert; rehash::Bool=true)
        data = _verifier_json_dict(cert)
        mutator(data)
        json_text = _verifier_json_text(data)
        return rehash ? _verifier_rehash_json(json_text) : json_text
    end

    function _verifier_strict_cli(json_text::AbstractString)
        path = tempname() * ".json"
        write(path, json_text)
        out = IOBuffer()
        err = IOBuffer()
        code = CertSDP.main(["verify", "--strict", path]; io=out, err=err)
        return (; code, out=String(take!(out)), err=String(take!(err)))
    end

    function _verifier_rejects(name, json_text, expected)
        result = _verifier_strict_cli(json_text)
        text = result.out * result.err
        @test result.code != 0
        @test occursin("[FAIL]", text)
        @test any(needle -> occursin(needle, text), expected)
        @test !occursin("[OK] certificate accepted", text)
        @test !occursin("[OK] SOS Gram certificate accepted", text)
        return result
    end

    function _verifier_bad_rational_nonpsd_certificate()
        P = _verifier_constant_lmi(Rational{BigInt}[1 2; 2 1])
        bad_matrix = substitute(P, [0 // 1])
        bad_proof = CertSDP._rational_psd_proof_unchecked(bad_matrix)
        bad_without_hash = RationalCertificate(P, [0 // 1], bad_proof, "")
        return RationalCertificate(P, [0 // 1], bad_proof,
                                   rational_certificate_hash(bad_without_hash))
    end

    function _verifier_bad_rational_schur_certificate()
        P = _verifier_constant_lmi(Rational{BigInt}[1 0 1
                                                    0 1 0
                                                    1 0 2])
        bad_matrix = substitute(P, [0 // 1])
        bad_proof = RationalPSDProof(:schur_zero,
                                     bad_matrix,
                                     PrincipalMinorProof{Rational{BigInt}}[],
                                     CertSDP._schur_zero_proof_rational_unchecked(bad_matrix,
                                                                                  [1, 2]),
                                     nothing)
        bad_without_hash = RationalCertificate(P, [0 // 1], bad_proof, "")
        return RationalCertificate(P, [0 // 1], bad_proof,
                                   rational_certificate_hash(bad_without_hash))
    end

    function _verifier_bad_algebraic_nonpsd_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 2; 2 0],
                       [[1 0; 0 1]];
                       vars=[:x],)
        bad_matrix = substitute(P, [alpha])
        bad_proof = AlgebraicPSDProof(:principal_minors,
                                      bad_matrix,
                                      [PrincipalMinorProof([1], alpha),
                                       PrincipalMinorProof([2], alpha),
                                       PrincipalMinorProof([1, 2], alpha^2 - 4)])
        bad_without_hash = AlgebraicCertificate(P, root, [alpha], bad_proof, "")
        return AlgebraicCertificate(P, root, [alpha], bad_proof,
                                    algebraic_certificate_hash(bad_without_hash))
    end

    rational_principal = _verifier_rational_principal_certificate()
    rational_schur = _verifier_rational_schur_certificate()
    rational_ldl = _verifier_rational_ldl_certificate()
    algebraic_principal = _verifier_algebraic_principal_certificate()
    algebraic_schur = _verifier_algebraic_schur_certificate()
    algebraic_ldl = _verifier_algebraic_ldl_certificate()
    sos_cert = _verifier_sos_certificate()

    @testset "valid fixtures are accepted under strict verification" begin
        for cert in (rational_principal,
                     rational_schur,
                     rational_ldl,
                     algebraic_principal,
                     algebraic_schur,
                     algebraic_ldl,
                     sos_cert)
            @test verify(cert; strict=true)
        end

        strict_cli = _verifier_strict_cli(certificate_json_v1_string(algebraic_principal))
        @test strict_cli.code == 0
        @test occursin("[OK] certificate accepted", strict_cli.out)
    end

    cases = NamedTuple[]

    push!(cases,
          (name="rational coordinate x mutation",
           json=_verifier_mutated_json(rational_principal) do data
               return data["solution"]["coordinates"]["x"] = "-5"
           end,
           expected=["substituted matrix matches rational solution"]))
    push!(cases,
          (name="rational coordinate y mutation",
           json=_verifier_mutated_json(rational_principal) do data
               return data["solution"]["coordinates"]["y"] = "7"
           end,
           expected=["substituted matrix matches rational solution"]))
    push!(cases,
          (name="rational substituted matrix mutation",
           json=_verifier_mutated_json(rational_principal) do data
               return data["proof"]["psd"]["substituted_matrix"][1][1] = "19"
           end,
           expected=["substituted matrix matches rational solution"]))
    push!(cases,
          (name="rational principal-minor determinant mutation",
           json=_verifier_mutated_json(rational_principal) do data
               return data["proof"]["psd"]["data"]["principal_minors"][3]["determinant"] = "19"
           end,
           expected=["principal-minor proof matches recomputation"]))
    push!(cases,
          (name="rational certificate hash mutation",
           json=_verifier_mutated_json(rational_principal; rehash=false) do data
               return data["certificate_id"] = ZERO_SHA
           end,
           expected=["certificate hash matches"]))
    push!(cases,
          (name="rational problem hash mutation",
           json=_verifier_mutated_json(rational_principal; rehash=false) do data
               return data["problem_hash"] = ZERO_SHA
           end,
           expected=["problem_hash mismatch"]))
    push!(cases,
          (name="rational PSD pivot mutation",
           json=_verifier_mutated_json(rational_schur) do data
               proof = data["proof"]["psd"]["data"]
               proof["pivot_block"] = [1, 3]
               proof["positive_block"]["indices"] = [1, 3]
               return proof["positive_block"]["leading_principal_minors"][2]["indices"] = [1,
                                                                                           3]
           end,
           expected=["Schur-zero positive-block minors match recomputation",
                     "Schur-zero Schur complement matches recomputation",
                     "positive_block_minor"]))
    push!(cases,
          (name="rational positive block minor mutation",
           json=_verifier_mutated_json(rational_schur) do data
               return data["proof"]["psd"]["data"]["positive_block"]["leading_principal_minors"][2]["determinant"] = "5"
           end,
           expected=["Schur-zero positive-block minors match recomputation"]))
    push!(cases,
          (name="rational Schur complement mutation",
           json=_verifier_mutated_json(rational_schur) do data
               return data["proof"]["psd"]["data"]["schur_complement"]["entries"][1][1] = "1"
           end,
           expected=["Schur-zero Schur complement matches recomputation"]))
    push!(cases,
          (name="rational LDL pivot mutation",
           json=_verifier_mutated_json(rational_ldl) do data
               return data["proof"]["psd"]["data"]["pivots"][1]["value"] = "2"
           end,
           expected=["LDL proof matches recomputation"]))
    push!(cases,
          (name="rational non-PSD fake matrix",
           json=certificate_json_v1_string(_verifier_bad_rational_nonpsd_certificate()),
           expected=["all principal minors are nonnegative"]))
    push!(cases,
          (name="rational nonzero Schur complement fake",
           json=certificate_json_v1_string(_verifier_bad_rational_schur_certificate()),
           expected=["Schur complement is exact zero"]))

    push!(cases,
          (name="algebraic wide root interval mutation",
           json=_verifier_mutated_json(algebraic_principal) do data
               return data["solution"]["root_interval"] = ["-2", "2"]
           end,
           expected=["algebraic root interval isolates one real root"]))
    push!(cases,
          (name="algebraic root interval without selected root",
           json=_verifier_mutated_json(algebraic_principal) do data
               return data["solution"]["root_interval"] = ["2", "3"]
           end,
           expected=["algebraic root interval isolates one real root"]))
    push!(cases,
          (name="algebraic minimal polynomial mutation",
           json=_verifier_mutated_json(algebraic_principal) do data
               data["solution"]["minimal_polynomial"] = "t^2 - 3"
               return data["solution"]["root_interval"] = ["3/2", "2"]
           end,
           expected=["principal-minor proof matches recomputation"]))
    push!(cases,
          (name="algebraic coordinate rational mutation",
           json=_verifier_mutated_json(algebraic_principal) do data
               return data["solution"]["coordinates"]["x"] = "1"
           end,
           expected=["substituted matrix matches algebraic solution"]))
    push!(cases,
          (name="algebraic coordinate sign mutation",
           json=_verifier_mutated_json(algebraic_principal) do data
               return data["solution"]["coordinates"]["x"] = "-t"
           end,
           expected=["substituted matrix matches algebraic solution"]))
    push!(cases,
          (name="algebraic substituted matrix mutation",
           json=_verifier_mutated_json(algebraic_principal) do data
               return data["proof"]["psd"]["substituted_matrix"][1][1] = "t + 1"
           end,
           expected=["substituted matrix matches algebraic solution"]))
    push!(cases,
          (name="algebraic principal-minor determinant mutation",
           json=_verifier_mutated_json(algebraic_principal) do data
               return data["proof"]["psd"]["data"]["principal_minors"][3]["determinant"] = "t"
           end,
           expected=["principal-minor proof matches recomputation"]))
    push!(cases,
          (name="algebraic certificate hash mutation",
           json=_verifier_mutated_json(algebraic_principal; rehash=false) do data
               return data["certificate_id"] = ZERO_SHA
           end,
           expected=["certificate hash matches"]))
    push!(cases,
          (name="algebraic problem hash mutation",
           json=_verifier_mutated_json(algebraic_principal; rehash=false) do data
               return data["problem_hash"] = ZERO_SHA
           end,
           expected=["problem_hash mismatch"]))
    push!(cases,
          (name="algebraic PSD pivot mutation",
           json=_verifier_mutated_json(algebraic_schur) do data
               proof = data["proof"]["psd"]["data"]
               proof["pivot_block"] = [1]
               proof["positive_block"]["indices"] = [1]
               proof["positive_block"]["leading_principal_minors"] = [proof["positive_block"]["leading_principal_minors"][1]]
               return proof["schur_complement"]["entries"] = [["0", "0"], ["0", "0"]]
           end,
           expected=["Schur-zero Schur complement matches recomputation",
                     "Schur complement is exact zero"]))
    push!(cases,
          (name="algebraic positive block minor mutation",
           json=_verifier_mutated_json(algebraic_schur) do data
               return data["proof"]["psd"]["data"]["positive_block"]["leading_principal_minors"][2]["determinant"] = "1"
           end,
           expected=["Schur-zero positive-block minors match recomputation"]))
    push!(cases,
          (name="algebraic Schur complement mutation",
           json=_verifier_mutated_json(algebraic_schur) do data
               return data["proof"]["psd"]["data"]["schur_complement"]["entries"][1][1] = "1"
           end,
           expected=["Schur-zero Schur complement matches recomputation"]))
    push!(cases,
          (name="algebraic LDL pivot mutation",
           json=_verifier_mutated_json(algebraic_ldl) do data
               return data["proof"]["psd"]["data"]["pivots"][1]["value"] = "1"
           end,
           expected=["LDL proof matches recomputation"]))
    push!(cases,
          (name="algebraic non-PSD fake matrix",
           json=certificate_json_v1_string(_verifier_bad_algebraic_nonpsd_certificate()),
           expected=["all principal minors are certified nonnegative"]))

    push!(cases,
          (name="SOS Gram entry mutation",
           json=certificate_json_v1_string(_verifier_rehash(SOSGramCertificate(sos_cert.problem,
                                                                               SymmetricRationalMatrix([2 0;
                                                                                                        0 1]),
                                                                               sos_cert.lmi_certificate,
                                                                               sos_cert.coefficient_proof,
                                                                               sos_cert.decomposition,
                                                                               ""))),
           expected=["embedded LMI solution matches Gram matrix"]))
    push!(cases,
          (name="SOS coefficient metadata mutation",
           json=begin
               matches = copy(sos_cert.coefficient_proof)
               first_match = matches[1]
               matches[1] = SOSCoefficientMatch(first_match.exponents,
                                                first_match.target_coefficient + 1,
                                                first_match.gram_coefficient,
                                                first_match.contributions)
               certificate_json_v1_string(_verifier_rehash(SOSGramCertificate(sos_cert.problem,
                                                                              sos_cert.gram_matrix,
                                                                              sos_cert.lmi_certificate,
                                                                              matches,
                                                                              sos_cert.decomposition,
                                                                              "")))
           end,
           expected=["SOS coefficient metadata matches recomputation"]))
    push!(cases,
          (name="SOS embedded LMI PSD proof mutation",
           json=begin
               fake_lmi_proof = RationalPSDProof(:principal_minors,
                                                 sos_cert.lmi_certificate.psd_proof.matrix,
                                                 [PrincipalMinorProof([1], 2 // 1),
                                                  sos_cert.lmi_certificate.psd_proof.principal_minors[2],
                                                  sos_cert.lmi_certificate.psd_proof.principal_minors[3]])
               fake_lmi_without_hash = RationalCertificate(sos_cert.lmi_certificate.problem,
                                                           sos_cert.lmi_certificate.solution,
                                                           fake_lmi_proof,
                                                           "")
               fake_lmi = RationalCertificate(sos_cert.lmi_certificate.problem,
                                              sos_cert.lmi_certificate.solution,
                                              fake_lmi_proof,
                                              rational_certificate_hash(fake_lmi_without_hash))
               certificate_json_v1_string(_verifier_rehash(SOSGramCertificate(sos_cert.problem,
                                                                              sos_cert.gram_matrix,
                                                                              fake_lmi,
                                                                              sos_cert.coefficient_proof,
                                                                              sos_cert.decomposition,
                                                                              "")))
           end,
           expected=["embedded rational PSD certificate accepted"]))
    push!(cases,
          (name="SOS problem hash mutation",
           json=begin
               data = JSON3.read(sos_gram_certificate_json_string(sos_cert),
                                 Dict{String, Any})
               data["problem_hash"] = ZERO_SHA
               _verifier_json_text(data)
           end,
           expected=["problem_hash mismatch"]))
    push!(cases,
          (name="SOS certificate id mutation",
           json=begin
               data = JSON3.read(sos_gram_certificate_json_string(sos_cert),
                                 Dict{String, Any})
               data["certificate_id"] = ZERO_SHA
               _verifier_json_text(data)
           end,
           expected=["certificate_id", "SOS certificate hash matches"]))

    @testset "mutated certificates are rejected by verify --strict" begin
        @test length(cases) >= 30
        for case in cases
            @testset "$(case.name)" begin
                _verifier_rejects(case.name, case.json, case.expected)
            end
        end
    end

    @testset "property-style exact A = B'B accepts, one-entry mutation rejects" begin
        Bs = [Rational{BigInt}[1 2; 0 3],
              Rational{BigInt}[1//2 -1; 3//2 2],
              Rational{BigInt}[1 0 2; 2 1 -1],
              Rational{BigInt}[0 0; 2 0],
              Rational{BigInt}[2 -1 0; 0 1 1; 1 0 1]]

        for (i, B) in enumerate(Bs)
            A = transpose(B) * B
            P = _verifier_constant_lmi(A; var=Symbol("z", i))
            cert = RationalCertificate(P, [0 // 1])
            @test verify(cert; strict=true)

            bad_A = copy(A)
            bad_A[1, 1] = -abs(bad_A[1, 1]) - 1
            bad_P = _verifier_constant_lmi(bad_A; var=Symbol("zbad", i))
            bad_matrix = substitute(bad_P, [0 // 1])
            bad_proof = CertSDP._rational_psd_proof_unchecked(bad_matrix)
            bad_without_hash = RationalCertificate(bad_P, [0 // 1], bad_proof, "")
            bad = RationalCertificate(bad_P, [0 // 1], bad_proof,
                                      rational_certificate_hash(bad_without_hash))

            output = IOBuffer()
            @test !verify(bad; io=output, strict=true)
            text = String(take!(output))
            @test occursin("[OK] principal-minor proof matches recomputation", text)
            @test occursin("[FAIL] all principal minors are nonnegative", text)
        end
    end
end
