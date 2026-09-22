normalize_residue <- function(x) {
  z <- toupper(trimws(as.character(x)))
  z[is.na(x) | is.na(z) | z %in% c("", "NA", "X", "-", "MISSING", "INDEL")] <- "MISSING"
  z
}

validate_sites_panel <- function(sites, expected_species = NULL) {
  if (!all(c("Species", V3_SITE_COLUMNS) %in% names(sites))) {
    stop("sites.csv is missing one or more required columns")
  }
  if (!is.null(expected_species) && nrow(sites) != expected_species) {
    stop("sites.csv row count does not match expected species count")
  }
  species <- trimws(as.character(sites$Species))
  if (anyNA(species) || any(!nzchar(species)) || anyDuplicated(species)) {
    stop("Species in sites.csv must be unique and non-empty")
  }
  sites$Species <- species
  for (site in V3_SITE_COLUMNS) {
    raw <- normalize_residue(sites[[site]])
    bad <- !raw %in% V3_ALLOWED_RESIDUES
    if (any(bad)) {
      stop(site, " contains unsupported residue codes: ", paste(sort(unique(raw[bad])), collapse = ", "))
    }
    sites[[site]] <- raw
  }
  sites
}

classify_high_low <- function(obs) {
  required <- c("Type", "Events", "Total", "Exact", "Lower", "Upper")
  if (!all(required %in% names(obs))) stop("observations is missing required columns")
  type <- tolower(trimws(as.character(obs$Type)))
  if (anyNA(type) || any(!type %in% c("count", "exact", "interval"))) {
    stop("Type must be count, exact, or interval")
  }
  high <- rep(NA_integer_, nrow(obs))
  reason <- rep("interval_crosses_threshold", nrow(obs))
  is_count <- type == "count"; is_exact <- type == "exact"; is_interval <- type == "interval"
  high[is_count] <- as.integer(2 * obs$Events[is_count] >= obs$Total[is_count])
  high[is_exact] <- as.integer(obs$Exact[is_exact] >= 0.5)
  high[is_interval & obs$Upper <= 0.5] <- 0L
  high[is_interval & obs$Lower >= 0.5] <- 1L
  reason[!is.na(high)] <- "classified"
  reason[is_interval & obs$Upper == 0.5] <- "interval_upper_50_LOW_by_rule"
  informative <- is_count | is_exact | !(is_interval & obs$Lower == 0 & obs$Upper == 1)
  data.frame(High = high, BinaryReason = reason,
             Informative = informative, stringsAsFactors = FALSE)
}

