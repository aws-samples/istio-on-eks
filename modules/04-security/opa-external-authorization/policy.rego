package istio.authz

import future.keywords

import input.attributes.destination.principal as principal
import input.attributes.request.http as http_request

default allow := false

allow if {
	some unprotected_operation in unprotected_operations
	unprotected_operation.method = http_request.method
	unprotected_operation.principal = principal
	regex.match(unprotected_operation.path, http_request.path)
}

allow if {
	some r in roles_for_user
	required_roles[r]
}

roles_for_user contains user_role

required_roles contains r if {
	perm := role_perms[r][_]
	perm.method = http_request.method
	perm.path = http_request.path
	perm.principal = principal
}

user_role := payload.realm_access.roles[0] if {
	[_, encoded] := split(http_request.headers.authorization, " ")
	[_, payload, _] := io.jwt.decode(encoded)
}

role_perms := {
	"guest": [{
		"method": "GET",
		"path": "/",
		"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
	}],
	"admin": [
		{
			"method": "GET",
			"path": "/",
			"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
		},
		{
			"method": "POST",
			"path": "/products",
			"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
		},
	],
}

unprotected_operations := [
	{
		"method": "GET",
		"path": "^/products/$",
		"principal": "spiffe://cluster.local/ns/workshop/sa/productcatalog-sa",
	},
	{
		"method": "GET",
		"path": "^/products/\\d+$",
		"principal": "spiffe://cluster.local/ns/workshop/sa/productcatalog-sa",
	},
	{
		"method": "POST",
		"path": "^/products/\\d+$",
		"principal": "spiffe://cluster.local/ns/workshop/sa/productcatalog-sa",
	},
	{
		"method": "GET",
		"path": "^/catalogDetail$",
		"principal": "spiffe://cluster.local/ns/workshop/sa/catalogdetail-sa",
	},
]
