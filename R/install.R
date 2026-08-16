#' Install NoLimits.jl (and CairoMakie) into the shared 'NoLimitsR' Julia
#' environment. `extras` adds optional integrations, e.g.
#' install_nolimits(extras = c("SimpleChains", "Lux", "CSV", "JLD2")).
install_nolimits <- function(extras = character()) {
  if (!JuliaConnectoR::juliaSetupOk()) {
    stop("No suitable Julia (>= 1.10) found. Install Julia (e.g. via juliaup) ",
         "or point JULIA_BINDIR at its bin directory.")
  }
  pkgs <- unique(c("NoLimits", "CairoMakie", extras))
  spec <- paste0('["', paste(pkgs, collapse = '", "'), '"]')
  JuliaConnectoR::juliaEval(paste0(
    'import Pkg; Pkg.activate("NoLimitsR"; shared = true); Pkg.add(', spec, ')'
  ))
  invisible(TRUE)
}
