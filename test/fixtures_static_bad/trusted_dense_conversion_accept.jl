@trusted_exact function bad_dense_conversion_accept(sparse_matrix)
    return Matrix(sparse_matrix) == Matrix(sparse_matrix)
end