validate_input_data <- function(obs, sites, expected_species = NULL,
                                expected_records = NULL) {
  sites <- validate_sites_panel(sites, expected_species)
  obs_cols <- c("RecordID", "ExperimentID", "Species", "Type", "Events", "Total",
                "Exact", "Lower", "Upper", "SourceID")
  if (!all(obs_cols %in% names(obs))) stop("observations.csv is missing required columns")
  if (!is.null(expected_records) && nrow(obs) != expected_records) {
    stop("observations.csv row count does not match expected record count")
  }
  for (col in c("RecordID", "ExperimentID", "Species", "SourceID")) {
    z <- trimws(as.character(obs[[col]]))
    if (anyNA(z) || any(!nzchar(z))) stop(col, " cannot be missing")
    obs[[col]] <- z
  }
  if (anyDuplicated(obs$RecordID)) stop("RecordID is duplicated")
  if (anyDuplicated(obs$ExperimentID)) stop("ExperimentID is duplicated")
  if (any(!obs$Species %in% sites$Species)) stop("An observation species is absent from sites.csv")
  obs$Type <- tolower(trimws(as.character(obs$Type)))
  if (anyNA(obs$Type) || any(!obs$Type %in% c("count", "exact", "interval"))) {
    stop("Type must be count, exact, or interval")
  }
  for (col in c("Events", "Total", "Exact", "Lower", "Upper")) {
    raw <- obs[[col]]
    if (!is.numeric(raw)) raw <- suppressWarnings(as.numeric(as.character(raw)))
    if (any(!is.na(obs[[col]]) & !is.finite(raw))) stop(col, " contains a non-numeric value")
    obs[[col]] <- raw
  }
  is_count <- obs$Type == "count"; is_exact <- obs$Type == "exact"; is_interval <- obs$Type == "interval"
  if (any(is_count & (is.na(obs$Events) | is.na(obs$Total) | obs$Total < 1 |
                    obs$Events < 0 | obs$Events > obs$Total |
                    obs$Events != floor(obs$Events) | obs$Total != floor(obs$Total)))) {
    stop("count rows require valid integer Events and Total")
  }
  if (any(is_count & (!is.na(obs$Exact) | !is.na(obs$Lower) | !is.na(obs$Upper)))) {
    stop("count rows must leave Exact/Lower/Upper empty")
  }
  if (any(!is_count & (!is.na(obs$Events) | !is.na(obs$Total)))) {
    stop("exact/interval rows must leave Events/Total empty")
  }
  if (any(is_exact & (is.na(obs$Exact) | obs$Exact <= 0 | obs$Exact > 1))) {
    stop("unknown-denominator exact values must be in (0, 1]")
  }
  if (any(is_exact & (!is.na(obs$Lower) | !is.na(obs$Upper)))) stop("exact rows cannot have bounds")
  if (any(is_interval & (is.na(obs$Lower) | is.na(obs$Upper) |
                        obs$Lower < 0 | obs$Upper > 1 | obs$Lower >= obs$Upper))) {
    stop("interval rows require 0 <= Lower < Upper <= 1")
  }
  if (any(is_interval & !is.na(obs$Exact))) stop("interval rows must leave Exact empty")
  list(observations = obs, sites = sites)
}

build_binary_counts <- function(obs, panel_species) {
  cl <- classify_high_low(obs)
  obs$High <- cl$High
  one <- data.frame(Species = obs$Species,
                    HighCount = as.integer(!is.na(obs$High) & obs$High == 1L),
                    LowCount = as.integer(!is.na(obs$High) & obs$High == 0L),
                    UnclassifiedCount = as.integer(is.na(obs$High)),
                    RecordCount = 1L, stringsAsFactors = FALSE)
  agg <- stats::aggregate(. ~ Species, one, sum)
  out <- data.frame(Species = panel_species, stringsAsFactors = FALSE)
  for (nm in setdiff(names(agg), "Species")) {
    v <- agg[[nm]][match(out$Species, agg$Species)]; v[is.na(v)] <- 0L
    out[[nm]] <- as.integer(v)
  }
  out$Trials <- out$HighCount + out$LowCount
  out
}

build_encoding_dictionary <- function(panel, rare_min = V3_RARE_MIN) {
  panel <- validate_sites_panel(panel)
  out <- list()
  for (site in V3_SITE_COLUMNS) {
    raw <- normalize_residue(panel[[site]])
    freq <- table(raw[raw != "MISSING"])
    out[[site]] <- list(frequencies = freq,
                        frequent = names(freq)[freq >= rare_min],
                        rare_min = as.integer(rare_min))
  }
  out
}

encode_panel <- function(panel, dictionary, predictor_sites = V3_PREDICTOR_SITES) {
  panel <- validate_sites_panel(panel)
  if (!all(V3_SITE_COLUMNS %in% names(panel))) stop("panel is missing required site columns")
  out <- panel
  reference <- c(Site3 = "C", Site20 = "K", Site117 = "K", Site151 = "C", Site196 = "C")
  for (site in V3_SITE_COLUMNS) {
    raw <- normalize_residue(panel[[site]])
    if (site == "Site315") {
      m1 <- ifelse(raw == "MISSING", "MISSING", ifelse(raw %in% c("K", "T"), "K_or_T", "other"))
    } else {
      ref <- reference[[site]]
      m1 <- ifelse(raw == "MISSING", "MISSING", ifelse(raw == ref, paste0(ref, "_validated"), "other"))
    }
    m2 <- ifelse(raw == "MISSING", "MISSING", ifelse(raw %in% c("C", "K", "S", "T"), "CKST", "non_CKST"))
    keep <- dictionary[[site]]$frequent
    m3 <- ifelse(raw == "MISSING", "MISSING", ifelse(raw %in% keep, raw, "OTHER"))
    out[[paste0("M1_", site)]] <- m1
    out[[paste0("M2_", site)]] <- m2
    out[[paste0("M3_", site)]] <- m3
  }
  list(data = out, predictor_sites = predictor_sites,
       dictionary = dictionary, raw_sites = V3_SITE_COLUMNS)
}

