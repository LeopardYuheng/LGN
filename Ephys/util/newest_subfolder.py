import os
import sys


def newest_subfolder(directory):
    try:
        subfolders = [f.path for f in os.scandir(directory) if f.is_dir()]
        newest_folder = max(subfolders, key=os.path.getmtime)
        return newest_folder
    except ValueError:
        print("Directory is empty or does not contain any subfolders")
        return None
