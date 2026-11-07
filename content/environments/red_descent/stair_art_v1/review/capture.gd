extends "res://content/environments/red_descent/masonry_repairs_v1/review/capture.gd"

func review_views() -> Array[Array]:
	var views: Array[Array] = super.review_views().filter(func(view: Array) -> bool: return view[0] in ["first-stair-lower", "first-stair-coping", "second-stair-lower", "second-stair-side"])
	views.append(["first-bell-close", Vector3(36.4,-3.65,-37.5), Vector3(36.4,-3.65,-41.55),55.0])
	views.append(["second-reliquary-close", Vector3(-28.7,-16.9,34.2), Vector3(-28.7,-16.9,38.05),60.0])
	return views

func review_passes() -> PackedStringArray:
	return PackedStringArray(["color", "albedo", "objects", "normals", "collision"])
