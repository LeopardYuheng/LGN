import os
import glob
import csv
import numpy as np
import pandas as pd
# from util.test_impedance_analyzer import TestImpedanceAnalyzer
import unittest

class ImpedanceAnalyzer:
    def __init__(self):
        pass

    @staticmethod
    def intan_to_ripple(intan_channels):
        intan_to_ripple_map = np.array([31,29,27,25,23,21,19,17,15,13,11,9,7,5,3,1,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32])
        ripple_channels = intan_to_ripple_map[intan_channels] 
        return ripple_channels

    @staticmethod
    def ripple_to_depth(unordered_indices):
        ordered_indices = np.array([32,15,28,11,24,7,18,3,29,16,25,10,21,6,17,2,30,13,26,9,22,5,20,1,31,14,27,12,23,8,19,4])
        unordered_to_ordered_indices = np.where(unordered_indices == ordered_indices[:, None])[1] 
        return unordered_to_ordered_indices # 0-index
    
    @staticmethod
    def ripple_to_depth2(unordered_indices):
        ordered_indices = np.array([32,15,28,11,24,7,18,3,29,16,25,10,21,6,17,2,30,13,26,9,22,5,20,1,31,14,27,12,23,8,19,4])
        unordered_indices = np.array(unordered_indices)
        unordered_indices = unordered_indices[unordered_indices != 0]
        index_mapping = {value: idx for idx, value in enumerate(ordered_indices)}
        ordered_positions = np.array([index_mapping[val] for val in unordered_indices])
        return ordered_positions + 1
    
    @staticmethod
    def intan_to_depth(unordered_indices):
        ordered_indices = np.array([31,8,29,10,27,12,24,14,1,23,3,20,5, 18, 7, 16, 30, 9, 28, 11, 26, 13, 25, 15, 0, 22, 2, 21, 4, 19, 6, 17])
        unordered_to_ordered_indices = np.where(unordered_indices == ordered_indices[:, None])[1] 
        return unordered_to_ordered_indices
    
    def get_intan_impedances(self, animal_id, server_drive, reorder=False, to_ripple=False):
        self.animal_id = animal_id
        self.server_drive = server_drive
        file_pattern = os.path.join(self.server_drive, self.animal_id, "Impedance", "*.csv")
        csv_files = glob.glob(file_pattern)
        
        if not csv_files:
            print(f"No CSV files found for animalID {self.animal_id}")
            return None
        
        csv_files.sort(key=os.path.getmtime, reverse=True)
        newest_csv_file = csv_files[0]
        print(f"Using latest impedance file: {newest_csv_file}")
        df = pd.read_csv(newest_csv_file)
        impedances = df['Impedance Magnitude at 1000 Hz (ohms)']
                  
        if reorder:
            if to_ripple:
                ripple_ch = self.intan_to_ripple(np.arange(32))
                indices = self.ripple_to_depth(ripple_ch)         
            else:
                indices = self.intan_to_depth(np.arange(32))
        elif to_ripple:
            indices = self.intan_to_ripple(np.arange(32))
        else:
            indices = np.arange(32)
        self.impedances = impedances[indices]
        return impedances[indices]
    
    def get_good_impedances(self, threshold):
        impedances = self.impedances
        impedances = impedances[impedances < threshold]
        return impedances, impedances.index.tolist()

   
if __name__ == "__main__":
    # suite = unittest.TestLoader().loadTestsFromTestCase(TestImpedanceAnalyzer)
    # unittest.TextTestRunner().run(suite)
    impedance_analyzer = ImpedanceAnalyzer()
    impedances = impedance_analyzer.get_intan_impedances('ICMS92')
    filtered_impedances, good_channels = impedance_analyzer.get_good_impedances(threshold=1e6)
    good_ripple_channels = impedance_analyzer.intan_to_ripple(good_channels)
    print(good_ripple_channels)
    
