library(odin2)
library(dust2)
library(monty)

#data <- read.csv("incidence.csv")
#head(data)
#plot(cases ~ time, data, pch = 19, las = 1,
 #    xlab = "Time (days)", ylab = "Cases")

sir <- odin({
  
  #initial
  initial(N) <- N0
  initial(S) <- S0
  initial(I) <- I0
  initial(R) <- R0
  initial(new_cases, zero_every = 7) <- 0
  initial(all_deaths, zero_every = 1) <- 0
  initial(all_recovery, zero_every = 7) <- 0
  
  #updates
  update(N) <- N - n_deathsI
  update(S) <- S - n_Sout
  update(I) <- I - n_deathsI - n_Recover + n_Sout
  update(R) <- R + n_Recover
  update(new_cases) <- new_cases + n_Sout 
  update(all_deaths) <- all_deaths + n_deathsI
  update(all_recovery) <- all_recovery + n_Recover
  
  
  #random outs
  n_Sout <- Binomial(S, p_Sout)
  n_Iout <- Binomial(I, p_Ideath + p_Recovery)
  n_deathsI <- Binomial(n_Iout, p_Ideath/(p_Ideath + p_Recovery))
  n_Recover <- n_Iout - n_deathsI
  
  #random probs
  p_Sout <- 1 - exp(-(lam) * dt)
  p_Ideath <- 1 - exp(-(mu_d)*dt)
  p_Recovery <- 1- exp(-(gam)*dt)
  
  #process flows
  beta <- parameter()
  lam <- beta * I / N
  
  gam <- parameter() # recovery
  mu_d <- parameter() # disease death
  
  N0 <- parameter(230600)
  I0 <- parameter()
  R0 <- 0
  S0 <- N0 - I0 - R0

}, quiet = TRUE)

#We can initialise this system and simulate it out over this time series and plot the results against the data
span_sys <- dust2::dust_system_create(
  sir(),
  pars = list(
    beta = 1.5,
    gam = 1 / 10,
    mu_d = 1 / 3,
    N0 = 230600,
    I0 = 5,
    dt = 1
  ),
  n_particles = 20,
  n_groups = 1,
  seed = NULL,
  deterministic = TRUE,
  #	n_threads = 8
)
dust_system_set_state_initial(span_sys)

time <- 0:200

y <- dust_system_simulate(span_sys, time)

y_tidy <- purrr::map_dfr(1:dim(y)[2], function(p) {
  df <- as.data.frame(t(y[, p, ]))
  colnames(df) <- c("N0", "S", "I", "R", "New_cases", "All_deaths", "All_recovery")  # adjust as needed
  df$time <- 0:(nrow(df) - 1)
  df$particle <- p
  df
})

##############################################################################################################
#A data frame of all deaths at different time steps
death_dt <- y_tidy |>
  dplyr::filter(particle == 1) |>
  dplyr::select(time, deaths = All_deaths)


#plot of deaths against time
library(ggplot2)

ggplot(death_dt, aes(x = time, y = deaths)) +
  geom_line(color = "red", linewidth = 1.2) +

  labs(title = "All Deaths Over Time", y = "Deaths", x = "Time") +
  theme_minimal()


deaths <- dust_unpack_state(span_sys, y)$all_deaths
matplot(time, t(deaths), type = "l", lty = 1, col = "#00000055",
        xlab = "Time (days)", ylab = "All deaths", las = 1)

points(deaths ~ time, data = death_dt, pch = 19, col = "red")



points(death_dt$time[death_dt$All_deaths > 0],
       death_dt$All_deaths[death_dt$All_deaths > 0],
       col = "red", pch = 19)
##############################################################################################################
#function returns an n_state by n_particle by n_time matrix 
data <- data.frame(death_dt)

