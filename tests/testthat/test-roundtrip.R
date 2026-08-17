test_that("model string -> DataModel -> fit -> predict -> plot round-trip", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")

  nl <- nolimits()

  model <- nl_model('
@fixedEffects begin
    A0    = RealNumber(10.0, scale=:log)
    k     = RealNumber(0.5,  scale=:log)
    omega = RealNumber(0.3,  scale=:log)
    sigma = RealNumber(0.5,  scale=:log)
end

@covariates begin
    time = Covariate()
end

@randomEffects begin
    eta = RandomEffect(Normal(0.0, omega); column=:ID)
end

@formulas begin
    pred = A0 * exp(eta) * exp(-k * time)
    y ~ Normal(pred, sigma)
end
')

  df <- data.frame(
    ID = rep(c("s1", "s2", "s3", "s4"), each = 4),
    time = rep(c(0, 1, 2, 4), times = 4),
    y = c(10.2, 6.1, 3.6, 1.4, 12.5, 7.8, 4.9, 1.9,
          8.1, 4.9, 3.0, 1.1, 11.0, 6.5, 4.1, 1.6)
  )
  jdf <- nl_data(df)

  dm <- nl$DataModel(model, jdf, primary_id = jl_sym("ID"), time_col = jl_sym("time"))
  res <- nl$fit_model(dm, nl$Laplace())
  expect_true(is.finite(nl$get_objective(res)))

  pred <- nl$predict(res, jdf)
  expect_true("prediction" %in% names(nl_collect(pred)))

  # get_random_effects returns a NamedTuple of tables; nl_collect unwraps the
  # single field instead of stringifying it into one row.
  redf <- nl_collect(nl$get_random_effects(res))
  expect_equal(nrow(redf), 4L)
  expect_true(is.numeric(redf$eta_1))
  expect_equal(sort(as.character(redf$ID)), c("s1", "s2", "s3", "s4"))

  path <- tempfile(fileext = ".png")
  nl_plot("plot_fits", res, file = path)
  expect_gt(file.size(path), 0)

  # A relative file= resolves against R's working directory, not Julia's.
  wd <- file.path(tempdir(), "plotwd")
  dir.create(file.path(wd, "sub"), recursive = TRUE, showWarnings = FALSE)
  old <- setwd(wd)
  on.exit(setwd(old), add = TRUE)
  nl_plot("plot_fits", res, file = file.path("sub", "rel.png"))
  expect_gt(file.size(file.path("sub", "rel.png")), 0)

  expect_error(nl_plot("plot_fits", res, file = "a.png", save_path = "b.png"),
               "save_path")
  expect_error(nl_plot("plot_no_such_thing", res, file = "a.png"),
               "plot_no_such_thing")

  # A Julia-side plotting failure must come back as a plain, catchable R error.
  # Some of them (a Makie font error for a CJK subject ID, whose own showerror
  # hits a Julia 1.12 world-age fault) used to corrupt the bridge and hang R
  # forever; nl_plot routes through the session's nl_safe_call to prevent that.
  expect_error(nl_plot("plot_fits", "not a fit result", file = "a.png"),
               "MethodError")
})

test_that("data frame edge cases convert without corruption", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")

  # Factor labels, not the underlying integer codes.
  fdf <- data.frame(ID = factor(c("s1", "s1", "s2", "s2")), time = c(0, 1, 0, 1),
                    y = c(1, 2, 3, 4))
  expect_equal(nl_collect(nl_data(fdf))$ID, c("s1", "s1", "s2", "s2"))

  # A length-1 R column reaches Julia as a scalar; nl_df must still see one row.
  one <- nl_collect(nl_data(data.frame(ID = "s1", time = 0, y = 1.0)))
  expect_equal(nrow(one), 1L)
  expect_equal(as.character(one$ID), "s1")

  expect_error(nl_data(data.frame(ID = character(0), time = numeric(0))),
               "at least one row")

  # Column names round-trip byte for byte.
  sdf <- data.frame(ID = c("s1", "s1"), time = c(0, 1), y = c(1, 2))
  names(sdf)[3] <- "y with space"
  expect_equal(names(nl_collect(nl_data(sdf))), c("ID", "time", "y with space"))
})

test_that("nl_model wraps a bare body even when a comment mentions @Model", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  bare <- nl_model('
# no @Model here, just a comment
@fixedEffects begin
    sigma = RealNumber(0.5, scale=:log)
end
@covariates begin
    time = Covariate()
end
@formulas begin
    y ~ Normal(time, sigma)
end
')
  typename <- JuliaConnectoR::juliaEval("x -> string(nameof(typeof(x)))")
  expect_equal(typename(bare), "Model")
})

test_that("unknown names on the nl surface error informatively", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  nl <- nolimits()
  expect_true(is.function(nl$fit_model))
  expect_error(nl$totally_bogus_name_xyz, "totally_bogus_name_xyz")
  expect_error(nl[["totally_bogus_name_xyz"]], "totally_bogus_name_xyz")
})

test_that("jl_sym rejects non-scalar and non-character input", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  expect_error(jl_sym(c("ID", "other")), "single string")
  expect_error(jl_sym(1), "single string")
  expect_error(nl_model(c("a", "b")), "single string")
  expect_error(nl_model(1), "single string")
})

test_that("session helpers are called by reference, not by module-qualified name", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  # Julia 1.12 warns about world age whenever a call re-resolves
  # `NoLimitsSession.<name>`; a reference proxy never does.
  f <- NoLimitsR:::.session_fun("nl_df")
  expect_true("JLREF" %in% names(attributes(f)))
  expect_null(attr(f, "JLFUN"))
})

test_that("nl_eval evaluates in the session module", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  expect_equal(nl_eval("1 + 1"), 2L)
})

test_that("status reports the environment and use_env guards a live session", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  st <- nolimits_status()
  expect_true(nzchar(st$nolimits_version))
  expect_error(nl_use_env("elsewhere"), "already running")
})

test_that("nl_attach exposes functions without the nl$ prefix", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  suppressMessages(nl_attach())
  on.exit(nl_detach(), add = TRUE)
  expect_true("NoLimitsR:api" %in% search())
  expect_true(is.function(get("fit_model", pos = "NoLimitsR:api")))
  expect_false("predict" %in% ls("NoLimitsR:api"))
  nl_detach()
  expect_false("NoLimitsR:api" %in% search())
})

test_that("nl_nt builds Julia NamedTuples for option kwargs", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  nl <- nolimits()
  lap <- nl$Laplace(optim_kwargs = nl_nt(show_trace = TRUE))
  expect_match(JuliaConnectoR::juliaCall("string", lap), "show_trace")
  nested <- nl_nt(a = nl_nt(b = 1))
  expect_match(JuliaConnectoR::juliaCall("string", nested), "b = 1")
})

test_that("nl_string and nl_get avoid raw bridge calls", {
  skip_if_not(JuliaConnectoR::juliaSetupOk(), "Julia not available")
  s <- nl_string(jl_sym("abc"))
  expect_type(s, "character")
  expect_match(s, "abc")
  expect_true(1 %in% unlist(nl_get(nl_nt(a = 1))))
})
