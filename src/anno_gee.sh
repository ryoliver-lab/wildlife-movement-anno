# Runs annotation script for each study in study.csv and environmental variable 
# in envs array

#argv[0]  <geePtsP> Folder holding the gee point datasets
#argv[1]  <gcsOutP> Path to the output folder for annotated csvs (excluding bucket)
## TODO: make optional: argv[1]  <envs> Array of environmental variables. Need to pass in envs as expanded 
# list (e.g. "env1 env2 env3"). Pass like this: "${envs[*]}"

#eval "$(docopts -h - : "$@" <<EOF
#Usage: anno_gee.sh [options] <argv> ...
#Options:
#      --help     Show help options.
#      --version  Print program version.
#----
#anno_gee 0.1
#EOF
#)"

#How to pass array to bash script
#https://stackoverflow.com/questions/17232526/how-to-pass-an-array-argument-to-the-bash-script
# geePtsP=${argv[0]}
# gcsOutP=${argv[1]}
# change syntax for bash instead of zsh
geePtsP=$1
gcsOutP=$2
# geePtsp=$geePtsP
# gcsOutP=$gcsOutP
#TODO: make this an optional argument. If passed in, don't read envs.csv
#TODO: don't allow passing in multiple, to keep it simple. multiple, use envs.csv
#envs=(${argv[2]}) 

#----Load variables from control files as arrays (hence the outside parentheses)
export genus=($(python3 -c "
with open('$genera_path', 'r') as f:
    lines = [line.strip() for line in f.readlines()]
print(' '.join(lines))
"))

envs=($(python3 -c "
import json
with open('config.json') as f:
    collections = json.load(f)['gee']['collections']
names = [item['name'] for item in collections if item['run'] == 1]
print(' '.join(names))
"))

bands=($(python3 -c "
import json
with open('config.json') as f:
    collections = json.load(f)['gee']['collections']
bands = [item['band'] for item in collections if item['run'] == 1]
print(' '.join(bands))
"))

colnames=($(python3 -c "
import json
with open('config.json') as f:
    collections = json.load(f)['gee']['collections']
colnames = [item['colname'] for item in collections if item['run'] == 1]
print(' '.join(colnames))
"))

# dont think this is necessary anymore cause not parsing a CSV anymore
# Remove \r suffix
#genus=( ${genus[@]%$'\r'} )
#envs=( ${envs[@]%$'\r'} )
#bands=( ${bands[@]%$'\r'} )
#colnames=( ${colnames[@]%$'\r'} )

# echo Annotating ${#studyIds[@]} studies.
echo Annotating ${#genus[@]} groups.

for gen in "${genus[@]}"
# for indId in "${indIds[@]}"
do 
  echo "*******"
  echo "Start processing genus ${gen}"
  echo "*******"
  
  #studyId=10763606 #LifeTrack White Stork Poland (419 rows)
  #studyId=8863543 #HUJ MPIAB White Stork E-Obs (3 million rows)
  #studyId=${studyIds[0]}
  # points=$geePtsP/$indId
  points=$geePtsP/$gen
  
  # get length of an array
  n=${#envs[@]}

  # use for loop to read all values and indexes
  for (( i=0; i<${n}; i++ ));
  do
  
    #i=0
    
    #TODO: do this as default if user doesn't pass in col_name info
    #envN=${env##*/} #gets the name (w/o path) of the env variable
    
    #TODO: check to see if $points exists in gee before annotating
    # earthengine asset info $points
    # earthengine asset info x
    # return_value=$?
    
    #TODO: need to handle band, colname as optional parameters
    # if column is not present don't pass parameters

    #echo "index: $i, env: ${envs[$i]}, band: ${bands[$i]}, col name: ${colnames[$i]}"
    out=$gcsOutP/${gen}_${colnames[$i]} #do not include url, bucket, or file extension
    
    echo Annotating "env: ${envs[$i]}, band: ${bands[$i]}, col name: ${colnames[$i]}"
    # $MOSEYENV_SRC/gee_anno.r $points ${envs[$i]} $out -b ${bands[$i]} -c ${colnames[$i]}
    python3 gee_anno.py $points $out $gen ${envs[$i]} ${colnames[$i]} ${bands[$i]} #&> logs/GEE_anno.log
  done

done
