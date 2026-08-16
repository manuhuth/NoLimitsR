# Package-local cache. .onLoad is deliberately absent: Julia must not boot at
# library() time (R CMD check on Julia-less machines, headless servers).
.nl <- new.env(parent = emptyenv())

.MIN_NOLIMITS <- "0.2.4"

.SESSION_SETUP <- '
module NoLimitsSession
using NoLimits
using NoLimits.Distributions
using NoLimits.OrdinaryDiffEq
using NoLimits.LinearAlgebra
const DataFrames = NoLimits.DataFrames
nl_df(tbl) = DataFrames.DataFrame(tbl)
nl_names(x) = string.(Base.names(nl_df(x)))
# Columns of exotic eltype (Symbol, enums) come back as R symbols, which
# as.data.frame then tries to evaluate; stringify anything not natively atomic.
nl_col(v) = eltype(v) <: Union{Real, AbstractString, Missing, Nothing} ? v : string.(v)
nl_table(x) = (df = nl_df(x); (; (Symbol(n) => nl_col(df[!, n]) for n in Base.names(df))...))
nl_eval_string(s::AbstractString) = Base.include_string(NoLimitsSession, s)
end
'

#' Access the NoLimits.jl API
#'
#' Boots Julia on first call (lazily) and returns an environment containing every
#' exported NoLimits.jl function and type, e.g. nl <- nolimits();
#' nl$fit_model(dm, nl$Laplace()). Memoized after the first call.
nolimits <- function() {
  if (!is.null(.nl$api)) {
    return(.nl$api)
  }
  if (!JuliaConnectoR::juliaSetupOk()) {
    stop("No suitable Julia (>= 1.10) found. Install Julia (e.g. via juliaup) ",
         "or point JULIA_BINDIR at its bin directory.")
  }
  JuliaConnectoR::juliaEval('import Pkg; Pkg.activate("NoLimitsR"; shared = true)')
  ok <- tryCatch({
    JuliaConnectoR::juliaEval("using NoLimits")
    TRUE
  }, error = function(e) FALSE)
  if (!ok) {
    stop("NoLimits.jl is not installed in the shared 'NoLimitsR' Julia ",
         "environment. Run NoLimitsR::install_nolimits() once.")
  }
  v <- JuliaConnectoR::juliaEval("string(pkgversion(NoLimits))")
  if (package_version(v) < .MIN_NOLIMITS) {
    stop("NoLimits.jl >= ", .MIN_NOLIMITS, " required, found ", v,
         ". Run NoLimitsR::install_nolimits().")
  }
  JuliaConnectoR::juliaEval(.SESSION_SETUP)
  .nl$api <- JuliaConnectoR::juliaImport("NoLimits")
  .nl$api
}
