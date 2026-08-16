.onUnload <- function(libpath) {
  try(JuliaConnectoR::stopJulia(), silent = TRUE)
}
