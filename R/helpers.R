#' Evaluate Julia code (multiple expressions allowed) in the session module.
#' Objects defined here (chains, helpers) are visible to later nl_model() calls.
#' Note: JuliaConnectoR::juliaEval evaluates in Main instead and is NOT visible
#' to model strings.
nl_eval <- function(code) {
  nolimits()
  JuliaConnectoR::juliaCall("NoLimitsSession.nl_eval_string", code)
}

#' Build a NoLimits Model from @Model DSL source. The string may contain a Julia
#' prelude before @Model (e.g. `using SimpleChains` and chain definitions). A bare
#' block body without @Model is wrapped in @Model begin ... end.
nl_model <- function(code) {
  code <- trimws(code)
  if (!grepl("@Model", code, fixed = TRUE)) {
    code <- paste0("@Model begin\n", code, "\nend")
  }
  nl_eval(code)
}

#' R data.frame -> Julia DataFrames.DataFrame (required input for DataModel).
nl_data <- function(df) {
  nolimits()
  JuliaConnectoR::juliaCall("NoLimitsSession.nl_df", df)
}

#' Julia table (e.g. a predict() result) -> R data.frame.
nl_collect <- function(x) {
  nolimits()
  cols <- JuliaConnectoR::juliaGet(JuliaConnectoR::juliaCall("NoLimitsSession.nl_table", x))
  as.data.frame(cols, stringsAsFactors = FALSE)
}

#' Julia Symbol from a string, for Symbol-typed arguments such as primary_id.
jl_sym <- function(s) {
  nolimits()
  JuliaConnectoR::juliaCall("Symbol", s)
}

#' Call any NoLimits plot_* function by name; saves to `file` (or a temp PNG) and
#' draws it in the active graphics device when interactive. Returns the path
#' invisibly. Loads CairoMakie on first use.
nl_plot <- function(fname, ..., file = NULL) {
  nl <- nolimits()
  if (is.null(.nl$makie)) {
    JuliaConnectoR::juliaEval("import CairoMakie")
    .nl$makie <- TRUE
  }
  path <- if (is.null(file)) tempfile(fileext = ".png") else file
  # NoLimits requires the save_path directory to exist; a bare filename has an
  # empty dirname, so hand Julia an absolute path.
  path <- normalizePath(path, mustWork = FALSE)
  do.call(nl[[fname]], c(list(...), list(save_path = path)))
  if (is.null(file) && interactive() && requireNamespace("png", quietly = TRUE)) {
    grid::grid.newpage()
    grid::grid.raster(png::readPNG(path))
  }
  invisible(path)
}
