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
const Tables = DataFrames.Tables
# JuliaConnectoR ships a length-1 R column as a scalar, which DataFrame(tbl)
# then measures with length() (a 2-character string looks like 2 rows).
nl_vec(v) = v isa AbstractVector ? v : [v]
nl_df(tbl::DataFrames.DataFrame) = tbl
# Accessors such as get_random_effects return a NamedTuple of DataFrames, which
# Tables.columns would happily read as a one-row table of stringified vectors.
function nl_df(tbl::NamedTuple{<:Any, <:Tuple{DataFrames.DataFrame, Vararg{DataFrames.DataFrame}}})
    length(tbl) == 1 && return only(tbl)
    error("got a NamedTuple of $(length(tbl)) tables (fields: $(join(keys(tbl), ", "))); " *
          raw"collect one field, e.g. x$eta (R) / x.eta (Python)")
end
function nl_df(tbl)
    cols = Tables.columns(tbl)
    DataFrames.DataFrame([string(n) => nl_vec(Tables.getcolumn(cols, n))
                          for n in Tables.columnnames(cols)])
end
# An all-NA R character/factor column carries no type across the bridge (a
# length-1 NA arrives as bare `missing`, so the eltype is `Missing`), which would
# come back as a numeric column. nl_data names the string columns so the type
# survives whatever the row count.
function nl_df(tbl, str_cols)
    df = nl_df(tbl)
    for n in string.(nl_vec(str_cols))
        n in Base.names(df) || continue
        eltype(df[!, n]) === Missing || continue
        df[!, n] = Vector{Union{Missing, String}}(df[!, n])
    end
    df
end
nl_names(x) = string.(Base.names(nl_df(x)))
# Columns of exotic eltype (Symbol, enums) come back as R symbols, which
# as.data.frame then tries to evaluate; stringify anything not natively atomic.
nl_col(v) = eltype(v) <: Union{Real, AbstractString, Missing, Nothing} ? v : string.(v)
nl_table(x) = (df = nl_df(x); (; (Symbol(n) => nl_col(df[!, n]) for n in Base.names(df))...))
nl_eval_string(s::AbstractString) = Base.include_string(NoLimitsSession, s)
nl_nt(; kwargs...) = (; kwargs...)
# Calls a NoLimits function by name (for nl_plot, whose target is a string).
nl_safe_call(fname::AbstractString, args...; kwargs...) =
    getfield(NoLimits, Symbol(fname))(args...; kwargs...)
# A plain R named list crosses as an RConnector.ElementList, which is neither a
# NamedTuple nor an AbstractDict, so every NoLimits option that normalizes through
# _as_namedtuple (optim_kwargs, theta_untransformed, constants_re, ...) would
# accept it and fail later inside Julia. Teaching the normalizer about the bridge
# type makes list() work like nl_nt() everywhere at once.
function NoLimits._as_namedtuple(x::Main.RConnector.ElementList)
    isempty(x.positionalelements) ||
        error("an R list used as a NamedTuple option needs a name for every element; " *
              "got $(length(x.positionalelements)) unnamed one(s). Use nl_nt(...) instead of list(...).")
    isempty(x.names) && return NamedTuple()
    return (; (n => NoLimits._as_namedtuple(x.namedelements[n]) for n in x.names)...)
end
end
'

# target env: .nl$env (shared name or directory path); default "NoLimitsR"
.env_target <- function() if (is.null(.nl$env)) "NoLimitsR" else .nl$env

# A separator makes it a directory project; a bare name is always a shared env.
# Testing dir.exists() here instead would silently pick up a same-named directory
# in the working directory (e.g. the package source dir "NoLimitsR").
.env_is_path <- function(env) grepl("[/\\\\]", env)

.activate_code <- function(env) {
  if (.env_is_path(env)) {
    sprintf('import Pkg; Pkg.activate("%s")',
            normalizePath(env, mustWork = FALSE, winslash = "/"))
  } else {
    sprintf('import Pkg; Pkg.activate("%s"; shared = true)', env)
  }
}

# `using NoLimits` also succeeds from Julia's stacked default environment (@v1.x),
# which pins nothing and isolates nothing, so both the boot and the status report
# insist that NoLimits is a recorded dependency of the target project.
.dep_error <- function(env, deps = .project_deps()) {
  if ("NoLimits" %in% deps) {
    return(NULL)
  }
  paste0("NoLimits.jl is not a dependency of the active project (",
         JuliaConnectoR::juliaEval("Base.active_project()"),
         "); it loaded from Julia's default environment instead. Run ",
         'NoLimitsR::install_nolimits(env = "', env, '").')
}

