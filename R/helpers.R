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
  .session_fun("nl_eval_string")(code)
}

#' Build a NoLimits Model from @Model DSL source. The string may contain a Julia
#' prelude before @Model (e.g. `using SimpleChains` and chain definitions). A bare
#' block body without @Model is wrapped in @Model begin ... end.
nl_model <- function(code) {
  if (!is.character(code) || length(code) != 1L) {
    stop("nl_model() needs a single string, got ", class(code)[1], " of length ",
         length(code), ".", call. = FALSE)
  }
  code <- trimws(code)
  if (!grepl("@Model", .strip_comments(code), fixed = TRUE)) {
    code <- paste0("@Model begin\n", code, "\nend")
  }
  nl_eval(code)
}

# ponytail: a `#` inside a string literal also counts as a comment start here;
# good enough to decide whether the source has a real @Model block.
.strip_comments <- function(code) {
  paste(sub("#.*$", "", strsplit(code, "\n", fixed = TRUE)[[1]]), collapse = "\n")
}

#' R data.frame -> Julia DataFrames.DataFrame (required input for DataModel).
#' Factor columns are sent as their character labels; the bridge would otherwise
#' ship the bare integer codes.
nl_data <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  if (nrow(df) == 0) {
    stop("nl_data() requires at least one row; the R-to-Julia bridge cannot ",
         "serialize zero-length columns.", call. = FALSE)
  }
  fac <- vapply(df, is.factor, logical(1))
  df[fac] <- lapply(df[fac], as.character)
  .session_fun("nl_df")(df)
}

#' Julia table (e.g. a predict() result) -> R data.frame.
nl_collect <- function(x) {
  cols <- JuliaConnectoR::juliaGet(.session_fun("nl_table")(x))
  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
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
  .session_fun("nl_nt")(...)
}

#' Julia Symbol from a string, for Symbol-typed arguments such as primary_id.
#' Limited to strings shorter than 10000 bytes: JuliaConnectoR converts the
#' returned Symbol back into an R symbol, and R caps name lengths there.
jl_sym <- function(s) {
  if (!is.character(s) || length(s) != 1L) {
    stop("jl_sym() needs a single string, got ", class(s)[1], " of length ",
         length(s), ".", call. = FALSE)
  }
  nolimits()
  JuliaConnectoR::juliaCall("Symbol", s)
}

#' Call any NoLimits plot_* function by name; saves to `file` (or a temp PNG) and
#' draws it in the active graphics device when interactive. Returns the path
#' invisibly. Loads CairoMakie on first use.
nl_plot <- function(fname, ..., file = NULL) {
  if ("save_path" %in% names(list(...))) {
    stop("nl_plot() sets save_path itself; pass the destination as file = ",
         "instead of save_path = (not both).", call. = FALSE)
  }
  nl <- nolimits()
  if (is.null(.nl$makie)) {
    JuliaConnectoR::juliaEval("import CairoMakie")
    .nl$makie <- TRUE
  }
  path <- if (is.null(file)) tempfile(fileext = ".png") else file
  # NoLimits requires the save_path directory to exist, and Julia runs as a
  # subprocess whose working directory never follows R's, so hand it an absolute
  # path. normalizePath() cannot do this: it returns a relative path unchanged
  # when the target file does not exist yet, which is the normal case here.
  path <- path.expand(path)
  if (!grepl("^(/|[A-Za-z]:)", path)) {
    path <- file.path(getwd(), path)
  }
  nl[[fname]]  # errors clearly for an unknown plot name
  # Routed through the session's nl_safe_call: a raw Julia plotting error can hang
  # the bridge while it is being reported (see nl_safe_call).
  do.call(.session_fun("nl_safe_call"), c(list(fname), list(...), list(save_path = path)))
  # Makie leaves ~30 MB of figure memory per plot behind; a collect here recovers
  # most of it (measured ~5 MB/plot residual) and costs little next to rendering.
  nl_eval("GC.gc(); nothing")
  if (is.null(file) && interactive() && requireNamespace("png", quietly = TRUE)) {
    grid::grid.newpage()
    grid::grid.raster(png::readPNG(path))
  }
  invisible(path)
}
