module Explain

using ..Kernel

export explain_file

function explain_file(path::AbstractString)
    report = Kernel.diagnose_file(path; strict=true)
    return Kernel.diagnostic_report_text(report)
end

end
