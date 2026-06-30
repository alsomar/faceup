# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    # Integration coverage for coordinated FaceUp wall extrusion: builds real
    # wall faces, runs the coordinated extrusion and measures the RESULT —
    # consistent thickness, straight collinear runs, clean manifolds — forward
    # and inverted. This is the geometry-level safety net for the offset/miter
    # machinery (the per-wall miter, collinear-run straightening, inverted map),
    # so a refactor that shares the preview/execute geometry path has something
    # to verify against.
    #
    # Each test builds inside a throwaway operation that teardown aborts, so the
    # active model is left untouched. Runs inside SketchUp via TestUp.
    class TC_coordinated_geometry < TestUp::TestCase

      def setup
        Sketchup.require 'asm_faceup/ops/tools'
        @model = Sketchup.active_model
        @model.start_operation('TC_coordinated_geometry', true)
        @group = @model.entities.add_group   # identity transform → group-local == world
      end

      def teardown
        @model.active_path = nil if @model.active_path
        @model.abort_operation
      end

      # ── Builders ──────────────────────────────────────────────────────────

      # A vertical wall face from plan endpoints, reversed so its normal points
      # toward `want` (the test controls which side thickens).
      def wall(p1, p2, want, h = 40)
        f = @group.entities.add_face(
          Geom::Point3d.new(p1[0], p1[1], 0),
          Geom::Point3d.new(p2[0], p2[1], 0),
          Geom::Point3d.new(p2[0], p2[1], h),
          Geom::Point3d.new(p1[0], p1[1], h))
        n = f.normal
        f.reverse! if n.x * want[0] + n.y * want[1] < 0
        f
      end

      # A wall radiating from `center` at `deg`, normal 90° CCW of its run — a
      # consistent orientation so neighbours miter rather than cross.
      def ray_wall(center, deg, len = 60)
        r  = deg * Math::PI / 180.0
        dx = Math.cos(r); dy = Math.sin(r)
        wall(center, [center[0] + len * dx, center[1] + len * dy], [-dy, dx])
      end

      # A wall split into `layers` stacked faces (same plan footprint, stacked in
      # z) — a subdivided / "bricked" wall. Every layer shares the corner plan
      # position with the same normal, which used to trip the collinear-run guard
      # in wall_miter_corner and butt the corner straight instead of mitering.
      def wall_bricks(p1, p2, want, layers = 3, h = 39)
        dz = h.to_f / layers
        (0...layers).map do |i|
          z0 = i * dz
          z1 = (i + 1) * dz
          f = @group.entities.add_face(
            Geom::Point3d.new(p1[0], p1[1], z0),
            Geom::Point3d.new(p2[0], p2[1], z0),
            Geom::Point3d.new(p2[0], p2[1], z1),
            Geom::Point3d.new(p1[0], p1[1], z1))
          n = f.normal
          f.reverse! if n.x * want[0] + n.y * want[1] < 0
          f
        end
      end

      # A horizontal cap face from plan corners at height `z`, reversed so its
      # normal points toward ±z per `want_z`.
      def cap(corners, want_z, z = 20)
        f = @group.entities.add_face(corners.map { |c| Geom::Point3d.new(c[0], c[1], z) })
        f.reverse! if f.normal.z * want_z < 0
        f
      end

      # Run coordinated FaceUp on `faces`, return the result groups.
      def extrude(faces, height)
        t = FaceUpTool.new
        t.instance_variable_set(:@mode, :face)
        t.instance_variable_set(:@coordinated_extrusion, true)
        t.instance_variable_set(:@ignore_external_context, true)
        @model.active_path = [@group]
        groups = t.send(:face2group, faces)
        t.send(:xtrd_groups, groups, height)
        @model.active_path = nil
        groups
      end

      # ── Measurements ──────────────────────────────────────────────────────

      # Perpendicular thickness of a wall box: signed gap between its two
      # largest (parallel) faces, projected on their normal.
      def thickness(group)
        fcs = group.entities.grep(Sketchup::Face)
        return nil if fcs.length < 6
        xf  = group.transformation
        big = fcs.sort_by { |f| -f.area }.first(2)
        n   = big[0].normal.transform(xf)
        p0  = big[0].vertices.first.position.transform(xf)
        p1  = big[1].vertices.first.position.transform(xf)
        ((p1.x - p0.x) * n.x + (p1.y - p0.y) * n.y + (p1.z - p0.z) * n.z).abs
      end

      def thicknesses(groups)
        groups.map { |g| thickness(g) }.compact.map { |t| t.round(2) }
      end

      # World z≈0 vertices of all result groups near a plan point.
      def base_verts_near(groups, pt, tol = 15)
        groups.flat_map { |g|
          xf = g.transformation
          g.entities.grep(Sketchup::Edge).flat_map(&:vertices).map { |v| v.position.transform(xf) }
        }.select { |p| p.z < 1 && (p.x - pt[0]).abs < tol && (p.y - pt[1]).abs < tol }
      end

      def vertex_at?(verts, pt, tol = 1.0)
        verts.any? { |p| (p.x - pt[0]).abs < tol && (p.y - pt[1]).abs < tol }
      end

      # ── Consistent thickness + manifold ───────────────────────────────────

      def test_l_corner_consistent_thickness
        faces  = [wall([0, 0], [60, 0], [0, -1]), wall([0, 0], [0, 60], [-1, 0])]
        groups = extrude(faces, 12)
        assert_equal [12.0, 12.0], thicknesses(groups).sort
        assert groups.all?(&:manifold?), 'L-corner walls should be manifold'
      end

      # Same L-corner but each wall is subdivided into stacked brick faces. The
      # miter must still reach the diagonal outer corner (−12, −12) instead of
      # butting straight and leaving a notch — a sibling brick at the corner
      # shares the normal but not the run direction, so it must not be mistaken
      # for a collinear run continuation.
      def test_subdivided_l_corner_still_miters
        faces  = wall_bricks([0, 0], [60, 0], [0, -1]) +
                 wall_bricks([0, 0], [0, 60], [-1, 0])
        groups = extrude(faces, 12)
        assert groups.all?(&:manifold?), 'subdivided L-corner walls should be manifold'
        verts = base_verts_near(groups, [-12, -12], 3)
        assert vertex_at?(verts, [-12, -12], 1.0),
               'subdivided wall L-corner should miter to the diagonal (-12,-12), not butt straight'
      end

      # A vertical-wall RUN (two collinear walls = a dominant run) meeting a
      # horizontal cap at the shared top edge is a MIXED junction. Dominant-run
      # straightening is a vertical-wall behaviour and must NOT pull the cap
      # along the wall direction — that would leave the cap with zero
      # perpendicular thickness (sheared flat). The full equidistant keeps every
      # face at thickness h, so all three panels stay solid.
      def test_wall_run_plus_cap_keeps_cap_thickness
        wa = wall([-30, 0], [0, 0], [0, -1], 20)
        wb = wall([0, 0], [30, 0], [0, -1], 20)
        cp = cap([[0, 0], [30, 0], [30, -20], [0, -20]], 1)
        groups = extrude([wa, wb, cp], 5)
        assert groups.all?(&:manifold?), 'wall-run + cap should be manifold'
        assert_equal [5.0, 5.0, 5.0], thicknesses(groups).sort
      end

      def test_y_junction_three_walls_consistent_thickness
        faces  = [0, 130, 250].map { |d| ray_wall([200, 40], d) }
        groups = extrude(faces, 12)
        assert_equal [12.0, 12.0, 12.0], thicknesses(groups)
        assert groups.all?(&:manifold?), '3-way junction walls should be manifold'
      end

      def test_run_plus_partition_consistent_thickness
        faces  = [wall([0, 0], [50, 0], [0, -1]), wall([50, 0], [100, 0], [0, -1]),
                  wall([50, 0], [70, 80], [0.97, -0.24])]
        groups = extrude(faces, 12)
        assert_equal [12.0, 12.0, 12.0], thicknesses(groups)
        assert groups.all?(&:manifold?)
      end

      def test_inverted_consistent_thickness
        faces  = [wall([0, 0], [50, 0], [0, -1]), wall([50, 0], [100, 0], [0, -1]),
                  wall([50, 0], [70, 80], [0.97, -0.24])] +
                 [0, 130, 250].map { |d| ray_wall([300, 40], d) }
        groups = extrude(faces, -12)
        assert_equal [12.0], thicknesses(groups).uniq
        assert groups.all?(&:manifold?), 'inverted walls should be manifold'
      end

      # ── Collinear runs stay straight (the forward + inverted fix) ─────────

      # A run split into two collinear panels with a partition meeting at the
      # split keeps the run straight: its offset edge runs through the junction
      # at the perpendicular offset, not bent toward the partition.
      def test_run_stays_straight_forward
        faces = [wall([0, 0], [50, 0], [0, -1]), wall([50, 0], [100, 0], [0, -1]),
                 wall([50, 0], [70, 80], [0.97, -0.24])]
        groups = extrude(faces, 12)
        verts  = base_verts_near(groups, [50, 0])
        assert vertex_at?(verts, [50, -12]), 'forward run offset should pass straight through (50,-12)'
      end

      def test_run_stays_straight_inverted
        faces = [wall([0, 0], [50, 0], [0, -1]), wall([50, 0], [100, 0], [0, -1]),
                 wall([50, 0], [70, 80], [0.97, -0.24])]
        groups = extrude(faces, -12)
        verts  = base_verts_near(groups, [50, 0])
        assert vertex_at?(verts, [50, 12]), 'inverted run offset should pass straight through (50,12)'
      end

      # ── Pass-through (T mid-span) doesn't void the miter map ─────────────

      # A long wall with a mid-span vertex (a partition meets it mid-run) must
      # still get consistent thickness — a footprint mid-vertex must not make
      # the whole map fall back to the inconsistent equidistant offset.
      def test_mid_span_junction_keeps_consistent_thickness
        long = @group.entities.add_face(
          Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(50, 0, 0), Geom::Point3d.new(100, 0, 0),
          Geom::Point3d.new(100, 0, 40), Geom::Point3d.new(50, 0, 40), Geom::Point3d.new(0, 0, 40))
        long.reverse! if long.normal.y > 0
        part = wall([50, 0], [50, 60], [1, 0])
        groups = extrude([long, part], 12)
        assert_equal [12.0], thicknesses(groups).uniq, 'mid-span junction must keep thickness h'
        assert groups.all?(&:manifold?)
      end

    end
  end
end
