# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    # Pure-logic coverage for the thorny cases behind coordinated FaceUp's
    # converging panels and the equidistant offset SurfaceUp shares with it.
    # Everything here is geometry math with hand-built inputs — no model
    # geometry — so it runs fast and deterministically inside TestUp.
    class TC_coordinated_holes < TestUp::TestCase

      # ── Helpers ───────────────────────────────────────────────────────────

      def setup
        Sketchup.require 'asm_faceup/ops/tools'
        @tool = FaceUpTool.new
      end

      def pt(x, y, z);  Geom::Point3d.new(x, y, z);  end
      def vec(x, y, z); Geom::Vector3d.new(x, y, z); end

      def assert_point(expected, actual, delta = 1e-6)
        assert_in_delta expected.x, actual.x, delta, "x"
        assert_in_delta expected.y, actual.y, delta, "y"
        assert_in_delta expected.z, actual.z, delta, "z"
      end

      # A vertex usable both as a hash key (object identity) and via #position.
      FakeVertex = Struct.new(:position)

      # A loop exposing #outer? and #vertices, for capture_panel_holes.
      FakeLoop = Struct.new(:outer, :vertices) do
        def outer?; outer; end
      end

      # A face exposing #loops and #outer_loop, for capture_panel_holes.
      class FakeFace
        def initialize(outer_loop, inner_loops)
          @outer_loop = outer_loop
          @loops      = [outer_loop] + inner_loops
        end
        def outer_loop; @outer_loop; end
        def loops;      @loops;      end
      end

      # Build a coordinated_face_hole_scale group hash from outer corner
      # positions and per-corner unit displacements. The lifted top at `dist`
      # is position + dist * disp (matching surface_top_pt).
      def build_group(corner_positions, corner_disps, has_holes: true)
        verts     = corner_positions.map { |p| FakeVertex.new(p) }
        vert_pos  = {}
        vert_disp = {}
        verts.each_with_index do |v, i|
          vert_pos[v]  = corner_positions[i]
          vert_disp[v] = corner_disps[i]
        end
        {
          vert_pos:    vert_pos,
          vert_disp:   vert_disp,
          outer_verts: verts,
          has_holes:   has_holes,
        }
      end

      # ── COORD_FACE_CAP_SAFETY ─────────────────────────────────────────────
      # The result caps a hair short of the exact self-intersection so the tip
      # is a clean thin point rather than a degenerate one; the preview must
      # apply the *same* factor or it would draw slightly deeper than it builds.

      def test_cap_safety_constant_is_below_one
        assert_operator FaceUpTool::COORD_FACE_CAP_SAFETY, :<, 1.0
        assert_operator FaceUpTool::COORD_FACE_CAP_SAFETY, :>, 0.9
      end

      # ── average_position (Ruby 2.2-safe centroid) ─────────────────────────

      def test_average_position_centroid
        c = @tool.send(:average_position, [pt(0, 0, 0), pt(2, 0, 0), pt(2, 2, 0), pt(0, 2, 0)])
        assert_point pt(1, 1, 0), c
      end

      def test_average_position_single_point
        c = @tool.send(:average_position, [pt(3, -4, 5)])
        assert_point pt(3, -4, 5), c
      end

      # ── compute_offset_vertex (equidistant offset) ────────────────────────
      # This is the core SurfaceUp/coordinated machinery. A flat region (one
      # normal, or several parallel normals from a fan triangulation) must
      # offset *straight* — which is exactly why SurfaceUp on a flat surface is
      # a straight prism and a hole in it keeps its size.

      def test_offset_single_normal_is_straight
        v = @tool.send(:compute_offset_vertex, pt(0, 0, 0), [vec(0, 0, 1)], 5.0)
        assert_point pt(0, 0, 5), v
      end

      def test_offset_parallel_normals_collapse_to_straight
        # A flat face fanned into triangles yields N identical normals; they
        # must merge so the vertex still offsets straight (no spurious inset).
        v = @tool.send(:compute_offset_vertex, pt(0, 0, 0), [vec(1, 0, 0), vec(1, 0, 0)], 5.0)
        assert_point pt(5, 0, 0), v
      end

      def test_offset_two_perpendicular_normals_is_equidistant_miter
        # Equidistant point sits at perpendicular distance h from both planes:
        # for x- and y-normals through the origin that is (h, h, 0).
        v = @tool.send(:compute_offset_vertex, pt(0, 0, 0), [vec(1, 0, 0), vec(0, 1, 0)], 5.0)
        assert_point pt(5, 5, 0), v
      end

      def test_offset_three_perpendicular_normals_is_corner
        # A box corner: equidistant from all three axis planes → (h, h, h).
        v = @tool.send(:compute_offset_vertex, pt(0, 0, 0),
                       [vec(1, 0, 0), vec(0, 1, 0), vec(0, 0, 1)], 5.0)
        assert_point pt(5, 5, 5), v
      end

      def test_offset_empty_normals_returns_position
        v = @tool.send(:compute_offset_vertex, pt(1, 2, 3), [], 5.0)
        assert_point pt(1, 2, 3), v
      end

      # ── solve_3x3 (Cramer's rule under the ≥3-normal offset) ───────────────

      def test_solve_3x3_diagonal_system
        w = @tool.send(:solve_3x3, [[2.0, 0, 0], [0, 3.0, 0], [0, 0, 4.0]], [2.0, 3.0, 4.0])
        assert_point pt(1, 1, 1), w
      end

      def test_solve_3x3_identity_returns_rhs
        w = @tool.send(:solve_3x3, [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]], [2.0, -3.0, 4.0])
        assert_point pt(2, -3, 4), w
      end

      def test_solve_3x3_singular_returns_nil
        # Zero bottom row → det 0 → nil, so compute_offset_vertex falls back to
        # the averaged-direction extrusion instead of dividing by zero.
        assert_nil @tool.send(:solve_3x3, [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 0.0]], [1.0, 1.0, 1.0])
      end

      # ── capture_panel_holes ───────────────────────────────────────────────
      # Holeless panels return nil so the builder skips the scaling pass
      # entirely; holed panels return outer + per-hole bottom positions.

      def test_capture_panel_holes_nil_without_hole
        outer = FakeLoop.new(true, [FakeVertex.new(pt(0, 0, 0))])
        face  = FakeFace.new(outer, [])
        assert_nil @tool.send(:capture_panel_holes, face)
      end

      def test_capture_panel_holes_returns_outer_and_holes
        outer = FakeLoop.new(true,
          [FakeVertex.new(pt(0, 0, 0)), FakeVertex.new(pt(10, 0, 0)),
           FakeVertex.new(pt(10, 10, 0)), FakeVertex.new(pt(0, 10, 0))])
        hole  = FakeLoop.new(false,
          [FakeVertex.new(pt(3, 3, 0)), FakeVertex.new(pt(7, 3, 0)),
           FakeVertex.new(pt(7, 7, 0)), FakeVertex.new(pt(3, 7, 0))])
        data = @tool.send(:capture_panel_holes, FakeFace.new(outer, [hole]))

        assert_equal 4, data[:outer].length
        assert_equal 1, data[:holes].length
        assert_equal 4, data[:holes].first.length
        assert_point pt(3, 3, 0), data[:holes].first.first
      end

      # ── coordinated_face_hole_scale ───────────────────────────────────────
      # The factor by which a coordinated panel's hole tapers: the outer
      # contour's radial contraction `s`, about the outer top centroid `ct`
      # (the panel's convergence apex). s < 1 inward, s > 1 outward.

      # Square at ±10 with corners pulled half-way to the centre axis while
      # rising: at dist 10 the top square is ±5, so s == 0.5 and ct == (0,0,10).
      def inward_group
        corners = [pt(10, 10, 0), pt(-10, 10, 0), pt(-10, -10, 0), pt(10, -10, 0)]
        disps   = [vec(-0.5, -0.5, 1), vec(0.5, -0.5, 1), vec(0.5, 0.5, 1), vec(-0.5, 0.5, 1)]
        build_group(corners, disps)
      end

      def test_hole_scale_inward_contracts
        @tool.instance_variable_set(:@mode, :face)
        ct, s = @tool.send(:coordinated_face_hole_scale, inward_group, 10.0)
        assert_in_delta 0.5, s, 1e-6
        assert_point pt(0, 0, 10), ct
      end

      def test_hole_scale_outward_expands
        @tool.instance_variable_set(:@mode, :face)
        corners = [pt(10, 10, 0), pt(-10, 10, 0), pt(-10, -10, 0), pt(10, -10, 0)]
        # Corners spread outward while rising → top square is ±15, s == 1.5.
        disps   = [vec(0.5, 0.5, 1), vec(-0.5, 0.5, 1), vec(-0.5, -0.5, 1), vec(0.5, -0.5, 1)]
        _ct, s  = @tool.send(:coordinated_face_hole_scale, build_group(corners, disps), 10.0)
        assert_in_delta 1.5, s, 1e-6
      end

      def test_hole_scale_nil_in_surface_mode
        # SurfaceUp never scales holes — it offsets hole verts equidistantly
        # like the contour, so this guard must short-circuit to nil.
        @tool.instance_variable_set(:@mode, :surface)
        assert_nil @tool.send(:coordinated_face_hole_scale, inward_group, 10.0)
      end

      def test_hole_scale_nil_without_holes
        @tool.instance_variable_set(:@mode, :face)
        g = inward_group
        g[:has_holes] = false
        assert_nil @tool.send(:coordinated_face_hole_scale, g, 10.0)
      end

      def test_hole_scale_nil_without_outer_verts
        @tool.instance_variable_set(:@mode, :face)
        g = inward_group
        g[:outer_verts] = nil
        assert_nil @tool.send(:coordinated_face_hole_scale, g, 10.0)
      end

      # ── surface_meta_bottom / surface_meta_top ────────────────────────────
      # The preview's per-point lift. Outer (:v) and hole (:hole) points lift
      # by their stored displacement; interior mesh points lift by the face
      # normal. In coordinated face mode a [ct, s] slides hole points toward
      # the apex so the preview tapers like the result; in surface mode (nil)
      # hole points stay on their straight lift.

      def lift_inputs
        v_outer = FakeVertex.new(pt(8, 0, 0))
        v_hole  = FakeVertex.new(pt(4, 4, 0))
        vert_pos  = { v_outer => pt(8, 0, 0), v_hole => pt(4, 4, 0) }
        vert_disp = { v_outer => vec(0, 0, 1), v_hole => vec(0, 0, 1) }
        [v_outer, v_hole, vert_pos, vert_disp]
      end

      def test_meta_bottom_outer_and_hole_use_vertex_position
        v = FakeVertex.new(pt(4, 4, 0))
        assert_point pt(4, 4, 0), @tool.send(:surface_meta_bottom, [:v, v])
        assert_point pt(4, 4, 0), @tool.send(:surface_meta_bottom, [:hole, v])
      end

      def test_meta_bottom_interior_uses_stored_point
        assert_point pt(1, 1, 0), @tool.send(:surface_meta_bottom, [:interior, pt(1, 1, 0), vec(0, 0, 1)])
      end

      def test_meta_top_outer_lifts_by_displacement
        v_outer, _v_hole, vert_pos, vert_disp = lift_inputs
        top = @tool.send(:surface_meta_top, [:v, v_outer], vert_disp, vert_pos, 10.0)
        assert_point pt(8, 0, 10), top
      end

      def test_meta_top_interior_lifts_by_normal
        top = @tool.send(:surface_meta_top, [:interior, pt(1, 1, 0), vec(0, 0, 1)], {}, {}, 10.0)
        assert_point pt(1, 1, 10), top
      end

      def test_meta_top_hole_without_scale_is_straight_lift
        # Surface mode passes nil hole_scale → hole point just rises straight.
        _v_outer, v_hole, vert_pos, vert_disp = lift_inputs
        top = @tool.send(:surface_meta_top, [:hole, v_hole], vert_disp, vert_pos, 10.0, nil)
        assert_point pt(4, 4, 10), top
      end

      def test_meta_top_hole_scales_toward_apex_not_own_centre
        # With ct = (0,0,10) and s = 0.5 the hole point (4,4,10) collapses to
        # (2,2,10) — pulled toward the OUTER apex (0,0), not the hole's own
        # centre. This is the convergence fix that keeps the hole inside the
        # narrowing block instead of poking through it.
        _v_outer, v_hole, vert_pos, vert_disp = lift_inputs
        top = @tool.send(:surface_meta_top, [:hole, v_hole], vert_disp, vert_pos, 10.0, [pt(0, 0, 10), 0.5])
        assert_point pt(2, 2, 10), top
      end

      # Preview/result parity: the preview's hole-scale math (surface_meta_top)
      # uses the very [ct, s] that coordinated_face_hole_scale derives — so a
      # hole point fed the group's own ct/s lands where scale_panel_holes would
      # put it on the built geometry.
      def test_preview_hole_scale_matches_derived_factor
        @tool.instance_variable_set(:@mode, :face)
        ct, s = @tool.send(:coordinated_face_hole_scale, inward_group, 10.0)
        vh        = FakeVertex.new(pt(4, 4, 0))
        vert_pos  = { vh => pt(4, 4, 0) }
        vert_disp = { vh => vec(0, 0, 1) }
        top = @tool.send(:surface_meta_top, [:hole, vh], vert_disp, vert_pos, 10.0, [ct, s])
        # s == 0.5 about (0,0,10): (4,4,10) → (2,2,10).
        assert_point pt(2, 2, 10), top
      end

    end
  end
end
