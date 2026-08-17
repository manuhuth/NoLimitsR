# Theophylline population PK with NoLimitsR.
#
# One-compartment oral-absorption ODE model (depot -> central), multiplicative
# log-normal random effects on ka, CL and V, fitted with warm-started Laplace.
# The ODE is linear, so NoLimits solves it in closed form.
#
# Prerequisites (once):
#   remotes::install_github("manuhuth/NoLimitsR") ; NoLimitsR::install_nolimits()
# Run from the repository root:
#   Rscript examples/theophylline.R
#
# Requires NoLimits.jl >= 0.2.5, which install_nolimits() takes from the registry.

library(NoLimitsR)

model_src <- '
@fixedEffects begin
    ka       = RealNumber(1.5)
    cl       = RealNumber(0.04)
    v        = RealNumber(0.5)
    omega_ka = RealNumber(0.5, scale=:log)
    omega_cl = RealNumber(0.3, scale=:log)
    omega_v  = RealNumber(0.3, scale=:log)
    sigma    = RealNumber(0.7, scale=:log)
end

@covariates begin
    t    = Covariate()
    Dose = ConstantCovariate(constant_on=:Subject)
end

@randomEffects begin
    eta_ka = RandomEffect(LogNormal(0.0, omega_ka); column=:Subject)
    eta_cl = RandomEffect(LogNormal(0.0, omega_cl); column=:Subject)
    eta_v  = RandomEffect(LogNormal(0.0, omega_v);  column=:Subject)
end

@preDifferentialEquation begin
    kai = ka * eta_ka
    cli = cl * eta_cl
    vi  = v * eta_v
end

@DifferentialEquation begin
    D(depot)   ~ -kai * depot
    D(central) ~ kai * depot - (cli / vi) * central
end

@initialDE begin
    depot   = Dose
    central = 0.0
end

@formulas begin
    cp = central(t) / vi
    conc ~ Normal(cp, sigma)
end
'

# Theophylline data ships with R (12 subjects, dose mg/kg, conc mg/L).
# Rebuild as a plain data.frame: datasets::Theoph carries nlme formula/units
# attributes that JuliaConnectoR warns about (harmlessly) when transferring.
df <- with(datasets::Theoph, data.frame(
  Subject = as.character(Subject),
  Wt = as.numeric(Wt),
  Dose = as.numeric(Dose),
  t = as.numeric(Time),
  conc = as.numeric(conc)
))

nl <- nolimits()
model <- nl_model(model_src)
# The data.frame goes straight in; NoLimits accepts any Tables.jl source.
dm <- nl$DataModel(model, df, primary_id = "Subject", time_col = "t")

# Starting-value check before fitting: both must be finite, and :ebe > :mean.
theta0 <- nl$get_params(dm, scale = "untransformed")
cat("loglik at theta0 (eta=mean):",
    nl$complete_data_loglikelihood(dm, theta0, eta = "mean"), "\n")
cat("loglik at theta0 (eta=ebe): ",
    nl$complete_data_loglikelihood(dm, theta0, eta = "ebe"), "\n")

res <- nl$fit_model(dm, nl$Laplace(), pooled_init = TRUE)

cat("objective:       ", nl$get_objective(res), "\n")
cat("marginal loglik: ", nl$get_marginal_likelihood(res), "\n")
cat("estimates (natural scale):\n")
cat(nl_string(nl$get_params(res, scale = "untransformed")), "\n")
cat("shrinkage:\n")
cat(nl_string(nl$compute_shrinkage(res)), "\n")

# Individual (EBE) predictions on the observed grid.
pred <- nl_collect(nl$predict(res, df, re_mode = "ebe"))
print(head(pred, 10))

# Diagnostics, saved as PNG.
nl_plot("plot_fits", res, file = "theoph_fits.png")
nl_plot("plot_dv_pred", res, file = "theoph_dv_pred.png")
cat("plots written: theoph_fits.png, theoph_dv_pred.png\n")
