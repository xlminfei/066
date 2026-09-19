"""Select only the two explicitly reviewed extension implementations."""
STABLE_PROTOCOL = "stable_beta_logtails_20260916_v1"
REPAIRED_MODELS = {"M1_P", "Site315_P", "M2_P", "M3_P", "Phylogeny_only_P"}


def exporter_name(receipt):
    protocol = receipt.get("score_protocol")
    if protocol is None:
        return "export_cv_extensions.R"
    if (protocol == STABLE_PROTOCOL and receipt.get("outcome") == "joint"
            and receipt.get("cv_type") == "phylo_distance" and receipt.get("model") in REPAIRED_MODELS):
        return "export_cv_extensions_stable.R"
    raise ValueError("Unreviewed numerical scoring protocol or CV scope")
