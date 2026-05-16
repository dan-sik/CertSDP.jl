module CertSDPJuMPExt

using CertSDP
import CertSDP: extract_lmi, extract_moi_lmi, num_blocks, single_lmi_problem

using JuMP: JuMP
import MathOptInterface as MOI

const PSD_CONES = Union{MOI.PositiveSemidefiniteConeSquare,
                        MOI.PositiveSemidefiniteConeTriangle}
"""
    extract_lmi(model::JuMP.Model) -> LMIProblem or BlockLMIProblem

Extract exact affine PSD constraints from a JuMP model. The extractor accepts
only affine-in-variable PSD cone constraints and records JuMP/MOI provenance in
`BlockLMIProblem.metadata`.
"""
function extract_lmi(model::JuMP.GenericModel; include_variable_psd::Bool=true)
    _reject_nonlinear_model!(model)
    _reject_unsupported_jump_constraints!(model; include_variable_psd)
    variable_order, variable_mapping = _jump_variable_mapping(model)

    blocks = LMIProblem[]
    constraint_metadata = Any[]
    for (F, S) in JuMP.list_of_constraint_types(model)
        S <: PSD_CONES || continue
        if _is_jump_affine_vector_type(F)
            for cref in JuMP.all_constraints(model, F, S)
                block, meta = _extract_jump_psd_constraint(cref, variable_mapping,
                                                           variable_order)
                push!(blocks, block)
                push!(constraint_metadata, meta)
            end
        elseif include_variable_psd && _is_jump_variable_vector_type(F)
            for cref in JuMP.all_constraints(model, F, S)
                block, meta = _extract_jump_psd_constraint(cref, variable_mapping,
                                                           variable_order)
                push!(blocks, block)
                push!(constraint_metadata, meta)
            end
        end
    end

    isempty(blocks) &&
        throw(ArgumentError("JuMP model contains no affine PSD constraints to extract"))

    metadata = Dict{Symbol, Any}(:source_format => "jump_moi",
                                 :source => "JuMP.Model",
                                 :bridge_provenance => _jump_bridge_provenance(model),
                                 :variables => variable_mapping[:metadata],
                                 :constraints => constraint_metadata,
                                 :unsupported_policy => "error_on_non_affine_or_non_psd_constraints")
    block_problem = BlockLMIProblem(blocks;
                                    objective=_jump_linear_objective(model,
                                                                     variable_mapping),
                                    block_kinds=fill(:psd, length(blocks)),
                                    metadata)
    return num_blocks(block_problem) == 1 ? single_lmi_problem(block_problem) :
           block_problem
end

"""
    extract_moi_lmi(model::MOI.ModelLike) -> LMIProblem or BlockLMIProblem

Extract exact affine PSD constraints from a MathOptInterface model-like object.
The extractor accepts `VectorAffineFunction` and `VectorOfVariables` in PSD
cones and rejects all unsupported constraint types.
"""
function extract_moi_lmi(model::MOI.ModelLike)
    _reject_unsupported_moi_constraints!(model)
    variables, variable_mapping = _moi_variable_mapping(model)

    blocks = LMIProblem[]
    constraint_metadata = Any[]
    for (F, S) in MOI.get(model, MOI.ListOfConstraintTypesPresent())
        S <: PSD_CONES || continue
        for ci in MOI.get(model, MOI.ListOfConstraintIndices{F, S}())
            set = MOI.get(model, MOI.ConstraintSet(), ci)
            func = MOI.get(model, MOI.ConstraintFunction(), ci)
            block, meta = _extract_moi_psd_constraint(func, set, ci, variable_mapping,
                                                      variables)
            push!(blocks, block)
            push!(constraint_metadata, meta)
        end
    end

    isempty(blocks) &&
        throw(ArgumentError("MOI model contains no affine PSD constraints to extract"))

    metadata = Dict{Symbol, Any}(:source_format => "jump_moi",
                                 :source => "MOI.ModelLike",
                                 :bridge_provenance => _moi_bridge_provenance(model),
                                 :variables => variable_mapping[:metadata],
                                 :constraints => constraint_metadata,
                                 :unsupported_policy => "error_on_non_affine_or_non_psd_constraints")
    block_problem = BlockLMIProblem(blocks;
                                    objective=_moi_linear_objective(model,
                                                                    variable_mapping),
                                    block_kinds=fill(:psd, length(blocks)),
                                    metadata)
    return num_blocks(block_problem) == 1 ? single_lmi_problem(block_problem) :
           block_problem
end