sir <- odin({
  
  #initial
  initial(N) <- N0
  initial(S) <- S0
  initial(I) <- I0
  initial(R) <- R0
  initial(new_cases, zero_every = 7) <- 0
  initial(all_deaths, zero_every = 1) <- 0
  initial(all_recovery, zero_every = 7) <- 0
  
  #updates
  update(N) <- N - n_deathsI
  update(S) <- S - n_Sout
  update(I) <- I - n_deathsI - n_Recover + n_Sout
  update(R) <- R + n_Recover
  update(new_cases) <- new_cases + n_Sout 
  update(all_deaths) <- all_deaths + n_deathsI
  update(all_recovery) <- all_recovery + n_Recover
  
  
  #random outs
  n_Sout <- Binomial(S, p_Sout)
  n_Iout <- Binomial(I, p_Ideath + p_Recovery)
  n_deathsI <- Binomial(n_Iout, p_Ideath/(p_Ideath + p_Recovery))
  n_Recover <- n_Iout - n_deathsI

  #random probs
  p_Sout <- 1 - exp(-(lam) * dt)
  p_Ideath <- 1 - exp(-(mu_d)*dt)
  p_Recovery <- 1- exp(-(gam)*dt)
  
  #process flows
  beta <- parameter()
  lam <- beta * I / N
  
  gam <- parameter() # recovery
  mu_d <- parameter() # disease death

  N0 <- parameter(230600)
  I0 <- parameter()
  R0 <- 0
  S0 <- N0 - I0 - R0
 
  # Comparison to data
  deaths <- data()

  deaths ~ Poisson(all_deaths)# use a Poisson to ask “what is the probability of 

  
}, quiet = TRUE)

pars <- list(
  beta = 0.5,
  gam = 0.1,
  mu_d = 0.01,
  I0 = 100
)

time_start <- -1
unfilter <- dust_unfilter_create(sir(), time_start, data)
dust_likelihood_run(unfilter, pars)

################################################################################
#Inference with particle MCMC (pMCMC)
prior <- monty_dsl({
  beta ~ Exponential(mean = 0.3)
  gam ~ Exponential(mean = 0.1)
  mu_d ~ Exponential(mean = 0.1)
})
#describe how a vector of statistical parameters (here beta and gamma) 
#will be converted into the inputs that the sir system needs to run
sir_packer <- monty_packer(c("beta", "gam","mu_d"), fixed = list(I0 = 5))

#convert from a list of name-value pairs suitable for initialising a dust2 
#system into a vector of parameters suitable for use with monty
sir_packer$pack(pars)

#monty model
likelihood <- dust_likelihood_monty(unfilter, sir_packer)
likelihood

#compute the likelihood
monty_model_density(likelihood, c(0.2, 0.1, 0.3))

# combining the prior and the likelihood to create a posterior
posterior <- prior + likelihood

#Proposes new parameter values at each step with variance 0.02
sampler <- monty_sampler_random_walk(diag(3) * 0.01)

#List to vector
sir_packer$pack(pars)

#vector to list
sir_packer$unpack(c(0.2, 0.1, 0.3))
#We can now run an MCMC for 100 samples,gives a set of acccepted parameter sets for exploring posterior dist
samples <- monty_sample(posterior, sampler, 5000,
                        initial = sir_packer$pack(pars))

plot(samples$density, type = "l")


plot(t(drop(samples$pars)), pch = 19, col = "#00000055")


######################################
sir_packer

library(mcstate)

sir_packer <- mcstate::dust_packet(
  model = sir,      # your odin model function
  pars = c("beta", "gam", "mu_d", "I0")  # the parameters you want to estimate
)


#reusing our packer, prior and sampler objects

likelihood_det <- dust_likelihood_monty(unfilter, sir_packer)
?sir_packer
posterior_det <- prior + likelihood_det
samples_det <- monty_sample(posterior_det, sampler, 1000,
                            initial = sir_packer$pack(pars))
time <- seq(1, length(data$deaths))

time_start <- -1

unfilter <- dust_unfilter_create(sir(), 0, data)

unfilter <- dust_unfilter_create(sir(), time_start , data)
dust_likelihood_run(unfilter, pars)

