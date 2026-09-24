#!/usr/bin/env Rscript
# Read-only review tests. Fixtures use tempdir; no compilation, fit or bulk stage.
args <- commandArgs(TRUE)
repo <- normalizePath(args[1L], mustWork = TRUE)
evidence_dir <- normalizePath(args[2L], mustWork = TRUE)
root <- file.path(repo, "v4")
source(file.path(root, "R", "load.R"))
loaded_analysis_id <- { load_v4(root); analysis_identity(root) }
loaded_support_id <- { source(file.path(root, "interactive_support.R"), encoding = "UTF-8"); sha256_file(file.path(root, "interactive_support.R")) }

results <- list()
record <- function(name, expression) {
  error <- tryCatch({ force(expression); NULL }, error = function(e) conditionMessage(e))
  results[[length(results) + 1L]] <<- data.frame(Check = name, Passed = is.null(error),
    Detail = if (is.null(error)) "PASS" else error)
  cat(if (is.null(error)) "PASS" else "FAIL", name,
      if (is.null(error)) "" else paste("|", error), "\n")
}
error_of <- function(expression) tryCatch({ force(expression); NA_character_ }, error = function(e) conditionMessage(e))
status_at <- function(out) jsonlite::read_json(file.path(out, "status.json"), simplifyVector = TRUE)
source_hashes <- vapply(file.path(root, c("interactive_analysis.R", "interactive_support.R")), sha256_file, character(1))
out <- tempfile("interactive_review_"); dir.create(out)
interactive_begin(root, out, loaded_analysis_id, loaded_support_id)
state <- interactive_step("prepare", root, out, prepare_stage(root, out))
sink_before <- sink.number(type = "output")
connections_before <- nrow(showConnections(all = TRUE))

record("caller_scope_and_running_before_evaluation", {
  returned <- interactive_step("scope", root, out, {
    stopifnot(status_at(out)$status == "RUNNING")
    caller_visible <- 41L
    cat("REVIEW_STDOUT\n")
    message("REVIEW_MESSAGE")
    warning("REVIEW_WARNING", immediate. = TRUE)
    caller_visible + 1L
  })
  stopifnot(identical(caller_visible, 41L), identical(returned, 42L),
            status_at(out)$status == "SCOPE_COMPLETE")
})
record("stdout_messages_warnings_logged", {
  lines <- readLines(file.path(out, "interactive_logs", "scope.log"), warn = FALSE)
  stopifnot(all(vapply(c("REVIEW_STDOUT", "MESSAGE: REVIEW_MESSAGE", "WARNING: REVIEW_WARNING"),
    function(text) any(grepl(text, lines, fixed = TRUE)), logical(1))))
})
record("repeated_step_appends_log", {
  interactive_step("scope", root, out, cat("REVIEW_SECOND_ATTEMPT\n"))
  lines <- readLines(file.path(out, "interactive_logs", "scope.log"), warn = FALSE)
  stopifnot(sum(grepl("START scope", lines, fixed = TRUE)) == 2L,
            any(grepl("REVIEW_STDOUT", lines, fixed = TRUE)))
})
record("error_status_and_short_circuit", {
  after_error <- FALSE
  error <- error_of(interactive_step("failure", root, out, {
    stop("REVIEW_EXPECTED_FAILURE")
    after_error <- TRUE
  }))
  stopifnot(grepl("REVIEW_EXPECTED_FAILURE", error, fixed = TRUE), !after_error,
    status_at(out)$status == "FAILED", status_at(out)$message == "REVIEW_EXPECTED_FAILURE")
})
record("interrupt_status_and_cleanup", {
  interruption <- structure(list(message = "review interrupt", call = NULL), class = c("interrupt", "condition"))
  error <- error_of(interactive_step("interrupt_test", root, out, signalCondition(interruption)))
  stopifnot(!is.na(error), status_at(out)$status == "INTERRUPTED",
            sink.number(type = "output") == sink_before)
})
record("existing_sink_preserved", {
  path <- tempfile(); connection <- file(path, "wt")
  sink(connection); depth <- sink.number(type = "output")
  returned <- interactive_step("nested_sink", root, out, { cat("REVIEW_NESTED_SINK\n"); 7L })
  same <- sink.number(type = "output") == depth
  sink(); close(connection)
  stopifnot(same, identical(returned, 7L), any(grepl("REVIEW_NESTED_SINK", readLines(path), fixed = TRUE)))
})
record("no_sink_or_connection_leak", {
  stopifnot(sink.number(type = "output") == sink_before,
            nrow(showConnections(all = TRUE)) == connections_before)
})
record("settings_restore_before_state_reuse", {
  SAMPLING$cores <- 1L; RARE_MIN <- 99L
  restored <- interactive_refresh_state(root, out)
  stopifnot(identical(restored, state), SAMPLING$cores == 4L, RARE_MIN == 4L)
})

plan <- task_plan(state)
task <- subset(plan, Route == "binary" & Model == "M1" & Design == "fivefold" & Fold == 1L)
fold <- state$fold_tables$fivefold$binary
train <- setdiff(state$binary_species, fold$Species[fold$Fold == 1L])
spec <- fit_spec(state, "binary", "M1", train, file.path(root, "stan", "joint_bb.stan"), seed = task$Seed)
record("valid_example_spec_accepted", check_interactive_example(root, out, task, spec))
changed <- spec
changed$formula <- brms::bf(stats::as.formula(paste("High | weights(TrainWeight * 2, scale = FALSE) ~",
  paste(c("1", spec$blueprint$columns), collapse = " + "))), center = FALSE)
