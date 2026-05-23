module AlgebraicFields

using ..Kernel

export verify_field_spec,
       parse_field_element,
       verify_field_element,
       canonical_field_hash,
       sign_exact

verify_field_spec(field::Kernel.AlgebraicFieldCertificate) =
    field.field_hash == Kernel.algebraic_field_certificate_hash(field)

parse_field_element(field::Kernel.AlgebraicFieldCertificate, object) =
    Kernel._parse_algebraic_element_object(object, field, "field_element")

verify_field_element(field::Kernel.AlgebraicFieldCertificate,
                     element::Kernel.AlgebraicElement) =
    element.field_hash == field.field_hash &&
    element.element_hash == Kernel.algebraic_element_hash(element)

canonical_field_hash(field::Kernel.AlgebraicFieldCertificate) =
    Kernel.algebraic_field_certificate_hash(field)

function sign_exact(field::Kernel.AlgebraicFieldCertificate,
                    element::Kernel.AlgebraicElement)
    positive = Kernel._algebraic_sign_positive(element, field)
    positive && return :positive_or_zero
    return :unknown
end

end
