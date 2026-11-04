"""Hand-checked tests for skin_eval.py. Run: tools/.venv/bin/python -m unittest discover tools/eval/tests"""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import skin_eval as se


class BinaryTests(unittest.TestCase):
    def test_counts_and_rates(self):
        # truth/pred: 3 TP, 1 FN, 2 FP, 4 TN
        pairs = [(1, 1)] * 3 + [(1, 0)] + [(0, 1)] * 2 + [(0, 0)] * 4
        m = se.binary_metrics(pairs)
        self.assertEqual((m['tp'], m['fn'], m['fp'], m['tn']), (3, 1, 2, 4))
        self.assertAlmostEqual(m['precision'], 3 / 5)
        self.assertAlmostEqual(m['recall'], 3 / 4)
        self.assertAlmostEqual(m['specificity'], 4 / 6)
        self.assertAlmostEqual(m['f1'], 2 * 0.6 * 0.75 / (0.6 + 0.75))
        self.assertAlmostEqual(m['accuracy'], 7 / 10)
        self.assertTrue(m['unreliable'])   # only 4 positives

    def test_no_answer_is_reported_not_dropped(self):
        m = se.binary_metrics([(1, 1), (1, None), (0, 0), (0, None)])
        self.assertEqual(m['no_answer'], 2)
        self.assertAlmostEqual(m['coverage'], 0.5)
        self.assertEqual((m['tp'], m['fn'], m['fp'], m['tn']), (1, 0, 0, 1))

    def test_zero_division_is_nan_not_crash(self):
        m = se.binary_metrics([(0, 0), (0, 0)])
        self.assertTrue(math.isnan(m['recall']))
        self.assertTrue(math.isnan(m['precision']))

    def test_wilson_known_value(self):
        # 8/10 -> Wilson 95% interval is about [0.490, 0.943]
        lo, hi = se.wilson(8, 10)
        self.assertAlmostEqual(lo, 0.490, places=3)
        self.assertAlmostEqual(hi, 0.943, places=3)
        self.assertTrue(math.isnan(se.wilson(0, 0)[0]))


class MulticlassTests(unittest.TestCase):
    def test_perfect_and_kappa(self):
        pairs = [(0, 0), (1, 1), (2, 2), (3, 3)]
        m = se.multiclass_metrics(pairs, [0, 1, 2, 3])
        self.assertAlmostEqual(m['accuracy'], 1.0)
        self.assertAlmostEqual(m['macro_f1'], 1.0)
        self.assertAlmostEqual(m['kappa_qw'], 1.0)

    def test_kappa_worse_than_chance_is_negative(self):
        pairs = [(0, 3), (3, 0)] * 5
        m = se.multiclass_metrics(pairs, [0, 1, 2, 3])
        self.assertLess(m['kappa_qw'], 0)

    def test_matrix_rows_are_truth(self):
        cm = se.confusion_matrix([(1, 0), (1, 0), (1, 1), (0, None)], [0, 1])
        self.assertEqual(cm[1][0], 2)
        self.assertEqual(cm[1][1], 1)
        self.assertEqual(cm[0]['no answer'], 1)


class EvaluateTests(unittest.TestCase):
    def test_end_to_end_and_blank_labels(self):
        labels = {'a': {'acne': '1', 'scar': '', 'redness': '0'},
                  'b': {'acne': '0', 'scar': '', 'redness': '1'}}
        preds = {'a': {'acne': '1', 'redness': '0'}, 'b': {'acne': '1', 'redness': ''}}
        r = se.evaluate(labels, preds)
        self.assertNotIn('scar', r['classes'])          # no labels -> no metrics invented
        self.assertEqual(r['classes']['acne']['fp'], 1)
        self.assertEqual(r['classes']['redness']['no_answer'], 1)
        self.assertIn('UNRELIABLE', se.render_md(r))

    def test_bad_value_rejected(self):
        with self.assertRaises(ValueError):
            se.to_bin('maybe')


if __name__ == '__main__':
    unittest.main()
