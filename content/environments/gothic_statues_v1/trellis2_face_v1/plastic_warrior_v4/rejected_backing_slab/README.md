# Rejected: backing slab

The first attempt incorrectly bypassed foreground segmentation on the opaque RGB reference. Actual mesh renders revealed a large rectangular slab behind the figure, so this reconstruction is rejected. The source was never edited.

The rerun uses the installed pipeline's U2Net semantic foreground segmentation before creating the DINO conditioning input. This is a preprocessing hypothesis; the actual rerun mesh must still be inspected.

Generation/cleanup receipts and the actual front render are retained. Dense rejected GLBs, checkpoints and additional renders remain local and are excluded from Git.
