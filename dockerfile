# base image for miniconda3
# TODO: replace latest with a version?
FROM continuumio/miniconda3:latest

# install bash + required tools for GCloud SDK
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        gnupg \
        apt-transport-https \
    && rm -rf /var/lib/apt/lists/*
    
# install Earth Engine API
RUN pip install earthengine-api==1.6.0

# Install dependencies for Google Cloud SDK
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash curl python3 python3-distutils unzip && \
    rm -rf /var/lib/apt/lists/*
    
RUN apt-get update && \
    apt-get install -y curl gnupg apt-transport-https lsb-release && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && \
    apt-get install -y google-cloud-cli

# create python environment based on yml
WORKDIR /app

COPY anno_env.yml /app/anno_env.yml

RUN conda env create -f /app/anno_env.yml && conda clean -afy

# ceate dir structure for intermediate outputs
# TODO: consider if these should be mounted instead
RUN mkdir -p /app/gee_data/annotated /app/gee_data/csvs_gee_ingest /app/ctfs

# copy workflow scripts
COPY src/ /app/src/

# make bash script executable
RUN chmod +x /app/src/workflow.sh

# run bash workflow as the default execution
#ENTRYPOINT ["/bin/bash", "/app/src/workflow.sh"]