model_reference_level <- function(model, variable, values) {
  if (model == "M1") {
    if (variable == "Site315") return("K_or_T")
    return(c(Site3 = "C_validated", Site20 = "K_validated", Site117 = "K_validated",
             Site196 = "C_validated")[[variable]])
  }
  if (model == "M2") return("CKST")
  if (model == "M3") {
    tab <- sort(table(values[values != "MISSING"]), decreasing = TRUE)
    if (length(tab)) return(names(tab)[[1L]])
  }
  NULL
}

row_in_span <- function(train_x, row_x, tolerance = 1e-8) {
  a <- qr(t(train_x), tol = tolerance)$rank
  b <- qr(t(rbind(train_x, row_x)), tol = tolerance)$rank
  a == b
}

make_design_blueprint <- function(encoded_data, response_species, model,
                                   predictor_sites = V3_PREDICTOR_SITES) {
  vars <- if (model == "Null") character() else paste0(model, "_", predictor_sites)
  if (!length(vars)) {
    x <- matrix(0, nrow(encoded_data), 0L)
    colnames(x) <- character()
    train_idx <- match(response_species, encoded_data$Species)
    train_matrix <- matrix(1, length(train_idx), 1L)
    return(list(X = x, columns = character(), variables = vars, references = list(),
                levels = list(), seen = list(), combination_seen = rep(TRUE, nrow(encoded_data)),
                training_combinations = "(intercept-only)", raw_seen = list(),
                fixed_effect_estimable = rep(TRUE, nrow(encoded_data)),
                training_species = response_species, train_matrix = train_matrix,
                rank = 1L, model = model))
  }
  matrix_parts <- list(); levels <- list(); references <- list(); seen <- list(); raw_seen <- list()
  for (var in vars) {
    site <- sub(paste0("^", model, "_"), "", var)
    vals <- as.character(encoded_data[[var]])
    observed <- sort(unique(vals))
    ref <- model_reference_level(model, site, vals)
    if (model == "M1") {
      required <- c(ref, "other", "MISSING")
    } else if (model == "M2") {
      required <- c("CKST", "non_CKST", "MISSING")
      ref <- "CKST"
    } else {
      if (is.null(ref) || !nzchar(ref)) ref <- "OTHER"
      required <- c(ref, setdiff(observed[observed != "MISSING"], ref), "OTHER", "MISSING")
    }
    if (is.null(ref) || !nzchar(ref)) ref <- required[[1L]]
    lev <- unique(c(ref, required, observed))
    if (any(!observed %in% lev)) stop("Blueprint level construction failed for ", var)
    idx <- match(response_species, encoded_data$Species)
    seen[[site]] <- sort(unique(vals[idx]))
    raw_seen[[site]] <- sort(unique(normalize_residue(encoded_data[[site]][idx])))
    levels[[site]] <- lev; references[[site]] <- ref
    part <- sapply(lev[-1L], function(z) as.integer(vals == z))
    if (is.null(dim(part))) part <- matrix(part, ncol = 1L)
    colnames(part) <- paste(model, site, lev[-1L], sep = "_")
    matrix_parts[[site]] <- part
  }
  x <- do.call(cbind, matrix_parts)
  if (is.null(dim(x))) x <- matrix(x, ncol = 1L)
  train_idx <- match(response_species, encoded_data$Species)
  train_x <- cbind(Intercept = 1, x[train_idx, , drop = FALSE])
  estimable <- vapply(seq_len(nrow(x)), function(i) row_in_span(train_x, c(1, x[i, ])), logical(1))
  combinations <- do.call(paste, c(encoded_data[, vars, drop = FALSE], sep = "|"))
  train_combinations <- combinations[train_idx]
  list(X = x, columns = colnames(x), variables = vars, references = references,
       levels = levels, seen = seen, combination_seen = combinations %in% train_combinations,
       training_combinations = unique(train_combinations), raw_seen = raw_seen,
       fixed_effect_estimable = estimable, training_species = response_species,
       train_matrix = train_x, rank = qr(train_x)$rank, model = model)
}

