@testset "fixture authenticity classification" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures", "certsdp3", "index.json"))
    index = JSON3.read(read(root, String))
    classes = Set(String(f[:source_class]) for f in index[:fixtures])
    @test "external_like" in classes
    @test "generated_stress" in classes
    for fixture in index[:fixtures]
        @test haskey(fixture, :semantic_checks_required)
        @test haskey(fixture, :subprocess_cli_commands)
    end
end

