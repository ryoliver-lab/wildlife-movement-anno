# Environmental Annotation for Movement Database via Google Earth Engine

Annotate wildlife movement tracks with environmental layers from Google Earth Engine using a built Docker image. 

# Steps

### GEE Project Setup

- Create GEE project.
  - Add a service account key: In the [Google Cloud Console](https://console.cloud.google.com), navigate to the Service Accounts tab in the left panel, then click the email for the service account. Select the Keys tab and select "Add key" and download the json file. See [Google's documentation](https://cloud.google.com/iam/docs/keys-create-delete#creating). This key allows for authentication within scripts without user input.
  - Add permission to access project's assets: In the console, navigate to the Service Account tab in the left panel and click the email for the service account. Select the Permissions tab, then select Manage Access. Add a role for "Earth Engine Resource Admin".
- Create a bucket in [Google Cloud Storage](https://console.cloud.google.com/storage).

### Config

- modify the config as necessary, such as env layers

### Database

- ensure input database meets the requirements such as table and attribute names

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
    anno-wf:latest
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
ECMWF/ERA5/DAILY | maximum_2m_air_temperature | 2 | tmax | units = Kelvin, pixel size = 27830 meters
MODIS/MOD09GA_006_NDVI | NDVI | 0 | ndvi | pixel size = 463.313 meters
[COPERNICUS/DEM/GLO30](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_DEM_GLO30) | DEM | 0 | elev | digital elevation model, units = meters above sea level, resolution = 30 meters, split up into tiles spatially. This dataset is timeless for our purposes, but has underlying timestamp metadata per individual image that is interpretable and filtered under the hood by default. Therefore this dataset must be mosaic'd for processing to ignore time.
[ECMWF/ERA5/DAILY](https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_DAILY) | total_precipitation | 4 | precip | units = meters, daily sums of total precipitation
projects/HII/v1/hii | human_impact_index | 0 | hfp | Custom collection created by [Wildlife Convervation Society](https://www.wcs.org/), see GEE layers displayed [here](https://code.earthengine.google.com/f904097220e577cad2e0dc5379371c91) and [data description](https://www.wcshumanfootprint.org/data-access). One image per year 2021-2020 that encompasses January 1 - December 31. But because the timestamps are specifically for the single day 1/1/YYYY and have no inherent end date for 12/31, we must both create a specific timestamp attribute in the event data for this layer and add the property for time end to the image collection.


### Notes:

- If we expand this docker image to use R as well to include analysis scripts, the image becomes larger with a differnt base. We need to use R with tidyverse and then control R package versions afterwards with `install.packages`

