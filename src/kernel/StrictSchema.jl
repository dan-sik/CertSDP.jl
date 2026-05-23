module StrictSchema

using ..Kernel

export SchemaResult,
       strict_schema_validate,
       semantic_schema_validate

struct SchemaResult
    accepted::Bool
    stage::Symbol
    reason::String
    path::String
end

function strict_schema_validate(input::AbstractString; from_file::Bool=false)
    json_text = from_file ? read(input, String) : input
    try
        Kernel.validate_certificate_schema_v3(json_text)
        return SchemaResult(true, :strict_schema, "accepted", "root")
    catch err
        return SchemaResult(false, :strict_schema, sprint(showerror, err), "root")
    end
end

function semantic_schema_validate(json_text::AbstractString)
    try
        cert = Kernel.parse_certificate_json_v3(json_text; strict=true)
        report = Kernel.verify_certificate(cert)
        report.accepted ||
            return SchemaResult(false, report.stage, report.reason,
                                String(report.obligation_id))
        return SchemaResult(true, :semantic_schema, "accepted", "root")
    catch err
        return SchemaResult(false, :semantic_schema, sprint(showerror, err),
                            "root")
    end
end

end
