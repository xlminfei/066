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
             Weighting = weighting, Normalization = "total_weight_equals_record_count",
             stringsAsFactors = FALSE)
}

build_eval_weights <- function(records, weighting = "record_equal", species_col = "Species") {
  out <- build_train_weights(records, weighting, species_col)
  out$Normalization <- "metric_valid_set_total_weight_equals_record_count"
  out
}

check_weight_contract <- function(weight_frame, tolerance = 1e-10) {
  if (!nrow(weight_frame) || any(!is.finite(weight_frame$weight)) || any(weight_frame$weight <= 0)) {
    return(FALSE)
  }
  if (abs(sum(weight_frame$weight) - nrow(weight_frame)) > tolerance) return(FALSE)
  sums <- tapply(weight_frame$weight, weight_frame$Species, sum)
  max(sums) - min(sums) <= tolerance
}
