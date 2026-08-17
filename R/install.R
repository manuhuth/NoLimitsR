#' Install NoLimits.jl (and CairoMakie) into a Julia environment. `env` is a
#' shared environment name or a directory path; a new env is created on first
#' use. `extras` adds optional integrations, e.g. c("SimpleChains", "JLD2").
install_nolimits <- function(extras = character(), env = "NoLimitsR") {
  if (!JuliaConnectoR::juliaSetupOk()) {
    stop("No suitable Julia (>= 1.10) found. Install Julia (e.g. via juliaup) ",
         "or point JULIA_BINDIR at its bin directory.")
  }
  pkgs <- unique(c("NoLimits", "CairoMakie", extras))
  spec <- paste0('["', paste(pkgs, collapse = '", "'), '"]')
  JuliaConnectoR::juliaEval(paste0(.activate_code(env), "; Pkg.add(", spec, ")"))
  invisible(TRUE)
}

#' Pkg.update() the target Julia environment. If Julia is already running, the
#' updated versions take effect in the NEXT session (loaded code is unchanged).
update_nolimits <- function(env = NULL) {
  if (!JuliaConnectoR::juliaSetupOk()) {
    stop("No suitable Julia (>= 1.10) found.")
  }
  env <- if (is.null(env)) .env_target() else env
  JuliaConnectoR::juliaEval(paste0(.activate_code(env), "; Pkg.update()"))
  if (!is.null(.nl$api)) {
    message("Julia is already running; updates take effect in the next session.")
  }
  invisible(TRUE)
}
