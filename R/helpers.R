#' Attach every NoLimits function to the search path so they can be called
#' without the nl$ prefix, e.g. fit_model(dm, Laplace()). By default, names
#' that would mask a function already visible on the search path (such as
#' stats::predict) are skipped and reported; reach those via nl$ as before.
#' Set exclude_masking = FALSE to attach everything anyway. Undo: nl_detach().
nl_attach <- function(exclude_masking = TRUE) {
  nl <- nolimits()
  nl_detach()
  nms <- ls(nl)
  skipped <- character()
  if (exclude_masking) {
    on_search <- function(n) {
      any(vapply(search(), function(db) {
        exists(n, where = db, mode = "function", inherits = FALSE)
      }, logical(1)))
    }
    skipped <- nms[vapply(nms, on_search, logical(1))]
    nms <- setdiff(nms, skipped)
  }
  # attach() is deliberate: an explicit, user-invoked, reversible convenience.
  attach(mget(nms, envir = nl), name = "NoLimitsR:api", warn.conflicts = FALSE)
  if (length(skipped) > 0) {
    message("Not attached (would mask existing R functions; use nl$ for these): ",
            paste(skipped, collapse = ", "))
  }
  invisible(nms)
}

#' Remove the functions attached by nl_attach() from the search path.
nl_detach <- function() {
  if ("NoLimitsR:api" %in% search()) {
    detach("NoLimitsR:api", character.only = TRUE)
  }
  invisible(NULL)
}

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

#' Render any Julia object (parameters, shrinkage, fit summaries) as a string,
#' the way Julia would print it.
nl_string <- function(x) {
  nolimits()
  JuliaConnectoR::juliaCall("string", x)
}

#' Materialize a Julia value into plain R data structures (lists, vectors). For
#' tables prefer nl_collect(), which returns a data.frame.
nl_get <- function(x) {
  nolimits()
  JuliaConnectoR::juliaGet(x)
}

#' Build a Julia NamedTuple from named arguments, for NamedTuple-typed options
#' such as Laplace(optim_kwargs = nl_nt(show_trace = TRUE)) or
#' fit_model(..., theta_0_untransformed = nl_nt(k = 0.7)). Nests naturally:
#' nl_nt(a = nl_nt(b = 1)).
nl_nt <- function(...) {
  nolimits()
  JuliaConnectoR::juliaCall("NoLimitsSession.nl_nt", ...)
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
