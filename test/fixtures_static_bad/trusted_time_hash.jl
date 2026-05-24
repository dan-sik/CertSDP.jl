@trusted_exact function bad_time_hash(x)
    return hash((x, time()))
end
