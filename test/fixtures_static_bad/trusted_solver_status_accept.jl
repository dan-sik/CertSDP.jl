@trusted_exact function bad_solver_status_accept(meta)
    return meta[:solver_status] == "optimal"
end
