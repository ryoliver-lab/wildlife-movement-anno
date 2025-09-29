#!/usr/bin/env python3

# Annotate movement data with environmental layers via GEE, 
# Initiate task to send annotations paired with event_id as CVS files to GCS

import ee
import os
import json
import sys
import glob
import time
import datetime

# for testing:
# os.chdir('src/anno')
#_datP = "projects/covid-mvmnt-2024-440720/assets/mortality/Lynx"
#_outP = "annotated_mortality_testing/Capreolus_hfp"
#_outP = "annotated_mortality_testing/Capreolus_elev"
#_outP = "annotated_mortality_testing/Lynx_tmax"
#_gen = "Lynx"
#_env_id = "projects/HII/v1/hii"
#_env_id = "COPERNICUS/DEM/GLO30"
#_env_id = "ECMWF/ERA5/DAILY"
#_col_name = "hfp"
#_col_name = "elev"
#_col_name = "tmax"
#_band = "hii"
#_band = "DEM"
#_band = "maximum_2m_air_temperature"

# store args as variables, starting at 1 index because 0 index is script name
_datP = sys.argv[1]
_outP = sys.argv[2]
_gen = sys.argv[3]
_env_id = sys.argv[4]
_col_name = sys.argv[5]
_band = sys.argv[6]

t0 = time.time()

# load config
config_path = '/app/src/config.json'
with open(config_path, 'r') as f:
    config = json.load(f)
    
# read text file for service account
with open(config['gcp']['service_account'], 'r') as f:
    sa_email = f.read().strip()

# extract variables from config
wd = config['paths']['wd']
input_dir = config['paths']['input_dir'] 
output_dir = config['paths']['output_dir']
_bucket = config['gcp']['bucket']
_colImageId = config['gee']['_colImageId']
_colMillis = config['gee']['_colMillis']
_colTimestamp = config['gee']['_colTimestamp'] 
_colTimestamp_hfp = config['gee']['_colTimestamp_hfp']

# function to extract pixel values from a specific band of a collection
def select_band(img):
  img = ee.Image(img).select([_band])
  
  if _col_name == "elev":
     fc = ptsGrp
  else:
    fc = ee.FeatureCollection(ee.List(img.get('features')))

  vals = img.reduceRegions(
        #reducer = ee.Reducer.first().setOutputs([_col_name]),
        reducer = ee.Reducer.median().setOutputs([_col_name]),
        scale = img.projection().nominalScale(),
        #tileScale = 16, # inc to split up tiles more finely, reduce oom errors
        collection = fc)
  # return collection without duplicate elements
  vals = vals.set(_colImageId, img.get('system:index'))
  return vals

# function to add a attribute for timestamp in milliseconds 
# to points data
def add_milli(f):
  mil = ee.Date(f.get(_timestamp)).millis()
  f = f.set(_colMillis, mil)
  return(f)

# function to add new property system:time_end to HFP images
# since each image represents 01/01-12-31 of each year,
# calcuate the milliseconds for 12/31 of the image's year
def add_end_prop(image):
    # retrieve indiviudal image start time (millisec)
    start_ms = ee.Number(image.get('system:time_start'))
    year = ee.Date(start_ms).get('year')
    # construct 12/31 of the same year in millisec
    end_date = ee.Date.fromYMD(year, 12, 31)
    end_date_ms = end_date.millis()
    return image.set('system:time_end', end_date_ms)

# set up service account credentials
credentials = ee.ServiceAccountCredentials(
    email = sa_email,
    key_file = config['paths']['key_file']
)
ee.Initialize(credentials)
time.sleep(10)

print(f"Processing {_datP}")

# convert point data to feature collection
pts = ee.FeatureCollection(_datP)

print(f"Setting up annotation tasks for {_col_name}")

# get GEE asset type
assetType = ee.data.getAsset(_env_id)['type']

# load GEE asset
if(assetType=='IMAGE'):
    layer = ee.Image(_env_id).select([_band])
elif (assetType=='IMAGE_COLLECTION'):
    if _col_name == "elev":
        # DEM is timeless for our purposes so combine into one layer 
        # to disregard timestamp metadata. If we treat as individual
        # images, the metadata inhibits spatial intersections under
        # the hood when point timestamps do not overlap
        layer = ee.ImageCollection(_env_id).mosaic()
    else:
        layer = ee.ImageCollection(_env_id)