design_from_blueprint <- function(encoded_data, blueprint) {
  if (!length(blueprint$variables)) return(matrix(0, nrow(encoded_data), 0L))
  parts <- list()
  for (site in names(blueprint$levels)) {
    var <- paste0(blueprint$model, "_", site)
    vals <- as.character(encoded_data[[var]])
    lev <- blueprint$levels[[site]]
    bad <- !vals %in% lev
    if (any(bad)) stop("Encoded category cannot be represented by blueprint for ", var, ": ", paste(sort(unique(vals[bad])), collapse = ", "))
    other_levels <- lev[-1L]
    part <- matrix(0L, nrow = nrow(encoded_data), ncol = length(other_levels))
    if (length(other_levels)) for (j in seq_along(other_levels)) part[, j] <- as.integer(vals == other_levels[[j]])
    colnames(part) <- paste(blueprint$model, site, other_levels, sep = "_")
    parts[[site]] <- part
  }
  x <- do.call(cbind, parts)
  if (is.null(dim(x))) x <- matrix(x, ncol = length(blueprint$columns))
  x[, blueprint$columns, drop = FALSE]
}

prepare_state <- function(input_dir, expected_species = NULL, expected_records = NULL,
                          output_dir = NULL) {
  obs_path <- file.path(input_dir, "observations.csv")
  sites_path <- file.path(input_dir, "sites.csv")
  if (!file.exists(obs_path) || !file.exists(sites_path)) stop("v3 input CSV files are missing")
  obs_raw <- utils::read.csv(obs_path, check.names = FALSE, stringsAsFactors = FALSE,
                             na.strings = c("", "NA"))
  sites_raw <- utils::read.csv(sites_path, check.names = FALSE, stringsAsFactors = FALSE,
                              na.strings = c("", "NA"))
  validated <- validate_input_data(obs_raw, sites_raw, expected_species, expected_records)
  obs <- validated$observations; sites <- validated$sites
  cl <- classify_high_low(obs); obs <- cbind(obs, cl)
  binary_counts <- build_binary_counts(obs, sites$Species)
  dictionary <- build_encoding_dictionary(sites)
  encoded <- encode_panel(sites, dictionary)
  binary_species <- binary_counts$Species[binary_counts$Trials > 0]
  joint_species <- unique(obs$Species[obs$Informative])
  blueprints <- list()
  for (model in V3_MODELS) {
    blueprints[[paste0("binary_", model)]] <- make_design_blueprint(encoded$data, binary_species, model)
    blueprints[[blueprint_key("joint_bb", model)]] <- make_design_blueprint(encoded$data, joint_species, model)
  }
  state <- list(version = V3_VERSION, observations = obs, sites = sites,
                encoded = encoded$data, dictionary = dictionary,
                binary_counts = binary_counts, binary_species = binary_species,
                joint_species = joint_species, blueprints = blueprints,
                predictor_sites = V3_PREDICTOR_SITES,
                input_hashes = c(observations = sha256_file(obs_path), sites = sha256_file(sites_path)),
                classification_rule = "point_ge_0.5_high; interval_upper_le_0.5_low; interval_lower_ge_0.5_high",
                rare_min = V3_RARE_MIN, preparation_identity = preparation_identity_v3())
  if (!is.null(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    save_rds_atomic(state, file.path(output_dir, "prepared_v3.rds"))
    write_csv_atomic(binary_counts, file.path(output_dir, "binary_counts.csv"))
    write_csv_atomic(encoded$data, file.path(output_dir, "panel_encoded.csv"))
  }
  state
}
