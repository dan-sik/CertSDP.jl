@trusted_exact function bad_float64_accept(x)
    y = Float64(x)
    return y >= 0
end
