package istio.authz

import future.keywords

import input.attributes.request.http as http_request

default allow := false

allow if {
	some unprotected_operation in unprotected_operations
	unprotected_operation.host = http_destination[0]
	unprotected_operation.port = http_destination[1]
	unprotected_operation.method = http_request.method
	regex.match(unprotected_operation.path, http_request.path)
}

allow if {
	some r in roles_for_user
	required_roles[r]
}

roles_for_user contains r if {
	r := user_roles[user_name][_]
}

required_roles contains r if {
	perm := role_perms[r][_]
	perm.host = http_destination[0]
	perm.port = http_destination[1]
	perm.method = http_request.method
	perm.path = http_request.path
}

http_destination := split(http_request.host, ":")

user_name := parsed if {
	[_, encoded] := split(http_request.headers.authorization, " ")
	[parsed, _] := split(base64url.decode(encoded), ":")
}

user_roles := {
	"alice": ["guest"],
	"bob": ["admin"],
}

role_perms := {
	"guest": [{
		"host": "frontend.workshop.svc.cluster.local",
		"port": "9000",
		"method": "GET",
		"path": "/",
	}],
	"admin": [
		{
			"host": "frontend.workshop.svc.cluster.local",
			"port": "9000",
			"method": "GET",
			"path": "/",
		},
		{
			"host": "frontend.workshop.svc.cluster.local",
			"port": "9000",
			"method": "POST",
			"path": "/products",
		},
	],
}

unprotected_operations := [
	{
		"host": "productcatalog.workshop.svc.cluster.local",
		"port": "5000",
		"method": "GET",
		"path": "^/products/$",
	},
	{
		"host": "productcatalog.workshop.svc.cluster.local",
		"port": "5000",
		"method": "GET",
		"path": "^/products/\\d+$",
	},
	{
		"host": "productcatalog.workshop.svc.cluster.local",
		"port": "5000",
		"method": "POST",
		"path": "^/products/\\d+$",
	},
	{
		"host": "catalogdetail.workshop.svc.cluster.local",
		"port": "3000",
		"method": "GET",
		"path": "^/catalogDetail$",
	}
]
