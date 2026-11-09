#' Install NoLimits.jl (with CairoMakie and AlgebraOfGraphics) into a Julia environment. `env` is a
#' shared environment name or a directory path; a new env is created on first
#' use. `extras` adds optional integrations, e.g. c("SimpleChains", "JLD2").
#' `rev` tracks an unreleased branch, tag or commit of NoLimits.jl, e.g.
#' rev = "main"; install_nolimits() without `rev` returns the environment to
#' registry releases. If Julia is already running, the change takes effect in
#' the NEXT session (loaded Julia code is never replaced in place).
install_nolimits <- function(extras = character(), env = "NoLimitsR", rev = NULL) {
  if (!JuliaConnectoR::juliaSetupOk()) {
    stop("No suitable Julia (>= 1.10) found. Install Julia (e.g. via juliaup) ",
         "or point JULIA_BINDIR at its bin directory.")
  }
  code <- if (is.null(rev)) {
    pkgs <- unique(c("NoLimits", "CairoMakie", "AlgebraOfGraphics", extras))
    spec <- paste0('["', paste(pkgs, collapse = '", "'), '"]')
    # Pkg.free converges a repo-tracking env back to the registry; it throws when
    # the package is already registry-tracked, so the failure is expected.
    paste0('; try Pkg.free("NoLimits") catch end; Pkg.add(', spec, ")")
  } else {
    pkgs <- unique(c("CairoMakie", "AlgebraOfGraphics", extras))
    spec <- paste0('["', paste(pkgs, collapse = '", "'), '"]')
    paste0('; Pkg.add(url = "https://github.com/manuhuth/NoLimits.jl", rev = "',
           rev, '"); Pkg.add(', spec, ")")
  }
  JuliaConnectoR::juliaEval(paste0(.activate_code(env), code))
  if (!is.null(.nl$api)) {
    message("Julia is already running; changes take effect in the next session.")
  }
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