function _reject_nonlinear_model!(model::JuMP.GenericModel)
    JuMP.num_nonlinear_constraints(model) == 0 ||
        throw(ArgumentError("unsupported JuMP model: nonlinear constraints are not supported by CertSDP.extract_lmi"))
    isnothing(JuMP.nonlinear_model(model)) ||
        throw(ArgumentError("unsupported JuMP model: nonlinear objective or expressions are not supported by CertSDP.extract_lmi"))
    return true
end

function _reject_unsupported_jump_constraints!(model::JuMP.GenericModel;
                                               include_variable_psd::Bool)
    for (F, S) in JuMP.list_of_constraint_types(model)
        if S <: PSD_CONES
            (_is_jump_affine_vector_type(F) ||
             (include_variable_psd && _is_jump_variable_vector_type(F))) &&
                continue
            throw(ArgumentError("unsupported nonlinear/bilinear JuMP PSD constraint: function type `$F` in set `$S`; only affine PSD constraints are supported"))
        end
        throw(ArgumentError("unsupported JuMP constraint type `$F` in set `$S`; extract_lmi only accepts affine PSD cone constraints"))
    end
    return true
end

_is_jump_affine_vector_type(::Type{<:AbstractVector{<:JuMP.GenericAffExpr}}) = true
_is_jump_affine_vector_type(::Type) = false
_is_jump_variable_vector_type(::Type{<:AbstractVector{<:JuMP.AbstractVariableRef}}) = true
_is_jump_variable_vector_type(::Type) = false

function _reject_unsupported_moi_constraints!(model::MOI.ModelLike)
    for (F, S) in MOI.get(model, MOI.ListOfConstraintTypesPresent())
        if S <: PSD_CONES
            (F <: MOI.VectorAffineFunction || F <: MOI.VectorOfVariables) && continue
            throw(ArgumentError("unsupported MOI PSD constraint: function type `$F` in set `$S`; only VectorAffineFunction or VectorOfVariables PSD constraints are supported"))
        end
        throw(ArgumentError("unsupported MOI constraint type `$F` in set `$S`; extract_moi_lmi only accepts affine PSD cone constraints"))
    end
    return true
end

function _jump_variable_mapping(model::JuMP.GenericModel)
    variables = JuMP.all_variables(model)
    sorted_variables = sort(variables; by=variable -> MOI_index_value(JuMP.index(variable)))
    index_by_variable = Dict{Any, Int}()
    metadata = Any[]
    cert_vars = Symbol[]
    for (i, variable) in enumerate(sorted_variables)
        cert_var = Symbol("x", i)
        index_by_variable[variable] = i
        push!(cert_vars, cert_var)
        push!(metadata,
              Dict{Symbol, Any}(:certsdp_variable => String(cert_var),
                                :jump_name => JuMP.name(variable),
                                :moi_index => MOI_index_value(JuMP.index(variable))))
    end
    return cert_vars,
           Dict{Symbol, Any}(:metadata => metadata,
                             :kind => "jump_variable_to_certsdp_variable",
                             :variable_count => length(cert_vars),
                             :index_by_variable => index_by_variable)
end

function _moi_variable_mapping(model::MOI.ModelLike)
    variables = MOI.get(model, MOI.ListOfVariableIndices())
    sort!(variables; by=MOI_index_value)
    index_by_variable = Dict{MOI.VariableIndex, Int}()
    metadata = Any[]
    cert_vars = Symbol[]
    for (i, variable) in enumerate(variables)
        cert_var = Symbol("x", i)
        index_by_variable[variable] = i
        name = try
            MOI.get(model, MOI.VariableName(), variable)
        catch
            ""
        end
        push!(cert_vars, cert_var)
        push!(metadata,
              Dict{Symbol, Any}(:certsdp_variable => String(cert_var),
                                :moi_name => name,
                                :moi_index => MOI_index_value(variable)))
    end
    return cert_vars,
           Dict{Symbol, Any}(:metadata => metadata,
                             :kind => "moi_variable_to_certsdp_variable",
                             :variable_count => length(cert_vars),
                             :index_by_variable => index_by_variable)
end

