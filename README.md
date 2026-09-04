# Environmental Annotation for Movement Database via Google Earth Engine

Annotate wildlife movement tracks with environmental layers from Google Earth Engine using a built Docker image. 

# Steps

### GEE Project Setup

- Create GEE project.
  - Add a service account key: In the [Google Cloud Console](https://console.cloud.google.com), navigate to the Service Accounts tab in the left panel, then click the email for the service account. Select the Keys tab and select "Add key" and download the json file. See [Google's documentation](https://cloud.google.com/iam/docs/keys-create-delete#creating). This key allows for authentication within scripts without user input.
  - Add permission to access project's assets: In the console, navigate to the Service Account tab in the left panel and click the email for the service account. Select the Permissions tab, then select Manage Access. Add a role for `Earth Engine Resource Admin`
- Create a bucket in [Google Cloud Storage](https://console.cloud.google.com/storage)
  - Create two subdirectories, one for storing GPS data pre-annotation, and the other for storing the annotated GPS data
  - Add roles for your bucket: On the homepage for your bucket, navigate to the Permissions tab and select Grant Access. Enter your service account email in the box labeled "New principals" and assign the following four roles: `Storage Admin`, `Storage Object Admin`, `Storage Object Creator`, `Storage Object Viewer`

### Config

- modify the config as necessary, such as environmental layers and the names of the bucket subdirectories

### Database

Ensure input database meets the following requirements:

- GPS event table is called "event"
- latitude and longitude are in degrees and called `lat` and `lon`
- timestamps are all in consistent format "%Y-%m-%d %H:%M:%S" and attribute is called `timestamp`
  - HH:MM:SS is not necessary to include, but if timestamps lack the time component then they will be appended with 00:00:00
- boolean attribute `is_death_centroid` (all values to F if you did not specifically calcuate death centroids as we do in the `mortality-db` repo)
- datetime attribute `anno_hfp_datetime` used for HII layer (see table) in the same format as `timestamp` but with correct year of event and day and month being January 1, and time can be either the correct time of the event or just 00:00:00 since none of our layers depend on time of day
- attribute `event_id` which is flexible but by default is a random numeric ID composed of enough digits for each value to be unique
- character column `genus` (used for separating many points into chunks to submit to GEE)

### Build Docker image

It is necessary to rebuilt the image anytime you modify the config or other files, so essentially every time you execute a new annotation run.

```
docker build -t anno-wf:latest .

```

### Run container

- run the container with the following command, mounting the input data, modified config, key file, text file that includes the service account name, and assets filepath.
  - `--rm` = remove container afterwards
  - `:ro` = read only
  
```
docker run -it --rm \
    -v /path/wildlife-movement-anno/data:/app/data \
    -v /path/wildlife-movement-anno/src/config.json:/app/src/config.json:ro \
    -v /path/covid-mvmnt-2024-key-file.json:/app/key-file.json:ro \
    -v /path/gee_sa.txt:/app/gee_sa.txt:ro \
    -v /path/gee_af.txt:/app/gee_af.txt:ro \
    anno-wf:latest > ./anno_output.txt 2>&1
```

### System Requirements

These have already been installed in the built Docker image:

- `miniconda3`
- `earthengine-api`
  - `conda install -c conda-forge earthengine-api`
  - version 1.6.0
- `google-cloud-sdk`
  - version:
  ```bash
  Google Cloud SDK 532.0.0
  bq 2.1.21
  core 2025.07.25
  gcloud-crc32c 1.0.0
  gsutil 5.35
  ```

### Resources

- [Google Cloud Console](https://console.cloud.google.com)
- [Google Cloud Storage](https://console.cloud.google.com/storage)
- [Task manager](https://code.earthengine.google.com/tasks)

### Environmental Layers Metadata

env ID | band ID | band index | col_name | details
-- | -- | -- | -- | --
[ECMWF/ERA5/DAILY](https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_DAILY) | maximum_2m_air_temperature | 2 | tmax | units = Kelvin, pixel size = 27830 meters
[MODIS/MOD09GA_006_NDVI](https://developers.google.com/earth-engine/datasets/catalog/MODIS_MOD09GA_006_NDVI) | NDVI | 0 | ndvi | pixel size = 463.313 meters
[COPERNICUS/DEM/GLO30](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_DEM_GLO30) | DEM | 0 | elev | digital elevation model, units = meters above sea level, resolution = 30 meters, split up into tiles spatially. This dataset is timeless for our purposes, but has underlying timestamp metadata per individual image that is interpretable and filtered under the hood by default. Therefore this dataset must be mosaic'd for processing to ignore time. Filter out negative values after annotation.
[ECMWF/ERA5/DAILY](https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_DAILY) | total_precipitation | 4 | precip | units = meters, daily sums of total precipitation. Filter out negative values after annotation.
projects/HII/v1/hii | human_impact_index | 0 | hfp | Custom collection created by [Wildlife Convervation Society](https://www.wcs.org/), see GEE layers displayed [here](https://code.earthengine.google.com/f904097220e577cad2e0dc5379371c91) and data descriptions: [GEE data access](https://www.wcshumanfootprint.org/data-access); [description of mapping human impacts](https://wcshumanfootprint.org/). Resolution = 300m. One image per year 2001-2020 that encompasses January 1 - December 31. But because the timestamps are specifically for the single day 1/1/YYYY and have no inherent end date for 12/31, we must both create a specific timestamp attribute in the event data for this layer and add the property for time end to the image collection.


### Notes

1. In `workflow.sh` the following code should appear as many times as there are annotation layers in the config:

```
col0=$(python3 -c "import json; collection=json.load(open('config.json'))['gee']['collections'][0]; print(collection['colname'] if collection.get('run') == 1 else '')")
[ -n "$col0" ] && sqlite3 $db "alter table event add column ${col0} REAL;"

```

With the number representing the n layer (indexing starts at 0). If there are too many of these lines in the bash script compared to layers in the config, the bash output will throw an error, but it just means it could not find n layer to add, not that anything went wrong with the annotation layers that were present in the config. If there are too few lines in the bash script compared to layers in the config, the annotations won't be added to the event table.

2. At the end of `workflow.sh` after all the annotation has completed and been merged into the event table, there are a few SQLite commands that do some housekeeping for attributes that are specific to our mortality workflow. If the columns referenced are not relevant, such as `time_to_death`, just remove those lines. Similarly to the first note, these will throw errors if the columns do not exist but do not indicate anything went awry with the annotation.  

### Future development

If we expand this docker image to use R as well to include analysis scripts, the image becomes larger with a different base. We need to use R with tidyverse and then control R package versions afterwards with `install.packages`

Please open an issue if you have an idea for how this repository could be improved. 
