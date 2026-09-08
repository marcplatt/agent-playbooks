# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"

require_relative "../lib/hrm_kernel/store"
require_relative "../scripts/hrm_kernel"

class HrmKernelStoreTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir("hrm-kernel-store")
    @project_root = File.realpath(@temporary)
    @state_dir = File.join(@project_root, "state")
    @store = HrmKernel::Store.new(@state_dir)
    @sequence = 0
  end

  def teardown
    FileUtils.remove_entry(@temporary) if File.exist?(@temporary)
  end

  def test_empty_store_has_no_materialized_state
    assert_equal({"cursor" => 0, "event_hash" => nil, "state" => nil}, @store.read)
    refute File.exist?(File.join(@state_dir, "events.jsonl"))
  end

  def test_hash_chain_permissions_and_exact_command_replay
    create = command("milestone.create", operator, milestone_data, id: "create-1")
    first = @store.transact(create)
    later = @store.transact(command("intent.record", operator, intent_data("intent-1"), id: "intent-1"))
    replayed = @store.transact(create)

    assert_equal 2, replayed.fetch("cursor")
    assert_equal later.fetch("event_hash"), replayed.fetch("event_hash")
    assert_equal 1, replayed.fetch("command_cursor")
    assert_equal first.fetch("command_event_hash"), replayed.fetch("command_event_hash")
    assert replayed.fetch("replayed")
    assert replayed.dig("projection", "intents").key?("intent-1")
    assert_equal 0o700, File.stat(@state_dir).mode & 0o777
    assert_equal 0o600, File.stat(File.join(@state_dir, "events.jsonl")).mode & 0o777
    assert_equal 0o600, File.stat(File.join(@state_dir, ".lock")).mode & 0o777

    lines = File.readlines(File.join(@state_dir, "events.jsonl"), chomp: true).map { |line| JSON.parse(line) }
    assert_nil lines.first.fetch("previous_hash")
    assert_equal lines.first.fetch("event_hash"), lines.last.fetch("previous_hash")
  end

  def test_reusing_command_id_with_different_content_fails_without_append
    original = command("milestone.create", operator, milestone_data, id: "same-id")
    @store.transact(original)
    changed = Marshal.load(Marshal.dump(original))
    changed["data"]["outcome"] = "Different outcome"

    assert_raises(HrmKernel::Error) { @store.transact(changed) }
    assert_equal 1, @store.read.fetch("cursor")
  end

  def test_v1_ledgers_cannot_be_resumed_or_rewritten_by_rc34
    @store.transact(command("milestone.create", operator, milestone_data))
    path = File.join(@state_dir, "events.jsonl")
    event = JSON.parse(File.read(path))
    assert_equal "ap-hrm-interaction/2", event.fetch("schema_version")
    assert_match(/Z\z/, event.fetch("occurred_at"))
    event["schema_version"] = "ap-hrm-interaction/1"
    event.delete("occurred_at")
    event["event_hash"] = @store.send(:event_hash, event)
    original = JSON.generate(event) + "\n"
    File.write(path, original)
    assert_raises(HrmKernel::Error) { @store.verify! }
    assert_raises(HrmKernel::Error) do
      @store.transact(command("intent.record", operator, intent_data("new")))
    end
    assert_equal original, File.read(path)
  end

  def test_rejected_first_command_does_not_create_ledger_or_state
    invalid = command(
      "milestone.create",
      operator,
      milestone_data.merge("project_root" => File.join(@project_root, "missing"))
    )

    assert_raises(HrmKernel::Error) { @store.transact(invalid) }
    assert_equal({"cursor" => 0, "event_hash" => nil, "state" => nil}, @store.read)
    refute File.exist?(File.join(@state_dir, "events.jsonl"))
  end

  def test_cli_reports_malformed_nested_shape_and_does_not_append
    malformed = command(
      "milestone.create",
      operator,
      milestone_data.merge("requirements" => "not-an-array")
    )
    output = StringIO.new
    errors = StringIO.new

    status = HrmKernel::CLI.run(
      ["apply", "--state-dir", @state_dir, "--input", "-"],
      stdin: StringIO.new(JSON.generate(malformed)),
      stdout: output,
      stderr: errors
    )

    assert_equal 1, status
    assert_empty output.string
    failure = JSON.parse(errors.string)
    assert failure.fetch("error")
    assert_equal "invalid_command", failure.fetch("code")
    assert_equal 0, @store.read.fetch("cursor")
    refute File.exist?(File.join(@state_dir, "events.jsonl"))
  end

  def test_cli_reviewer_receives_original_intent_without_private_source_references
    @store.transact(command("milestone.create", operator, milestone_data))
    intent = intent_data("intent-review")
    @store.transact(command("intent.record", operator, intent))
    output = StringIO.new
    errors = StringIO.new

    status = HrmKernel::CLI.run(
      ["status", "--state-dir", @state_dir, "--role", "reviewer"],
      stdout: output, stderr: errors
    )

    assert_equal 0, status
    assert_empty errors.string
    projected = JSON.parse(output.string).dig("projection", "intents", "intent-review")
    assert_equal intent.fetch("text"), projected.fetch("desired_behavior")
    refute projected.key?("source")
  end

  def test_submit_binds_report_to_current_revision_and_artifacts
    prepare_claimed_work_order
    artifacts = write_deliverables
    stale_report = check_report(artifacts, revision: 2)
    write_json(".codex/checks/check-view.json", stale_report)
    submit = submit_command(artifacts)

    assert_raises(HrmKernel::Error) { @store.transact(submit) }
    assert_equal 3, @store.read.fetch("cursor")

    write_json(".codex/checks/check-view.json", check_report(artifacts))
    submit = submit_command(artifacts)
    @store.transact(submit)
    assert_equal "completed", @store.read.dig("state", "work_orders", "work-1", "status")
  end

  def test_tampered_artifact_blocks_review_ready_and_leaves_ledger_unchanged
    submit_completed_work
    File.open(File.join(@project_root, "app/view.rb"), "a") { |file| file.write("tampered\n") }

    review_ready = command(
      "milestone.review_ready",
      orchestrator,
      {"review_id" => "review-1"}
    )
    assert_raises(HrmKernel::Error) { @store.transact(review_ready) }
    assert_equal 4, @store.read.fetch("cursor")
  end

  def test_tampered_check_report_blocks_acceptance
    submit_completed_work
    @store.transact(command("milestone.review_ready", orchestrator, {"review_id" => "review-1"}))
    File.open(File.join(@project_root, ".codex/checks/check-view.json"), "a") { |file| file.write(" ") }

    acceptance = command(
      "milestone.review",
      operator,
      {
        "review_id" => "review-1",
        "decision" => "accepted",
        "text" => "Accepted after local review.",
        "source" => {"thread_id" => "thread-1", "message_id" => "message-review"}
      }
    )
    assert_raises(HrmKernel::Error) { @store.transact(acceptance) }
    assert_equal 5, @store.read.fetch("cursor")
  end

  def test_truncated_corrupt_and_hash_mismatched_ledgers_fail_closed
    @store.transact(command("milestone.create", operator, milestone_data))
    ledger = File.join(@state_dir, "events.jsonl")
    original = File.binread(ledger)

    File.open(ledger, "wb") { |file| file.write(original.delete_suffix("\n")) }
    assert_raises(HrmKernel::Error) { @store.verify! }

    File.open(ledger, "wb") { |file| file.write("not-json\n") }
    assert_raises(HrmKernel::Error) { @store.verify! }

    event = JSON.parse(original)
    event["command"]["data"]["outcome"] = "tampered"
    File.open(ledger, "wb") { |file| file.write(JSON.generate(event) << "\n") }
    assert_raises(HrmKernel::Error) { @store.verify! }
  end

  def test_symlink_state_and_evidence_paths_are_rejected
    target = File.join(@project_root, "target")
    Dir.mkdir(target, 0o700)
    link = File.join(@project_root, "linked-state")
    File.symlink(target, link)
    assert_raises(HrmKernel::Error) { HrmKernel::Store.new(link) }

    @store.transact(command("milestone.create", operator, milestone_data))
    @store.transact(command("work_order.create", orchestrator, work_order_data))
    @store.transact(command("work_order.claim", worker, claim_data))
    FileUtils.mkdir_p(File.join(@project_root, "app"))
    outside = File.join(@project_root, "outside.rb")
    File.write(outside, "outside\n")
    File.symlink(outside, File.join(@project_root, "app/view.rb"))
    artifacts = [{"path" => "app/view.rb", "sha256" => Digest::SHA256.file(outside).hexdigest}]
    write_json(".codex/checks/check-view.json", check_report(artifacts))
    assert_raises(HrmKernel::Error) { @store.transact(submit_command(artifacts)) }
    assert_equal 3, @store.read.fetch("cursor")
  end

  def test_nonprivate_unrelated_directory_is_rejected_without_mutation
    unrelated = File.join(@project_root, "unrelated")
    Dir.mkdir(unrelated, 0o755)
    marker = File.join(unrelated, "keep.txt")
    File.write(marker, "keep\n")

    assert_raises(HrmKernel::Error) { HrmKernel::Store.new(unrelated) }
    assert_equal 0o755, File.stat(unrelated).mode & 0o777
    assert_equal "keep\n", File.read(marker)
    assert_equal ["keep.txt"], Dir.children(unrelated)
  end

  def test_private_unrelated_directory_is_rejected_without_mutation
    unrelated = File.join(@project_root, "private-unrelated")
    Dir.mkdir(unrelated, 0o700)
    marker = File.join(unrelated, "sentinel")
    File.write(marker, "preserve")

    assert_raises(HrmKernel::Error) { HrmKernel::Store.new(unrelated) }
    assert_equal 0o700, File.stat(unrelated).mode & 0o777
    assert_equal "preserve", File.read(marker)
    assert_equal ["sentinel"], Dir.children(unrelated)
  end

  def test_concurrent_writers_are_serialized_without_lost_events
    @store.transact(command("milestone.create", operator, milestone_data))
    process_ids = 6.times.map do |index|
      fork do
        child_store = HrmKernel::Store.new(@state_dir)
        child_store.transact(
          command(
            "intent.record",
            operator,
            intent_data("intent-#{index}", message_id: "message-#{index}"),
            id: "concurrent-#{index}"
          )
        )
        exit! 0
      rescue StandardError
        exit! 1
      end
    end
    statuses = process_ids.map { |pid| Process.wait2(pid).last }

    assert statuses.all?(&:success?)
    read = @store.read
    assert_equal 7, read.fetch("cursor")
    assert_equal 6, read.dig("state", "intents").length
    assert @store.verify!.fetch("valid")
  end

  private

  def command(type, actor, data, id: nil)
    @sequence += 1
    {
      "command_id" => id || "command-#{@sequence}",
      "type" => type,
      "actor" => actor,
      "data" => data
    }
  end

  def operator
    {"id" => "operator-1", "role" => "operator"}
  end

  def orchestrator
    {"id" => "orchestrator-1", "role" => "orchestrator"}
  end

  def worker
    {"id" => "worker-1", "role" => "worker"}
  end

  def milestone_data
    {
      "milestone_id" => "milestone-1",
      "outcome" => "The reviewed local view is correct.",
      "project_root" => @project_root,
      "requirements" => [{"id" => "req-view", "text" => "The view displays the intended value."}],
      "allowed_paths" => ["app/view.rb"]
    }
  end

  def intent_data(id, message_id: "message-#{id}")
    {
      "intent_id" => id,
      "kind" => "clarification",
      "text" => "Record local clarification #{id}.",
      "source" => {"thread_id" => "thread-1", "message_id" => message_id},
      "requirement_ids" => ["req-view"]
    }
  end

  def work_order_data
    {
      "work_order_id" => "work-1",
      "intent_id" => "milestone_initial",
      "objective" => "Implement the local view.",
      "requirement_ids" => ["req-view"],
      "paths" => ["app/view.rb"],
      "check_ids" => ["check-view"],
      "effect_class" => "local_repository"
    }
  end

  def claim_data
    {"work_order_id" => "work-1", "revision" => 1, "claim_id" => "claim-1"}
  end

  def prepare_claimed_work_order
    @store.transact(command("milestone.create", operator, milestone_data))
    @store.transact(command("work_order.create", orchestrator, work_order_data))
    @store.transact(command("work_order.claim", worker, claim_data))
  end

  def write_deliverables
    path = File.join(@project_root, "app/view.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "approved value\n")
    [{"path" => "app/view.rb", "sha256" => Digest::SHA256.file(path).hexdigest}]
  end

  def check_report(artifacts, revision: 1)
    {
      "check_id" => "check-view",
      "conclusion" => "passed",
      "work_order_id" => "work-1",
      "revision" => revision,
      "artifacts" => artifacts
    }
  end

  def write_json(relative_path, value)
    path = File.join(@project_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "w") { |file| file.write(JSON.generate(value)) }
  end

  def submit_command(artifacts)
    report_path = File.join(@project_root, ".codex/checks/check-view.json")
    command(
      "work_order.submit",
      worker,
      {
        "work_order_id" => "work-1",
        "revision" => 1,
        "claim_id" => "claim-1",
        "artifacts" => artifacts,
        "checks" => [{
          "id" => "check-view",
          "conclusion" => "passed",
          "artifact_path" => ".codex/checks/check-view.json",
          "sha256" => Digest::SHA256.file(report_path).hexdigest
        }]
      }
    )
  end

  def submit_completed_work
    prepare_claimed_work_order
    artifacts = write_deliverables
    write_json(".codex/checks/check-view.json", check_report(artifacts))
    @store.transact(submit_command(artifacts))
  end
end
