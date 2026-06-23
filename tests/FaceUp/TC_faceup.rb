# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_faceup < TestUp::TestCase

      # ── Helpers ───────────────────────────────────────────────────────────

      # Stubs for inference_color — duck-typed InputPoint
      FakeEndpoint = Struct.new(:position)
      FakeEdge     = Struct.new(:start, :end)

      FakeIP = Struct.new(:vertex, :edge, :face, :position)

      def setup
        Sketchup.require 'asm_faceup/ops/tools'
        # Instantiating FaceUpTool calls initialize, which reads CONFIG and
        # the active model attribute — both available in the TestUp environment.
        @tool = FaceUpTool.new
      end

      # ── KEYS constant ─────────────────────────────────────────────────────

      def test_keys_esc_is_27
        assert_equal 27, FaceUpTool::KEYS[:esc]
      end

      def test_keys_tab_is_9
        assert_equal 9, FaceUpTool::KEYS[:tab]
      end

      def test_keys_arrow_left_is_37
        assert_equal 37, FaceUpTool::KEYS[:arrow_left]
      end

      def test_keys_arrow_right_is_39
        assert_equal 39, FaceUpTool::KEYS[:arrow_right]
      end

      def test_keys_arrow_up_is_38
        assert_equal 38, FaceUpTool::KEYS[:arrow_up]
      end

      def test_keys_is_frozen
        assert FaceUpTool::KEYS.frozen?
      end

      # ── UNIT_SUFFIXES constant ────────────────────────────────────────────

      def test_unit_suffixes_mm
        assert_equal 'mm', FaceUpTool::UNIT_SUFFIXES['mm']
      end

      def test_unit_suffixes_cm
        assert_equal 'cm', FaceUpTool::UNIT_SUFFIXES['cm']
      end

      def test_unit_suffixes_m
        assert_equal 'm', FaceUpTool::UNIT_SUFFIXES['m']
      end

      def test_unit_suffixes_inch
        assert_equal '"', FaceUpTool::UNIT_SUFFIXES['inch']
      end

      def test_unit_suffixes_feet
        assert_equal "'", FaceUpTool::UNIT_SUFFIXES['feet']
      end

      def test_unit_suffixes_yard
        assert_equal 'yd', FaceUpTool::UNIT_SUFFIXES['yard']
      end

      def test_unit_suffixes_model_is_nil
        assert_nil FaceUpTool::UNIT_SUFFIXES['model']
      end

      def test_unit_suffixes_is_frozen
        assert FaceUpTool::UNIT_SUFFIXES.frozen?
      end

      # ── default_extrusion_to_length ───────────────────────────────────────

      def test_default_extrusion_mm_returns_length
        result = @tool.send(:default_extrusion_to_length, 100, 'mm')
        assert_equal '100mm'.to_l, result
      end

      def test_default_extrusion_cm_returns_length
        result = @tool.send(:default_extrusion_to_length, 50, 'cm')
        assert_equal '50cm'.to_l, result
      end

      def test_default_extrusion_m_returns_length
        result = @tool.send(:default_extrusion_to_length, 2, 'm')
        assert_equal '2m'.to_l, result
      end

      def test_default_extrusion_inch_returns_length
        result = @tool.send(:default_extrusion_to_length, 12, 'inch')
        assert_equal '12"'.to_l, result
      end

      def test_default_extrusion_feet_returns_length
        result = @tool.send(:default_extrusion_to_length, 6, 'feet')
        assert_equal "6'".to_l, result
      end

      def test_default_extrusion_yard_returns_length
        result = @tool.send(:default_extrusion_to_length, 3, 'yard')
        assert_equal '3yd'.to_l, result
      end

      def test_default_extrusion_model_units_returns_length
        result = @tool.send(:default_extrusion_to_length, 1, 'model')
        assert_equal 1.to_l, result
      end

      def test_default_extrusion_invalid_string_returns_zero
        result = @tool.send(:default_extrusion_to_length, 'not_a_number', 'mm')
        assert_equal 0.to_l, result
      end

      def test_default_extrusion_zero_value_returns_zero_length
        result = @tool.send(:default_extrusion_to_length, 0, 'm')
        assert_equal 0.to_l, result
      end

      # ── closest_point_on_axis ─────────────────────────────────────────────

      # Axis: Z from origin. Ray: horizontal at (5,0,3) going along X.
      # Closest point on Z axis to that ray is (0,0,3), so t == 3.
      def test_closest_point_on_axis_perpendicular_ray
        anchor   = Geom::Point3d.new(0, 0, 0)
        axis_vec = Geom::Vector3d.new(0, 0, 1)
        ray_origin = Geom::Point3d.new(5, 0, 3)
        ray_dir    = Geom::Vector3d.new(1, 0, 0)

        t = @tool.send(:closest_point_on_axis, anchor, axis_vec, ray_origin, ray_dir)
        assert_in_delta 3.0, t, 1e-8
      end

      # Axis: X from origin. Ray: along X offset by (0,2,5) — i.e. parallel.
      # Denominator is zero (parallel lines): must return 0.0 without raising.
      def test_closest_point_on_axis_parallel_ray_returns_zero
        anchor   = Geom::Point3d.new(0, 0, 0)
        axis_vec = Geom::Vector3d.new(1, 0, 0)
        ray_origin = Geom::Point3d.new(0, 2, 5)
        ray_dir    = Geom::Vector3d.new(1, 0, 0)

        t = @tool.send(:closest_point_on_axis, anchor, axis_vec, ray_origin, ray_dir)
        assert_in_delta 0.0, t, 1e-8
      end

      # Axis: Y from (0,0,1). Ray: straight down at (3,7,10).
      # Closest Y-axis point to the ray is at t == 7.
      def test_closest_point_on_axis_non_origin_anchor
        anchor   = Geom::Point3d.new(0, 0, 1)
        axis_vec = Geom::Vector3d.new(0, 1, 0)
        ray_origin = Geom::Point3d.new(3, 7, 10)
        ray_dir    = Geom::Vector3d.new(0, 0, -1)

        t = @tool.send(:closest_point_on_axis, anchor, axis_vec, ray_origin, ray_dir)
        assert_in_delta 7.0, t, 1e-8
      end

      # ── inference_color ───────────────────────────────────────────────────

      def test_inference_color_vertex_snap
        ip = FakeIP.new(Object.new, nil, nil, Geom::Point3d.new(0, 0, 0))
        assert_equal FaceUpTool::INFERENCE_COLORS[:vertex],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_edge_at_midpoint
        p1  = Geom::Point3d.new(0, 0, 0)
        p2  = Geom::Point3d.new(2, 0, 0)
        mid = Geom::Point3d.new((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, (p1.z + p2.z) / 2.0)

        edge = FakeEdge.new(FakeEndpoint.new(p1), FakeEndpoint.new(p2))
        ip   = FakeIP.new(nil, edge, nil, mid)

        assert_equal FaceUpTool::INFERENCE_COLORS[:midpoint],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_edge_not_at_midpoint
        p1  = Geom::Point3d.new(0, 0, 0)
        p2  = Geom::Point3d.new(2, 0, 0)
        off = Geom::Point3d.new(0.3, 0, 0)  # near start, not midpoint

        edge = FakeEdge.new(FakeEndpoint.new(p1), FakeEndpoint.new(p2))
        ip   = FakeIP.new(nil, edge, nil, off)

        assert_equal FaceUpTool::INFERENCE_COLORS[:edge],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_face_snap
        ip = FakeIP.new(nil, nil, Object.new, Geom::Point3d.new(1, 1, 0))
        assert_equal FaceUpTool::INFERENCE_COLORS[:face],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_free_point
        ip = FakeIP.new(nil, nil, nil, Geom::Point3d.new(5, 5, 5))
        assert_equal FaceUpTool::INFERENCE_COLORS[:none],
                     @tool.send(:inference_color, ip)
      end

      # ── convex_hull_2d ────────────────────────────────────────────────────

      def test_convex_hull_2d_drops_interior_point
        pts = [[0, 0], [2, 0], [2, 2], [0, 2], [1, 1]]
        hull = ASM_Extensions::FaceUp.convex_hull_2d(pts)
        assert_equal 4, hull.length
        assert(hull.none? { |p| p == [1, 1] }, "interior point should be dropped")
      end

      def test_convex_hull_2d_collinear_points_collapse
        pts = [[0, 0], [1, 0], [2, 0], [2, 2], [0, 2]]
        hull = ASM_Extensions::FaceUp.convex_hull_2d(pts)
        # The collinear (1,0) on the bottom edge must not be a hull vertex.
        assert_equal 4, hull.length
      end

      # ── min_area_rect_angle ───────────────────────────────────────────────

      # Area of the bounding box after rotating the points by `theta`,
      # using the same projection convention as min_area_rect_angle.
      def bb_area_at(pts, theta)
        c = Math.cos(theta)
        s = Math.sin(theta)
        us = pts.map { |p|  p[0] * c + p[1] * s }
        vs = pts.map { |p| -p[0] * s + p[1] * c }
        (us.max - us.min) * (vs.max - vs.min)
      end

      def test_min_area_rect_angle_axis_aligned_rect_is_multiple_of_90
        pts   = [[0, 0], [3, 0], [3, 1], [0, 1]]
        angle = ASM_Extensions::FaceUp.min_area_rect_angle(pts)
        # Already optimal: angle must be a multiple of 90° (BB area has period π/2).
        norm = angle % (Math::PI / 2.0)
        norm = (Math::PI / 2.0) - norm if norm > Math::PI / 4.0
        assert_in_delta 0.0, norm, 1e-6
      end

      def test_min_area_rect_angle_beats_axis_aligned_for_diamond
        # Square rotated 45°: min-area rect runs along its 45° edges, not the axes.
        pts   = [[0, 1], [1, 0], [0, -1], [-1, 0]]
        angle = ASM_Extensions::FaceUp.min_area_rect_angle(pts)
        assert_operator bb_area_at(pts, angle), :<=, bb_area_at(pts, 0.0) + 1e-9
        # The diamond's min area is 2.0 (side √2), vs 4.0 axis-aligned.
        assert_in_delta 2.0, bb_area_at(pts, angle), 1e-6
      end

    end
  end
end