function _extract_jump_psd_constraint(cref,
                                      variable_mapping::Dict{Symbol, Any},
                                      variable_order::Vector{Symbol})
    object = JuMP.constraint_object(cref)
    set = object.set
    m = set.side_dimension
    entries = _jump_psd_entries(object.func, set, cref)
    A0 = zeros(Rational{BigInt}, m, m)
    coefficients = [zeros(Rational{BigInt}, m, m) for _ in variable_order]

    for (vector_index, expr) in enumerate(entries)
        row, col = _matrix_position(set, vector_index)
        constant, terms = _jump_affine_terms(expr, variable_mapping[:index_by_variable])
        _add_psd_entry!(A0, set, row, col, constant)
        for (variable_index, coefficient) in terms
            _add_psd_entry!(coefficients[variable_index], set, row, col, coefficient)
        end
    end
    _check_square_psd_symmetric!(A0, coefficients, set,
                                 "JuMP PSD constraint `$(JuMP.name(cref))`")

    block = LMIProblem(A0, coefficients; vars=variable_order)
    metadata = Dict{Symbol, Any}(:source => "JuMP.ConstraintRef",
                                 :name => JuMP.name(cref),
                                 :moi_constraint_index => MOI_index_value(JuMP.index(cref)),
                                 :moi_function_type => string(typeof(object.func)),
                                 :moi_set_type => string(typeof(set)),
                                 :cone => _psd_cone_name(set),
                                 :side_dimension => m,
                                 :vectorized_length => length(entries),
                                 :shape => string(typeof(getfield(cref, :shape))))
    return block, metadata
end

function _extract_moi_psd_constraint(func,
                                     set::PSD_CONES,
                                     ci::MOI.ConstraintIndex,
                                     variable_mapping::Dict{Symbol, Any},
                                     variable_order::Vector{Symbol})
    m = set.side_dimension
    A0 = zeros(Rational{BigInt}, m, m)
    coefficients = [zeros(Rational{BigInt}, m, m) for _ in variable_order]

    if func isa MOI.VectorAffineFunction
        length(func.constants) == _psd_vector_length(set) ||
            throw(ArgumentError("MOI PSD constraint $(MOI_index_value(ci)) has vector length $(length(func.constants)); expected $(_psd_vector_length(set)) for $(typeof(set))"))
        for (vector_index, constant) in enumerate(func.constants)
            row, col = _matrix_position(set, vector_index)
            _add_psd_entry!(A0, set, row, col,
                            _exact_rational(constant,
                                            "MOI PSD constant[$vector_index]"))
        end
        for term in func.terms
            row, col = _matrix_position(set, term.output_index)
            variable_index = get(variable_mapping[:index_by_variable],
                                 term.scalar_term.variable,
                                 nothing)
            isnothing(variable_index) &&
                throw(ArgumentError("MOI PSD constraint uses variable $(term.scalar_term.variable) that is not present in the model variable list"))
            coefficient = _exact_rational(term.scalar_term.coefficient,
                                          "MOI PSD coefficient[$(term.output_index)]")
            _add_psd_entry!(coefficients[variable_index], set, row, col,
                            coefficient)
        end
    elseif func isa MOI.VectorOfVariables
        length(func.variables) == _psd_vector_length(set) ||
            throw(ArgumentError("MOI PSD variable vector has length $(length(func.variables)); expected $(_psd_vector_length(set)) for $(typeof(set))"))
        for (vector_index, variable) in enumerate(func.variables)
            row, col = _matrix_position(set, vector_index)
            variable_index = get(variable_mapping[:index_by_variable], variable, nothing)
            isnothing(variable_index) &&
                throw(ArgumentError("MOI PSD constraint uses variable $variable that is not present in the model variable list"))
            _add_psd_entry!(coefficients[variable_index], set, row, col,
                            Rational{BigInt}(1))
        end
    else
        throw(ArgumentError("unsupported MOI PSD function $(typeof(func)); expected VectorAffineFunction or VectorOfVariables"))
    end
    _check_square_psd_symmetric!(A0, coefficients, set,
                                 "MOI PSD constraint $(MOI_index_value(ci))")

    block = LMIProblem(A0, coefficients; vars=variable_order)
    metadata = Dict{Symbol, Any}(:source => "MOI.ConstraintIndex",
                                 :moi_constraint_index => MOI_index_value(ci),
                                 :moi_function_type => string(typeof(func)),
                                 :moi_set_type => string(typeof(set)),
                                 :cone => _psd_cone_name(set),
                                 :side_dimension => m,
                                 :vectorized_length => _psd_vector_length(set))
    return block, metadata
end

function _jump_psd_entries(func::AbstractVector,
                           set::MOI.PositiveSemidefiniteConeSquare,
                           cref)
    expected = set.side_dimension^2
    length(func) == expected ||
        throw(ArgumentError("JuMP PSD constraint `$(JuMP.name(cref))` has vector length $(length(func)); expected $expected for square PSD cone"))
    return func
