package istio.authz

import future.keywords

test_productcatalog_get_products_all_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "productcatalog.workshop.svc.cluster.local:5000",
			"method": "GET",
			"path": "/products/",
		}}},
		"parsed_path": ["products"],
	}

	allow with input as request
}

test_productcatalog_get_products_id_all_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "productcatalog.workshop.svc.cluster.local:5000",
			"method": "GET",
			"path": "/products/1",
		}}},
		"parsed_path": [
			"products",
			"1",
		],
	}

	allow with input as request
}

test_productcatalog_post_products_id_all_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "productcatalog.workshop.svc.cluster.local:5000",
			"method": "POST",
			"path": "/products/1",
		}}},
		"parsed_path": [
			"products",
			"1",
		],
	}

	allow with input as request
}

test_catalogdetail_get_catalogdetail_all_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "catalogdetail.workshop.svc.cluster.local:3000",
			"method": "GET",
			"path": "/catalogDetail",
		}}},
		"parsed_path": ["catalogDetail"],
	}

	allow with input as request
}

test_frontend_get_root_missing_auth_denied if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "GET",
			"path": "/",
		}}},
		"parsed_path": [""],
	}

	not allow with input as request
}

test_frontend_get_root_no_role_denied if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "GET",
			"path": "/",
			"headers": {"authorization": "Basic Y2hhcmxpZTpwYXNzd29yZAo="},
		}}},
		"parsed_path": [""],
	}

	not allow with input as request
}

test_frontend_get_root_guest_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "GET",
			"path": "/",
			"headers": {"authorization": "Basic YWxpY2U6cGFzc3dvcmQK"},
		}}},
		"parsed_path": [""],
	}

	allow with input as request
}

test_frontend_get_root_admin_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "GET",
			"path": "/",
			"headers": {"authorization": "Basic Ym9iOnBhc3N3b3JkCg=="},
		}}},
		"parsed_path": [""],
	}

	allow with input as request
}

test_frontend_post_products_missing_auth_denied if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "POST",
			"path": "/products",
		}}},
		"parsed_path": ["products"],
	}

	not allow with input as request
}

test_frontend_post_products_no_role_denied if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "POST",
			"path": "/products",
			"headers": {"authorization": "Basic Y2hhcmxpZTpwYXNzd29yZAo="},
		}}},
		"parsed_path": ["products"],
	}

	not allow with input as request
}

test_frontend_post_products_guest_denied if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "POST",
			"path": "/products",
			"headers": {"authorization": "Basic YWxpY2U6cGFzc3dvcmQK"},
		}}},
		"parsed_path": ["products"],
	}

	not allow with input as request
}

test_frontend_post_products_admin_allowed if {
	request := {
		"attributes": {"request": {"http": {
			"host": "frontend.workshop.svc.cluster.local:9000",
			"method": "POST",
			"path": "/products",
			"headers": {"authorization": "Basic Ym9iOnBhc3N3b3JkCg=="},
		}}},
		"parsed_path": ["products"],
	}

	allow with input as request
}
