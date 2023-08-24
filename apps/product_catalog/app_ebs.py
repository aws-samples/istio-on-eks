# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import werkzeug
werkzeug.cached_property = werkzeug.utils.cached_property
from flask import Flask, request, url_for
from flask_restplus import Api, Resource, fields
from flask_cors import CORS
import requests
import os
import logging
# from aws_xray_sdk.core import xray_recorder
# from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
# xray_recorder.configure(context_missing='LOG_ERROR')
# from aws_xray_sdk.core import patch_all
import pymysql
from pymysql.err import DatabaseError
import json

#patch_all()

flask_app = Flask(__name__)

log_level = logging.INFO
flask_app.logger.setLevel(log_level)
# enable CORS
CORS(flask_app, resources={r'/*': {'origins': '*'}})

#configure SDK code
# xray_recorder.configure(service='Product-Catalog')
# XRayMiddleware(flask_app, xray_recorder)

AGG_APP_URL = os.environ.get("AGG_APP_URL")
DB_APP_URL = os.environ.get("DATABASE_SERVICE_URL")

list_of_names = ""

if AGG_APP_URL is None:
    AGG_APP_URL="http://localhost:3000/catalogDetail"

flask_app.logger.info('AGG_APP_URL is ' + str(AGG_APP_URL))
flask_app.logger.info('DB_APP_URL is ' + str(DB_APP_URL))

# Connect to the database
def create_connection():
    return pymysql.connect(host=DB_APP_URL,
                             user='root',
                             password='',
                             db='dev',
                             charset='utf8mb4',
                             cursorclass=pymysql.cursors.DictCursor
    )

# Fix of returning swagger.json on HTTP
@property
def specs_url(self):
    """
    The Swagger specifications absolute url (ie. `swagger.json`)
    :rtype: str
    """
    return url_for(self.endpoint('specs'), _external=False)

Api.specs_url = specs_url
app = Api(app = flask_app,
          version = "1.0",
          title = "Product Catalog",
          description = "Complete dictionary of Products available in the Product Catalog")

name_space = app.namespace('products', description='Products from Product Catalog')

model = app.model('Name Model',
                  {'name': fields.String(required = True,
                                         description="Name of the Product",
                                         help="Product Name cannot be blank.")})

class create_dict(dict): 
  
    # __init__ function 
    def __init__(self): 
        self = dict() 
          
    # Function to add key:value 
    def add(self, key, value): 
        self[key] = value
        
@name_space.route('/')
class Products(Resource):
    """
    Manipulations with products.
    """
    def get(self):
        """
        List of products.
        Returns a list of products
        """
        try:
            flask_app.logger.info('Inside Get request')
            response = requests.get(str(AGG_APP_URL))
            detailsContent = response.json()
            connection = create_connection()
            cursor = connection.cursor()
            cursor.execute("SELECT `prodId`, `prodName` FROM `product`")

            payload = []
            content = {}
            #mydict = create_dict()
            list_of_names = {}
            for row in cursor.fetchall():
               prodId = str(row["prodId"])
               prodName = str(row["prodName"])
               list_of_names[prodId] = prodName
               #content = {row['prodId']:row['prodName']}
               #payload.append(content)
            flask_app.logger.info(list_of_names)
            #prod_json = json.dumps(mydict, indent=2, sort_keys=True)
            #flask_app.logger.info(mydict)
            return {
                "products": list_of_names,
                "details" : detailsContent
            }
            cursor.close()
            connection.close()  
        except KeyError as e:
            flask_app.logger.error('Error 500 Could not retrieve information ' + e.__doc__ )
            name_space.abort(500, e.__doc__, status = "Could not retrieve information", statusCode = "500")
        except Exception as e:
            flask_app.logger.error('Error 400 Could not retrieve information ' + e.__doc__ )
            name_space.abort(400, e.__doc__, status = "Could not retrieve information", statusCode = "400")

@name_space.route('/ping')
class Ping(Resource):
    def get(self):
        return "healthy"

@name_space.route("/<int:id>")
@name_space.param('id', 'Specify the ProductId')
class MainClass(Resource):

    @app.doc(responses={ 200: 'OK', 400: 'Invalid Argument', 500: 'Mapping Key Error' })
    def get(self, id=None):
        try:
            name = list_of_names[id]
            flask_app.logger.info('AGG_APP_URL is ' + str(AGG_APP_URL))
            response = requests.get(str(AGG_APP_URL))
            content = response.json()
            flask_app.logger.info('Get Request succeeded ' + list_of_names[id])
            return {
                "status": "Product Details retrieved",
                "name" : list_of_names[id],
                "details" : content['details']
            }
        except KeyError as e:
            flask_app.logger.error('Error 500 Could not retrieve information ' + e.__doc__ )
            name_space.abort(500, e.__doc__, status = "Could not retrieve information", statusCode = "500")
        except Exception as e:
            flask_app.logger.error('Error 400 Could not retrieve information ' + e.__doc__ )
            name_space.abort(400, e.__doc__, status = "Could not retrieve information", statusCode = "400")


    @app.doc(responses={ 200: 'OK', 400: 'Invalid Argument', 500: 'Mapping Key Error' })
    @app.expect(model)
    def post(self, id):
        try:
            connection = create_connection()

            cursor = connection.cursor()
            sql = ("INSERT INTO product (prodId, prodName) VALUES (%s, %s)")
            data = (id, request.json['name'])
            cursor.execute(sql, data)
            connection.commit()
            cursor.close()
            connection.close()  
            flask_app.logger.info('Post Request succeeded ' + request.json['name'])
            return {
                "status": "New Product added to Product Catalog",
                "name": request.json['name']
            }
        except DatabaseError as e:
            err_code = e.args[0]
            if err_code == 2003:
                print('bad connection string')
            else:
                raise
        except KeyError as e:
            flask_app.logger.error('Error 500 Could not retrieve information ' + e.__doc__ )
            name_space.abort(500, e.__doc__, status = "Could not save information", statusCode = "500")
        except Exception as e:
            flask_app.logger.error('Error 400 Could not retrieve information ' + e.__doc__ )
            name_space.abort(400, e.__doc__, status = "Could not save information", statusCode = "400")


if __name__ == '__main__':
    app.run(host="0.0.0.0", debug=True)