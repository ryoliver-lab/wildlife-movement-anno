#!/bin/bash

# Annotate species point data with environmental data

# TODO: determine best way to set wd and if it should be repo head or src/anno or if should
# move anno config to repo head & combine with overall wf config
# TODO: consider adding chmod +x to shell scripts too?

cd /app/src
source /opt/conda/etc/profile.d/conda.sh
# activate conda env
export conda_env=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['conda_env'])")
conda activate $conda_env

# authenticate gcloud service account
export sak=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['key_file'])")
gcloud auth activate-service-account --key-file=$(echo $sak)
export project=$(python3 -c "import json; print(json.load(open('config.json'))['gcp']['project'])")
gcloud config set project $project

# authenticate ee (the name of this variable MUST be exactly this, ee checks for this variable)
export GOOGLE_APPLICATION_CREDENTIALS=$(echo $sak)

export wd=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['wd'])")
src=$wd/src # not sure I need this
export db=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['db'])")
#export MOSEYENV_SRC=$wd/src/anno

export genera_path=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['genera_path'])")

sql="SELECT DISTINCT genus
    FROM event"

sqlite3 $db "$sql;" > $genera_path

sleep 10

# read in the assets subfolder from txt file stored locally
export geePtsP=$(python3 -c "
import json
with open('config.json', 'r') as f:
    config = json.load(f)
with open(config['gee']['assets_folder'], 'r') as f:
    print(f.read().strip())
")

# local folder that holds the CSV files to be ingested into GEE
export csvP=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['csvP'])")
# communicates which environmental data to annotate with in GEE
#export envP=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['envP'])")
# local folder that holds the annotated CSV files after GEE step is complete
export annoP=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['annoP'])")

##= -- GCS & GEE DIRS --
# geePtsP=project/covid-mvmnt/assets/tracks #folder holding the gee point datasets
export gcsBucket=$(python3 -c "import json; print(json.load(open('config.json'))['gcp']['bucket'])")
# dir for CSVs in GCS that will be imported GEE
export gcsInP=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['input_dir'])")
# output folder for annotated CSVs (excluding bucket name) in GCS
export gcsOutP=$(python3 -c "import json; print(json.load(open('config.json'))['paths']['output_dir'])")

# -- GEE URLs --
export gcsInURL=gs://${gcsBucket}/${gcsInP} #This is the url to the gee ingest folder
export gcsOutURL=gs://${gcsBucket}/${gcsOutP} #This is the url to the output folder (includes bucket)

# number of points in each annotation task
export groupSize=$(python3 -c "import json; print(json.load(open('config.json'))['gee']['groupSize'])")

# send csv files to GCS & GEE ingest_GEE dir
bash ./gee_ingest.sh trial_1 $geePtsP $gcsInURL $csvP $groupSize

# check for running or queued ingest tasks at an interval, units = seconds
checkInterval=10

while [ $(earthengine --service_account_file="$sak" task list | grep -e "RUNNING" -e "READY" | wc -l) -gt 0 ]; do
    echo "Tasks still running or queued at $(date)"
    sleep $checkInterval
done

echo "All tasks complete for gee_ingest.sh. Executing annotation."

# generate annotations in GEE
chmod +x gee_anno.py
bash ./anno_gee.sh $geePtsP $gcsOutP 

# check for running or queued annotation tasks
checkInterval=300

while [ $(earthengine --service_account_file="$sak" task list | grep -e "RUNNING" -e "READY" | wc -l) -gt 0 ]; do
    echo "Tasks still running or queued at $(date)"
    sleep $checkInterval
done

echo "All tasks complete for annotation. Downloading annotations to database."

# import annotated data into database:
# use the config to define the env columns to create
col0=$(python3 -c "import json; collection=json.load(open('config.json'))['gee']['collections'][0]; print(collection['colname'] if collection.get('run') == 1 else '')")
[ -n "$col0" ] && sqlite3 $db "alter table event add column ${col0} REAL;"

col1=$(python3 -c "import json; collection=json.load(open('config.json'))['gee']['collections'][1]; print(collection['colname'] if collection.get('run') == 1 else '')")
[ -n "$col1" ] && sqlite3 $db "alter table event add column ${col1} REAL;"

col2=$(python3 -c "import json; collection=json.load(open('config.json'))['gee']['collections'][2]; print(collection['colname'] if collection.get('run') == 1 else '')")
[ -n "$col2" ] && sqlite3 $db "alter table event add column ${col2} REAL;"

col3=$(python3 -c "import json; collection=json.load(open('config.json'))['gee']['collections'][3]; print(collection['colname'] if collection.get('run') == 1 else '')")
[ -n "$col3" ] && sqlite3 $db "alter table event add column ${col3} REAL;"

col4=$(python3 -c "import json; collection=json.load(open('config.json'))['gee']['collections'][4]; print(collection['colname'] if collection.get('run') == 1 else '')")
[ -n "$col4" ] && sqlite3 $db "alter table event add column ${col4} REAL;"

# populate the database event table with the annotations
bash ./import_anno.sh $gcsOutURL $annoP $db --table event

# split the death centroids from the events and add as separate table
sqlite3 $db "CREATE TABLE death_centroids AS SELECT * FROM event WHERE is_death_centroid = 1;"
# drop death centroid points from event table
sqlite3 $db "DELETE FROM event WHERE is_death_centroid = 1;"
# drop columns that were appended when combined death centroid df & event table
# and are no longer needed. Note that final GPS date/times for events are 
# stored in the animal metadata table
sqlite3 $db "ALTER TABLE event DROP COLUMN is_death_centroid;"
sqlite3 $db "ALTER TABLE event DROP COLUMN final_gps_location_date;"
sqlite3 $db "ALTER TABLE event DROP COLUMN final_gps_location_datetime;"
sqlite3 $db "ALTER TABLE death_centroids DROP COLUMN time_to_death;"
sqlite3 $db "ALTER TABLE death_centroids RENAME COLUMN timestamp TO death_datetime;"
