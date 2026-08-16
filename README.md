# NoLimitsR

R interface to [NoLimits.jl](https://github.com/manuhuth/NoLimits.jl), a Julia
package for nonlinear mixed-effects analysis of longitudinal data.

Every exported NoLimits.jl name is reachable through the environment returned by
`nolimits()`. The wrapper adds only session management and a handful of conversion
helpers, so new NoLimits features are available as soon as the Julia package is
updated.

## Installation

Install Julia 1.10 or newer, for example with [juliaup](https://github.com/JuliaLang/juliaup),
then install the R package and the Julia dependencies:

```r
install.packages("JuliaConnectoR")
# install NoLimitsR from source, e.g. R CMD INSTALL NoLimitsR

NoLimitsR::install_nolimits()
```

`install_nolimits()` adds NoLimits.jl and CairoMakie to a shared Julia environment
named `NoLimitsR`. It downloads and precompiles the Julia packages, which takes
several minutes on the first run. Optional integrations go through the same call:

```r
NoLimitsR::install_nolimits(extras = c("SimpleChains", "Lux", "CSV", "JLD2"))
```

Julia boots lazily on the first `nolimits()` call, not at `library()` time.

## Quickstart

```r
library(NoLimitsR)

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

nl$get_objective(res)
head(nl_collect(nl$predict(res, jdf)))

nl_plot("plot_fits", res, file = "fits.png")
```

## Models with a Julia prelude (neural networks and other extras)

`nl_model` accepts arbitrary Julia code before the `@Model` block, which is how
neural-network parameters, custom functions, and weak-dependency imports enter a
model. Install the optional Julia package once:

```r
NoLimitsR::install_nolimits(extras = "SimpleChains")
```

Then put the prelude in the model string:

```r
model <- nl_model('
using SimpleChains
chain = SimpleChain(static(1), TurboDense(tanh, 2), TurboDense(identity, 1))

@Model begin
    @fixedEffects begin
        z = NNParameters(chain; function_name=:NN1, calculate_se=false)
        sigma = RealNumber(0.5, scale=:log)
    end
    @covariates begin
        time = Covariate()
    end
    @formulas begin
        pred = NN1([time], z)[1]
        y ~ Normal(pred, sigma)
    end
end
')
```

The same mechanism covers Lux, CSV, JLD2, Copulas, and Turing.

## Notes

- Dynamic surface: any NoLimits.jl export is available as `nl$<name>`, where
  `nl <- nolimits()`. See the NoLimits.jl documentation for the API, the wrapper adds
  nothing on top of it. Names ending in `!` need backticks, as in ``nl$`foo!` ``.
  Julia macros are not part of the dynamic surface, which is what `nl_model` and
  `nl_eval` are for.
- Symbols: use `jl_sym("ID")` for Symbol-typed arguments such as `primary_id` and
  `time_col`. All other keyword arguments pass through as normal R named arguments.
- Getting data in and out: `nl_data(df)` turns an R data.frame into a Julia
  `DataFrame`, which is what `DataModel` expects, and `nl_collect(x)` turns a Julia
  table such as a `predict` result back into an R data.frame. Scalars convert
  automatically.
- R only: use `nl_eval(code)` for Julia code that model strings must see. It evaluates
  in the session module, possibly several expressions at once, so anything it defines
  is visible to later `nl_model` calls. `JuliaConnectoR::juliaEval` evaluates in `Main`
  instead and is not visible to model strings.
- Plotting: `nl_plot("plot_fits", res, file = "fits.png")` calls any NoLimits `plot_*`
  function and forwards `save_path`. Without `file` it writes a temporary PNG and draws
  it in the active graphics device in interactive sessions. CairoMakie is loaded on the
  first plot call only.
- Model, DataModel, and fit-result objects are live references into the Julia session
  and do not survive the process. Persist fits with `save_fit`/`load_fit` after
  `install_nolimits(extras = "JLD2")`. A reloaded fit needs its model string
  re-evaluated, because models themselves are not serializable.

## License

MIT
