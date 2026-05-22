module Schemas

export schema_layer_marker,
       certsdp3_schema_files

schema_layer_marker() = :certsdp3_strict_schema

function certsdp3_schema_files()
    return String[
        "certsdp_certificate_v3.schema.json",
        "certsdp_problem_v3.schema.json",
        "certsdp_sparse_lmi_v3.schema.json",
        "certsdp_sos_v3.schema.json",
        "certsdp_nc_quantum_v3.schema.json",
        "certsdp_report_v3.schema.json",
    ]
end

end
