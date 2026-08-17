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
  JuliaConnectoR::juliaEval(.SESSION_SETUP)
  .nl$api <- JuliaConnectoR::juliaImport("NoLimits")
  .nl$api
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
  st$installed_packages <- JuliaConnectoR::juliaEval(
    "join(sort!(collect(keys(Pkg.project().dependencies))), \", \")"
  )
  st
}
