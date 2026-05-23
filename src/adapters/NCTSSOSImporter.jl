module NCTSSOSImporter

using ..Adapters

export import_nctssos_artifact,
       certify_nctssos_artifact

import_nctssos_artifact(args...; kwargs...) =
    Adapters.import_nctssos_artifact(args...; kwargs...)

certify_nctssos_artifact(args...; kwargs...) =
    Adapters.certify_nctssos_artifact(args...; kwargs...)

end
