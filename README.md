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

## Prefix-free usage

`nl_attach()` puts every NoLimits function on the search path, so plain calls work:

```r
nl_attach()
res <- fit_model(dm, Laplace(), pooled_init = TRUE)
nl_detach()
```

Names that would mask an existing R function (for example `stats::predict`) are
skipped and reported; call those through `nl$predict(...)` as usual, or attach
them anyway with `nl_attach(exclude_masking = FALSE)`. The `nl$` form remains
fully supported and autocompletes all functions in RStudio.

## NamedTuple options

Options that are NamedTuples in Julia are built with `nl_nt()`:

```r
res <- nl$fit_model(dm, nl$Laplace(optim_kwargs = nl_nt(show_trace = TRUE)),
                    theta_0_untransformed = nl_nt(k = 0.7))
```

`nl_nt` nests naturally, e.g. `nl_nt(a = nl_nt(b = 1))`.

## Environments

By default everything lives in the shared Julia environment named `NoLimitsR`, so
all R sessions on the machine use the same NoLimits.jl version. A per-project
environment takes one extra call, where `env` is either a shared environment name
or a directory path, a path being anything that contains a `/`:

```r
NoLimitsR::install_nolimits(env = "myproject")   # once, creates the environment
nl_use_env("myproject")                          # before the first nolimits() call
```

Pre-release versions can be tracked with `install_nolimits(rev = "main")`, which
installs NoLimits.jl straight from that branch, tag or commit instead of the
registry. A plain `install_nolimits()` returns the environment to registry
releases. When Julia is already running, both take effect at the next R session.

`nolimits_status()` is the first thing to run when something looks wrong. It
reports whether a suitable Julia was found, the target and active environment, the
Julia and NoLimits.jl versions, and the packages installed in the environment.

`update_nolimits()` runs `Pkg.update()` on the target environment, or on the one
given by `update_nolimits(env = ...)`. If Julia is already running, the updated
versions take effect in the next session, because loaded Julia code is never
replaced in place.

The environment is a boot-time choice for the same reason: Julia cannot unload a
package. Call `nl_use_env()` before the first `nolimits()` call, or use
`nl_use_env(env, restart = TRUE)` to stop the running Julia process and switch,
which discards all existing Julia objects (models, data, fits).

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
  `time_col`. It takes a single string shorter than 10000 bytes, which is where R's own
  limit on symbol names sits. All other keyword arguments pass through as normal R
  named arguments.
- Getting data in and out: `nl_data(df)` turns an R data.frame into a Julia
  `DataFrame`, which is what `DataModel` expects, and `nl_collect(x)` turns a Julia
  table such as a `predict` result back into an R data.frame. Scalars convert
  automatically. Column names round-trip unchanged, and Julia `missing` becomes `NA`.
  `nl_string(x)` prints any Julia object the way Julia would, which is the quickest
  look at parameters, shrinkage, or a fit summary, and `nl_get(x)` pulls a non-table
  Julia value into plain R lists and vectors.
- Conversion caveats:
  - Always go through `nl_data()`. The bridge sends a factor column as its bare
    integer codes, so `nl_data()` converts factors to their character labels first.
    A raw data.frame handed straight to a Julia function skips that step and silently
    substitutes codes for labels, which is easy to miss on a subject-ID column. Convert
    with `as.character()` yourself if you bypass `nl_data()`.
  - Duplicate column names are renamed. DataFrames.jl requires unique names, so two
    columns called `x` arrive as `x` and `x_2` without a warning.
  - List-columns are stringified. A column holding vectors comes back as text such as
    `[1, 2]`, because a Julia column of exotic element type has no atomic R
    equivalent. Split such columns into plain columns before converting.
  - Zero-row frames are rejected: the bridge cannot serialize zero-length columns, so
    `nl_data()` stops with a message instead.
- NamedTuple options: `nl_nt()` builds the NamedTuple that options such as
  `optim_kwargs` expect. Options that NoLimits keys by value rather than by name, such
  as `constants_re`, are Julia dictionaries instead and are built with `nl_eval()`.
- R only: use `nl_eval(code)` for Julia code that model strings must see. It evaluates
  in the session module, possibly several expressions at once, so anything it defines
  is visible to later `nl_model` calls. Evaluating in Julia's `Main` instead, which is
  what the underlying bridge does by default, is not visible to model strings.
- Julia console output, for example optimizer traces from `optim_kwargs` with
  `show_trace` or progress logs, streams to the R console automatically. In Jupyter or
  the VS Code Interactive Window, raw Julia output may appear in the terminal running
  the kernel instead of in the cell.
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
