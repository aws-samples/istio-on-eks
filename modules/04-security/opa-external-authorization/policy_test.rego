package istio.authz

import future.keywords

get_bearer_token(user) := token if {
	token := {
		"alice": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MDcwNjc0OTQsImlhdCI6MTcwNzA2NzE5NCwiaXNzIjoiaHR0cDovL2tleWNsb2FrLmV4YW1wbGUuY29tL3JlYWxtcy9pc3RpbyIsImF1ZCI6InByb2R1Y3RhcHAiLCJzdWIiOiJhbGljZUBleGFtcGxlLmNvbSIsInR5cCI6IkJlYXJlciIsInJlYWxtX2FjY2VzcyI6eyJyb2xlcyI6WyJndWVzdCJdfSwic2NvcGUiOiJwcm9maWxlIGVtYWlsIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiJBbGljZSIsInByZWZlcnJlZF91c2VybmFtZSI6ImFsaWNlIiwiZ2l2ZW5fbmFtZSI6IkFsaWNlIiwiZW1haWwiOiJhbGljZUBleGFtcGxlLmNvbSJ9.4XV28MCT1-8i_FAx2of0f5oPFuU4i14lO9wlzGntuCc",
		"bob": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MDcwNjc0OTQsImlhdCI6MTcwNzA2NzE5NCwiaXNzIjoiaHR0cDovL2tleWNsb2FrLmV4YW1wbGUuY29tL3JlYWxtcy9pc3RpbyIsImF1ZCI6InByb2R1Y3RhcHAiLCJzdWIiOiJib2JAZXhhbXBsZS5jb20iLCJ0eXAiOiJCZWFyZXIiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiYWRtaW4iXX0sInNjb3BlIjoicHJvZmlsZSBlbWFpbCIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJuYW1lIjoiQm9iIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiYm9iIiwiZ2l2ZW5fbmFtZSI6IkJvYiIsImVtYWlsIjoiYm9iQGV4YW1wbGUuY29tIn0.6Bj2uZgMScCOq4h8XY1Klg0kk1vkZv9Fg_dnY6srjA4",
		"charlie": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MDcwNjc0OTQsImlhdCI6MTcwNzA2NzE5NCwiaXNzIjoiaHR0cDovL2tleWNsb2FrLmV4YW1wbGUuY29tL3JlYWxtcy9pc3RpbyIsImF1ZCI6InByb2R1Y3RhcHAiLCJzdWIiOiJjaGFybGllQGV4YW1wbGUuY29tIiwidHlwIjoiQmVhcmVyIiwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbIm90aGVyIl19LCJzY29wZSI6InByb2ZpbGUgZW1haWwiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkNoYXJsaWUiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJjaGFybGllIiwiZ2l2ZW5fbmFtZSI6IkNoYXJsaWUiLCJlbWFpbCI6ImNoYXJsaWVAZXhhbXBsZS5jb20ifQ.8QYfbWaPygOt8KXteauGSO-G_Q_27O17llsRPVfSg4k",
	}[user]
}

test_productcatalog_get_products_all_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/productcatalog-sa",
			},
			"request": {
				"http": {
					"host": "productcatalog.workshop.svc.cluster.local:5000",
					"method": "GET",
					"path": "/products/",
				}
			}
		},
		"parsed_path": ["products"],
	}

	allow with input as request
}

test_productcatalog_get_products_id_all_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/productcatalog-sa",
			},
			"request": {
				"http": {
					"host": "productcatalog.workshop.svc.cluster.local:5000",
					"method": "GET",
					"path": "/products/1",
				}
			}
		},
		"parsed_path": [
			"products",
			"1",
		],
	}

	allow with input as request
}

test_productcatalog_post_products_id_all_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/productcatalog-sa",
			},
			"request": {
				"http": {
					"host": "productcatalog.workshop.svc.cluster.local:5000",
					"method": "POST",
					"path": "/products/1",
				}
			}
		},
		"parsed_path": [
			"products",
			"1",
		],
	}

	allow with input as request
}

test_catalogdetail_get_catalogdetail_all_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/catalogdetail-sa",
			},
			"request": {
				"http": {
					"host": "catalogdetail.workshop.svc.cluster.local:3000",
					"method": "GET",
					"path": "/catalogDetail",
				}
			}
		},
		"parsed_path": ["catalogDetail"],
	}

	allow with input as request
}

test_frontend_get_root_missing_auth_denied if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "GET",
					"path": "/",
				}
			}
		},
		"parsed_path": [""],
	}

	not allow with input as request
}

test_frontend_get_root_no_role_denied if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "GET",
					"path": "/",
					"headers": {"authorization": concat(" ", ["Bearer", get_bearer_token("charlie")])},
				}
			}
		},
		"parsed_path": [""],
	}

	not allow with input as request
}

test_frontend_get_root_guest_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "GET",
					"path": "/",
					"headers": {"authorization": concat(" ", ["Bearer", get_bearer_token("alice")])},
				}
			}
		},
		"parsed_path": [""],
	}

	allow with input as request
}

test_frontend_get_root_admin_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "GET",
					"path": "/",
					"headers": {"authorization": concat(" ", ["Bearer", get_bearer_token("bob")])},
				}
			}
		},
		"parsed_path": [""],
	}

	allow with input as request
}

test_frontend_post_products_missing_auth_denied if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "POST",
					"path": "/products",
				}
			}
		},
		"parsed_path": ["products"],
	}

	not allow with input as request
}

test_frontend_post_products_no_role_denied if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "POST",
					"path": "/products",
					"headers": {"authorization": concat(" ", ["Bearer", get_bearer_token("charlie")])},
				}
			}
		},
		"parsed_path": ["products"],
	}

	not allow with input as request
}

test_frontend_post_products_guest_denied if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "POST",
					"path": "/products",
					"headers": {"authorization": concat(" ", ["Bearer", get_bearer_token("alice")])},
				}
			}
		},
		"parsed_path": ["products"],
	}

	not allow with input as request
}

test_frontend_post_products_admin_allowed if {
	request := {
		"attributes": {
			"destination": {
				"principal": "spiffe://cluster.local/ns/workshop/sa/frontend-sa",
			},
			"request": {
				"http": {
					"host": "frontend.workshop.svc.cluster.local:9000",
					"method": "POST",
					"path": "/products",
					"headers": {"authorization": concat(" ", ["Bearer", get_bearer_token("bob")])},
				}
			}
		},
		"parsed_path": ["products"],
	}

	allow with input as request
}