end

function _jump_psd_entries(func::AbstractVector,
                           set::MOI.PositiveSemidefiniteConeTriangle,
                           cref)
    expected = div(set.side_dimension * (set.side_dimension + 1), 2)
    length(func) == expected ||
        throw(ArgumentError("JuMP PSD constraint `$(JuMP.name(cref))` has vector length $(length(func)); expected $expected for triangle PSD cone"))
    return func
end

function _jump_affine_terms(expr::JuMP.GenericAffExpr, index_by_variable)
    constant = _exact_rational(expr.constant, "JuMP affine constant")
    terms = Pair{Int, Rational{BigInt}}[]
    for (variable, coefficient) in expr.terms
        variable_index = get(index_by_variable, variable, nothing)
        isnothing(variable_index) &&
            throw(ArgumentError("JuMP affine PSD expression uses variable `$variable` that is not owned by the extracted model"))
        push!(terms,
              variable_index => _exact_rational(coefficient,
                                                "JuMP affine coefficient for `$variable`"))
    end
    return constant, terms
end

function _jump_affine_terms(variable::JuMP.AbstractVariableRef, index_by_variable)
    variable_index = get(index_by_variable, variable, nothing)
    isnothing(variable_index) &&
        throw(ArgumentError("JuMP PSD variable `$variable` is not owned by the extracted model"))
    return Rational{BigInt}(0), [variable_index => Rational{BigInt}(1)]
end

function _jump_affine_terms(value::Number, index_by_variable)
    return _exact_rational(value, "JuMP PSD numeric constant"),
           Pair{Int, Rational{BigInt}}[]
end

function _jump_affine_terms(expr, index_by_variable)
    throw(ArgumentError("unsupported JuMP PSD expression type `$(typeof(expr))`; only affine expressions are supported"))
end

function _matrix_position(set::MOI.PositiveSemidefiniteConeSquare, vector_index::Integer)
    m = set.side_dimension
    1 <= vector_index <= m * m ||
        throw(ArgumentError("PSD square vector index $vector_index is outside 1:$(m * m)"))
    row = ((vector_index - 1) % m) + 1
    col = div(vector_index - 1, m) + 1
    return row, col
end

function _matrix_position(set::MOI.PositiveSemidefiniteConeTriangle, vector_index::Integer)
    row, col = MOI.Utilities.inverse_trimap(vector_index)
    return row, col
end

_psd_vector_length(set::MOI.PositiveSemidefiniteConeSquare) = set.side_dimension^2
function _psd_vector_length(set::MOI.PositiveSemidefiniteConeTriangle)
    return div(set.side_dimension * (set.side_dimension + 1), 2)
end

function _add_symmetric_entry!(matrix::Matrix{Rational{BigInt}},
                               row::Integer,
                               col::Integer,
                               value::Rational{BigInt})
    matrix[row, col] += value
    row == col || (matrix[col, row] += value)
    return matrix
end

function _add_psd_entry!(matrix::Matrix{Rational{BigInt}},
                         ::MOI.PositiveSemidefiniteConeTriangle,
                         row::Integer,
                         col::Integer,
                         value::Rational{BigInt})
    return _add_symmetric_entry!(matrix, row, col, value)
end

function _add_psd_entry!(matrix::Matrix{Rational{BigInt}},
                         ::MOI.PositiveSemidefiniteConeSquare,
                         row::Integer,
                         col::Integer,
                         value::Rational{BigInt})
    matrix[row, col] += value
    return matrix
end

function _check_square_psd_symmetric!(A0::Matrix{Rational{BigInt}},
                                      coefficients::Vector{Matrix{Rational{BigInt}}},
                                      ::MOI.PositiveSemidefiniteConeTriangle,
                                      source::AbstractString)
    return true
end

function _check_square_psd_symmetric!(A0::Matrix{Rational{BigInt}},
                                      coefficients::Vector{Matrix{Rational{BigInt}}},
                                      ::MOI.PositiveSemidefiniteConeSquare,
                                      source::AbstractString)
    _check_exact_symmetric(A0, "$source constant matrix")
    for (i, matrix) in enumerate(coefficients)
        _check_exact_symmetric(matrix, "$source coefficient matrix x$i")
    end
    return true
end

function _check_exact_symmetric(matrix::Matrix{Rational{BigInt}},
                                source::AbstractString)
    for j in axes(matrix, 2), i in (j + 1):size(matrix, 1)
        matrix[i, j] == matrix[j, i] ||
            throw(ArgumentError("unsupported asymmetric square PSD constraint: $source has entry ($i, $j)=$(matrix[i, j]) but ($j, $i)=$(matrix[j, i]); CertSDP.extract_lmi currently requires affine square PSD matrices to be explicitly symmetric"))
    end
    return true
