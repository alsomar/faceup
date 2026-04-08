# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_extruder < TestUp::TestCase

      # ── Helpers ───────────────────────────────────────────────────────────

      # Stubs for inference_color — duck-typed InputPoint
      FakeEndpoint = Struct.new(:position)
      FakeEdge     = Struct.new(:start, :end)

      FakeIP = Struct.new(:vertex, :edge, :face, :position)

      def setup
        Sketchup.require 'asm_faceup/ops/tools'
        # Instantiating ExtruderTool calls initialize, which reads CONFIG and
        # the active model attribute — both available in the TestUp environment.
        @tool = ExtruderTool.new
      end

      # ── KEYS constant ─────────────────────────────────────────────────────

      def test_keys_esc_is_27
        assert_equal 27, ExtruderTool::KEYS[:esc]
      end

      def test_keys_space_is_32
        assert_equal 32, ExtruderTool::KEYS[:space]
      end

      def test_keys_tab_is_9
        assert_equal 9, ExtruderTool::KEYS[:tab]
      end

      def test_keys_arrow_left_is_37
        assert_equal 37, ExtruderTool::KEYS[:arrow_left]
      end

      def test_keys_arrow_right_is_39
        assert_equal 39, ExtruderTool::KEYS[:arrow_right]
      end

      def test_keys_arrow_up_is_38
        assert_equal 38, ExtruderTool::KEYS[:arrow_up]
      end

      def test_keys_is_frozen
        assert ExtruderTool::KEYS.frozen?
      end

      # ── UNIT_SUFFIXES constant ────────────────────────────────────────────

      def test_unit_suffixes_mm
        assert_equal 'mm', ExtruderTool::UNIT_SUFFIXES['mm']
      end

      def test_unit_suffixes_cm
        assert_equal 'cm', ExtruderTool::UNIT_SUFFIXES['cm']
      end

      def test_unit_suffixes_m
        assert_equal 'm', ExtruderTool::UNIT_SUFFIXES['m']
      end

      def test_unit_suffixes_inch
        assert_equal '"', ExtruderTool::UNIT_SUFFIXES['inch']
      end

      def test_unit_suffixes_feet
        assert_equal "'", ExtruderTool::UNIT_SUFFIXES['feet']
      end

      def test_unit_suffixes_model_is_nil
        assert_nil ExtruderTool::UNIT_SUFFIXES['model']
      end

      def test_unit_suffixes_is_frozen
        assert ExtruderTool::UNIT_SUFFIXES.frozen?
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
        assert_equal ExtruderTool::INFERENCE_COLORS[:vertex],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_edge_at_midpoint
        p1  = Geom::Point3d.new(0, 0, 0)
        p2  = Geom::Point3d.new(2, 0, 0)
        mid = Geom::Point3d.new((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, (p1.z + p2.z) / 2.0)

        edge = FakeEdge.new(FakeEndpoint.new(p1), FakeEndpoint.new(p2))
        ip   = FakeIP.new(nil, edge, nil, mid)

        assert_equal ExtruderTool::INFERENCE_COLORS[:midpoint],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_edge_not_at_midpoint
        p1  = Geom::Point3d.new(0, 0, 0)
        p2  = Geom::Point3d.new(2, 0, 0)
        off = Geom::Point3d.new(0.3, 0, 0)  # near start, not midpoint

        edge = FakeEdge.new(FakeEndpoint.new(p1), FakeEndpoint.new(p2))
        ip   = FakeIP.new(nil, edge, nil, off)

        assert_equal ExtruderTool::INFERENCE_COLORS[:edge],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_face_snap
        ip = FakeIP.new(nil, nil, Object.new, Geom::Point3d.new(1, 1, 0))
        assert_equal ExtruderTool::INFERENCE_COLORS[:face],
                     @tool.send(:inference_color, ip)
      end

      def test_inference_color_free_point
        ip = FakeIP.new(nil, nil, nil, Geom::Point3d.new(5, 5, 5))
        assert_equal ExtruderTool::INFERENCE_COLORS[:none],
                     @tool.send(:inference_color, ip)
      end

    end
  end
end
