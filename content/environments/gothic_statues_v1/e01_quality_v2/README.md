# E01 quality experiments

The eleven single-image TripoSG/TRELLIS attempts did not resolve the requested multi-view problem. They remain local diagnostics; none replaces the shipped `../e01_crawling_v1/` model. `attempt_summary.json` records their assessment.

The user rejected both generated four-view sheets: first for inconsistencies, then for twisted/broken legs. Their local receipts preserve that status; rejected sheets and raw reconstruction meshes remain local diagnostics. No 3D reconstruction has run from those sheets.

The current direction is [female_ik_v4](female_ik_v4/README.md): reuse the actual CC0 female character, solve a fixed pose with inverse kinematics, and render all four views from that single mesh. The actual hips and chest supply alignment cues. The rig, static GLB, transparent views, editable target controls and checks are included. This delivers a coherent pose foundation; statue detail and user visual approval remain open.

The next [ImageGen statue sheet](statue_from_rig_v1/README.md) uses that rig sheet for pose and the previously approved statue for carving style. It includes a short tunic and carved hair, with four separately saved panels. The user approved these images for 3D; generated details still vary slightly between views.

The user subsequently approved that sheet for 3D. [Three joint four-image reconstructions](four_view_reconstruction_v1/README.md) are now available, including a camera-conditioned InstantMesh trial and two TRELLIS multi-image trials. The strongest rough preview preserves the crawl but still has weak face/finger detail and thin-surface defects. It is not a final asset replacement or dungeon integration.

The fingers were rejected. [Two new single-image retries](single_image_retry_v1/README.md) use only the approved front panel; TripoSG has the cleaner hand silhouette but remains approximate. Larger TRELLIS.2-4B geometry weights and an isolated MLX runtime are downloaded/prepared. Its required official DINOv3 encoder still awaits Meta access approval, so the larger model has not generated a new statue yet.
