module TSSOSImporter

using ..Adapters

export import_tssos_artifact,
       certify_tssos_artifact

import_tssos_artifact(args...; kwargs...) =
    Adapters.import_tssos_artifact(args...; kwargs...)

certify_tssos_artifact(args...; kwargs...) =
    Adapters.certify_tssos_artifact(args...; kwargs...)

end