else:
    sys.exit(f"Invalid asset type: {assetType}")

# define groups based on number of rows
# 'grp' is the column name assigned by the SQL command in gee_ingest.sh
maxgrp = pts.aggregate_max('grp').getInfo()
groups = range(maxgrp+1) # need +1 because indexing starts at 0
if(len(groups)>1):
  print(f'Splitting annotation into {len(groups)} tasks')

# iterate each subset of points over each GEE env layer set in config
# note: groups start at 0
for group in groups:

  # for testing:
  # group = 0

  ptsGrp = pts.filter(ee.Filter.eq('grp', group))
  # Make sure there are points in the group. Can result in 0 records if .group
  # does not exist in the dataset.
  assert ptsGrp.size().getInfo() > 0, "No points in group. Cannot execute annotation."

  if assetType == 'IMAGE':
    # Note that the band is selected above, when loading the layer
    anno = layer.reduceRegions(
      reducer = ee.Reducer.median().setOutputs([_col_name]),
      collection = ptsGrp,
      scale = layer.projection().nominalScale()
      #tileScale = 16 # inc to split up tiles more finely, reduce oom errors
    )
  elif assetType == 'IMAGE_COLLECTION':
    # define bounding box of points
    ptsGrpBounds = ptsGrp.geometry().bounds()
    
    # reduce bounds of layer in different ways depending on if
    # collection is a mosaic or a true imageCollection
    if _col_name == "elev":
      layerReducedToBounds = layer.clip(ptsGrpBounds)
      # if annotating with mosaic layer, execute similar reduceRegions operation
      # as done for single image, but adjusted for mosaic
      anno = select_band(layerReducedToBounds)

    else:
      layerReducedToBounds = layer.filterBounds(ptsGrpBounds)
       
      # if annotating layer HFP, use _colTimestamp_hfp, otherwise normal timestamp
      if _col_name == "hfp":
        _timestamp = _colTimestamp_hfp
      else:
        _timestamp = _colTimestamp
      
      ptsGrp = ptsGrp.map(add_milli)

      if _col_name == "hfp":
        # add property for time end
        layerReducedToBounds = layerReducedToBounds.map(add_end_prop)

      # Define a filter operation to keep only the ImageCollection images with 
      # temporal ranges that include the timestamp of the points.
      filter = ee.Filter.And(
                ee.Filter.lessThanOrEquals(leftField = 'system:time_start',
                                            rightField = _colMillis),
                ee.Filter.greaterThan(leftField = 'system:time_end',
                                      rightField = _colMillis))
      
      # apply the temporal filter to output a feature collection where each point
      # has a new property called "features" that contains a list of all images that
      # match temporally.
      joined = ee.Join.saveAll('features').apply(layerReducedToBounds, ptsGrp, filter)
      #print(joined.size().getInfo())

      # assert that the size of joined is > 0
      #assert joined.size().getInfo() > 0, "Data after filtering is of size 0"
      
      anno = joined.map(select_band).flatten()

  # if the asset type is neither IMAGE nor IMAGE_COLLECTION
  # Note: this catch is redundant, can remove
  else:
    sys.exit(f"Invalid asset type: {assetType}")
  
  # sort by event ID and remove rows with NA values
  anno = anno.sort('anno_id').filter(ee.Filter.notNull([_col_name]))
  
  # remove negative erroneous values
  if _col_name != "ndvi":
    anno = anno.filter(ee.Filter.gte(_col_name, 0))
  
  fileN = f'{_gen}_{_col_name}_{group}'

  task = ee.batch.Export.table.toCloudStorage(
          collection = anno,
          description = fileN,
          bucket = _bucket,
          fileNamePrefix = os.path.join(_outP, fileN),
          fileFormat = 'csv',
          selectors = ['anno_id', _col_name]
          )
  
  print("Starting task")
  task.start()
  
  print(f'Task for group {group} started')
  print(f'Results will be saved to gs://{_bucket}/{_outP}/{fileN}.csv')

print(f"Script completed in {time.time() - t0} seconds")
