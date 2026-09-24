# v4 publication analysis: the single source of model and inference settings.
VERSION <- "ratio_analysis_v4_RS_20260924"
MODELS <- c("Null", "M1", "M2", "M3")
ROUTES <- c("binary", "joint_bb")
DESIGNS <- c(fivefold = 5L, tenfold = 10L)
TRAIN_WEIGHTING <- "record_equal"
EVAL_WEIGHTING <- "species_equal"
SITE_COLUMNS <- c("Site3", "Site20", "Site117", "Site151", "Site196", "Site315")
PREDICTOR_SITES <- setdiff(SITE_COLUMNS, "Site151")
RARE_MIN <- 4L
ALLOWED_RESIDUES <- c("A","C","D","E","F","G","H","I","K","L","M","N","P","Q","R","S","T","V","W","Y","MISSING")
SEED <- 20260920L
SEED_OTHER <- 20260923L
B_ELPD <- 2000L  # Actual v3.4 production value, formerly supplied by JSON.
B_OTHER_METRICS <- 50000L
PRIORS <- list(intercept=1.5, beta=0.5, rho_a=1, rho_b=1, log_phi_mean=log(10), log_phi_sd=1)
SAMPLING <- list(chains=4L, cores=4L, iter=4000L, warmup=2000L, adapt_delta=0.99, max_treedepth=12L)
EXPECTED_COUNTS <- c(panel_species=365L, records=153L, binary_records=152L, binary_species=50L, joint_species=51L, point_records=145L, point_species=48L)
INPUT_SHA256 <- c(
  "observations.csv" = "3c886f7f2c11012463296b350a931543542b4e1c0d128ad3c408fda9ae824d79",
  "sites.csv" = "0a99692b060f13d1faaa870d06ea7dca9a4f16bc289636bcc88f5d105ebdacb5",
  "folds_binary_species_5.csv" = "933f627f122e5efda378435a580b583491fad0a640814ff9e777bed7c45b8114",
  "folds_binary_species_10.csv" = "2de8e002f7b5fa6628a3269665cae29d0c6335dd2148e55e31fc3ed5cfb975aa",
  "folds_joint_bb_species_5.csv" = "7d63d8e34fd7a90174bafcfdec6a54ea1a5d6e50c486eb1102f272d1afc1ebc5",
  "folds_joint_bb_species_10.csv" = "6ab52895401b3e17adfac0753407e4140f968a00bd071d05b50abda645bb0ccf"
)
