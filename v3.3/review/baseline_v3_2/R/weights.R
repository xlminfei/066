validate_weighting <- function(weighting) {
  if (!weighting %in% c("record_equal", "species_equal")) stop("Unknown weighting: ", weighting)
  weighting
}

build_train_weights <- function(records, weighting = "record_equal", species_col = "Species") {
  validate_weighting(weighting)
  if (!nrow(records)) stop("Cannot build weights for zero records")
  species <- as.character(records[[species_col]])
  if (anyNA(species) || any(!nzchar(species))) stop("Training species cannot be missing")
  n <- nrow(records); counts <- table(species); s <- length(counts)
  weight <- if (weighting == "record_equal") rep(1, n) else n / (s * as.numeric(counts[species]))
  data.frame(row_id = seq_len(n), Species = species, weight = as.numeric(weight),
             Weighting = weighting, WeightAlgorithm = V3_WEIGHT_ALGORITHM,
              Normalization = "total_weight_equals_record_count",
             stringsAsFactors = FALSE)
}

build_eval_weights <- function(records, weighting = "record_equal", species_col = "Species") {
  out <- build_train_weights(records, weighting, species_col)
  out$Normalization <- "metric_valid_set_total_weight_equals_record_count"
  out$WeightAlgorithm <- V3_WEIGHT_ALGORITHM
  out
}

check_weight_contract <- function(weight_frame, tolerance = 1e-10) {
  if (!is.data.frame(weight_frame) || !nrow(weight_frame) ||
      !all(c("Species", "weight", "Weighting") %in% names(weight_frame))) return(FALSE)
  if (length(tolerance) != 1L || !is.numeric(tolerance) || !is.finite(tolerance) || tolerance < 0) return(FALSE)
  weight <- weight_frame$weight
  species <- as.character(weight_frame$Species)
  mode <- as.character(weight_frame$Weighting)
  if (!is.numeric(weight) || any(!is.finite(weight)) || any(weight <= 0) ||
      anyNA(species) || any(!nzchar(trimws(species))) ||
      anyNA(mode) || length(unique(mode)) != 1L ||
      !mode[1] %in% c("record_equal", "species_equal")) return(FALSE)
  n <- nrow(weight_frame)
  if (abs(sum(weight) - n) > tolerance * max(1,n)) return(FALSE)
  if (mode[1] == "record_equal") return(all(abs(weight - 1) <= tolerance))
  counts <- table(species)
  expected <- n / (length(counts) * as.numeric(counts[species]))
  all(abs(weight - expected) <= tolerance * pmax(1, expected))
}
