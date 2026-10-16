extends Node3D

# Original procedural geometry: no external model, texture, rig or animation dependency.
var wings: Array[Node3D] = []
var age: float = 0.0

func _ready() -> void:
	var feather: StandardMaterial3D = surface(Color("425872"))
	var breast: StandardMaterial3D = surface(Color("a9bac6"))
	var beak: StandardMaterial3D = surface(Color("dca85f"))
	var eye: StandardMaterial3D = surface(Color("0e1825"))
	var body: SphereMesh = sphere(0.15, 0.28)
	var torso: MeshInstance3D = part(body, Vector3(0, 0.08, 0), breast)
	torso.scale = Vector3(0.85, 1.0, 1.5)
	part(sphere(0.105, 0.2), Vector3(0, 0.22, -0.18), feather)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.045
	cone.height = 0.14
	cone.radial_segments = 6
	var bill: MeshInstance3D = part(cone, Vector3(0, 0.22, -0.31), beak)
	bill.rotation.x = -PI / 2.0
	for side: float in [-1.0, 1.0]:
		part(sphere(0.022, 0.044), Vector3(side * 0.085, 0.25, -0.23), eye)
		var pivot: Node3D = Node3D.new()
		pivot.position = Vector3(side * 0.1, 0.14, 0.0)
		add_child(pivot)
		wings.append(pivot)
		var wing: PrismMesh = PrismMesh.new()
		wing.size = Vector3(0.38, 0.035, 0.23)
		var mesh: MeshInstance3D = part(wing, Vector3(side * 0.18, 0, 0.03), feather, pivot)
		mesh.rotation.y = side * -0.2
		var leg: CylinderMesh = CylinderMesh.new()
		leg.top_radius = 0.013
		leg.bottom_radius = 0.013
		leg.height = 0.12
		part(leg, Vector3(side * 0.055, -0.09, 0.0), beak)
	var tail: PrismMesh = PrismMesh.new()
	tail.size = Vector3(0.17, 0.04, 0.25)
	part(tail, Vector3(0, 0.1, 0.29), feather).rotation.x = -0.15

func surface(color: Color) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	return result

func sphere(radius: float, height: float) -> SphereMesh:
	var result: SphereMesh = SphereMesh.new()
	result.radius = radius
	result.height = height
	result.radial_segments = 8
	result.rings = 4
	return result

func part(mesh: Mesh, location: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	result.mesh = mesh
	result.position = location
	result.material_override = material
	parent.add_child(result)
	return result

func animate(delta: float, flying: bool, phase: float) -> void:
	age += delta
	for index: int in range(wings.size()):
		var side: float = -1.0 if index == 0 else 1.0
		var angle: float = sin(age * 18.0 + phase) * 0.8 if flying else 0.05
		wings[index].rotation.z = lerp_angle(wings[index].rotation.z, side * angle, minf(delta * 15.0, 1.0))
		wings[index].rotation.y = lerp_angle(wings[index].rotation.y, 0.0 if flying else -side * 1.15, minf(delta * 15.0, 1.0))
		wings[index].scale.x = lerpf(wings[index].scale.x, 1.0 if flying else 0.6, minf(delta * 15.0, 1.0))
	position.y = sin(age * (9.0 if flying else 2.0) + phase) * (0.035 if flying else 0.012)
