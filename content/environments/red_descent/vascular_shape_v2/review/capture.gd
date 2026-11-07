extends "res://content/environments/red_descent/vascular_repairs_v1/review/capture.gd"

func review_views() -> Array[Array]:
	var views: Array[Array] = super.review_views()
	views.append(["first-junction-close", Vector3(34.4,-3.1,-40.65), Vector3(34.4,-3.15,-41.5),55.0])
	views.append(["second-junction-close", Vector3(-29.6,-17.55,37.2), Vector3(-30.1,-17.6,38.05),55.0])
	return views
