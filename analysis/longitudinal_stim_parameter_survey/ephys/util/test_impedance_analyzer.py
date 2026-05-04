import unittest
import numpy as np
from numpy.testing import assert_array_equal
from util.impedance_analyzer import ImpedanceAnalyzer

class TestImpedanceAnalyzer(unittest.TestCase):
    
    def setUp(self):
        self.analyzer = ImpedanceAnalyzer()
        
    def test_intan_to_ripple_1(self):
        intan_ch = np.arange(32)
        result = ImpedanceAnalyzer.intan_to_ripple(intan_ch)
        ripple_ch = [31,29,27,25,23,21,19,17,15,13,11,9,7,5,3,1,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32]
        assert_array_equal(result, ripple_ch) 
        
    def test_intan_to_ripple_2(self):
        intan_ch = np.array([31,30,1,0])
        result = ImpedanceAnalyzer.intan_to_ripple(intan_ch)
        ripple_ch = [32,30,29,31]
        assert_array_equal(result, ripple_ch)  

    def test_ripple_to_depth1(self):
        ripple_ch = np.arange(1,33)
        result = ImpedanceAnalyzer.ripple_to_depth(ripple_ch)
        ripple_ch_depth_ordered = [32,15,28,11,24,7,18,3,29,16,25,10,21,6,17,2,30,13,26,9,22,5,20,1,31,14,27,12,23,8,19,4]
        assert_array_equal(ripple_ch[result], ripple_ch_depth_ordered)   
        
    def test_ripple_to_depth2(self):
        ripple_ch = np.array([4,19,15,32])
        result = ImpedanceAnalyzer.ripple_to_depth(ripple_ch)
        ripple_ch_depth_ordered = [32,15,19,4]
        assert_array_equal(ripple_ch[result], ripple_ch_depth_ordered)   

    def test_intan_to_depth1(self):
        intan_ch = np.arange(32)
        result = ImpedanceAnalyzer.intan_to_depth(intan_ch) 
        intan_ch_depth_ordered = [31,8,29,10,27,12,24,14,1,23,3,20,5,18,7,16,30,9,28,11,26,13,25,15,0,22,2,21,4,19,6,17]
        assert_array_equal(intan_ch[result], intan_ch_depth_ordered)
        
    def test_intan_to_depth2(self):
        intan_ch = np.array([17,6,8,31])
        result = ImpedanceAnalyzer.intan_to_depth(intan_ch) 
        intan_ch_depth_ordered = [31,8,6,17]
        assert_array_equal(intan_ch[result], intan_ch_depth_ordered)
        
    def test_get_intan_impedances(self):
        impedances = self.analyzer.get_intan_impedances('ICMS92')
        assert_array_equal(impedances.index.tolist(),np.arange(32))
        
        impedances = self.analyzer.get_intan_impedances('ICMS92', reorder=True)
        intan_ch_depth_ordered = [31,8,29,10,27,12,24,14,1,23,3,20,5,18,7,16,30,9,28,11,26,13,25,15,0,22,2,21,4,19,6,17]
        assert_array_equal(impedances.index.tolist(),intan_ch_depth_ordered)
        
        impedances = self.analyzer.get_intan_impedances('ICMS92', reorder=True, to_ripple=True)
        print(impedances)
        
    
if __name__ == '__main__':
    unittest.main()