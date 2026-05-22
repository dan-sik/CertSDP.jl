module Debug

export reset_densification_counter!,
       densification_counter,
       densification_events,
       record_densification!

mutable struct DensificationState
    count::Int
    events::Vector{NamedTuple{(:reason, :size, :gate_id),
                              Tuple{Symbol, Int, Symbol}}}
end

const DENSIFICATION_STATE = DensificationState(0, NamedTuple{(:reason, :size, :gate_id),
                                                             Tuple{Symbol, Int, Symbol}}[])

function reset_densification_counter!()
    DENSIFICATION_STATE.count = 0
    empty!(DENSIFICATION_STATE.events)
    return 0
end

densification_counter() = DENSIFICATION_STATE.count

densification_events() = copy(DENSIFICATION_STATE.events)

function record_densification!(reason::Symbol, size::Integer, gate_id::Symbol)
    DENSIFICATION_STATE.count += 1
    push!(DENSIFICATION_STATE.events, (reason=reason, size=Int(size),
                                       gate_id=gate_id))
    return DENSIFICATION_STATE.count
end

end