.project_deps <- function() {
  JuliaConnectoR::juliaEval("sort!(collect(keys(Pkg.project().dependencies)))")
}

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
  env <- .env_target()
  JuliaConnectoR::juliaEval(.activate_code(env))
  ok <- tryCatch({
    JuliaConnectoR::juliaEval("using NoLimits")
    TRUE
  }, error = function(e) FALSE)
  if (!ok) {
    hint <- if (is.null(.nl$env)) {
      "Run NoLimitsR::install_nolimits() once."
    } else {
      paste0('Run NoLimitsR::install_nolimits(env = "', env, '") once.')
    }
    stop("NoLimits.jl is not installed in the '", env, "' Julia environment. ",
         hint)
  }
  v <- JuliaConnectoR::juliaEval("string(pkgversion(NoLimits))")
  if (package_version(v) < .MIN_NOLIMITS) {
    stop("NoLimits.jl >= ", .MIN_NOLIMITS, " required, found ", v,
         ". Run NoLimitsR::install_nolimits().")
  }
  dep_err <- .dep_error(env)
  if (!is.null(dep_err)) {
    stop(dep_err)
  }
  JuliaConnectoR::juliaEval(.SESSION_SETUP)
  api <- JuliaConnectoR::juliaImport("NoLimits")
  class(api) <- c("nolimits_api", class(api))
  .nl$api <- api
  .nl$api
}

#' @export
`$.nolimits_api` <- function(x, name) .nl_export(x, name)

#' @export
`[[.nolimits_api` <- function(x, name) .nl_export(x, name)

# Unknown names must not come back as NULL: the caller then hits R's generic
# "attempt to apply non-function" far from the actual typo.
.nl_export <- function(x, name) {
  v <- get0(name, envir = x, inherits = FALSE)
  if (is.null(v)) {
    stop("NoLimits.jl has no export '", name, "'", call. = FALSE)
  }
  v
}

# Julia 1.12 warns (and a future Julia will error) whenever `NoLimitsSession.<name>`
# is resolved from the bridge's serving task, whose world age predates the session
# module. The proxy resolves the binding once, at eval time in the latest world, and
# invokelatest runs the call in the latest world too. The try/catch stringifies any
# Julia error inside Julia: the bridge would otherwise print a stack trace, and
# printing a frame re-resolves the binding (the same warning) while some errors
# (a Makie font failure) corrupt the socket mid-report and hang R forever.
.session_fun <- function(name) {
  key <- paste0(".fun_", name)
  if (is.null(.nl[[key]])) {
    nolimits()
    .nl[[key]] <- JuliaConnectoR::juliaEval(sprintf('
      let f = NoLimitsSession.%s
          (a...; k...) -> try
                  Base.invokelatest(f, a...; k...)
              catch e
                  msg = try
                      sprint(showerror, e)
                  catch
                      try
                          string(e)
                      catch
                          string(typeof(e))
                      end
                  end
                  error(first(msg, 2000))
              end
      end', name))
  }
  .nl[[key]]
}

#' Choose the Julia environment (shared name or directory path) used at boot.
#' Must be called before the first nolimits() call; with restart = TRUE it stops
#' the running Julia process and switches, losing ALL existing Julia objects.
nl_use_env <- function(env, restart = FALSE) {
  if (!is.null(.nl$api)) {
    if (!restart) {
      stop("Julia is already running with environment '", .env_target(),
           "'. Use nl_use_env(env, restart = TRUE) to stop Julia and switch; ",
           "all existing Julia objects will be lost.")
    }
    try(JuliaConnectoR::stopJulia(), silent = TRUE)
    rm(list = ls(.nl), envir = .nl)
  }
  .nl$env <- env
  invisible(env)
}

#' Diagnostic report: Julia setup, versions, active environment, packages.
#' Boots Julia (lazily) when the setup allows it.
nolimits_status <- function() {
  st <- list(
    julia_setup_ok = JuliaConnectoR::juliaSetupOk(),
    target_env = .env_target(),
    started = !is.null(.nl$api)
  )
  if (!st$julia_setup_ok) {
    return(st)
  }
  boot <- tryCatch({
    nolimits()
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(boot)) {
    st$error <- boot
    return(st)
  }
  st$started <- TRUE
  st$julia_version <- JuliaConnectoR::juliaEval("string(VERSION)")
  st$project <- JuliaConnectoR::juliaEval("Base.active_project()")
  st$nolimits_version <- JuliaConnectoR::juliaEval("string(pkgversion(NoLimits))")
  deps <- .project_deps()
  st$installed_packages <- paste(deps, collapse = ", ")
  dep_err <- .dep_error(st$target_env, deps)
  if (!is.null(dep_err)) {
    st$error <- dep_err
  }
  st
}
