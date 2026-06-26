# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    # Pure-logic coverage for SurfaceUp's distinctive machinery: the parallel-
    # normal merge under the equidistant offset, and the collinear-vertex
    # "repair" that now runs unconditionally in every mode. The equidistant
    # offset core SurfaceUp shares with coordinated FaceUp (compute_offset_vertex,
    # solve_3x3, the hole-scale mode guard) is covered in TC_coordinated_holes.
    class TC_surface < TestUp::TestCase

      def setup
        Sketchup.require 'asm_faceup/ops/tools'
        @tool = FaceUpTool.new
      end

      def vec(x, y, z); Geom::Vector3d.new(x, y, z); end

      # An edge exposing #line as [point, direction] — all the collinear test
      # needs from a Sketchup::Edge.
      FakeLineEdge = Struct.new(:dir) do
        def line; [Geom::Point3d.new(0, 0, 0), dir]; end
      end

      # ── dedupe_parallel_normals ───────────────────────────────────────────
      # A flat region fanned into triangles feeds N identical normals into the
      # offset; they must collapse to one so MᵀM doesn't go rank-deficient and
      # bias the LSQ. This path also folds the cluster with inject — it must
      # NOT use Array#sum, which only exists from Ruby 2.4 (min target is
      # SketchUp 2017 / Ruby 2.2).

      def test_dedupe_merges_identical_normals
        out = @tool.send(:dedupe_parallel_normals, [vec(1, 0, 0), vec(1, 0, 0), vec(1, 0, 0)])
        assert_equal 1, out.length
        assert_in_delta 1.0, out.first.dot(vec(1, 0, 0)), 1e-9
      end

      def test_dedupe_keeps_perpendicular_normals
        out = @tool.send(:dedupe_parallel_normals, [vec(1, 0, 0), vec(0, 1, 0)])
        assert_equal 2, out.length
      end

      def test_dedupe_clusters_only_parallel
        out = @tool.send(:dedupe_parallel_normals, [vec(1, 0, 0), vec(1, 0, 0), vec(0, 1, 0)])
        assert_equal 2, out.length
      end

      def test_dedupe_single_normal_passthrough
        out = @tool.send(:dedupe_parallel_normals, [vec(0, 0, 1)])
        assert_equal 1, out.length
      end

      # ── simplifiable_kept_indices (mandatory edge repair) ─────────────────
      # A vertex flanked by two parallel edges is a redundant point on a
      # straight run and gets dropped, so the offset and the self-intersection
      # clamp don't bind on a spurious sub-edge.

      # Square with an extra midpoint on the bottom edge — verts 0..4, the
      # midpoint is index 1, between two +x edges.
      def square_with_midpoint_edges
        [FakeLineEdge.new(vec(1, 0, 0)),    # 0: (0,0)->(5,0)
         FakeLineEdge.new(vec(1, 0, 0)),    # 1: (5,0)->(10,0)
         FakeLineEdge.new(vec(0, 1, 0)),    # 2: (10,0)->(10,10)
         FakeLineEdge.new(vec(-1, 0, 0)),   # 3: (10,10)->(0,10)
         FakeLineEdge.new(vec(0, -1, 0))]   # 4: (0,10)->(0,0)
      end

      def test_kept_indices_drops_collinear_midpoint
        verts = Array.new(5) { Object.new }
        kept  = @tool.send(:simplifiable_kept_indices, verts, square_with_midpoint_edges)
        assert_equal [0, 2, 3, 4], kept
      end

      def test_kept_indices_keeps_clean_quad
        verts = Array.new(4) { Object.new }
        edges = [FakeLineEdge.new(vec(1, 0, 0)), FakeLineEdge.new(vec(0, 1, 0)),
                 FakeLineEdge.new(vec(-1, 0, 0)), FakeLineEdge.new(vec(0, -1, 0))]
        assert_equal [0, 1, 2, 3], @tool.send(:simplifiable_kept_indices, verts, edges)
      end

      def test_kept_indices_passthrough_below_four
        verts = Array.new(3) { Object.new }
        edges = [FakeLineEdge.new(vec(1, 0, 0)), FakeLineEdge.new(vec(0, 1, 0)),
                 FakeLineEdge.new(vec(-1, -1, 0))]
        assert_equal [0, 1, 2], @tool.send(:simplifiable_kept_indices, verts, edges)
      end

      def test_kept_indices_degenerate_keeps_all
        # All edges parallel → every vertex would drop, leaving < 3 → keep all.
        verts = Array.new(4) { Object.new }
        edges = Array.new(4) { FakeLineEdge.new(vec(1, 0, 0)) }
        assert_equal [0, 1, 2, 3], @tool.send(:simplifiable_kept_indices, verts, edges)
      end

      # ── compute_active_outer_loop_indices (surface-group repair) ──────────
      # The surface version drops a collinear vertex only when BOTH flanking
      # edges are boundary edges (one adjacent face). A collinear vertex on a
      # seam shared with another face in the group is kept, so the seam stays
      # welded to its neighbour.

      FakeLoop2 = Struct.new(:vertices, :edges)
      FakeFace2 = Struct.new(:outer_loop)

      def build_face2(edges)
        FakeFace2.new(FakeLoop2.new(Array.new(edges.length) { Object.new }, edges))
      end

      def all_boundary(edges, face)
        ef = {}
        edges.each { |e| ef[e] = [face] }
        ef
      end

      def test_active_indices_drops_collinear_on_boundary
        edges  = square_with_midpoint_edges
        face   = build_face2(edges)
        result = @tool.send(:compute_active_outer_loop_indices, [face], all_boundary(edges, face), true)
        assert_equal [0, 2, 3, 4], result[face]
      end

      def test_active_indices_keeps_collinear_on_shared_seam
        edges = square_with_midpoint_edges
        face  = build_face2(edges)
        ef    = all_boundary(edges, face)
        ef[edges[0]] = [face, Object.new]   # the two edges flanking the
        ef[edges[1]] = [face, Object.new]   # midpoint are shared seams (size 2)
        result = @tool.send(:compute_active_outer_loop_indices, [face], ef, true)
        assert_equal [0, 1, 2, 3, 4], result[face]
      end

      def test_active_indices_no_simplify_keeps_all
        edges  = square_with_midpoint_edges
        face   = build_face2(edges)
        result = @tool.send(:compute_active_outer_loop_indices, [face], all_boundary(edges, face), false)
        assert_equal [0, 1, 2, 3, 4], result[face]
      end

    end
  end
end
