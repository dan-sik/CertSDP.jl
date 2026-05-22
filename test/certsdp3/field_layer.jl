@testset "Gate L field API" begin
    @test CertSDP.QQ isa CertSDP.ExactField
    sqrt2 = CertSDP.QuadraticField(2)
    @test CertSDP.field_hash(sqrt2) == CertSDP.field_hash(CertSDP.QuadraticField(2))

    alpha = CertSDP.FieldElement(sqrt2, Dict(Int[] => 1//1, Int[1] => 1//1))
    @test (alpha * alpha) == CertSDP.FieldElement(sqrt2, Dict(Int[] => 3//1,
                                                               Int[1] => 2//1))
    parsed = CertSDP.parse_field_element(sqrt2, CertSDP.field_element_json(alpha))
    @test parsed == alpha
    embedding = Dict(:field_hash => CertSDP.field_hash(sqrt2),
                     :element => CertSDP.field_element_string(alpha),
                     :sign => "positive",
                     :root_interval => ["7/5", "3/2"])
    @test CertSDP.verify_field_element(sqrt2, alpha; sign=:positive,
                                       embedding_certificate=embedding)
    bad_embedding = Dict(:field_hash => "sha256:" * repeat("0", 64),
                         :element => CertSDP.field_element_string(alpha),
                         :sign => "positive",
                         :root_interval => ["7/5", "3/2"])
    @test_throws ArgumentError CertSDP.verify_field_element(sqrt2, alpha;
                                                           sign=:positive,
                                                           embedding_certificate=bad_embedding)

    multi = CertSDP.MultiquadraticField([3, 2])
    @test CertSDP.field_element_string(CertSDP.FieldElement(multi, 1//1)) == "1"
    cyclo = CertSDP.CyclotomicField(5)
    @test CertSDP.field_hash(cyclo) != CertSDP.field_hash(multi)
    cubic = CertSDP.NumberField(CertSDP.parse_polynomial("t^3 - t - 1"))
    @test CertSDP.parse_field_spec(CertSDP.field_json(cubic)) == cubic
end
