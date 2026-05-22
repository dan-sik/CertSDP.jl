module Perf

using ..Kernel

export ReplayMeasurement,
       measure_replay,
       memory_budget_check,
       validation_summary

struct ReplayMeasurement
    path::String
    accepted::Bool
    # CERTSDP_NUMERIC_DIAGNOSTIC_ONLY: wall-clock timing is not used for verifier acceptance
    elapsed_seconds::Float64
    allocated_bytes::Int64
    report::Kernel.DiagnosticReport
end

function measure_replay(path::AbstractString)
    report_ref = Ref{Kernel.DiagnosticReport}()
    allocated_ref = Ref{Int64}(0)
    elapsed = @elapsed begin
        allocated = @allocated begin
            report_ref[] = Kernel.replay_file(String(path); strict=true)
        end
        allocated_ref[] = Int64(allocated)
    end
    return ReplayMeasurement(String(path), report_ref[].accepted, elapsed,
                             allocated_ref[], report_ref[])
end

function memory_budget_check(measurement::ReplayMeasurement; max_memory_mb::Real)
    return measurement.allocated_bytes <= round(Int64, max_memory_mb * 1024^2)
end

function validation_summary(measurements::AbstractVector{ReplayMeasurement})
    total_seconds = sum(measurement.elapsed_seconds for measurement in measurements)
    peak_mb = isempty(measurements) ? 0.0 :
              maximum(measurement.allocated_bytes for measurement in measurements) /
              1024^2
    return (;
        count=length(measurements),
        accepted=count(measurement -> measurement.accepted, measurements),
        rejected=count(measurement -> !measurement.accepted, measurements),
        total_runtime_seconds=total_seconds,
        peak_memory_mb=peak_mb,
    )
end

end
