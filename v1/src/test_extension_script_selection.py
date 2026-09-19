from pathlib import Path
import importlib.util
import unittest


class ProtocolSelection(unittest.TestCase):
    def selector(self):
        spec = importlib.util.find_spec("extension_script_selection")
        self.assertIsNotNone(spec, "Extension selection must distinguish the original and fixed-draw numerical protocols")
        import extension_script_selection
        return extension_script_selection.exporter_name

    def test_original_results_keep_original_exporter(self):
        self.assertEqual(self.selector()({"outcome": "binary", "model": "M1_P", "cv_type": "species"}), "export_cv_extensions.R")

    def test_exactly_the_reviewed_joint_phylo_repairs_use_stable_exporter(self):
        select = self.selector()
        for model in ["M1_P", "Site315_P", "M2_P", "M3_P", "Phylogeny_only_P"]:
            self.assertEqual(select({"outcome": "joint", "model": model, "cv_type": "phylo_distance", "score_protocol": "stable_beta_logtails_20260916_v1"}), "export_cv_extensions_stable.R")

    def test_unknown_protocol_is_rejected(self):
        with self.assertRaises(ValueError):
            self.selector()({"score_protocol": "unknown"})

    def test_same_version_on_an_unreviewed_scope_is_rejected(self):
        select = self.selector()
        with self.assertRaises(ValueError):
            select({"outcome": "joint", "model": "M1_P", "cv_type": "species", "score_protocol": "stable_beta_logtails_20260916_v1"})


if __name__ == "__main__":
    unittest.main()
