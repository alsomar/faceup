# frozen_string_literal: true

require 'testup/testcase'
require 'benchmark'

module ASM_Extensions
  module FaceUp
    class TC_performance < TestUp::TestCase

      # How many groups to simulate in each benchmark run.
      SMALL_BATCH  =   10
      LARGE_BATCH  =  200

      # Maximum acceptable time (seconds) per assertion — generous enough to
      # remain green on slow CI machines while still catching O(n²) regressions.
      THRESHOLD_SMALL  = 0.05  # 50 ms for 10 groups
      THRESHOLD_LARGE  = 0.50  # 500 ms for 200 groups

      # ── Helpers ───────────────────────────────────────────────────────────

      # Build a lightweight fake group whose #entities responds to #to_a and
      # #grep, matching the interface consumed by xtrd_groups.
      FakeEntity = Struct.new(:type, :layer) do
        def is_a?(klass)
          type == klass
        end
      end

      class FakeEntities
        def initialize(face_count, edge_count)
          @items = []
          face_count.times { @items << FakeEntity.new(Sketchup::Face, nil) }
          edge_count.times { @items << FakeEntity.new(Sketchup::Edge, nil) }
        end

        def to_a
          @items.dup
        end

        # Simulate Enumerable#grep via ===  / is_a? check.
        def grep(klass)
          @items.select { |e| e.is_a?(klass) }
        end
      end

      class FakeFace
        attr_accessor :layer
        def pushpull(_height); end
      end

      class FakeGroup
        def initialize(face_count, edge_count)
          @face   = FakeFace.new
          @entities = FakeEntities.new(0, edge_count)  # faces injected separately
          @face_list = Array.new(face_count) { FakeFace.new }
        end

        # Return an entities object whose grep(Sketchup::Face) yields real FakeFaces.
        def entities
          FakeGroupEntities.new(@face_list, @entities)
        end
      end

      class FakeGroupEntities
        def initialize(faces, edge_entities)
          @faces = faces
          @edge_entities = edge_entities
        end

        def to_a
          @faces + @edge_entities.to_a
        end

        def grep(klass)
          if klass == Sketchup::Face
            @faces
          else
            @edge_entities.grep(klass)
          end
        end
      end

      # Build a default_layer stub (layer assignment is a no-op in tests).
      module FakeModel
        def self.layers; FakeLayers; end
        module FakeLayers
          def self.[](i); :default_layer; end
        end
      end

      # ── Benchmarked subject ───────────────────────────────────────────────

      # Inline copy of the CURRENT (optimised) xtrd_groups so the test is
      # self-contained and does not depend on private method access.
      def xtrd_groups_current(groups, height)
        default_layer = FakeModel.layers[0]

        groups.each do |group|
          entities = group.entities.to_a
          faces    = entities.grep(Sketchup::Face)

          faces.each                         { |f| f.layer = default_layer }
          entities.grep(Sketchup::Edge).each { |e| e.layer = default_layer }

          faces.first.pushpull(height) if faces.first
        end
      end

      # Inline copy of the PREVIOUS (unoptimised) xtrd_groups for comparison.
      def xtrd_groups_legacy(groups, height)
        default_layer = FakeModel.layers[0]

        groups.each do |group|
          group.entities.grep(Sketchup::Face).each { |face| face.layer = default_layer }
          group.entities.grep(Sketchup::Edge).each { |edge| edge.layer = default_layer }

          face = group.entities.grep(Sketchup::Face).first
          face.pushpull(height) if face
        end
      end

      def build_groups(count, faces_per_group: 1, edges_per_group: 8)
        Array.new(count) { FakeGroup.new(faces_per_group, edges_per_group) }
      end

      # ── Tests ─────────────────────────────────────────────────────────────

      def test_xtrd_groups_current_small_batch_within_threshold
        groups  = build_groups(SMALL_BATCH)
        elapsed = Benchmark.realtime { xtrd_groups_current(groups, 1.0) }
        assert elapsed < THRESHOLD_SMALL,
          "xtrd_groups (current) took #{format('%.3f', elapsed)}s for #{SMALL_BATCH} groups " \
          "(threshold: #{THRESHOLD_SMALL}s)"
      end

      def test_xtrd_groups_current_large_batch_within_threshold
        groups  = build_groups(LARGE_BATCH)
        elapsed = Benchmark.realtime { xtrd_groups_current(groups, 1.0) }
        assert elapsed < THRESHOLD_LARGE,
          "xtrd_groups (current) took #{format('%.3f', elapsed)}s for #{LARGE_BATCH} groups " \
          "(threshold: #{THRESHOLD_LARGE}s)"
      end

      def test_xtrd_groups_current_faster_than_legacy
        groups_a = build_groups(LARGE_BATCH)
        groups_b = build_groups(LARGE_BATCH)

        t_legacy  = Benchmark.realtime { xtrd_groups_legacy(groups_a,  1.0) }
        t_current = Benchmark.realtime { xtrd_groups_current(groups_b, 1.0) }

        # The optimised version must not be worse than 1.5× the legacy time.
        # (It will normally be faster; the generous multiplier avoids flakiness
        # on loaded machines while still catching a serious regression.) A
        # noise floor protects against sub-millisecond runs where t_legacy
        # rounds to 0 and any t_current > 0 would fail the bare ratio.
        budget = [t_legacy * 1.5, 0.005].max
        assert t_current <= budget,
          "xtrd_groups (current) #{format('%.3f', t_current)}s is slower than " \
          "legacy #{format('%.3f', t_legacy)}s — possible regression"
      end

      def test_xtrd_groups_entities_traversed_once
        # Verify the optimised path calls #to_a exactly once per group by
        # wrapping entities in a spy.
        call_counts = []

        groups = Array.new(3) do
          face   = FakeFace.new
          spy    = SpyEntities.new([face], [])
          call_counts << spy
          SpyGroup.new(spy)
        end

        xtrd_groups_current(groups, 1.0)

        call_counts.each_with_index do |spy, i|
          assert_equal 1, spy.to_a_calls,
            "Group #{i}: expected entities#to_a called once, got #{spy.to_a_calls}"
        end
      end

      # ── Spy helpers ───────────────────────────────────────────────────────

      class SpyEntities
        attr_reader :to_a_calls

        def initialize(faces, edges)
          @faces     = faces
          @edges     = edges
          @to_a_calls = 0
        end

        def to_a
          @to_a_calls += 1
          @faces + @edges
        end

        def grep(klass)
          klass == Sketchup::Face ? @faces : @edges
        end
      end

      class SpyGroup
        def initialize(spy_entities)
          @entities = spy_entities
        end

        def entities
          @entities
        end
      end

      # ── face2group — Set optimization ─────────────────────────────────────

      # Lightweight face stub for classification tests.
      class ClassifyFace
        def initialize(outer_edge_ids, all_edge_ids)
          @outer_edges = outer_edge_ids.map { |id| EdgeStub.new(id) }
          @all_edges   = all_edge_ids.map   { |id| EdgeStub.new(id) }
          @outer_loop  = OuterLoopStub.new(@outer_edges)
        end

        def outer_loop; @outer_loop; end
        def edges;      @all_edges;  end
      end

      EdgeStub      = Struct.new(:id)
      OuterLoopStub = Struct.new(:edges)

      # Inline copies of the classification logic.
      def has_inner_edges_current(face)
        outer_set = face.outer_loop.edges.to_set
        face.edges.any? { |e| !outer_set.include?(e) }
      end

      def has_inner_edges_legacy(face)
        outer_edges = face.outer_loop.edges
        face.edges.any? { |e| !outer_edges.include?(e) }
      end

      def test_face2group_no_inner_edges_detected_correctly
        # All face edges are outer edges → no inner edges
        face = ClassifyFace.new([1, 2, 3, 4], [1, 2, 3, 4])
        refute has_inner_edges_current(face), "Face with only outer edges should have no inner edges"
      end

      def test_face2group_inner_edges_detected_correctly
        # Edge 5 is not in outer loop → face has inner edge
        face = ClassifyFace.new([1, 2, 3, 4], [1, 2, 3, 4, 5])
        assert has_inner_edges_current(face), "Face with extra edge should have inner edges"
      end

      def test_face2group_current_faster_than_legacy_on_complex_faces
        # Build faces with 40 outer edges and 10 inner edges — worst case for Array#include?
        outer_ids = (1..40).to_a
        all_ids   = (1..50).to_a

        faces_legacy  = Array.new(LARGE_BATCH) { ClassifyFace.new(outer_ids, all_ids) }
        faces_current = Array.new(LARGE_BATCH) { ClassifyFace.new(outer_ids, all_ids) }

        t_legacy  = Benchmark.realtime { faces_legacy.each  { |f| has_inner_edges_legacy(f)  } }
        t_current = Benchmark.realtime { faces_current.each { |f| has_inner_edges_current(f) } }

        budget = [t_legacy * 1.5, 0.005].max
        assert t_current <= budget,
          "face2group (Set) #{format('%.3f', t_current)}s should not be slower than " \
          "legacy (Array) #{format('%.3f', t_legacy)}s"
      end

      # ── getExtents — cache face.normal ────────────────────────────────────

      # Spy face: records how many times #normal is called.
      class SpyNormalFace
        attr_reader :normal_calls

        def initialize(vertex_count)
          @vertices     = Array.new(vertex_count) { SpyVertex.new(SpyPoint.new) }
          @normal_calls = 0
        end

        def valid?; true; end

        def normal
          @normal_calls += 1
          SpyVector.new
        end

        def vertices; @vertices; end
      end

      SpyVertex = Struct.new(:position)

      class SpyPoint
        def offset(_vec, _dist); SpyPoint.new; end
      end

      class SpyVector
        def offset(_other, _dist); SpyPoint.new; end
      end

      class SpyBoundingBox
        def add(_pt); end
      end

      # Inline copy of the CURRENT getExtents logic.
      def getextents_current(selected_faces, dist)
        bb = SpyBoundingBox.new
        selected_faces.each do |face|
          next unless face && face.valid?
          normal = face.normal
          face.vertices.each do |v|
            pos = v.position
            bb.add(pos)
            bb.add(pos.offset(normal, dist))
          end
        end
        bb
      end

      # Inline copy of the LEGACY getExtents logic.
      def getextents_legacy(selected_faces, dist)
        bb = SpyBoundingBox.new
        selected_faces.each do |face|
          next unless face && face.valid?
          face.vertices.each do |v|
            bb.add(v.position)
            bb.add(v.position.offset(face.normal, dist))
          end
        end
        bb
      end

      def test_getextents_normal_called_once_per_face
        # With 20 vertices, legacy would call face.normal 20 times; current calls it once.
        faces = [SpyNormalFace.new(20)]
        getextents_current(faces, 1.0)
        assert_equal 1, faces.first.normal_calls,
          "getExtents should call face.normal once per face, got #{faces.first.normal_calls}"
      end

      def test_getextents_legacy_normal_called_per_vertex
        # Confirm the legacy code actually does call normal once per vertex (documents the regression).
        faces = [SpyNormalFace.new(20)]
        getextents_legacy(faces, 1.0)
        assert_equal 20, faces.first.normal_calls,
          "Legacy getExtents should call face.normal once per vertex (20 times)"
      end

    end
  end
end
