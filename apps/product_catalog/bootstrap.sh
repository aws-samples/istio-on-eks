#!/bin/sh
export FLASK_APP=./app_aurora.py
export FLASK_DEBUG=1
flask run -h 0.0.0.0