end

function _exact_rational(value::Integer, path::AbstractString)
    return Rational{BigInt}(BigInt(value), BigInt(1))
end

function _exact_rational(value::Rational, path::AbstractString)
    return Rational{BigInt}(BigInt(numerator(value)), BigInt(denominator(value)))
end

function _exact_rational(value::AbstractFloat, path::AbstractString)
    isfinite(value) || throw(ArgumentError("$path must be finite; got $value"))
    return Rational{BigInt}(value)
end

function _exact_rational(value, path::AbstractString)
    throw(ArgumentError("$path has unsupported coefficient type $(typeof(value)); expected an exact integer/rational or finite floating point value"))
end

function _jump_linear_objective(model::JuMP.GenericModel,
                                variable_mapping::Dict{Symbol, Any})
    objective = zeros(Rational{BigInt}, variable_mapping[:variable_count])
    JuMP.objective_sense(model) === JuMP.FEASIBILITY_SENSE && return objective
    objective_type = JuMP.objective_function_type(model)
    if objective_type <: Number
        return objective
    elseif objective_type <: JuMP.AbstractVariableRef ||
           objective_type <: JuMP.GenericAffExpr
        constant, terms = _jump_affine_terms(JuMP.objective_function(model),
                                             variable_mapping[:index_by_variable])
        for (variable_index, coefficient) in terms
            objective[variable_index] += coefficient
        end
        return objective
    end
    throw(ArgumentError("unsupported JuMP objective type `$objective_type`; extract_lmi only preserves affine objectives"))
end

function _moi_linear_objective(model::MOI.ModelLike,
                               variable_mapping::Dict{Symbol, Any})
    objective = zeros(Rational{BigInt}, variable_mapping[:variable_count])
    sense = try
        MOI.get(model, MOI.ObjectiveSense())
    catch
        MOI.FEASIBILITY_SENSE
    end
    sense === MOI.FEASIBILITY_SENSE && return objective
    objective_type = try
        MOI.get(model, MOI.ObjectiveFunctionType())
    catch
        return objective
    end
    if objective_type <: MOI.VariableIndex
        variable = MOI.get(model, MOI.ObjectiveFunction{objective_type}())
        variable_index = get(variable_mapping[:index_by_variable], variable, nothing)
        isnothing(variable_index) ||
            (objective[variable_index] += Rational{BigInt}(1))
        return objective
    elseif objective_type <: MOI.ScalarAffineFunction
        func = MOI.get(model, MOI.ObjectiveFunction{objective_type}())
        for term in func.terms
            variable_index = get(variable_mapping[:index_by_variable],
                                 term.variable,
                                 nothing)
            isnothing(variable_index) &&
                throw(ArgumentError("MOI affine objective uses variable $(term.variable) that is not present in the model variable list"))
            objective[variable_index] += _exact_rational(term.coefficient,
                                                         "MOI objective coefficient")
        end
        return objective
    end
    throw(ArgumentError("unsupported MOI objective function type `$objective_type`; extract_moi_lmi only preserves affine objectives"))
end

function _jump_bridge_provenance(model::JuMP.GenericModel)
    active = IOBuffer()
    try
        JuMP.print_active_bridges(active, model)
    catch err
        print(active, "unavailable: ", sprint(showerror, err))
    end
    graph = IOBuffer()
    try
        JuMP.print_bridge_graph(graph, model)
    catch err
        print(graph, "unavailable: ", sprint(showerror, err))
    end
    return Dict{Symbol, Any}(:frontend => "JuMP",
                             :bridge_constraints => JuMP.bridge_constraints(model),
                             :active_bridges => String(take!(active)),
                             :bridge_graph => String(take!(graph)))
end

function _moi_bridge_provenance(model::MOI.ModelLike)
    return Dict{Symbol, Any}(:frontend => "MathOptInterface",
                             :model_type => string(typeof(model)),
                             :bridge_constraints => model isa
                                                    MOI.Bridges.AbstractBridgeOptimizer)
end

_psd_cone_name(::MOI.PositiveSemidefiniteConeSquare) = "PositiveSemidefiniteConeSquare"
_psd_cone_name(::MOI.PositiveSemidefiniteConeTriangle) = "PositiveSemidefiniteConeTriangle"

MOI_index_value(index) = getfield(index, :value)

end
