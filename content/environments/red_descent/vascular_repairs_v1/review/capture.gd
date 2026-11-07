extends "res://content/environments/red_descent/stair_art_v1/review/capture.gd"

func review_views() -> Array[Array]:
	var views: Array[Array] = super.review_views()
	views.append(["first-root-grazing", Vector3(33.2,-3.6,-39.8), Vector3(36,-3.8,-41.4),70.0])
	views.append(["second-root-grazing", Vector3(-32.8,-17,36.5), Vector3(-29,-17.1,38.1),70.0])
	return views
