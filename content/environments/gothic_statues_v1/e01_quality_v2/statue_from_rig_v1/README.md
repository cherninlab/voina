# Marble statue from the existing female rig

One built-in ImageGen call used `../female_ik_v4/four_views.png` as the authoritative pose/anatomy/camera reference and `../../e01_crawling_v1/source/approved.png` only for classical marble, face, hair and short-tunic style. [Exact prompt](prompt.txt), [generation receipt](receipt.json), [complete sheet](sheet.png).

The output is cut into [front](front.png), [left](left.png), [back](back.png) and [right](right.png) panels. Cutting is mechanical: no per-panel rescaling, recentering or repainting. The gray background remains; mask it before any reconstruction.

The grounded knees, supporting right hand, raised left reach and short tunic read across all views. ImageGen changed the reach's elbow bend and some head, hair, garment and projection details. These are generated approximations of the rig, not calibrated renders of an identical finished mesh. New statue images await user review before 3D work; neither this sheet nor its crops have been submitted to a reconstruction model.