record("weight_formula_has_same_code_but_different_target", {
  code <- as.character(brms::make_stancode(changed$formula, data = changed$data,
    family = brms::bernoulli(), prior = changed$prior, save_pars = brms::save_pars(all = TRUE)))
  original <- brms::make_standata(spec$formula, data = spec$data, family = brms::bernoulli(), prior = spec$prior)
  altered <- brms::make_standata(changed$formula, data = changed$data, family = brms::bernoulli(), prior = changed$prior)
  stopifnot(identical(code, spec$code), all(original$weights == 1), all(altered$weights == 2),
            !identical(original, altered))
})
record("changed_weight_formula_rejected_before_fit", {
  error <- error_of(check_interactive_example(root, out, task, changed))
  stopifnot(!is.na(error), grepl("公式", error, fixed = TRUE))
})
record("mismatched_example_fold_rejected", {
  bad_task <- task; bad_task$Fold <- 2L
  stopifnot(!is.na(error_of(check_interactive_example(root, out, bad_task, spec))))
})
record("finish_without_fit_inventory_rejected", {
  error <- error_of(interactive_finish(root, out))
  stopifnot(!is.na(error), status_at(out)$status == "FAILED", !dir.exists(file.path(out, "fits")))
})
record("all_nonblank_code_lines_have_chinese_comments", {
  for (file in c("interactive_analysis.R", "interactive_support.R")) {
    lines <- readLines(file.path(root, file), encoding = "UTF-8", warn = FALSE)
    code <- nzchar(trimws(lines)) & !grepl("^\\s*#", lines)
    stopifnot(all(grepl("#.*[\\x{4e00}-\\x{9fff}]", lines[code], perl = TRUE)))
  }
})
copy_session <- function() {
  copied <- tempfile("interactive_source_identity_"); dir.create(copied)
  files <- c("settings.R", "run_all.R", "01_prepare.R", "02_fit.R", "03_evaluate.R", "04_plot.R",
    "interactive_support.R", "interactive_analysis.R", paste0("R/", list.files(file.path(root, "R"), pattern = "[.]R$")),
    "stan/joint_bb.stan", paste0("data/", list.files(file.path(root, "data"), pattern = "[.]csv$")))
  for (file in files) {
    path <- file.path(copied, file); dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(root, file), path))
  }
  environment <- new.env(parent = .GlobalEnv)
  source(file.path(copied, "R", "load.R"), local = environment)
  core_id <- { environment$load_v4(copied, envir = environment); environment$analysis_identity(copied) }
  support_id <- {
    source(file.path(copied, "interactive_support.R"), local = environment, encoding = "UTF-8")
    environment$sha256_file(file.path(copied, "interactive_support.R"))
  }
  directory <- file.path(copied, "output"); dir.create(directory)
  environment$interactive_begin(copied, directory, core_id, support_id)
  list(root = copied, output = directory, environment = environment)
}
record("core_edit_before_prepare_rejected_before_execution", {
  session <- copy_session(); e <- session$environment
  cat('\nbuild_encoding_dictionary <- function(...) stop("EDITED_SOURCE_SENTINEL")\n',
      file = file.path(session$root, "R", "data_encoding.R"), append = TRUE)
  error <- error_of(e$interactive_step("prepare", session$root, session$output,
    e$prepare_stage(session$root, session$output)))
  stopifnot(!is.na(error), !file.exists(file.path(session$output, "prepared.rds")))
})
record("support_edit_after_begin_rejected_before_execution", {
  session <- copy_session(); e <- session$environment; executed <- FALSE
  cat("\n# Changed after loading for a read-only review fixture.\n",
      file = file.path(session$root, "interactive_support.R"), append = TRUE)
  error <- error_of(e$interactive_step("fixture", session$root, session$output, { executed <- TRUE }))
  stopifnot(!is.na(error), !executed)
})
record("main_file_edit_after_begin_rejected_before_execution", {
  session <- copy_session(); e <- session$environment; executed <- FALSE
  cat("\n# Changed after session initialization for a review fixture.\n",
      file = file.path(session$root, "interactive_analysis.R"), append = TRUE)
  error <- error_of(e$interactive_step("fixture", session$root, session$output, { executed <- TRUE }))
  stopifnot(!is.na(error), !executed)
})

table <- do.call(rbind, results)
write_csv_atomic(table, file.path(evidence_dir, "support_checks.csv"))
write_json_atomic(list(status = if (all(table$Passed)) "PASS" else "FAIL", checks = nrow(table),
  passed = sum(table$Passed), failed = sum(!table$Passed), interface_sha256 = as.list(source_hashes),
  analysis_id = state$analysis_id, no_mcmc = TRUE,
  scope = "caller scope, status and logging, failure/interrupt cleanup, reset, formula semantics, task pairing and final rejection"),
  file.path(evidence_dir, "support_status.json"))
if (!all(table$Passed)) stop("Interactive support review found ", sum(!table$Passed), " failed checks")
cat("INTERACTIVE_SUPPORT_REVIEW_PASS:", nrow(table), "checks; no MCMC\n")
