# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Use an official Python runtime as an image
#FROM python:3.9-slim
FROM public.ecr.aws/amazonlinux/amazonlinux:latest

#RUN apt-get update \
#    && apt-get install curl -y \
#    && rm -rf /var/lib/apt/lists/*

RUN dnf -y localinstall https://dev.mysql.com/get/mysql80-community-release-el9-4.noarch.rpm && \
    dnf -y install mysql mysql-community-client && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    yum install -y unzip && \
    unzip awscliv2.zip && \
    ./aws/install && \
    yum install -y pip

RUN mkdir /app
WORKDIR /app

# We copy just the requirements.txt first to leverage Docker cache
COPY requirements.txt /app
RUN pip install -r requirements.txt

COPY . /app

# ENV AGG_APP_URL='http://prodinfo.octank-mesh-ns.svc.cluster.local:3000/productAgreement'

#WORKDIR /docker_app
EXPOSE 8080
ENTRYPOINT ["/app/bootstrap.sh"]