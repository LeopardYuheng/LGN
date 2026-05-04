import numpy as np
import pandas as pd 
from spikeinterface.postprocessing import (
    compute_spike_amplitudes, compute_unit_locations,
    compute_template_similarity, compute_correlograms,compute_noise_levels, compute_isi_histograms, 
    compute_template_metrics, 
)
from spikeinterface import full as si
from spikeinterface import qualitymetrics as qm


def auto_curate(we, sorting, job_kwargs):
    
    #compute everything you need first 
    
    #_ = qm.compute_amplitude_medians(we)
   # amplitude_cv_median, amplitude_cv_range= qm.compute_amplitude_cv_metrics(we)

    template_matrics= compute_template_metrics(we)
    
    _= compute_isi_histograms(we)
    _ = compute_spike_amplitudes(we, **job_kwargs)
    _ = compute_unit_locations(we)
    _ = compute_template_similarity(we)
    _ = compute_correlograms(we)
    _ = compute_noise_levels(we)
   
       
    isi_violations_ratio, isi_violations_count = qm.compute_isi_violations(we, isi_threshold_ms=1.0)
   
    #set threshold
    #amplitude_cutoff_thresh = 0.1
    firing_rate_thresh=0.1
    isi_violations_ratio_thresh = 1
    presence_ratio_thresh = 0.5
    snr_thresh = 3.5
    snr_thresh_high =30
    amplitude_medians_thresh = 35#40 Nov22
    peak_to_valley_thresh = 0.0011#0.0015 Nov22
    peak_to_valley_thresh_lower =0.0004
    half_width_thresh= 0.00037#0.00035 Nov22
    half_width_thresh_lower = 0.00018
    #amplitude_cv_median_thresh=1
    #amplitude_cv_range_thresh=5


    # keep units whose max absolute amplitude < 1000 uV and filter the shape 
    extrema = si.get_template_extremum_amplitude(we)
    peak_to_valley=template_matrics["peak_to_valley"]
    peak_to_valley=peak_to_valley.values
    peak_to_valley=peak_to_valley.astype(float)
    half_width=template_matrics["half_width"]
    half_width=half_width.values
    half_width=half_width.astype(float)
    unit_ids = we.unit_ids
    keep_unit_ids1 = []
    keep_unit_ids11 = []
    keep_unit_ids111 = []

    for i, extremum in enumerate(extrema):
        if extremum < 1000: 
            keep_unit_ids1.append(unit_ids[i])
            
    for i, peak2valley in enumerate(peak_to_valley):
        if peak_to_valley_thresh_lower < peak2valley < peak_to_valley_thresh:
            keep_unit_ids11.append(unit_ids[i])
            
    for i, hfwidth in enumerate(half_width):
        if  half_width_thresh_lower < hfwidth < half_width_thresh:
            keep_unit_ids111.append(unit_ids[i])
    
    keep_unit_ids_first = np.intersect1d(keep_unit_ids1, keep_unit_ids11)
    
    keep_unit_ids_final = np.intersect1d(keep_unit_ids_first, keep_unit_ids111)
    
    keep_unit_ids0 = np.array(keep_unit_ids_final)
    
    
    
    
    
            
    # other metrics
    

    #amplitude_cv_median, amplitude_cv_range= qm.compute_amplitude_cv_metrics(waveform_extractor=we)
    #sliding_rp_violations = qm.compute_sliding_rp_violations(waveform_extractor=we, bin_size_ms=0.25)
    
    
    
    
    our_query = f"(presence_ratio > {presence_ratio_thresh})&\
           ({snr_thresh_high}>snr> {snr_thresh})&\
                 (firing_rate> {firing_rate_thresh})&\
                     (amplitude_median> {amplitude_medians_thresh })&\
                         (isi_violations_ratio < {isi_violations_ratio_thresh})"
                
                #(presence_ratio > {presence_ratio_thresh})&\
                    #(isi_violations_ratio < {isi_violations_ratio_thresh}) & \
                        #(amplitude_cutoff < {amplitude_cutoff_thresh}) & \
                            
                           # (amplitude_median> {amplitude_medians_thresh })
                            
    """                        
    metrics = qm.compute_quality_metrics(we)       
    """                
    metrics = qm.compute_quality_metrics(we,
                                         metric_names=['firing_rate',
                                                       'presence_ratio',
                                                       'snr',
                                                       'amplitude_median',
                                                       'isi_violation'
                                                       ])
    
     #'amplitude_median',



   # metrics = qm.compute_quality_metrics(we,
    #                                     metric_names=['firing_rate',
     #                                                  'presence_ratio',
      #                                                 'snr', 'isi_violation',
       #                                                'amplitude_cutoff','firing_range','amplitude_median',])
    
    
   # assert 'amplitude_cv_median' in metrics.columns
   # assert 'amplitude_cv_range' in metrics.columns
   # assert 'sliding_rp_violations' in metrics.columns
    
    # Apply query
    keep_units2 = metrics.query(our_query)
    keep_unit_ids2 = keep_units2.index.values
    # Get intersection of both unit id arrays
    keep_unit_ids = np.intersect1d(keep_unit_ids0, keep_unit_ids2)
    remove_unit_ids = np.setdiff1d(unit_ids, keep_unit_ids)
    #we_curated=keep_unit_ids

    we_curated = we.select_units(
        keep_unit_ids, new_folder=None)
    sorting_curated = sorting.select_units(keep_unit_ids)
    return we_curated, sorting_curated, remove_unit_ids
