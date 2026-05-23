module ExactArithmeticSafety

using ..TrustedKernel

export assert_trusted_exact_path,
       verify_no_numeric_fallback,
       trusted_arithmetic_modes

assert_trusted_exact_path() = TrustedKernel.assert_trusted_exact_path()

verify_no_numeric_fallback() = TrustedKernel.verify_no_numeric_fallback()

trusted_arithmetic_modes() = TrustedKernel.trusted_arithmetic_modes()

end
