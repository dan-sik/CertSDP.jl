module UntrustedAdapters

using ..Adapters

export adapter_trusted_boundary,
       certify_adapter_candidate

adapter_trusted_boundary() = Adapters.adapter_trusted_boundary()

certify_adapter_candidate(candidate) = Adapters.certify_adapter_candidate(candidate)

end
