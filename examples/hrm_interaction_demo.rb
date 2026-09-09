#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "rbconfig"
require "tmpdir"

class HrmInteractionDemo
  CLI = File.expand_path("../scripts/hrm_kernel.rb", __dir__)

  def initialize(output_dir)
    @output_dir = File.realpath(prepare_output_dir(output_dir))
    @project_root = File.join(@output_dir, "fictional-project")
    @state_dir = File.join(@output_dir, "state")
    @command_sequence = 0
    FileUtils.mkdir_p(@project_root, mode: 0o700)
    @project_root = File.realpath(@project_root)
  end

  def run
    write("site/index.html", initial_html)
    write("site/styles.css", initial_css)

    apply("milestone.create", operator,
          "milestone_id" => "demo-product-surface",
          "outcome" => "The fictional product surface and local API mirror show the approved presentation.",
          "project_root" => @project_root,
          "requirements" => [
            {"id" => "req-ui", "text" => "The local product surface shows the approved presentation."}
          ],
          "allowed_paths" => [
            "site/index.html", "site/styles.css", "lib/demo_api_mirror.rb", "data/consumer.json"
          ])

    exercise_stale_decision_rejection

    apply("work_order.create", orchestrator, order_data(
      "work-initial", "milestone_initial",
      "Build the fictional local product surface.",
      ["req-ui"], ["site/index.html", "site/styles.css"], ["check-initial-ui"]
    ))
    apply("work_order.claim", worker,
          "work_order_id" => "work-initial", "revision" => 1, "claim_id" => "claim-initial")
    initial_artifacts = artifacts("site/index.html", "site/styles.css")
    initial_checks = check_fixture("check-initial-ui", "work-initial", 1, initial_artifacts)
    apply("work_order.submit", worker, submission(
      "work-initial", 1, "claim-initial", initial_artifacts, initial_checks
    ))
    apply("milestone.review_ready", orchestrator, "review_id" => "review-initial")
    apply("milestone.review", operator,
          "review_id" => "review-initial",
          "decision" => "changes_requested",
          "text" => "Use blue as the fictional accent color.",
          "source" => source("message-review-initial"))

    apply("intent.record", operator,
          "intent_id" => "intent-blue",
          "kind" => "presentation_adjustment",
          "text" => "Use blue as the fictional accent color.",
          "source" => source("message-blue"),
          "requirement_ids" => ["req-ui"])
    apply("work_order.amend", orchestrator, order_data(
      "work-initial", "intent-blue",
      "Apply the approved blue accent to the fictional local surface.",
      ["req-ui"], ["site/index.html", "site/styles.css"], ["check-blue-ui"]
    ).merge("expected_revision" => 1).tap { |data| data.delete("effect_class") })

    stale_submission = submission(
      "work-initial", 1, "claim-initial", initial_artifacts, initial_checks
    )
    assert_failed_without_ledger_change("work_order.submit", worker, stale_submission)

    apply("work_order.claim", worker,
          "work_order_id" => "work-initial", "revision" => 2, "claim_id" => "claim-blue")
    write("site/styles.css", blue_css)
    blue_artifacts = artifacts("site/index.html", "site/styles.css")
    blue_checks = check_fixture("check-blue-ui", "work-initial", 2, blue_artifacts)
    apply("work_order.submit", worker, submission(
      "work-initial", 2, "claim-blue", blue_artifacts, blue_checks
    ))
    resolve_finding(
      "review-initial-requested-change",
      "The independent review confirms that the current surface now uses the requested blue accent.",
      [{"work_order_id" => "work-initial", "revision" => 2, "check_ids" => ["check-blue-ui"]}]
    )
    apply("milestone.review_ready", orchestrator, "review_id" => "review-blue")
    apply("milestone.review", operator,
          "review_id" => "review-blue",
          "decision" => "changes_requested",
          "text" => "Add the missing local API mirror and its fictional consumer.",
          "source" => source("message-review-blue"))

    apply("intent.record", operator,
          "intent_id" => "intent-api-mirror",
          "kind" => "milestone_change",
          "text" => "Add the missing local API mirror and its fictional consumer.",
          "source" => source("message-api-mirror"),
          "requirement_ids" => ["req-api"],
          "requirements" => [
            {"id" => "req-api", "text" => "A local API mirror and consumer expose the approved accent."}
          ])
    apply("work_order.create", orchestrator, order_data(
      "work-api-mirror", "intent-api-mirror",
      "Implement the fictional local API mirror and consumer.",
      ["req-api"], ["lib/demo_api_mirror.rb", "data/consumer.json"], ["check-api-mirror"]
    ))
    apply("work_order.claim", worker,
          "work_order_id" => "work-api-mirror", "revision" => 1, "claim_id" => "claim-api-mirror")
    write("lib/demo_api_mirror.rb", api_mirror)
    write("data/consumer.json", JSON.pretty_generate("accent" => "blue", "source" => "local_demo") << "\n")
    mirror_artifacts = artifacts("lib/demo_api_mirror.rb", "data/consumer.json")
    mirror_checks = check_fixture("check-api-mirror", "work-api-mirror", 1, mirror_artifacts)
    apply("work_order.submit", worker, submission(
      "work-api-mirror", 1, "claim-api-mirror", mirror_artifacts, mirror_checks
    ))
    resolve_finding(
      "review-blue-requested-change",
      "The independent review confirms that the current candidate includes the requested API mirror and consumer.",
      [
        {"work_order_id" => "work-initial", "revision" => 2, "check_ids" => ["check-blue-ui"]},
        {"work_order_id" => "work-api-mirror", "revision" => 1, "check_ids" => ["check-api-mirror"]}
      ]
    )
    apply("milestone.review_ready", orchestrator, "review_id" => "review-api-mirror")
    apply("milestone.review", operator,
          "review_id" => "review-api-mirror",
          "decision" => "accepted",
          "text" => "The fictional local milestone outcome is accepted.",
          "source" => source("message-review-api-mirror"))

    verified = cli("verify", "--state-dir", @state_dir)
    raise "ledger verification did not pass" unless verified.fetch("valid")

    status = cli("status", "--state-dir", @state_dir, "--role", "operator", "--actor-id", "operator-demo")
    result = {
      "ledger_path" => File.join(@state_dir, "events.jsonl"),
      "demo_artifact_path" => File.join(@project_root, "site/index.html"),
      "phase" => status.dig("projection", "milestone", "phase"),
      "outcomes" => [
        {"review_id" => "review-initial", "decision" => "changes_requested"},
        {"review_id" => "review-blue", "decision" => "changes_requested"},
        {"review_id" => "review-api-mirror", "decision" => "accepted"},
        {"stale_decision_rejected" => true, "stale_worker_result_rejected" => true}
      ],
      "execution_note" => "Fictional fixture commands were applied; no host model worker was launched."
    }
    result_path = File.join(@output_dir, "demo-result.json")
    result["result_path"] = result_path
    write_absolute(result_path, JSON.pretty_generate(result) << "\n")
    puts JSON.generate(result)
  end

  private

  def prepare_output_dir(requested)
    return Dir.mktmpdir("hrm-interaction-demo-").tap { |path| File.chmod(0o700, path) } unless requested

    path = File.expand_path(requested)
    raise ArgumentError, "--output-dir must not already exist: #{path}" if File.exist?(path) || File.symlink?(path)

    Dir.mkdir(path, 0o700)
    path
  end

  def apply(type, actor, data)
    command = next_command(type, actor, data)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, CLI, "apply", "--state-dir", @state_dir, "--input", "-",
      stdin_data: JSON.generate(command)
    )
    raise "#{type} failed: #{stderr.strip}" unless status.success?

    JSON.parse(stdout)
  end

  def assert_failed_without_ledger_change(type, actor, data)
    cursor_before = status_cursor
    command = next_command(type, actor, data)
    _stdout, _stderr, status = Open3.capture3(
      RbConfig.ruby, CLI, "apply", "--state-dir", @state_dir, "--input", "-",
      stdin_data: JSON.generate(command)
    )
    raise "#{type} unexpectedly succeeded" if status.success?
    raise "#{type} failure changed the ledger" unless status_cursor == cursor_before
  end

  def cli(*arguments)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, CLI, *arguments)
    raise "CLI failed: #{stderr.strip}" unless status.success?

    JSON.parse(stdout)
  end

  def status_cursor
    cli("status", "--state-dir", @state_dir, "--role", "orchestrator").fetch("cursor")
  end

  def resolve_finding(finding_id, text, evidence_refs)
    status = cli("status", "--state-dir", @state_dir, "--role", "reviewer", "--actor-id", "reviewer-demo")
    candidate_digest = status.dig("projection", "milestone", "current_candidate", "candidate_digest")
    raise "current candidate digest is unavailable" unless candidate_digest

    apply(
      "finding.resolve",
      reviewer,
      "finding_id" => finding_id,
      "candidate_digest" => candidate_digest,
      "disposition" => "fixed",
      "text" => text,
      "evidence_refs" => evidence_refs
    )
  end

  def next_command(type, actor, data)
    @command_sequence += 1
    {
      "command_id" => "demo-command-#{@command_sequence}",
      "type" => type,
      "actor" => actor,
      "data" => data
    }
  end

  def exercise_stale_decision_rejection
    request = {
      "decision_id" => "decision-accent",
      "revision" => 1,
      "kind" => "business_meaning",
      "exact_effect" => "select the fictional demo accent",
      "requirement_ids" => ["req-ui"],
      "question" => "Which fictional accent should the demo use?",
      "authority_gap" => {
        "reason" => "The initial fictional requirement does not select an accent.",
        "source_ref" => "demo:req-ui"
      }
    }
    apply("decision.request", orchestrator, request)
    apply("decision.revise", orchestrator, request.merge(
      "expected_revision" => 1,
      "question" => "Should the fictional demo use the reviewed blue accent?"
    ).tap { |data| data.delete("revision") })
    stale_answer = {
      "decision_id" => "decision-accent",
      "revision" => 1,
      "kind" => "business_meaning",
      "exact_effect" => "select the fictional demo accent",
      "disposition" => "accepted",
      "source" => source("message-stale-answer"),
      "text" => "Use blue."
    }
    assert_failed_without_ledger_change("decision.respond", operator, stale_answer)
    apply("decision.respond", operator, stale_answer.merge(
      "revision" => 2,
      "source" => source("message-current-answer")
    ))
  end

  def order_data(work_order_id, intent_id, objective, requirement_ids, paths, check_ids)
    {
      "work_order_id" => work_order_id,
      "intent_id" => intent_id,
      "objective" => objective,
      "requirement_ids" => requirement_ids,
      "paths" => paths,
      "check_ids" => check_ids,
      "effect_class" => "local_repository"
    }
  end

  def submission(work_order_id, revision, claim_id, submitted_artifacts, checks)
    {
      "work_order_id" => work_order_id,
      "revision" => revision,
      "claim_id" => claim_id,
      "artifacts" => submitted_artifacts,
      "checks" => checks
    }
  end

  def artifacts(*paths)
    paths.map do |path|
      {"path" => path, "sha256" => Digest::SHA256.file(File.join(@project_root, path)).hexdigest}
    end
  end

  def check_fixture(check_id, work_order_id, revision, submitted_artifacts)
    assert_check!(check_id)
    relative_path = ".codex/checks/#{check_id}.json"
    report = {
      "check_id" => check_id,
      "conclusion" => "passed",
      "work_order_id" => work_order_id,
      "revision" => revision,
      "artifacts" => submitted_artifacts
    }
    write(relative_path, JSON.generate(report) << "\n")
    [{
      "id" => check_id,
      "conclusion" => "passed",
      "artifact_path" => relative_path,
      "sha256" => Digest::SHA256.file(File.join(@project_root, relative_path)).hexdigest
    }]
  end

  def assert_check!(check_id)
    html = File.read(File.join(@project_root, "site/index.html"), encoding: "UTF-8")
    css = File.read(File.join(@project_root, "site/styles.css"), encoding: "UTF-8")
    raise "fictional HTML does not load its stylesheet" unless html.include?('href="styles.css"')

    case check_id
    when "check-initial-ui"
      raise "initial neutral accent check failed" unless css.include?("--accent: #777777")
    when "check-blue-ui"
      raise "approved blue accent check failed" unless css.include?("--accent: #1f5eff")
    when "check-api-mirror"
      load File.join(@project_root, "lib/demo_api_mirror.rb")
      consumer = JSON.parse(File.read(File.join(@project_root, "data/consumer.json"), encoding: "UTF-8"))
      raise "API mirror and consumer disagree" unless DemoApiMirror::RESPONSE == consumer
    else
      raise "unknown demo check #{check_id.inspect}"
    end
  end

  def write(relative_path, content)
    write_absolute(File.join(@project_root, relative_path), content)
  end

  def write_absolute(path, content)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(content) }
  end

  def source(message_id)
    {"thread_id" => "demo-thread", "message_id" => message_id}
  end

  def operator
    {"id" => "operator-demo", "role" => "operator"}
  end

  def orchestrator
    {"id" => "orchestrator-demo", "role" => "orchestrator"}
  end

  def worker
    {"id" => "worker-demo", "role" => "worker"}
  end

  def reviewer
    {"id" => "reviewer-demo", "role" => "reviewer"}
  end

  def initial_html
    <<~HTML
      <!doctype html>
      <html lang="en">
        <head><meta charset="utf-8"><link rel="stylesheet" href="styles.css"><title>Fictional demo</title></head>
        <body><main><h1>Fictional product</h1><p>Local review fixture</p></main></body>
      </html>
    HTML
  end

  def initial_css
    ":root { --accent: #777777; }\nh1 { color: var(--accent); }\n"
  end

  def blue_css
    ":root { --accent: #1f5eff; }\nh1 { color: var(--accent); }\n"
  end

  def api_mirror
    <<~RUBY
      # frozen_string_literal: true

      module DemoApiMirror
        RESPONSE = {"accent" => "blue", "source" => "local_demo"}.freeze
      end
    RUBY
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby examples/hrm_interaction_demo.rb [--output-dir NEW_DIR]"
  parser.on("--output-dir DIR", "Create the retained demo in a directory that does not exist") do |value|
    options[:output_dir] = value
  end
end.parse!

HrmInteractionDemo.new(options[:output_dir]).run
