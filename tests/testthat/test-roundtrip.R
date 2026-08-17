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

  path <- tempfile(fileext = ".png")
  nl_plot("plot_fits", res, file = path)
  expect_gt(file.size(path), 0)
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
